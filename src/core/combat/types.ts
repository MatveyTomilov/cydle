import type { Channel, DamageType, NodeType, StatusId, TargetMode } from '../types';
import type { ResolvedBuild } from '../build/build';
import type { Modifier, StatSheet } from '../math/stats';
import type { SerializedRng } from '../rng';

export interface StatusStack {
  sourceId: string;
  sourceActorId: string;
  expiresAt: number;
  nextTickAt: number;
  snapshot: number;
  stacks: number;
}

export interface RuntimeBuff {
  id: string;
  sourceId: string;
  name: string;
  mods: Modifier[];
  expiresAt: number;
  consumeOnHit?: boolean;
  stacks: number;
}

export interface TempShield {
  sourceId: string;
  amount: number;
  cap: number;
  expiresAt: number;
}

export interface CastState {
  actionId: string;
  skillId: string | null;
  startedAt: number;
  resolveAt: number;
  endAt: number;
  targetId: string | null;
  interruptible: boolean;
  telegraph: boolean;
  dangerTag?: string;
  channel: Channel;
  abilityId?: string;
  resolved?: boolean;
}

export interface CombatActor {
  id: string;
  kind: 'operator' | 'drone' | 'enemy' | 'boss' | 'ally';
  side: 'player' | 'enemy';
  templateId: string;
  name: string;
  positionTag: string;
  isBoss: boolean;
  isMechanical: boolean;
  isHealer: boolean;
  hp: number;
  shield: number;
  tempShields: TempShield[];
  energy: number;
  heat: number;
  heatLockout: boolean;
  lockoutUntil: number;
  statuses: Partial<Record<StatusId, StatusStack[]>>;
  buffs: RuntimeBuff[];
  cooldowns: Record<string, number>;
  cast: CastState | null;
  channelBusy: Partial<Record<Channel, number>>;
  nextAttackAt: number;
  flags: Record<string, number>;
  counters: Record<string, number>;
  icds: Record<string, number>;
  oncePerCombat: Record<string, boolean>;
  abilityNext: Record<string, number>;
  alive: boolean;
  baseSheet: StatSheet;
  baseMods: Modifier[];
  runtimeMods: Modifier[];
  effSheet?: StatSheet;
  effFingerprint?: string;
  ownerId?: string;
  eliteMod?: string;
  noLoot?: boolean;
  controlled?: boolean;
  damageDealt: number;
  damageTaken: number;
  killedAt?: number;
  escapedAt?: number;
  threatUnits: number;
  attackDamage: number;
  attackIntervalMs: number;
  attackType: DamageType;
  accuracyBase: number;
  procMultiplier: number;
  deathBurst?: { damage: number; type: DamageType; telegraphMs: number };
  summoned?: boolean;
  lastMainAttackAt: number;
  lastTargetId: string | null;
  sameTargetHits: number;
  lastSkillId: string | null;
  sameSkillCount: number;
  lastDigitalSkill: { skillId: string; targetId: string } | null;
  shieldSpentWindow: number[];
  energyGainWindow: number[];
  markBy?: string;
}

export type CombatEventKind =
  | 'COMBAT_START' | 'COMBAT_END' | 'ATTACK' | 'HIT' | 'MISS' | 'CRIT' | 'DAMAGE' | 'DOT_TICK'
  | 'STATUS_APPLY' | 'STATUS_EXPIRE' | 'HEAL' | 'SHIELD_GAIN' | 'SHIELD_EXPIRE' | 'ENERGY' | 'HEAT'
  | 'HEAT_LOCKOUT' | 'HEAT_LOCKOUT_END' | 'CAST_START' | 'CAST_INTERRUPT' | 'CAST_FIZZLE' | 'SKILL_USE'
  | 'DEATH' | 'SUMMON' | 'RULE_FAIL' | 'TRIGGER' | 'CHAIN_LIMIT' | 'PHASE' | 'ESCAPE' | 'TELEGRAPH'
  | 'BUFF' | 'CONTROL' | 'REVIVE' | 'WANTED';

export interface CombatEvent {
  eventId: number;
  timestamp: number;
  kind: CombatEventKind;
  actorId: string;
  targetId?: string;
  actionId?: string;
  skillId?: string;
  damageType?: DamageType;
  amountBeforeDefense?: number;
  amountAfterDefense?: number;
  shieldConsumed?: number;
  hpLost?: number;
  bypassed?: number;
  incomingTags: string[];
  producedTags: string[];
  causeId?: number;
  originActionId?: string;
  chainDepth: number;
  text: string;
  reason?: string;
  roll?: number;
  crit?: boolean;
  statusId?: StatusId;
  data?: Record<string, number | string | boolean>;
}

/* ---------------- Тактика ---------------- */

export type TacticCondition =
  | { kind: 'always' }
  | { kind: 'hpBelow'; value: number }
  | { kind: 'hpAbove'; value: number }
  | { kind: 'shieldBelow'; value: number }
  | { kind: 'energyAtLeast'; value: number }
  | { kind: 'energyBelow'; value: number }
  | { kind: 'heatAtLeast'; value: number }
  | { kind: 'heatBelow'; value: number }
  | { kind: 'heatLocked' }
  | { kind: 'enemiesAtLeast'; value: number }
  | { kind: 'enemiesAtMost'; value: number }
  | { kind: 'enemyCasting'; interruptibleOnly?: boolean }
  | { kind: 'enemyType'; value: 'boss' | 'healer' | 'mechanical' | 'elite' }
  | { kind: 'targetStatus'; status: StatusId; minStacks?: number }
  | { kind: 'droneAlive'; value: number }
  | { kind: 'cooldownReady'; skillId: string }
  | { kind: 'effectUptime'; status: StatusId }
  | { kind: 'timeAtLeast'; value: number }
  | { kind: 'not'; inner: TacticCondition }
  | { kind: 'any'; inner: TacticCondition[] }
  | { kind: 'all'; inner: TacticCondition[] };

export interface TacticRule {
  id: string;
  priority: number;
  enabled: boolean;
  skillId: string | 'AUTO';
  target: TargetMode;
  conditions: TacticCondition[];
  logic: 'AND' | 'OR';
  note?: string;
}

export interface TacticalProfile {
  id: string;
  name: string;
  rules: TacticRule[];
}

export interface EncounterEnemySpec {
  templateId: string;
  elite?: string;
  hpMult?: number;
  damageMult?: number;
  summoned?: boolean;
  noLoot?: boolean;
}

export interface CombatConfig {
  seed: string;
  depth: number;
  biome: string;
  nodeType: NodeType;
  build: ResolvedBuild;
  enemies: EncounterEnemySpec[];
  tactics: TacticalProfile;
  allies?: EncounterEnemySpec[];
  startHpFraction?: number;
  startShieldFraction?: number;
  startEnergy?: number;
  startHeat?: number;
  droneHp?: Record<string, number>;
  extraEnemyDigitalBonus?: number;
  coolingPenalty?: number;
  enemyWindupMult?: number;
  elitePen?: number;
  maxDurationMs?: number;
  recordLog?: boolean;
  ambientHeatPerSec?: number;
  initialTempShield?: number;
  initialExtraHeat?: number;
  wanted?: number;
}

export interface CombatMetrics {
  damageDealt: number;
  damageTaken: number;
  damageByType: Record<DamageType, number>;
  damageBySource: Record<string, number>;
  takenBySource: Record<string, number>;
  hits: number;
  misses: number;
  crits: number;
  dodgesTaken: number;
  kills: number;
  skillUses: Record<string, number>;
  ruleFailures: { ruleId: string; reason: string; count: number; firstAt: number }[];
  energySpent: number;
  energyStarvedMs: number;
  heatLockouts: number;
  heatLockoutMs: number;
  shieldAbsorbed: number;
  hpLost: number;
  healingDone: number;
  statusTicks: number;
  procsTriggered: number;
  chainLimitHits: number;
  ttk: { enemyId: string; name: string; ms: number }[];
  droneDeaths: number;
  escaped: string[];
  lowestHpFraction: number;
  timeWithoutShieldMs: number;
}

export interface CombatResult {
  outcome: 'VICTORY' | 'DEFEAT' | 'TIMEOUT';
  durationMs: number;
  seed: string;
  metrics: CombatMetrics;
  log: CombatEvent[];
  logTruncated: boolean;
  operator: { hp: number; maxHP: number; shield: number; energy: number; heat: number };
  drones: { itemId: string; hp: number; maxHP: number; alive: boolean }[];
  enemiesKilled: string[];
  bossKilled: boolean;
  wantedDelta: number;
  revealDelta: number;
  usedSkills: string[];
  rngState: SerializedRng[];
  rulesHash: string;
  deathReport?: DeathReport;
}

export interface DeathReport {
  lethalCause: string;
  lethalSource: string;
  lastEvents: CombatEvent[];
  shieldAbsorbed: number;
  missedInterrupts: number;
  energyStarvedMs: number;
  heatLockoutMs: number;
  bySource: { source: string; damage: number }[];
}
