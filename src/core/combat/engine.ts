/**
 * Детерминированное боевое ядро (разделы 2, 4, 6–8, 23.2 мастер-ТЗ).
 * Единственный переход состояния — stepCombat: ровно один тик 100 мс.
 * Вся математика урона проходит через math/damage.ts ровно один раз.
 * Никакого Math.random, настенных часов и глобальных счётчиков событий.
 */
import { ENEMY_BY_ID, BOSS_BY_ID, enemyTemplate } from '../../data/enemies';
import { ITEM_BY_ID } from '../../data/items';
import { SKILL_BY_ID } from '../../data/skills';
import { UNIQUE_TEMPLATE_BY_ID } from '../../data/uniques';
import type { BossPhaseTrigger, BossTemplate, EnemyAbility, EnemyTemplate, SkillDef } from '../../data/types';
import type { ResolvedBuild } from '../build/build';
import { D, H, TICK_MS, attackIntervalMs, clamp, cooldownMs, finite } from '../math/formula';
import {
  mitigatePacket, partitionDamage, pCrit, pHit, ZERO_PEN,
  type DefenseSnapshot, type PenetrationSnapshot,
} from '../math/damage';
import {
  bundle, conditionSignature, emptySheet, mod, resolveStats, sheetOf,
  type ActorView, type Modifier, type StatContext, type StatSheet,
} from '../math/stats';
import { Rng, hashString, stableStringify, type SerializedRng } from '../rng';
import { STATUS_DEFS } from './status';
import type { CastState, CombatActor, CombatConfig, CombatEvent, CombatEventKind, CombatMetrics, CombatResult, DeathReport, TacticCondition, TacticRule, TacticalProfile } from './types';
import type { Channel, DamageType, NodeType, StatusId, TargetMode } from '../types';

export const COMBAT_RULES_VERSION = 'cydle-combat-1.0';
export const MAX_LOG_EVENTS = 5000;
const DEFAULT_MAX_DURATION_MS = 180000;
const SHIELD_REGEN_DELAY_MS = 4000;
const HEAT_LOCKOUT_RELEASE = 80;

export type CombatOutcome = 'VICTORY' | 'DEFEAT' | 'TIMEOUT';

export interface CombatState {
  seed: string;
  depth: number;
  biome: string;
  nodeType: NodeType;
  timeMs: number;
  maxDurationMs: number;
  operator: CombatActor;
  drones: CombatActor[];
  enemies: CombatActor[];
  allies: CombatActor[];
  rng: SerializedRng;
  nextEventId: number;
  log: CombatEvent[];
  logTruncated: boolean;
  metrics: CombatMetrics;
  outcome: CombatOutcome | null;
  build: ResolvedBuild;
  tactics: TacticalProfile;
  rulesHash: string;
  wantedDelta: number;
  revealDelta: number;
  recordLog: boolean;
  ambientHeatPerSec: number;
  coolingPenalty: number;
  enemyWindupMult: number;
  elitePen: number;
  extraEnemyDigitalBonus: number;
}

/* ------------------------------------------------------------------ */
/* Создание акторов                                                    */
/* ------------------------------------------------------------------ */

function emptyMetrics(): CombatMetrics {
  return {
    damageDealt: 0, damageTaken: 0,
    damageByType: { KINETIC: 0, ENERGY: 0, DIGITAL: 0 },
    damageBySource: {}, takenBySource: {},
    hits: 0, misses: 0, crits: 0, dodgesTaken: 0, kills: 0,
    skillUses: {}, ruleFailures: [],
    energySpent: 0, energyStarvedMs: 0, heatLockouts: 0, heatLockoutMs: 0,
    shieldAbsorbed: 0, hpLost: 0, healingDone: 0, statusTicks: 0,
    procsTriggered: 0, interrupts: 0, chainLimitHits: 0, ttk: [], droneDeaths: 0, escaped: [],
    lowestHpFraction: 1, timeWithoutShieldMs: 0,
  };
}

function baseActor(partial: Partial<CombatActor> & Pick<CombatActor, 'id' | 'kind' | 'side' | 'templateId' | 'name'>): CombatActor {
  return {
    positionTag: partial.side === 'player' ? 'left' : 'right',
    isBoss: false, isMechanical: false, isHealer: false,
    hp: 1, shield: 0, tempShields: [], energy: 0, heat: 0,
    heatLockout: false, lockoutUntil: 0,
    statuses: {}, buffs: [], cooldowns: {}, cast: null, reactionCast: null, channelBusy: {},
    nextAttackAt: 0, flags: {}, counters: {}, icds: {}, oncePerCombat: {}, abilityNext: {},
    alive: true, baseSheet: emptySheet(), baseMods: [], runtimeMods: [],
    damageDealt: 0, damageTaken: 0, threatUnits: 1,
    attackDamage: 0, attackIntervalMs: 1000, attackType: 'KINETIC',
    accuracyBase: 100, procMultiplier: 1,
    lastMainAttackAt: -100000, lastTargetId: null, sameTargetHits: 0,
    lastSkillId: null, sameSkillCount: 0, lastDigitalSkill: null,
    shieldSpentWindow: [], energyGainWindow: [],
    ...partial,
  };
}

function enemySheet(t: EnemyTemplate, depth: number, extraDigitalBonus: number): StatSheet {
  const sheet = emptySheet();
  sheet.maxHP = t.hp * H(depth);
  sheet.maxShield = t.shield * H(depth);
  sheet.armor = t.armor;
  sheet.energyRes = t.resE;
  sheet.digitalRes = t.resD;
  sheet.evasion = t.evasion;
  sheet.accuracy = (t as BossTemplate).accuracy ?? 100;
  sheet.critChance = 0;
  sheet.critMultiplier = 1.5;
  void extraDigitalBonus;
  return sheet;
}

/** Базовый лист врага/дрона как OVERRIDE-модификаторы — чтобы effectiveSheet
 *  пересчитывался тем же pipeline, что и билд оператора. */
const OVERRIDE_STATS = ['maxHP', 'maxShield', 'armor', 'energyRes', 'digitalRes', 'evasion', 'accuracy', 'critChance', 'critMultiplier'] as const;
function sheetOverrideMods(sheet: StatSheet, source: { id: string; name: string; kind: 'enemy' | 'item' }): Modifier[] {
  return OVERRIDE_STATS.map((stat) => mod(stat, 'OVERRIDE', sheet[stat], source, { id: `${source.id}:base:${stat}` }));
}

function createEnemyActor(spec: { templateId: string; hpMult?: number; damageMult?: number; summoned?: boolean; noLoot?: boolean; elite?: string }, index: number, depth: number, extraDigitalBonus: number): CombatActor {
  const t = enemyTemplate(spec.templateId);
  if (!t) throw new Error(`Неизвестный шаблон врага: ${spec.templateId}`);
  const sheet = enemySheet(t, depth, extraDigitalBonus);
  const hp = sheet.maxHP * (spec.hpMult ?? 1);
  const actor = baseActor({
    id: `enemy:${index}`, kind: t.role === 'boss' ? 'boss' : 'enemy', side: 'enemy',
    templateId: t.id, name: t.name, isBoss: t.role === 'boss',
    isMechanical: t.mechanical, isHealer: t.healer,
    hp, shield: sheet.maxShield, baseSheet: sheet,
    baseMods: sheetOverrideMods(sheet, { id: `enemy:${t.id}`, name: t.name, kind: 'enemy' }),
    attackDamage: t.damage * D(depth) * (spec.damageMult ?? 1),
    attackIntervalMs: t.intervalMs, attackType: t.type,
    accuracyBase: sheet.accuracy, threatUnits: t.threatUnits,
    nextAttackAt: t.intervalMs,
    summoned: spec.summoned, noLoot: spec.noLoot, eliteMod: spec.elite,
  });
  actor.flags.lastDamagedAt = -100000;
  for (const ability of [...t.abilities, ...('rotating' in t ? t.rotating ?? [] : [])]) actor.abilityNext[ability.id] = ability.firstAtMs;
  return actor;
}

function createOperator(build: ResolvedBuild, config: CombatConfig): CombatActor {
  const sheet = build.stats;
  const weapon = build.mainWeapon!;
  const actor = baseActor({
    id: 'operator', kind: 'operator', side: 'player',
    templateId: weapon.templateId, name: 'Оператор',
    hp: sheet.maxHP * clamp(config.startHpFraction ?? 1, 0, 1),
    shield: sheet.maxShield * clamp(config.startShieldFraction ?? 1, 0, 1),
    energy: clamp(config.startEnergy ?? 0, 0, sheet.maxEnergy),
    heat: clamp((config.startHeat ?? 0) + (config.initialExtraHeat ?? 0), 0, sheet.maxHeat),
    baseSheet: sheet, baseMods: build.modifiers,
    attackDamage: weapon.damage,
    attackIntervalMs: attackIntervalMs(weapon.intervalMs, sheet.attackSpeed, sheet.moreAttackSpeed),
    attackType: weapon.type,
    accuracyBase: sheet.accuracy, procMultiplier: sheet.procMultiplier,
    nextAttackAt: attackIntervalMs(weapon.intervalMs, sheet.attackSpeed, sheet.moreAttackSpeed),
  });
  actor.flags.lastDamagedAt = -100000;
  if (config.initialTempShield && config.initialTempShield > 0) {
    actor.tempShields.push({ sourceId: 'initial', amount: config.initialTempShield, cap: config.initialTempShield, expiresAt: 60000 });
  }
  return actor;
}

function createDroneActor(build: ResolvedBuild, index: number, config: CombatConfig): CombatActor | null {
  const drone = build.drones[index];
  if (!drone) return null;
  const sheet = emptySheet();
  const owner = build.stats;
  sheet.maxHP = drone.hp * (1 + owner.droneHP / 100) * owner.moreDroneHP;
  sheet.maxShield = drone.shield * (1 + owner.droneShield / 100);
  sheet.armor = drone.armor;
  sheet.evasion = 0;
  sheet.accuracy = 100 + owner.droneAccuracy;
  sheet.critChance = 0;
  const hpOverride = config.droneHp?.[drone.itemId];
  const droneName = (UNIQUE_TEMPLATE_BY_ID[drone.templateId] ?? ITEM_BY_ID[drone.templateId])?.name ?? drone.templateId;
  const actor = baseActor({
    id: `drone:${index}`, kind: 'drone', side: 'player',
    templateId: drone.templateId, name: droneName,
    hp: clamp(hpOverride ?? sheet.maxHP, 0, sheet.maxHP),
    shield: sheet.maxShield, baseSheet: sheet,
    baseMods: sheetOverrideMods(sheet, { id: `drone:${drone.templateId}`, name: droneName, kind: 'item' }),
    attackDamage: drone.damage,
    attackIntervalMs: attackIntervalMs(drone.intervalMs, owner.droneAttackSpeed, 1),
    attackType: drone.type,
    accuracyBase: sheet.accuracy,
    nextAttackAt: drone.intervalMs,
    ownerId: 'operator',
  });
  actor.flags.lastDamagedAt = -100000;
  actor.flags.droneIndex = index;
  return actor;
}

/* ------------------------------------------------------------------ */
/* Инициализация боя                                                   */
/* ------------------------------------------------------------------ */

export function createCombatState(config: CombatConfig): CombatState {
  if (!config.build.valid) {
    throw new Error(`Invalid build: ${config.build.issues.map((i) => i.message).join('; ') || 'сборка не прошла валидацию'}`);
  }
  if (!config.build.mainWeapon) throw new Error('Invalid build: отсутствует основное оружие.');
  if (!Number.isInteger(config.depth) || config.depth < 1) throw new Error('Invalid depth: глубина должна быть целым числом ≥ 1.');
  if (!config.enemies.length) throw new Error('Invalid encounter: список врагов пуст.');
  for (const spec of config.enemies) {
    if (!ENEMY_BY_ID[spec.templateId] && !BOSS_BY_ID[spec.templateId]) {
      throw new Error(`Неизвестный шаблон врага: ${spec.templateId}`);
    }
  }
  const extraDigital = config.extraEnemyDigitalBonus ?? 0;
  const operator = createOperator(config.build, config);
  const drones: CombatActor[] = [];
  for (let i = 0; i < config.build.drones.length; i++) {
    const d = createDroneActor(config.build, i, config);
    if (d) drones.push(d);
  }
  const enemies = config.enemies.map((spec, i) => createEnemyActor(spec, i, config.depth, extraDigital));
  const allies = (config.allies ?? []).map((spec, i) => {
    const a = createEnemyActor(spec, i, config.depth, 0);
    return { ...a, id: `ally:${i}`, side: 'player' as const, kind: 'ally' as const, positionTag: 'left' };
  });
  const rng = new Rng('combat', config.seed);
  const rulesHash = hashString(stableStringify({ version: COMBAT_RULES_VERSION, tactics: config.tactics }));
  const state: CombatState = {
    seed: config.seed, depth: config.depth, biome: config.biome, nodeType: config.nodeType,
    timeMs: 0, maxDurationMs: config.maxDurationMs ?? DEFAULT_MAX_DURATION_MS,
    operator, drones, enemies, allies,
    rng: rng.serialize(), nextEventId: 1, log: [], logTruncated: false,
    metrics: emptyMetrics(), outcome: null,
    build: config.build, tactics: config.tactics, rulesHash,
    wantedDelta: 0, revealDelta: 0, recordLog: config.recordLog !== false,
    ambientHeatPerSec: config.ambientHeatPerSec ?? 0,
    coolingPenalty: config.coolingPenalty ?? 0,
    enemyWindupMult: config.enemyWindupMult ?? 1,
    elitePen: config.elitePen ?? 0,
    extraEnemyDigitalBonus: extraDigital,
  };
  emit(state, 'COMBAT_START', 'operator', { text: `Бой начался: ${enemies.map((e) => e.name).join(', ')}.` });
  return state;
}

/* ------------------------------------------------------------------ */
/* Служебные функции                                                   */
/* ------------------------------------------------------------------ */

export function allActors(state: CombatState): CombatActor[] {
  return [state.operator, ...state.drones, ...state.allies, ...state.enemies];
}

function livingEnemies(state: CombatState): CombatActor[] {
  return state.enemies.filter((e) => e.alive);
}

function livingPlayerSide(state: CombatState): CombatActor[] {
  return [state.operator, ...state.drones, ...state.allies].filter((a) => a.alive);
}

function actorById(state: CombatState, id: string): CombatActor | undefined {
  return allActors(state).find((a) => a.id === id);
}

function emit(
  state: CombatState,
  kind: CombatEventKind,
  actorId: string,
  extra: Partial<CombatEvent> = {},
): CombatEvent {
  const event: CombatEvent = {
    eventId: state.nextEventId++,
    timestamp: state.timeMs,
    kind, actorId,
    incomingTags: [], producedTags: [], chainDepth: 0,
    text: '',
    ...extra,
  };
  if (state.recordLog) {
    state.log.push(event);
    if (state.log.length > MAX_LOG_EVENTS) {
      state.log.splice(0, state.log.length - MAX_LOG_EVENTS);
      state.logTruncated = true;
    }
  }
  return event;
}

/* ------------------------------------------------------------------ */
/* Эффективные характеристики и статусы                                */
/* ------------------------------------------------------------------ */

export function statusStacks(actor: CombatActor, id: StatusId): number {
  const arr = actor.statuses[id];
  if (!arr) return 0;
  let n = 0;
  for (const e of arr) n += e.stacks;
  return n;
}

export function hasStatus(actor: CombatActor, id: StatusId): boolean {
  return (actor.statuses[id]?.length ?? 0) > 0;
}

function actorView(actor: CombatActor): ActorView {
  const s = actor.baseSheet;
  const statuses: Partial<Record<StatusId, number>> = {};
  for (const key of Object.keys(actor.statuses) as StatusId[]) statuses[key] = statusStacks(actor, key);
  return {
    hp: actor.hp, maxHP: s.maxHP, shield: actor.shield, maxShield: s.maxShield,
    energy: actor.energy, heat: actor.heat, statuses,
    isBoss: actor.isBoss, isMechanical: actor.isMechanical, isDrone: actor.kind === 'drone',
  };
}

function combatContext(state: CombatState, actor: CombatActor): StatContext {
  return {
    self: actorView(actor),
    enemiesAlive: actor.side === 'player' ? livingEnemies(state).length : livingPlayerSide(state).length,
    dronesAlive: state.drones.filter((d) => d.alive).length,
    timeMs: state.timeMs,
    heatLockout: actor.heatLockout,
    flags: actor.flags,
  };
}

/** Статусы, отображаемые в лист характеристик через единый pipeline. */
function statusMods(actor: CombatActor): Modifier[] {
  const out: Modifier[] = [];
  const src = (id: string, name: string) => ({ id, name, kind: 'status' as const });
  const ab = statusStacks(actor, 'ARMOR_BREAK');
  if (ab > 0) out.push(mod('armor', 'FLAT', -10 * ab, src('status:ARMOR_BREAK', 'Разлом брони'), { id: 'status:ARMOR_BREAK:armor' }));
  if (hasStatus(actor, 'GUARD')) out.push(mod('incomingKinetic', 'LESS', 0.2, src('status:GUARD', 'Дефлектор'), { id: 'status:GUARD:ink' }));
  const ov = statusStacks(actor, 'OVERCLOCK');
  if (ov > 0) out.push(mod('attackSpeed', 'INCREASED', 20 * ov, src('status:OVERCLOCK', 'Форсаж'), { id: 'status:OVERCLOCK:as' }));
  if (hasStatus(actor, 'ACC_BUFF')) out.push(mod('accuracy', 'FLAT', 8, src('status:ACC_BUFF', 'Пристрелка'), { id: 'status:ACC_BUFF:acc' }));
  if (hasStatus(actor, 'EVASION_BUFF')) out.push(mod('evasion', 'INCREASED', 20, src('status:EVASION_BUFF', 'Предвидение'), { id: 'status:EVASION_BUFF:eva' }));
  if (hasStatus(actor, 'SHIELD_REGEN_BUFF')) out.push(mod('shieldRegen', 'FLAT', 10, src('status:SHIELD_REGEN_BUFF', 'Щитовой отклик'), { id: 'status:SHIELD_REGEN_BUFF:regen' }));
  return out;
}

function buffMods(actor: CombatActor): Modifier[] {
  const out: Modifier[] = [];
  for (const b of actor.buffs) for (const m of b.mods) out.push(m);
  return out;
}

/**
 * Эффективный лист: базовые модификаторы + runtime + баффы + статусы,
 * пересчитанные тем же resolveStats с боевым контекстом. Кешируется по
 * fingerprint активных условий/стеков. Без runtime-надстроек — baseSheet.
 */
function eff(state: CombatState, actor: CombatActor): StatSheet {
  const hasExtras = actor.runtimeMods.length > 0 || actor.buffs.length > 0 || Object.keys(actor.statuses).length > 0;
  if (!hasExtras) return actor.baseSheet;
  const mods = [...actor.baseMods, ...actor.runtimeMods, ...buffMods(actor), ...statusMods(actor)];
  const ctx = combatContext(state, actor);
  const statusSig = (Object.keys(actor.statuses) as StatusId[]).sort().map((k) => `${k}:${statusStacks(actor, k)}`).join(',');
  const buffSig = actor.buffs.map((b) => `${b.id}x${b.stacks}`).sort().join(',');
  const rtSig = actor.runtimeMods.map((m) => m.id).sort().join(',');
  const fingerprint = `${conditionSignature(mods, ctx)}|${statusSig}|${buffSig}|${rtSig}`;
  if (actor.effSheet && actor.effFingerprint === fingerprint) return actor.effSheet;
  const sheet = sheetOf(resolveStats(bundle(mods), ctx));
  actor.effSheet = sheet;
  actor.effFingerprint = fingerprint;
  return sheet;
}

/** Публичный доступ к эффективному листу актора (Build Lab / тесты). */
export function effectiveSheet(state: CombatState, actor: CombatActor): StatSheet {
  return eff(state, actor);
}

function defenseOf(state: CombatState, actor: CombatActor): DefenseSnapshot {
  const s = eff(state, actor);
  return { armor: s.armor, energyRes: s.energyRes, digitalRes: s.digitalRes };
}

function penOf(state: CombatState, actor: CombatActor): PenetrationSnapshot {
  const s = eff(state, actor);
  return {
    armorPen: s.armorPen, armorPenPercent: s.armorPenPercent,
    energyPen: s.energyPen, energyPenPercent: s.energyPenPercent,
    digitalPen: s.digitalPen, digitalPenPercent: s.digitalPenPercent,
  };
}

/** Множитель исходящего урона оператора/дрона по типу и каналу. */
function outgoingMultiplier(state: CombatState, actor: CombatActor, type: DamageType, isMain: boolean): number {
  const s = eff(state, actor);
  const typeIncreased = type === 'KINETIC' ? s.kineticDamage : type === 'ENERGY' ? s.energyDamage : s.digitalDamage;
  let mult = (1 + typeIncreased / 100) * (1 + s.allDamage / 100);
  if (isMain) mult *= 1 + s.mainDamage / 100;
  if (actor.kind === 'drone') mult *= (1 + s.droneDamage / 100) * s.moreDrone;
  const typeMore = type === 'KINETIC' ? s.moreKinetic : type === 'ENERGY' ? s.moreEnergy : s.moreDigital;
  mult *= typeMore * s.moreDirect;
  if (isMain) mult *= s.moreMain;
  const berserk = statusStacks(actor, 'BERSERK');
  if (berserk > 0) mult *= 1 + 0.15 * berserk;
  if (hasStatus(actor, 'CONTROLLED')) mult *= 0.4;
  if (actor.kind === 'drone' && hasStatus(actor, 'DRONE_JAM')) mult *= 0.5;
  return mult;
}

function incomingMultiplier(state: CombatState, target: CombatActor, type: DamageType): number {
  const s = eff(state, target);
  const typeMult = type === 'KINETIC' ? s.incomingKinetic : type === 'ENERGY' ? s.incomingEnergy : s.incomingDigital;
  return s.incomingAll * typeMult;
}

/** Скорость действий: SHOCK −30%, DRONE_JAM у дрона −50%. */
function actionSpeedMult(actor: CombatActor): number {
  let m = 1;
  m *= 1 + Math.max(0, actor.flags.bossAttackSpeedBonus ?? 0);
  if (hasStatus(actor, 'SHOCK')) m *= 0.7;
  if (actor.kind === 'drone' && hasStatus(actor, 'DRONE_JAM')) m *= 0.5;
  return m;
}

export interface ApplyStatusOpts {
  stacks?: number;
  durationMs?: number;
  snapshot?: number;
  causeId?: number;
  actionId?: string;
}

/** Наложение статуса: snapshot DoT в момент наложения, независимые стеки/refresh, ICD STUN. */
export function applyStatus(state: CombatState, source: CombatActor, target: CombatActor, statusId: StatusId, opts: ApplyStatusOpts = {}): void {
  if (!target.alive) return;
  const def = STATUS_DEFS[statusId];
  if (!def) return;
  const srcSheet = eff(state, source);
  const stacks = Math.max(1, Math.floor(opts.stacks ?? 1));
  let duration = opts.durationMs ?? def.durationMs;
  if (def.tickMs) duration *= 1 + (srcSheet.dotDuration + (statusId === 'VIRUS' ? srcSheet.virusDuration : 0)) / 100;
  if (statusId === 'STUN') {
    if ((target.icds['STUN'] ?? 0) > state.timeMs) return;
    target.icds['STUN'] = state.timeMs + 3000;
    if (target.isBoss) duration *= 0.5;
  }
  let snapshot = 0;
  if (def.snapshotFrom === 'rawDamage') {
    snapshot = (opts.snapshot ?? 0) * (1 + (srcSheet.statusDamage + (statusId === 'BLEED' ? srcSheet.bleedDamage : 0)) / 100);
  } else if (def.snapshotFrom === 'techPower') {
    snapshot = srcSheet.techPower * (1 + srcSheet.statusDamage / 100) * (1 + srcSheet.virusDamage / 100);
  }
  let maxStacks = def.maxStacks;
  if (statusId === 'BLEED') maxStacks += Math.floor(srcSheet.bleedStackCap);
  if (statusId === 'VIRUS') maxStacks += Math.floor(srcSheet.virusStackCap);

  const arr = target.statuses[statusId] ?? (target.statuses[statusId] = []);
  if (def.independentStacks) {
    for (let i = 0; i < stacks; i++) {
      if (arr.length >= maxStacks) arr.shift();
      arr.push({
        sourceId: `${source.id}:${statusId}`, sourceActorId: source.id,
        expiresAt: state.timeMs + duration, nextTickAt: state.timeMs + (def.tickMs ?? duration),
        snapshot, stacks: 1,
      });
    }
  } else {
    const existing = arr[0];
    if (existing) {
      existing.stacks = clamp(existing.stacks + stacks, 1, maxStacks);
      existing.expiresAt = state.timeMs + duration;
      existing.sourceActorId = source.id;
      if (def.tickMs) existing.snapshot = snapshot;
    } else {
      arr.push({
        sourceId: `${source.id}:${statusId}`, sourceActorId: source.id,
        expiresAt: state.timeMs + duration, nextTickAt: state.timeMs + (def.tickMs ?? duration),
        snapshot, stacks: clamp(stacks, 1, maxStacks),
      });
    }
  }
  if (statusId === 'MARK') target.markBy = source.id;
  emit(state, 'STATUS_APPLY', source.id, {
    targetId: target.id, statusId, causeId: opts.causeId, actionId: opts.actionId,
    text: `${target.name}: ${def.name}${def.independentStacks ? ` ×${arr.length}` : ''}.`,
    data: { stacks: statusStacks(target, statusId), snapshot, durationMs: duration },
  });
}

const DOT_IDS: StatusId[] = ['BLEED', 'BURN', 'VIRUS'];

/** Периодический урон статусов: snapshot × доля × стеки, резисты цели на каждом тике, без crit/on-hit. */
function tickStatuses(state: CombatState): void {
  for (const actor of allActors(state)) {
    if (!actor.alive) continue;
    for (const id of DOT_IDS) {
      const arr = actor.statuses[id];
      if (!arr) continue;
      const def = STATUS_DEFS[id];
      if (!def.tickMs || !def.damageType) continue;
      for (const entry of arr) {
        if (entry.nextTickAt > state.timeMs) continue;
        entry.nextTickAt += def.tickMs;
        const raw = entry.snapshot * (def.tickFraction ?? 0) * entry.stacks;
        if (raw <= 0) continue;
        const mitigated = mitigatePacket(raw, def.damageType, defenseOf(state, actor), ZERO_PEN);
        const incoming = mitigated.afterDefense * incomingMultiplier(state, actor, def.damageType);
        const partition = partitionDamage(incoming, { hp: actor.hp, shield: actor.shield, temp: actor.tempShields }, 0, eff(state, actor).incomingShield);
        applyPartition(actor, partition);
        actor.flags.lastDamagedAt = state.timeMs;
        state.metrics.statusTicks++;
        const dealt = partition.shieldConsumed + partition.hpLost;
        actor.damageTaken += dealt;
        const source = actorById(state, entry.sourceActorId);
        if (source) source.damageDealt += dealt;
        if (source?.side === 'player') {
          state.metrics.damageDealt += dealt;
          state.metrics.damageByType[def.damageType] += incoming;
          state.metrics.damageBySource[entry.sourceActorId] = (state.metrics.damageBySource[entry.sourceActorId] ?? 0) + dealt;
          state.metrics.shieldAbsorbed += partition.shieldConsumed;
        } else {
          state.metrics.damageTaken += dealt;
          state.metrics.takenBySource[entry.sourceActorId] = (state.metrics.takenBySource[entry.sourceActorId] ?? 0) + dealt;
          if (actor.kind === 'operator') state.metrics.hpLost += partition.hpLost;
        }
        emit(state, 'DOT_TICK', entry.sourceActorId, {
          targetId: actor.id, statusId: id, damageType: def.damageType,
          amountBeforeDefense: raw, amountAfterDefense: incoming,
          shieldConsumed: partition.shieldConsumed, hpLost: partition.hpLost,
          text: `${def.name} → ${actor.name}: ${incoming.toFixed(1)} ${def.damageType}.`,
        });
      }
    }
  }
}

/** Истечение статусов/баффов/временных щитов (шаг 1 порядка событий). */
function expireStatuses(state: CombatState): void {
  for (const actor of allActors(state)) {
    for (const key of Object.keys(actor.statuses) as StatusId[]) {
      const arr = actor.statuses[key]!;
      const kept = arr.filter((e) => e.expiresAt > state.timeMs);
      if (kept.length !== arr.length) emit(state, 'STATUS_EXPIRE', actor.id, { statusId: key, text: `${actor.name}: ${STATUS_DEFS[key].name} истёк.` });
      if (kept.length) actor.statuses[key] = kept; else delete actor.statuses[key];
    }
    if (actor.buffs.some((b) => b.expiresAt <= state.timeMs)) actor.buffs = actor.buffs.filter((b) => b.expiresAt > state.timeMs);
    if (actor.tempShields.some((p) => p.expiresAt <= state.timeMs)) {
      for (const p of actor.tempShields) {
        if (p.expiresAt <= state.timeMs) emit(state, 'SHIELD_EXPIRE', actor.id, { text: `${actor.name}: временный щит истёк.`, data: { sourceId: p.sourceId, amount: p.amount } });
      }
      actor.tempShields = actor.tempShields.filter((p) => p.expiresAt > state.timeMs);
    }
  }
}

/* ------------------------------------------------------------------ */
/* Непрерывные ресурсы (ровно один раз за тик, до событий)             */
/* ------------------------------------------------------------------ */

function applyContinuous(state: CombatState, dtSec: number): void {
  const op = state.operator;
  if (op.alive) {
    const s = eff(state, op);
    op.energy = clamp(op.energy + s.energyRegen * dtSec, 0, s.maxEnergy);
    const cooling = Math.max(0, s.heatCooling - state.coolingPenalty);
    const bossAmbient = state.enemies.filter((enemy) => enemy.alive && enemy.isBoss)
      .reduce((total, enemy) => total + ((enemyTemplate(enemy.templateId) as BossTemplate).ambientHeatPerSec ?? 0), 0);
    const ambient = state.ambientHeatPerSec + bossAmbient;
    const before = op.heat;
    op.heat = clamp(op.heat + (ambient - cooling) * dtSec, 0, s.maxHeat);
    if (!op.heatLockout && before < s.maxHeat && op.heat >= s.maxHeat) {
      op.heatLockout = true;
      state.metrics.heatLockouts++;
      emit(state, 'HEAT_LOCKOUT', op.id, { text: 'Перегрев: main-канал заблокирован до охлаждения ≤ 80.' });
    }
    if (op.heatLockout && op.heat <= HEAT_LOCKOUT_RELEASE) {
      op.heatLockout = false;
      emit(state, 'HEAT_LOCKOUT_END', op.id, { text: 'Перегрев снят.' });
    }
    if (op.heatLockout) state.metrics.heatLockoutMs += dtSec * 1000;
    const sinceHit = state.timeMs - (op.flags.lastDamagedAt ?? -100000);
    const regen = s.shieldRegen * (hasStatus(op, 'SHIELD_LEAK') ? 0.7 : 1);
    if (sinceHit >= SHIELD_REGEN_DELAY_MS && regen > 0 && op.shield < s.maxShield) {
      op.shield = clamp(op.shield + regen * dtSec, 0, s.maxShield);
    }
    if (op.shield <= 0) state.metrics.timeWithoutShieldMs += dtSec * 1000;
    state.metrics.lowestHpFraction = Math.min(state.metrics.lowestHpFraction, op.hp / Math.max(1, s.maxHP));
  }
  for (const actor of [...state.drones, ...state.enemies, ...state.allies]) {
    if (!actor.alive) continue;
    const s = eff(state, actor);
    const sinceHit = state.timeMs - (actor.flags.lastDamagedAt ?? -100000);
    const regen = s.shieldRegen * (hasStatus(actor, 'SHIELD_LEAK') ? 0.7 : 1);
    if (sinceHit >= SHIELD_REGEN_DELAY_MS && regen > 0 && actor.shield < s.maxShield) {
      actor.shield = clamp(actor.shield + regen * dtSec, 0, s.maxShield);
    }
  }
}

/* ------------------------------------------------------------------ */
/* Разрешение атак                                                     */
/* ------------------------------------------------------------------ */

interface AttackPacket {
  type: DamageType;
  amount: number;
  procWeight: number;
}

function attackPackets(state: CombatState, actor: CombatActor): AttackPacket[] {
  if (actor.kind === 'operator') {
    const w = state.build.mainWeapon!;
    if (w.packets && w.packets.length) {
      return w.packets.map((p) => ({ type: p.type, amount: p.amount, procWeight: p.procWeight ?? w.procWeight ?? 1 }));
    }
    const count = w.pelletCount ?? 1;
    const weight = w.pelletProcWeight ?? w.procWeight ?? 1;
    return Array.from({ length: count }, () => ({ type: w.type, amount: w.damage, procWeight: weight }));
  }
  return [{ type: actor.attackType, amount: actor.attackDamage, procWeight: 1 }];
}

function pickAutoTarget(state: CombatState, actor: CombatActor): CombatActor | undefined {
  if (actor.side === 'enemy') {
    return state.operator.alive ? state.operator : livingPlayerSide(state)[0];
  }
  return livingEnemies(state)[0];
}

interface HitOptions {
  actionId: string;
  isMain: boolean;
  procWeight: number;
  skillId?: string;
  penOverride?: PenetrationSnapshot;
  bypassShieldRatio?: number;
  abilityId?: string;
}

/**
 * Единый конвейер попадания (раздел 6): roll hit → roll crit → raw → защита
 * пакета → incoming-множители → щиты → HP. Возвращает raw до защиты при
 * попадании и −1 при промахе. Используется и автоатакой, и умениями.
 */
function applyHit(state: CombatState, rng: Rng, actor: CombatActor, target: CombatActor, baseRaw: number, type: DamageType, opts: HitOptions): number {
  const as = eff(state, actor);
  const ds = eff(state, target);
  const skillTag = opts.skillId ? { skillId: opts.skillId } : {};
  let accuracy = as.accuracy;
  if (actor.kind === 'drone' && hasStatus(target, 'DRONE_MARK')) accuracy += 15;
  const hitChance = pHit(accuracy, ds.evasion);
  if (!rng.chance(hitChance)) {
    state.metrics.misses++;
    if (target.kind === 'operator') state.metrics.dodgesTaken++;
    emit(state, 'MISS', actor.id, { targetId: target.id, actionId: opts.actionId, ...skillTag, damageType: type, text: `${actor.name}: промах по ${target.name}.`, roll: hitChance });
    return -1;
  }
  const crit = rng.chance(pCrit(as.critChance));
  let raw = baseRaw * outgoingMultiplier(state, actor, type, opts.isMain);
  if (actor.side === 'enemy' && type === 'DIGITAL') raw *= 1 + state.extraEnemyDigitalBonus;
  if (hasStatus(target, 'SCAN_MARK')) raw *= 1.12;
  if (crit) {
    raw *= as.critMultiplier * as.moreCritDamage;
    state.metrics.crits++;
  }
  raw = finite(raw, 0);
  const mitigated = mitigatePacket(raw, type, defenseOf(state, target), opts.penOverride ?? penOf(state, actor));
  let incoming = mitigated.afterDefense * incomingMultiplier(state, target, type);
  if (hasStatus(target, 'MARK')) {
    incoming *= 1.3;
    delete target.statuses.MARK;
    target.markBy = undefined;
  }
  const partition = partitionDamage(incoming, { hp: target.hp, shield: target.shield, temp: target.tempShields }, opts.bypassShieldRatio ?? 0, ds.incomingShield);
  applyPartition(target, partition);
  target.flags.lastDamagedAt = state.timeMs;
  state.metrics.hits++;
  const dealt = partition.shieldConsumed + partition.hpLost;
  actor.damageDealt += dealt;
  target.damageTaken += dealt;
  if (actor.side === 'player') {
    state.metrics.damageDealt += dealt;
    state.metrics.damageByType[type] += incoming;
    state.metrics.damageBySource[actor.id] = (state.metrics.damageBySource[actor.id] ?? 0) + dealt;
    state.metrics.shieldAbsorbed += partition.shieldConsumed;
  } else {
    state.metrics.damageTaken += dealt;
    state.metrics.takenBySource[actor.id] = (state.metrics.takenBySource[actor.id] ?? 0) + dealt;
    if (target.kind === 'operator') state.metrics.hpLost += partition.hpLost;
  }
  emit(state, 'DAMAGE', actor.id, {
    targetId: target.id, actionId: opts.actionId, ...skillTag, damageType: type, crit,
    amountBeforeDefense: raw, amountAfterDefense: incoming,
    shieldConsumed: partition.shieldConsumed, hpLost: partition.hpLost, bypassed: partition.bypassed,
    text: `${actor.name} → ${target.name}: ${incoming.toFixed(1)} ${type}${crit ? ' (крит)' : ''}, щит −${partition.shieldConsumed.toFixed(1)}, HP −${partition.hpLost.toFixed(1)}.`,
    data: { overkill: partition.overkill, ...(opts.abilityId ? { abilityId: opts.abilityId } : {}) },
  });
  return raw;
}

function resolveAttack(state: CombatState, rng: Rng, actor: CombatActor): void {
  const target = pickAutoTarget(state, actor);
  if (!target) return;
  const isOperator = actor.kind === 'operator';
  const weapon = isOperator ? state.build.mainWeapon! : null;
  const as = eff(state, actor);
  if (isOperator) {
    if (actor.heatLockout) return;
    const energyCost = weapon!.energyPerAttack ?? 0;
    if (energyCost > 0 && actor.energy < energyCost) {
      state.metrics.energyStarvedMs += TICK_MS;
      return;
    }
    if (energyCost > 0) {
      actor.energy = clamp(actor.energy - energyCost, 0, as.maxEnergy);
      state.metrics.energySpent += energyCost;
    }
    let heatGain = weapon!.heatPerAttack ?? 0;
    if (hasStatus(actor, 'OVERCLOCK')) heatGain += 5;
    if (heatGain > 0) actor.heat = clamp(actor.heat + heatGain, 0, as.maxHeat);
  }
  actor.counters.attacks = (actor.counters.attacks ?? 0) + 1;
  const actionId = `${actor.id}:atk:${actor.counters.attacks}`;
  actor.lastMainAttackAt = state.timeMs;
  emit(state, 'ATTACK', actor.id, { targetId: target.id, actionId, text: `${actor.name} атакует ${target.name}.` });

  const packets = attackPackets(state, actor);
  const isMain = actor.kind === 'operator';
  for (const packet of packets) {
    const current = pickAutoTarget(state, actor);
    if (!current) return;
    applyHit(state, rng, actor, current, packet.amount, packet.type, { actionId, isMain, procWeight: packet.procWeight });
  }
}

function applyPartition(actor: CombatActor, partition: ReturnType<typeof partitionDamage>): void {
  for (const consumed of partition.tempConsumed) {
    const pool = actor.tempShields.find((p) => p.sourceId === consumed.sourceId);
    if (pool) pool.amount = Math.max(0, pool.amount - consumed.amount);
  }
  actor.tempShields = actor.tempShields.filter((p) => p.amount > 0);
  const regularConsumed = partition.shieldConsumed - partition.tempConsumed.reduce((s, c) => s + c.amount, 0);
  actor.shield = Math.max(0, actor.shield - regularConsumed);
  actor.hp = Math.max(0, actor.hp - partition.hpLost);
}

function scheduleNextAttack(state: CombatState, actor: CombatActor): void {
  let interval = actor.attackIntervalMs;
  if (actor.kind === 'operator') {
    const s = eff(state, actor);
    interval = attackIntervalMs(state.build.mainWeapon!.intervalMs, s.attackSpeed, s.moreAttackSpeed);
  }
  interval /= actionSpeedMult(actor);
  actor.nextAttackAt += interval;
  if (actor.nextAttackAt <= state.timeMs) actor.nextAttackAt = state.timeMs + interval;
}

/* ------------------------------------------------------------------ */
/* Тактические правила и таргетинг (раздел 8)                          */
/* ------------------------------------------------------------------ */

function byId(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function skillChannel(skillId: string): Channel | null {
  return SKILL_BY_ID[skillId]?.channel ?? null;
}

function equippedSkill(state: CombatState, skillId: string): SkillDef | undefined {
  return state.build.skills.find((s) => s.id === skillId);
}

/** Стоимость энергии программы с учётом скидок (раздел 11/14). Снимается на старте каста. */
function skillEnergyCost(state: CombatState, actor: CombatActor, skill: SkillDef): number {
  const s = eff(state, actor);
  let cost = skill.energyCost;
  if (cost <= 0) return 0;
  if (skill.basis === 'TECH_E') cost = Math.max(1, cost - s.energySkillCostFlat);
  if (skill.id === 'SK_EMP') cost = Math.max(1, cost - s.empCostFlat);
  if (skill.id === 'SK_SHIELD') cost = Math.max(1, cost - s.shieldCostFlat);
  cost *= 1 - clamp(s.skillEnergyCostLess, 0, 60) / 100;
  if (skill.channel === 'reaction') cost *= 1 + s.reactionCostMore / 100;
  return Math.max(0, cost);
}

/** Cooldown реакции: LESS к базе (reactionCooldownLess), затем общая формула восстановления. */
function reactionCooldownMs(skill: SkillDef, s: StatSheet): number {
  const base = skill.cooldownMs * (1 - clamp(s.reactionCooldownLess, 0, 80) / 100);
  return cooldownMs(base, s.cooldownRecovery);
}

/** Изменение нагрева с проверкой пересечения порога перегрева и снятия lockout. */
function gainHeat(state: CombatState, actor: CombatActor, amount: number): void {
  if (amount === 0) return;
  const s = eff(state, actor);
  const before = actor.heat;
  actor.heat = clamp(actor.heat + amount, 0, s.maxHeat);
  if (amount > 0 && !actor.heatLockout && before < s.maxHeat && actor.heat >= s.maxHeat) {
    actor.heatLockout = true;
    state.metrics.heatLockouts++;
    emit(state, 'HEAT_LOCKOUT', actor.id, { text: 'Перегрев: main-канал заблокирован до охлаждения ≤ 80.' });
  }
  if (actor.heatLockout && actor.heat <= HEAT_LOCKOUT_RELEASE) {
    actor.heatLockout = false;
    emit(state, 'HEAT_LOCKOUT_END', actor.id, { text: 'Перегрев снят.' });
  }
}

/** Выбор цели по селектору; недоступная цель → первый живой враг по stable actorId. */
function selectTarget(state: CombatState, actor: CombatActor, mode: TargetMode): CombatActor | undefined {
  if (mode === 'self') return actor;
  const enemies = livingEnemies(state).sort((a, b) => byId(a.id, b.id));
  if (!enemies.length) return undefined;
  const fallback = enemies[0]!;
  switch (mode) {
    case 'target':
      return (actor.lastTargetId ? enemies.find((e) => e.id === actor.lastTargetId) : undefined) ?? fallback;
    case 'lowestHPPercent':
      return [...enemies].sort((a, b) => (a.hp / Math.max(1, a.baseSheet.maxHP)) - (b.hp / Math.max(1, b.baseSheet.maxHP)) || byId(a.id, b.id))[0];
    case 'marked':
      return enemies.find((e) => hasStatus(e, 'MARK') || hasStatus(e, 'SCAN_MARK') || hasStatus(e, 'DRONE_MARK')) ?? fallback;
    case 'healer':
      return enemies.find((e) => e.isHealer) ?? fallback;
    case 'imminentCast':
      return enemies.find((e) => e.cast && e.cast.interruptible) ?? fallback;
    case 'boss':
      return enemies.find((e) => e.isBoss) ?? fallback;
    case 'infected':
      return enemies.find((e) => hasStatus(e, 'VIRUS')) ?? fallback;
    case 'secondary':
    case 'otherEnemy':
      return enemies.find((e) => e.id !== actor.lastTargetId) ?? fallback;
    case 'nearest':
    case 'allEnemies':
    case 'attacker':
    default:
      return fallback;
  }
}

function selectSkillTargets(state: CombatState, actor: CombatActor, skill: SkillDef): CombatActor[] {
  const enemies = livingEnemies(state).sort((a, b) => byId(a.id, b.id));
  if (skill.targetMode === 'allEnemies') return enemies.slice(0, skill.maxTargets ?? enemies.length);
  const primary = selectTarget(state, actor, skill.targetMode);
  return primary ? [primary] : [];
}

function evalTacticCondition(state: CombatState, actor: CombatActor, c: TacticCondition, target?: CombatActor): boolean {
  switch (c.kind) {
    case 'always': return true;
    case 'hpBelow': return actor.hp / Math.max(1, actor.baseSheet.maxHP) < c.value;
    case 'hpAbove': return actor.hp / Math.max(1, actor.baseSheet.maxHP) > c.value;
    case 'shieldBelow': return actor.baseSheet.maxShield <= 0 || actor.shield / actor.baseSheet.maxShield < c.value;
    case 'energyAtLeast': return actor.energy >= c.value;
    case 'energyBelow': return actor.energy < c.value;
    case 'heatAtLeast': return actor.heat >= c.value;
    case 'heatBelow': return actor.heat < c.value;
    case 'heatLocked': return actor.heatLockout;
    case 'enemiesAtLeast': return livingEnemies(state).length >= c.value;
    case 'enemiesAtMost': return livingEnemies(state).length <= c.value;
    case 'enemyCasting': return livingEnemies(state).some((e) => e.cast && (!c.interruptibleOnly || e.cast.interruptible));
    case 'enemyType': return livingEnemies(state).some((e) => (c.value === 'boss' ? e.isBoss : c.value === 'healer' ? e.isHealer : c.value === 'mechanical' ? e.isMechanical : !!e.eliteMod));
    case 'targetStatus': return !!target && statusStacks(target, c.status) >= (c.minStacks ?? 1);
    case 'droneAlive': return state.drones.filter((d) => d.alive).length >= c.value;
    case 'cooldownReady': return (actor.cooldowns[c.skillId] ?? 0) <= state.timeMs;
    case 'effectUptime': return hasStatus(actor, c.status);
    case 'timeAtLeast': return state.timeMs >= c.value;
    case 'not': return !evalTacticCondition(state, actor, c.inner, target);
    case 'any': return c.inner.some((x) => evalTacticCondition(state, actor, x, target));
    case 'all': return c.inner.every((x) => evalTacticCondition(state, actor, x, target));
  }
}

function ruleConditionsPass(state: CombatState, actor: CombatActor, rule: TacticRule, target?: CombatActor): boolean {
  if (!rule.conditions.length) return true;
  return rule.logic === 'OR'
    ? rule.conditions.some((c) => evalTacticCondition(state, actor, c, target))
    : rule.conditions.every((c) => evalTacticCondition(state, actor, c, target));
}

/** Диагностика отказа правила: агрегируется по (ruleId, reason), событие — один раз. */
function recordRuleFail(state: CombatState, ruleId: string, reason: string): void {
  const existing = state.metrics.ruleFailures.find((f) => f.ruleId === ruleId && f.reason === reason);
  if (existing) { existing.count++; return; }
  state.metrics.ruleFailures.push({ ruleId, reason, count: 1, firstAt: state.timeMs });
  emit(state, 'RULE_FAIL', 'operator', { reason, text: `Правило ${ruleId}: ${reason}.`, data: { ruleId } });
}

type MainChoice = { kind: 'auto' } | { kind: 'skill'; skill: SkillDef; target: CombatActor | undefined; rule: TacticRule };

/** Первое валидное правило main-канала по приоритету и stable ruleId; иначе AUTO. */
function selectMainRule(state: CombatState, actor: CombatActor): MainChoice {
  const rules = state.tactics.rules
    .filter((r) => r.enabled && (r.skillId === 'AUTO' || skillChannel(r.skillId) === 'main'))
    .sort((a, b) => b.priority - a.priority || byId(a.id, b.id));
  for (const rule of rules) {
    if (rule.skillId === 'AUTO') {
      if (ruleConditionsPass(state, actor, rule)) return { kind: 'auto' };
      recordRuleFail(state, rule.id, 'conditions');
      continue;
    }
    const skill = equippedSkill(state, rule.skillId);
    if (!skill) { recordRuleFail(state, rule.id, 'not_equipped'); continue; }
    if ((actor.cooldowns[skill.id] ?? 0) > state.timeMs) { recordRuleFail(state, rule.id, 'cooldown'); continue; }
    if (actor.energy < skillEnergyCost(state, actor, skill)) { recordRuleFail(state, rule.id, 'energy'); continue; }
    const target = selectTarget(state, actor, rule.target);
    if (!target && skill.targetMode !== 'self') { recordRuleFail(state, rule.id, 'no_target'); continue; }
    if (skill.requires?.includes('VIRUS') && (!target || !hasStatus(target, 'VIRUS'))) { recordRuleFail(state, rule.id, 'requirement'); continue; }
    if (!ruleConditionsPass(state, actor, rule, target)) { recordRuleFail(state, rule.id, 'conditions'); continue; }
    return { kind: 'skill', skill, target, rule };
  }
  return { kind: 'auto' };
}

/* ------------------------------------------------------------------ */
/* Касты активных умений (Windup → Resolve → Recovery → Ready)         */
/* ------------------------------------------------------------------ */

function startSkillCast(state: CombatState, actor: CombatActor, skill: SkillDef, target: CombatActor | undefined): void {
  const s = eff(state, actor);
  const cost = skillEnergyCost(state, actor, skill);
  actor.energy = clamp(actor.energy - cost, 0, s.maxEnergy);
  state.metrics.energySpent += cost;
  gainHeat(state, actor, skill.heatDelta);
  const cd = skill.channel === 'reaction' ? reactionCooldownMs(skill, s) : cooldownMs(skill.cooldownMs, s.cooldownRecovery);
  actor.cooldowns[skill.id] = state.timeMs + cd;
  actor.counters.casts = (actor.counters.casts ?? 0) + 1;
  const actionId = `${actor.id}:skill:${skill.id}:${actor.counters.casts}`;
  const cast: CastState = {
    actionId, skillId: skill.id, startedAt: state.timeMs,
    resolveAt: state.timeMs + skill.windupMs, endAt: state.timeMs + skill.windupMs + skill.recoveryMs,
    targetId: target?.id ?? null, interruptible: skill.interruptible, telegraph: false, channel: skill.channel,
  };
  if (skill.channel === 'reaction') actor.reactionCast = cast;
  else actor.cast = cast;
  actor.lastSkillId = skill.id;
  if (target) actor.lastTargetId = target.id;
  if (skill.channel === 'main') actor.nextAttackAt = cast.endAt;
  emit(state, 'CAST_START', actor.id, {
    skillId: skill.id, targetId: target?.id, actionId,
    text: `${actor.name}: ${skill.name}.`,
    data: { channel: skill.channel, windupMs: skill.windupMs, recoveryMs: skill.recoveryMs, cooldownMs: cd },
  });
  if (cast.telegraph) {
    emit(state, 'TELEGRAPH', actor.id, {
      skillId: skill.id, targetId: target?.id, actionId,
      text: `${actor.name} готовит ${skill.name}.`,
      data: { dangerTag: cast.dangerTag ?? '', windupMs: skill.windupMs },
    });
  }
}

function castTarget(state: CombatState, actor: CombatActor, cast: CastState): CombatActor | undefined {
  if (cast.targetId) {
    const t = actorById(state, cast.targetId);
    if (t && t.alive) return t;
  }
  const skill = cast.skillId ? SKILL_BY_ID[cast.skillId] : undefined;
  if (skill?.targetMode === 'self') return actor;
  return livingEnemies(state).sort((a, b) => byId(a.id, b.id))[0];
}

function actorAbilities(actor: CombatActor): EnemyAbility[] {
  const template = enemyTemplate(actor.templateId);
  return [...template.abilities, ...('rotating' in template ? template.rotating ?? [] : [])];
}

function isScheduledAbility(ability: EnemyAbility): boolean {
  if (['heavyAttack', 'heal', 'heat', 'shieldRestore', 'mark', 'shieldBypass'].includes(ability.kind)) return true;
  // Zero-time applyStatus entries encode event-driven effects (on hit/death), not timed casts.
  return ability.kind === 'applyStatus' && (ability.firstAtMs > 0 || ability.everyMs > 0);
}

function readyEnemyAbility(state: CombatState, actor: CombatActor): EnemyAbility | undefined {
  return actorAbilities(actor)
    .filter((ability) => isScheduledAbility(ability) && (actor.abilityNext[ability.id] ?? Number.MAX_SAFE_INTEGER) <= state.timeMs)
    .sort((a, b) => (actor.abilityNext[a.id] ?? 0) - (actor.abilityNext[b.id] ?? 0) || byId(a.id, b.id))[0];
}

function startEnemyAbility(state: CombatState, actor: CombatActor, ability: EnemyAbility): void {
  const castSpeed = Math.max(0, actor.flags.bossCastSpeedIncrease ?? 0);
  const windup = Math.max(0, ability.windupMs * state.enemyWindupMult / (1 + castSpeed));
  actor.counters.abilities = (actor.counters.abilities ?? 0) + 1;
  const actionId = `${actor.id}:ability:${ability.id}:${actor.counters.abilities}`;
  const cast: CastState = {
    actionId, skillId: null, startedAt: state.timeMs,
    resolveAt: state.timeMs + windup, endAt: state.timeMs + windup,
    targetId: state.operator.alive ? state.operator.id : null,
    interruptible: ability.interruptible, telegraph: ability.telegraphMs > 0,
    dangerTag: ability.kind, channel: 'main', abilityId: ability.id,
  };
  actor.cast = cast;
  const intervalMult = Math.max(0.01, actor.flags.bossAbilityIntervalMultiplier ?? 1);
  actor.abilityNext[ability.id] = ability.everyMs > 0 ? state.timeMs + ability.everyMs * intervalMult : Number.MAX_SAFE_INTEGER;
  actor.nextAttackAt = Math.max(actor.nextAttackAt, cast.endAt);
  emit(state, 'CAST_START', actor.id, {
    targetId: cast.targetId ?? undefined, actionId,
    text: `${actor.name} готовит: ${ability.desc}`,
    data: { abilityId: ability.id, windupMs: windup, interruptible: ability.interruptible },
  });
  if (cast.telegraph) emit(state, 'TELEGRAPH', actor.id, {
    targetId: cast.targetId ?? undefined, actionId,
    text: `${actor.name}: ${ability.desc}`,
    data: { abilityId: ability.id, dangerTag: ability.kind, windupMs: windup },
  });
}

const MAX_SUMMONED_ENEMIES = 2;

function spawnSummonedEnemy(state: CombatState, owner: CombatActor, templateId: string): CombatActor | undefined {
  const livingSummons = state.enemies.filter((enemy) => enemy.alive && enemy.summoned).length;
  if (livingSummons >= MAX_SUMMONED_ENEMIES) {
    emit(state, 'CAST_FIZZLE', owner.id, { reason: 'summon_cap', text: `${owner.name}: лимит призывов достигнут.`, data: { templateId, summonCap: MAX_SUMMONED_ENEMIES } });
    return undefined;
  }
  if (!enemyTemplate(templateId)) {
    emit(state, 'CAST_FIZZLE', owner.id, { reason: 'unknown_summon', text: `${owner.name}: неизвестный призыв ${templateId}.` });
    return undefined;
  }
  const summon = createEnemyActor({ templateId, summoned: true, noLoot: true }, state.enemies.length, state.depth, state.extraEnemyDigitalBonus);
  summon.id = `enemy:${state.enemies.length}`;
  summon.ownerId = owner.id;
  summon.nextAttackAt = state.timeMs + summon.attackIntervalMs;
  state.enemies.push(summon);
  emit(state, 'SUMMON', owner.id, {
    targetId: summon.id, text: `${owner.name} вызывает ${summon.name}.`,
    data: { templateId, hp: summon.hp, noLoot: true },
  });
  return summon;
}

function addBossAttackSpeed(state: CombatState, actor: CombatActor, amount: number): void {
  actor.flags ??= {};
  const previous = actor.flags.bossAttackSpeedBonus ?? 0;
  const current = previous + amount;
  actor.flags.bossAttackSpeedBonus = current;
  if (actor.nextAttackAt > state.timeMs) {
    actor.nextAttackAt = state.timeMs + (actor.nextAttackAt - state.timeMs) * (1 + previous) / (1 + current);
  }
}

function applyBossPhase(state: CombatState, actor: CombatActor, phase: BossPhaseTrigger, phaseIndex: number): void {
  actor.flags ??= {};
  emit(state, 'PHASE', actor.id, {
    text: `${actor.name}: ${phase.desc}`,
    data: { phaseIndex, hpFraction: phase.hpFraction, phaseKind: phase.kind },
  });
  const amount = phase.amount ?? 0;
  switch (phase.kind) {
    case 'summon':
      if (phase.summonId) spawnSummonedEnemy(state, actor, phase.summonId);
      break;
    case 'attackSpeed':
      addBossAttackSpeed(state, actor, amount);
      break;
    case 'intervalReduce':
      if (phase.target === 'abilities') {
        const previous = Math.max(0.01, actor.flags.bossAbilityIntervalMultiplier ?? 1);
        const current = Math.max(0.01, previous * (1 - clamp(amount, 0, 0.95)));
        actor.flags.bossAbilityIntervalMultiplier = current;
        for (const [abilityId, nextAt] of Object.entries(actor.abilityNext)) {
          if (nextAt > state.timeMs && nextAt < Number.MAX_SAFE_INTEGER) {
            actor.abilityNext[abilityId] = state.timeMs + (nextAt - state.timeMs) * current / previous;
          }
        }
      } else {
        addBossAttackSpeed(state, actor, amount);
      }
      break;
    case 'castSpeed': {
      const previous = Math.max(0, actor.flags.bossCastSpeedIncrease ?? 0);
      const current = previous + amount;
      actor.flags.bossCastSpeedIncrease = current;
      if (actor.cast && !actor.cast.resolved && actor.cast.resolveAt > state.timeMs) {
        const factor = (1 + previous) / (1 + current);
        actor.cast.resolveAt = state.timeMs + (actor.cast.resolveAt - state.timeMs) * factor;
        actor.cast.endAt = state.timeMs + (actor.cast.endAt - state.timeMs) * factor;
      }
      break;
    }
    case 'bypassUpgrade':
      actor.flags.digitalShieldBypassBonus = (actor.flags.digitalShieldBypassBonus ?? 0) + amount;
      break;
    case 'cleanse':
      for (const statusId of Object.keys(actor.statuses) as StatusId[]) {
        if (!STATUS_DEFS[statusId]?.harmful) continue;
        delete actor.statuses[statusId];
        emit(state, 'STATUS_EXPIRE', actor.id, { statusId, text: `${actor.name}: ${STATUS_DEFS[statusId].name} очищен фазой.` });
      }
      break;
  }
}

function resolveBossPhases(state: CombatState): void {
  const bosses = state.enemies.filter((enemy) => enemy.alive && enemy.isBoss).sort((a, b) => byId(a.id, b.id));
  for (const actor of bosses) {
    if (actor.hp <= 0) continue;
    const template = enemyTemplate(actor.templateId);
    if (!('phases' in template)) continue;
    const hpFraction = actor.hp / Math.max(1, actor.baseSheet.maxHP);
    const phases = template.phases.map((phase, phaseIndex) => ({ phase, phaseIndex }))
      .sort((a, b) => b.phase.hpFraction - a.phase.hpFraction || a.phaseIndex - b.phaseIndex);
    for (const { phase, phaseIndex } of phases) {
      const flag = `bossPhase:${phaseIndex}`;
      if (actor.flags[flag] || hpFraction > phase.hpFraction) continue;
      actor.flags[flag] = 1;
      applyBossPhase(state, actor, phase, phaseIndex);
    }
  }
}

function resolveEnemyAbility(state: CombatState, rng: Rng, actor: CombatActor, cast: CastState): void {
  const ability = actorAbilities(actor).find((a) => a.id === cast.abilityId);
  if (!ability) {
    emit(state, 'CAST_FIZZLE', actor.id, { actionId: cast.actionId, reason: 'unknown_ability', text: `${actor.name}: неизвестное действие.` });
    return;
  }
  const abilityEvent = (text: string, target?: CombatActor) => emit(state, 'TRIGGER', actor.id, {
    targetId: target?.id, actionId: cast.actionId, text,
    data: { abilityId: ability.id, abilityKind: ability.kind },
  });
  const playerTarget = (preferredId?: string): CombatActor | undefined => {
    const party = livingPlayerSide(state).sort((a, b) => byId(a.id, b.id));
    return (preferredId ? party.find((a) => a.id === preferredId) : undefined) ?? party[0];
  };

  switch (ability.kind) {
    case 'heavyAttack':
    case 'shieldBypass': {
      const target = playerTarget(cast.targetId ?? undefined);
      if (!target) {
        emit(state, 'CAST_FIZZLE', actor.id, { actionId: cast.actionId, reason: 'no_target', text: `${actor.name}: цель недоступна.` });
        return;
      }
      const type = ability.damageType ?? actor.attackType;
      const base = ability.damage ?? actor.attackDamage;
      const phaseBypass = type === 'DIGITAL' ? actor.flags.digitalShieldBypassBonus ?? 0 : 0;
      const raw = applyHit(state, rng, actor, target, base, type, {
        actionId: cast.actionId, isMain: false, procWeight: 0,
        bypassShieldRatio: (ability.bypassShieldRatio ?? (ability.kind === 'shieldBypass' ? ability.amount ?? 0 : 0)) + phaseBypass,
        abilityId: ability.id,
      });
      if (raw >= 0 && ability.status) applyStatus(state, actor, target, ability.status, { stacks: 1, durationMs: ability.statusDurationMs, snapshot: raw, actionId: cast.actionId });
      break;
    }
    case 'applyStatus': {
      const targets = ability.status === 'DRONE_JAM'
        ? state.drones.filter((drone) => drone.alive).sort((a, b) => byId(a.id, b.id))
        : [playerTarget(cast.targetId ?? undefined)].filter((target): target is CombatActor => !!target);
      if (!targets.length) {
        emit(state, 'CAST_FIZZLE', actor.id, { actionId: cast.actionId, reason: 'no_target', text: `${actor.name}: цель недоступна.` });
        return;
      }
      for (const target of targets) applyStatus(state, actor, target, ability.status!, { stacks: 1, durationMs: ability.statusDurationMs, actionId: cast.actionId });
      abilityEvent(`${actor.name}: ${ability.desc}`, targets[0]);
      break;
    }
    case 'heat': {
      const target = playerTarget();
      if (!target) return;
      const amount = ability.amount ?? 0;
      gainHeat(state, target, amount);
      emit(state, 'HEAT', actor.id, { targetId: target.id, actionId: cast.actionId, text: `${target.name}: нагрев +${amount}.`, data: { abilityId: ability.id, amount } });
      abilityEvent(`${actor.name}: ${ability.desc}`, target);
      break;
    }
    case 'mark': {
      const target = playerTarget();
      if (!target || !ability.status) return;
      applyStatus(state, actor, target, ability.status, { stacks: 1, durationMs: ability.statusDurationMs, actionId: cast.actionId });
      abilityEvent(`${actor.name}: ${ability.desc}`, target);
      break;
    }
    case 'heal': {
      const ally = [actor, ...state.enemies].filter((candidate) => candidate.alive)
        .sort((a, b) => a.hp / Math.max(1, eff(state, a).maxHP) - b.hp / Math.max(1, eff(state, b).maxHP) || byId(a.id, b.id))[0];
      if (!ally) return;
      const before = ally.hp;
      ally.hp = clamp(ally.hp + (ability.amount ?? 0), 0, eff(state, ally).maxHP);
      const healed = ally.hp - before;
      emit(state, 'HEAL', actor.id, { targetId: ally.id, actionId: cast.actionId, text: `${actor.name} восстанавливает ${healed.toFixed(1)} HP: ${ally.name}.`, data: { abilityId: ability.id, amount: healed } });
      break;
    }
    case 'shieldRestore': {
      const before = actor.shield;
      actor.shield = clamp(actor.shield + (ability.amount ?? 0), 0, eff(state, actor).maxShield);
      emit(state, 'SHIELD_GAIN', actor.id, { actionId: cast.actionId, text: `${actor.name}: щит +${(actor.shield - before).toFixed(1)}.`, data: { abilityId: ability.id, amount: actor.shield - before } });
      break;
    }
    default:
      abilityEvent(`${actor.name}: ${ability.desc}`);
  }
}

/** Продвижение активных кастов: STUN приостанавливает, resolveAt разрешает эффект, endAt освобождает канал. */
function advanceCasts(state: CombatState, rng: Rng): void {
  for (const actor of allActors(state)) {
    if (!actor.alive || !actor.cast) continue;
    const cast = actor.cast;
    if (hasStatus(actor, 'STUN')) {
      cast.resolveAt += TICK_MS;
      cast.endAt += TICK_MS;
      if (cast.channel === 'main') actor.nextAttackAt += TICK_MS;
      continue;
    }
    if (!cast.resolved && state.timeMs >= cast.resolveAt) {
      cast.resolved = true;
      if (cast.abilityId) resolveEnemyAbility(state, rng, actor, cast);
      else if (cast.skillId) resolveSkillCast(state, rng, actor, cast);
    }
    if (state.timeMs >= cast.endAt) actor.cast = null;
  }
}

/** Реактивный канал разрешается раньше обычных кастов (шаг 2 порядка событий). */
function advanceReactionCasts(state: CombatState, rng: Rng): void {
  for (const actor of allActors(state)) {
    if (!actor.alive || !actor.reactionCast) continue;
    const cast = actor.reactionCast;
    if (hasStatus(actor, 'STUN')) {
      cast.resolveAt += TICK_MS;
      cast.endAt += TICK_MS;
      continue;
    }
    if (!cast.resolved && state.timeMs >= cast.resolveAt) {
      cast.resolved = true;
      if (cast.skillId) resolveSkillCast(state, rng, actor, cast);
    }
    if (state.timeMs >= cast.endAt) actor.reactionCast = null;
  }
}

/** Прерывание прерываемого каста цели. Возвращает true, если каст был сорван. */
function interruptCast(state: CombatState, target: CombatActor, sourceId: string, actionId: string): boolean {
  const cast = target.cast;
  if (!cast || !cast.interruptible) return false;
  target.cast = null;
  state.metrics.interrupts++;
  emit(state, 'CAST_INTERRUPT', sourceId, {
    targetId: target.id, actionId, skillId: cast.skillId ?? undefined,
    text: `${target.name}: каст прерван.`,
    data: { interruptedSkill: cast.skillId ?? '', abilityId: cast.abilityId ?? '' },
  });
  return true;
}

function skillBase(state: CombatState, actor: CombatActor, skill: SkillDef): { base: number; type: DamageType } | null {
  const s = eff(state, actor);
  switch (skill.basis) {
    case 'MAIN_K': return { base: state.build.mainWeapon!.damage, type: 'KINETIC' };
    case 'MAIN_ANY': { const w = state.build.mainWeapon!; return { base: w.damage, type: w.type }; }
    case 'TECH_E': return { base: s.techPower, type: 'ENERGY' };
    case 'TECH_D': return { base: s.techPower, type: 'DIGITAL' };
    case 'OFFHAND': { const w = state.build.sidearm; return w ? { base: w.damage, type: w.type } : null; }
    case 'NONE': return null;
  }
}

function applySkillOnHit(state: CombatState, actor: CombatActor, target: CombatActor, skill: SkillDef, cast: CastState, raw: number, isLastHit: boolean): void {
  for (const effect of skill.extraEffects ?? []) {
    if (effect.type !== 'trigger' || effect.event !== 'ON_HIT' || effect.action.kind !== 'applyStatus') continue;
    if (skill.id === 'SK_BLADE' && !isLastHit) continue;
    const action = effect.action;
    const opts = { stacks: action.stacks ?? 1, durationMs: action.durationMs, snapshot: raw, actionId: cast.actionId };
    if (action.target === 'allEnemies') {
      for (const e of livingEnemies(state)) applyStatus(state, actor, e, action.status, opts);
    } else if (action.target === 'otherEnemy') {
      const other = livingEnemies(state).sort((a, b) => byId(a.id, b.id)).find((e) => e.id !== target.id);
      if (other) applyStatus(state, actor, other, action.status, opts);
    } else {
      applyStatus(state, actor, action.target === 'self' ? actor : target, action.status, opts);
    }
  }
}

function applySkillHit(state: CombatState, rng: Rng, actor: CombatActor, target: CombatActor, baseInfo: { base: number; type: DamageType }, coefficient: number, skill: SkillDef, cast: CastState, isLastHit: boolean): number {
  const s = eff(state, actor);
  let raw = baseInfo.base * coefficient;
  if (skill.tags.includes('D')) raw *= s.moreSkillDigital;
  if (skill.tags.includes('E')) raw *= s.moreSkillEnergy;
  if (skill.special === 'EXECUTE' && target.hp / Math.max(1, target.baseSheet.maxHP) < 0.3) raw *= 1.4 * s.moreExecute;
  if (skill.special === 'CHAIN_HEAT' && actor.heat >= 80) raw *= 1.25;
  const isMain = skill.basis === 'MAIN_K' || skill.basis === 'MAIN_ANY';
  let penOverride: PenetrationSnapshot | undefined;
  if (skill.id === 'SK_PIERCE') { const p = penOf(state, actor); penOverride = { ...p, armorPen: p.armorPen + 20 }; }
  const result = applyHit(state, rng, actor, target, raw, baseInfo.type, { actionId: cast.actionId, isMain, procWeight: skill.procWeight, skillId: skill.id, penOverride });
  if (result >= 0) {
    applySkillOnHit(state, actor, target, skill, cast, result, isLastHit);
    if (skill.special === 'LEECH' && hasStatus(target, 'VIRUS')) {
      const before = actor.energy;
      actor.energy = clamp(actor.energy + 8, 0, s.maxEnergy);
      emit(state, 'ENERGY', actor.id, { text: `${actor.name}: +${(actor.energy - before).toFixed(1)} энергии (Паразит).`, data: { amount: actor.energy - before } });
    }
  }
  return result;
}

/** Детонация: 0.60 остаточного потенциала до 3 стеков VIRUS как мгновенный D-урон. */
function resolveDetonate(state: CombatState, rng: Rng, actor: CombatActor, target: CombatActor, skill: SkillDef, cast: CastState): void {
  const arr = target.statuses.VIRUS ?? [];
  if (!arr.length) return;
  const def = STATUS_DEFS.VIRUS;
  const tickMs = def.tickMs ?? 1000;
  const frac = def.tickFraction ?? 0;
  const consumeCount = Math.min(3, arr.length);
  let potential = 0;
  for (let i = 0; i < consumeCount; i++) {
    const e = arr[i]!;
    const remainingTicks = Math.max(0, Math.ceil((e.expiresAt - state.timeMs) / tickMs));
    potential += e.snapshot * frac * remainingTicks * e.stacks;
  }
  target.statuses.VIRUS = arr.slice(consumeCount);
  if (!target.statuses.VIRUS.length) delete target.statuses.VIRUS;
  const s = eff(state, actor);
  const raw = potential * s.detonateCoefficient * s.moreSkillDigital;
  applyHit(state, rng, actor, target, raw, 'DIGITAL', { actionId: cast.actionId, isMain: false, procWeight: skill.procWeight, skillId: skill.id });
}

/** Эффекты защитных реакций (раздел 11): щит/EMP/дефлектор/продувка/ремодуль/синхрометка. */
function resolveReaction(state: CombatState, rng: Rng, actor: CombatActor, skill: SkillDef, cast: CastState): void {
  const s = eff(state, actor);
  switch (skill.special) {
    case 'TEMP_SHIELD': {
      const cap = 90;
      const existing = actor.tempShields.find((p) => p.sourceId === 'SK_SHIELD');
      const before = existing?.amount ?? 0;
      const amount = Math.min(cap, before + 60);
      if (existing) { existing.amount = amount; existing.expiresAt = state.timeMs + 5000; }
      else actor.tempShields.push({ sourceId: 'SK_SHIELD', amount, cap, expiresAt: state.timeMs + 5000 });
      emit(state, 'SHIELD_GAIN', actor.id, { actionId: cast.actionId, text: `${actor.name}: аварийный щит +${(amount - before).toFixed(0)}.`, data: { amount: amount - before, total: amount, cap } });
      return;
    }
    case 'EMP': {
      const target = castTarget(state, actor, cast);
      if (!target) return;
      interruptCast(state, target, actor.id, cast.actionId);
      const baseInfo = skillBase(state, actor, skill);
      if (baseInfo) applySkillHit(state, rng, actor, target, baseInfo, skill.coefficient, skill, cast, true);
      return;
    }
    case 'GUARD': {
      applyStatus(state, actor, actor, 'GUARD', { stacks: 1, durationMs: 2000, actionId: cast.actionId });
      return;
    }
    case 'VENT': {
      // Охлаждение −35 уже применено на старте каста (heatDelta); здесь только запись в таймлайн.
      emit(state, 'HEAT', actor.id, { actionId: cast.actionId, text: `${actor.name}: продувка, нагрев ${actor.heat.toFixed(0)}.`, data: { heat: actor.heat } });
      return;
    }
    case 'HEAL': {
      const maxHP = s.maxHP;
      const bonus = Math.min(0.10 * maxHP, 0.12 * maxHP);
      const heal = Math.min(30 + bonus, 0.22 * maxHP) * (1 + s.healing / 100);
      const before = actor.hp;
      actor.hp = clamp(actor.hp + heal, 0, maxHP);
      const actual = actor.hp - before;
      state.metrics.healingDone += actual;
      emit(state, 'HEAL', actor.id, { actionId: cast.actionId, text: `${actor.name}: ремодуль +${actual.toFixed(1)} HP.`, data: { amount: actual, overheal: heal - actual } });
      return;
    }
    case 'DRONE_MARK': {
      const target = castTarget(state, actor, cast);
      if (target) applyStatus(state, actor, target, 'DRONE_MARK', { stacks: 1, durationMs: 5000 + s.droneMarkBonusMs, actionId: cast.actionId });
      return;
    }
  }
}

function resolveSkillCast(state: CombatState, rng: Rng, actor: CombatActor, cast: CastState): void {
  const skill = cast.skillId ? SKILL_BY_ID[cast.skillId] : undefined;
  if (!skill) return;
  state.metrics.skillUses[skill.id] = (state.metrics.skillUses[skill.id] ?? 0) + 1;
  const isReaction = skill.channel === 'reaction';
  emit(state, isReaction ? 'REACTION' : 'SKILL_USE', actor.id, { skillId: skill.id, targetId: cast.targetId ?? undefined, actionId: cast.actionId, text: `${actor.name}: ${skill.name}.`, data: { channel: skill.channel } });

  if (isReaction) { resolveReaction(state, rng, actor, skill, cast); return; }

  if (skill.special === 'OVERCLOCK') {
    applyStatus(state, actor, actor, 'OVERCLOCK', { stacks: 1, durationMs: 8000, actionId: cast.actionId });
    return;
  }
  if (skill.special === 'SCAN') {
    const target = castTarget(state, actor, cast);
    if (target) applyStatus(state, actor, target, 'SCAN_MARK', { stacks: 1, durationMs: 6000 + eff(state, actor).scanMarkBonusMs, actionId: cast.actionId });
    return;
  }

  const target = castTarget(state, actor, cast);
  if (skill.special === 'DETONATE') {
    if (target) resolveDetonate(state, rng, actor, target, skill, cast);
    return;
  }
  const baseInfo = skillBase(state, actor, skill);
  if (!baseInfo) return;

  if (skill.targetMode === 'allEnemies' || skill.maxTargets) {
    for (const t of selectSkillTargets(state, actor, skill)) {
      applySkillHit(state, rng, actor, t, baseInfo, skill.coefficient, skill, cast, true);
    }
    return;
  }

  const hits = Math.max(1, skill.hits);
  const coef = skill.hitCoefficient ?? skill.coefficient;
  for (let i = 0; i < hits; i++) {
    const pinned = cast.targetId ? actorById(state, cast.targetId) : undefined;
    const current = pinned && pinned.alive ? pinned : livingEnemies(state).sort((a, b) => byId(a.id, b.id))[0];
    if (!current) break;
    applySkillHit(state, rng, actor, current, baseInfo, coef, skill, cast, i === hits - 1);
  }
  if (skill.splash && target) {
    const others = livingEnemies(state).filter((e) => e.id !== target.id).sort((a, b) => byId(a.id, b.id)).slice(0, skill.splash.targets);
    for (const o of others) {
      applySkillHit(state, rng, actor, o, baseInfo, skill.splash.coefficient, skill, cast, true);
      if (skill.splash.status) applyStatus(state, actor, o, skill.splash.status, { stacks: 1, actionId: cast.actionId });
    }
  }
}

function startAutoAttack(state: CombatState, rng: Rng, actor: CombatActor): void {
  resolveAttack(state, rng, actor);
  scheduleNextAttack(state, actor);
}

function chooseOperatorAction(state: CombatState, rng: Rng, actor: CombatActor): void {
  if (actor.heatLockout) {
    recordRuleFail(state, 'AUTO', 'heat_lockout');
    return;
  }
  const choice = selectMainRule(state, actor);
  if (choice.kind === 'skill') startSkillCast(state, actor, choice.skill, choice.target);
  else startAutoAttack(state, rng, actor);
}

type ReactionChoice = { kind: 'none' } | { kind: 'skill'; skill: SkillDef; target: CombatActor | undefined; rule: TacticRule };

/** Первое валидное правило reaction-канала по приоритету и stable ruleId; канал независим от main. */
function selectReactionRule(state: CombatState, actor: CombatActor): ReactionChoice {
  const rules = state.tactics.rules
    .filter((r) => r.enabled && r.skillId !== 'AUTO' && skillChannel(r.skillId) === 'reaction')
    .sort((a, b) => b.priority - a.priority || byId(a.id, b.id));
  for (const rule of rules) {
    const skill = equippedSkill(state, rule.skillId);
    if (!skill) { recordRuleFail(state, rule.id, 'not_equipped'); continue; }
    if ((actor.cooldowns[skill.id] ?? 0) > state.timeMs) { recordRuleFail(state, rule.id, 'cooldown'); continue; }
    if (actor.energy < skillEnergyCost(state, actor, skill)) { recordRuleFail(state, rule.id, 'energy'); continue; }
    const target = selectTarget(state, actor, rule.target);
    if (!target && skill.targetMode !== 'self') { recordRuleFail(state, rule.id, 'no_target'); continue; }
    if (skill.special === 'EMP' && (!target || !target.cast || !target.cast.interruptible)) { recordRuleFail(state, rule.id, 'no_interruptible'); continue; }
    if (!ruleConditionsPass(state, actor, rule, target)) { recordRuleFail(state, rule.id, 'conditions'); continue; }
    return { kind: 'skill', skill, target, rule };
  }
  return { kind: 'none' };
}

function chooseReaction(state: CombatState, actor: CombatActor): void {
  const choice = selectReactionRule(state, actor);
  if (choice.kind === 'skill') startSkillCast(state, actor, choice.skill, choice.target);
}

/* ------------------------------------------------------------------ */
/* Смерти и завершение                                                 */
/* ------------------------------------------------------------------ */

function resolveDeaths(state: CombatState): void {
  for (const actor of allActors(state)) {
    if (!actor.alive || actor.hp > 0) continue;
    actor.alive = false;
    actor.killedAt = state.timeMs;
    actor.cast = null;
    emit(state, 'DEATH', actor.id, { text: `${actor.name} уничтожен.` });
    if (actor.side === 'enemy') {
      state.metrics.kills++;
      state.metrics.ttk.push({ enemyId: actor.id, name: actor.name, ms: state.timeMs });
    }
    if (actor.kind === 'drone') state.metrics.droneDeaths++;
  }
}

function checkTerminal(state: CombatState): void {
  if (state.outcome) return;
  if (!state.operator.alive) {
    state.outcome = 'DEFEAT';
  } else if (!state.enemies.some((e) => e.alive)) {
    state.outcome = 'VICTORY';
  } else if (state.timeMs >= state.maxDurationMs) {
    state.outcome = 'TIMEOUT';
  }
  if (state.outcome) {
    emit(state, 'COMBAT_END', 'operator', { text: `Бой завершён: ${state.outcome}.`, data: { outcome: state.outcome } });
  }
}

/* ------------------------------------------------------------------ */
/* Единственный переход состояния                                      */
/* ------------------------------------------------------------------ */

function cloneState(state: CombatState): CombatState {
  const { build, tactics, log, ...rest } = state;
  const copy = structuredClone(rest);
  // baseMods статичны на протяжении боя — разделяем по ссылке, не клонируем каждый тик.
  const src = [state.operator, ...state.drones, ...state.allies, ...state.enemies];
  const dst = [copy.operator, ...copy.drones, ...copy.allies, ...copy.enemies];
  for (let i = 0; i < dst.length; i++) dst[i]!.baseMods = src[i]!.baseMods;
  // События неизменяемы после создания; массив копируем поверхностно, чтобы
  // push в новом состоянии не мутировал лог входного состояния.
  return { ...copy, build, tactics, log: [...log] };
}

export function stepCombat(state: CombatState): CombatState {
  if (state.outcome) return state;
  const next = cloneState(state);
  const rng = Rng.fromSerialized(next.rng);
  const dtSec = TICK_MS / 1000;
  next.timeMs += TICK_MS;

  applyContinuous(next, dtSec);

  // Периодический урон статусов (включая финальный тик на границе истечения),
  // затем истечение статусов/баффов/временных щитов — до новых действий.
  tickStatuses(next);
  expireStatuses(next);

  // Реактивные/interrupt-действия разрешаются раньше обычных кастов (шаг 2), затем main (шаг 3).
  advanceReactionCasts(next, rng);
  advanceCasts(next, rng);

  // Выбор новых действий (шаг 7): у оператора независимые reaction- и main-каналы.
  const ready = allActors(next)
    .filter((a) => a.alive)
    .sort((a, b) => byId(a.id, b.id));
  for (const actor of ready) {
    if (actor.kind === 'operator') {
      if (!actor.reactionCast) chooseReaction(next, actor);
      if (!actor.cast && actor.nextAttackAt <= next.timeMs) chooseOperatorAction(next, rng, actor);
    } else if (!actor.cast) {
      const ability = actor.side === 'enemy' ? readyEnemyAbility(next, actor) : undefined;
      if (ability) startEnemyAbility(next, actor, ability);
      else if (actor.nextAttackAt <= next.timeMs) startAutoAttack(next, rng, actor);
    }
  }

  resolveBossPhases(next);
  resolveDeaths(next);
  checkTerminal(next);
  next.rng = rng.serialize();
  return next;
}

/* ------------------------------------------------------------------ */
/* Headless-раннер                                                     */
/* ------------------------------------------------------------------ */

function deathReportOf(state: CombatState): DeathReport {
  const lethal = [...state.log].reverse().find((e) => e.kind === 'DAMAGE' && e.targetId === 'operator' && (e.hpLost ?? 0) > 0);
  const cutoff = state.timeMs - 30000;
  const bySource = Object.entries(state.metrics.takenBySource)
    .map(([source, damage]) => ({ source, damage }))
    .sort((a, b) => b.damage - a.damage);
  return {
    lethalCause: lethal ? `${lethal.damageType ?? 'урон'} ${lethal.amountAfterDefense?.toFixed(1) ?? ''}` : 'не установлен',
    lethalSource: lethal?.actorId ?? 'не установлен',
    lastEvents: state.log.filter((e) => e.timestamp >= cutoff),
    shieldAbsorbed: state.metrics.shieldAbsorbed,
    missedInterrupts: 0,
    energyStarvedMs: state.metrics.energyStarvedMs,
    heatLockoutMs: state.metrics.heatLockoutMs,
    bySource,
  };
}

export function resultFromState(state: CombatState): CombatResult {
  const op = state.operator;
  return {
    outcome: state.outcome ?? 'TIMEOUT',
    durationMs: state.timeMs,
    seed: state.seed,
    metrics: state.metrics,
    log: state.log,
    logTruncated: state.logTruncated,
    operator: { hp: op.hp, maxHP: op.baseSheet.maxHP, shield: op.shield, energy: op.energy, heat: op.heat },
    drones: state.drones.map((d) => ({ itemId: d.templateId, hp: d.hp, maxHP: d.baseSheet.maxHP, alive: d.alive })),
    enemiesKilled: state.enemies.filter((e) => !e.alive).map((e) => e.id),
    bossKilled: state.enemies.some((e) => e.isBoss && !e.alive),
    wantedDelta: state.wantedDelta,
    revealDelta: state.revealDelta,
    usedSkills: Object.keys(state.metrics.skillUses),
    rngState: [state.rng],
    rulesHash: state.rulesHash,
    deathReport: state.outcome === 'DEFEAT' ? deathReportOf(state) : undefined,
  };
}

export function simulateCombat(config: CombatConfig): CombatResult {
  let state = createCombatState(config);
  const maxSteps = Math.ceil(state.maxDurationMs / TICK_MS) + 1;
  for (let i = 0; i < maxSteps && !state.outcome; i++) {
    state = stepCombat(state);
  }
  if (!state.outcome) {
    state = { ...state, outcome: 'TIMEOUT' };
  }
  return resultFromState(state);
}
