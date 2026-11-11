/**
 * Детерминированное боевое ядро (разделы 2, 4, 6–8, 23.2 мастер-ТЗ).
 * Единственный переход состояния — stepCombat: ровно один тик 100 мс.
 * Вся математика урона проходит через math/damage.ts ровно один раз.
 * Никакого Math.random, настенных часов и глобальных счётчиков событий.
 */
import { ENEMY_BY_ID, BOSS_BY_ID, enemyTemplate } from '../../data/enemies';
import { ITEM_BY_ID } from '../../data/items';
import { UNIQUE_TEMPLATE_BY_ID } from '../../data/uniques';
import type { BossTemplate, EnemyTemplate } from '../../data/types';
import type { ResolvedBuild } from '../build/build';
import { D, H, TICK_MS, attackIntervalMs, clamp, finite } from '../math/formula';
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
import type { CombatActor, CombatConfig, CombatEvent, CombatEventKind, CombatMetrics, CombatResult, DeathReport, TacticalProfile } from './types';
import type { DamageType, NodeType, StatusId } from '../types';

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
    procsTriggered: 0, chainLimitHits: 0, ttk: [], droneDeaths: 0, escaped: [],
    lowestHpFraction: 1, timeWithoutShieldMs: 0,
  };
}

function baseActor(partial: Partial<CombatActor> & Pick<CombatActor, 'id' | 'kind' | 'side' | 'templateId' | 'name'>): CombatActor {
  return {
    positionTag: partial.side === 'player' ? 'left' : 'right',
    isBoss: false, isMechanical: false, isHealer: false,
    hp: 1, shield: 0, tempShields: [], energy: 0, heat: 0,
    heatLockout: false, lockoutUntil: 0,
    statuses: {}, buffs: [], cooldowns: {}, cast: null, channelBusy: {},
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
  for (const ability of t.abilities) actor.abilityNext[ability.id] = ability.firstAtMs;
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
    const ambient = state.ambientHeatPerSec;
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
    const ds = eff(state, current);
    let accuracy = as.accuracy;
    if (actor.kind === 'drone' && hasStatus(current, 'DRONE_MARK')) accuracy += 15;
    const hitChance = pHit(accuracy, ds.evasion);
    if (!rng.chance(hitChance)) {
      state.metrics.misses++;
      if (current.kind === 'operator') state.metrics.dodgesTaken++;
      emit(state, 'MISS', actor.id, { targetId: current.id, actionId, damageType: packet.type, text: `${actor.name}: промах по ${current.name}.`, roll: hitChance });
      continue;
    }
    const critChance = pCrit(as.critChance);
    const crit = rng.chance(critChance);
    let raw = packet.amount * outgoingMultiplier(state, actor, packet.type, isMain);
    if (actor.side === 'enemy' && packet.type === 'DIGITAL') raw *= 1 + state.extraEnemyDigitalBonus;
    if (hasStatus(current, 'SCAN_MARK')) raw *= 1.12;
    if (crit) {
      raw *= as.critMultiplier * as.moreCritDamage;
      state.metrics.crits++;
    }
    raw = finite(raw, 0);
    const mitigated = mitigatePacket(raw, packet.type, defenseOf(state, current), penOf(state, actor));
    let incoming = mitigated.afterDefense * incomingMultiplier(state, current, packet.type);
    if (hasStatus(current, 'MARK')) {
      incoming *= 1.3;
      delete current.statuses.MARK;
      current.markBy = undefined;
    }
    const partition = partitionDamage(incoming, { hp: current.hp, shield: current.shield, temp: current.tempShields }, 0, ds.incomingShield);
    applyPartition(current, partition);
    current.flags.lastDamagedAt = state.timeMs;
    state.metrics.hits++;
    const dealt = partition.shieldConsumed + partition.hpLost;
    actor.damageDealt += dealt;
    current.damageTaken += dealt;
    if (actor.side === 'player') {
      state.metrics.damageDealt += dealt;
      state.metrics.damageByType[packet.type] += incoming;
      state.metrics.damageBySource[actor.id] = (state.metrics.damageBySource[actor.id] ?? 0) + dealt;
      state.metrics.shieldAbsorbed += partition.shieldConsumed;
    } else {
      state.metrics.damageTaken += dealt;
      state.metrics.takenBySource[actor.id] = (state.metrics.takenBySource[actor.id] ?? 0) + dealt;
      if (current.kind === 'operator') state.metrics.hpLost += partition.hpLost;
    }
    emit(state, 'DAMAGE', actor.id, {
      targetId: current.id, actionId, damageType: packet.type, crit,
      amountBeforeDefense: raw, amountAfterDefense: incoming,
      shieldConsumed: partition.shieldConsumed, hpLost: partition.hpLost, bypassed: partition.bypassed,
      text: `${actor.name} → ${current.name}: ${incoming.toFixed(1)} ${packet.type}${crit ? ' (крит)' : ''}, щит −${partition.shieldConsumed.toFixed(1)}, HP −${partition.hpLost.toFixed(1)}.`,
      data: { overkill: partition.overkill },
    });
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

  const due = allActors(next)
    .filter((a) => a.alive && a.nextAttackAt <= next.timeMs)
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  for (const actor of due) {
    resolveAttack(next, rng, actor);
    scheduleNextAttack(next, actor);
  }

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