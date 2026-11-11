import type { Condition, ModOp, StatId } from '../core/math/stats';
import type {
  BiomeId, Channel, DamageType, FactionId, ImplantSlotType, ItemCategory, NodeType, Rarity, SkillTag, StatusId, TargetMode,
} from '../core/types';

/* ---------------- Эффекты: типизированные сериализуемые операторы ---------------- */

export interface StatEffect {
  type: 'stat';
  stat: StatId;
  op: ModOp;
  value: number;
  condition?: Condition;
  stackGroup?: string;
  synScalable?: boolean;
  note?: string;
}

export type TriggerEvent =
  | 'ON_HIT'            // успешное прямое попадание
  | 'ON_CRIT'
  | 'ON_KILL'
  | 'ON_TAKEN_DAMAGE'
  | 'ON_SHIELD_ABSORB'
  | 'ON_DODGE'
  | 'ON_HEAT_FULL'
  | 'ON_HEAT_LOCKOUT_END'
  | 'ON_CAST'           // после применения умения (filter по skillId)
  | 'ON_INTERRUPT'
  | 'ON_DRONE_DEATH'
  | 'ON_ALLY_DEATH'
  | 'ON_STATUS_EXPIRE'
  | 'ON_COMBAT_START'
  | 'ON_COMBAT_END'
  | 'PERIODIC'          // каждые periodMs
  | 'ON_ATTACK_COUNTER' // каждый N-й прямой удар
  | 'ON_HP_THRESHOLD'
  | 'ON_BEFORE_HIT'
  | 'ON_ENEMY_TELEGRAPH'
  | 'ON_EFFECT_SHIELD_SPENT';

export type TriggerAction =
  | { kind: 'secondaryDamage'; basis: 'techPower' | 'mainWeapon' | 'droneTech' | 'flat' | 'consumedShield' | 'virusRemaining'; coefficient: number; damageType: DamageType; targeting: TargetMode; maxTargets?: number; canProc?: boolean; tags?: string[] }
  | { kind: 'applyStatus'; status: StatusId; stacks?: number; durationMs?: number; target: 'target' | 'self' | 'allEnemies' | 'otherEnemy' }
  | { kind: 'tempShield'; amount: number; cap: number; durationMs: number; scaleWithArmorT?: boolean; fromFlag?: string; ratio?: number }
  | { kind: 'heal'; flat: number; maxHPFraction?: number; capFraction?: number }
  | { kind: 'restoreEnergy'; amount: number; perSecondCap?: number }
  | { kind: 'restoreShield'; amount: number }
  | { kind: 'changeHeat'; amount: number; removeLockout?: boolean }
  | { kind: 'buff'; mods: StatEffect[]; durationMs: number; maxStacks?: number; flag?: string; consumeOnHit?: boolean }
  | { kind: 'transferVirus'; stacks: number }
  | { kind: 'consumeShieldForDamage'; fraction: number; maxMultiplier: number; windowMs: number }
  | { kind: 'interrupt' }
  | { kind: 'reduceCooldown'; skillId?: string; amountMs: number }
  | { kind: 'charge'; amountFromAbsorbed: number; capFormula: 'H(T)' | 'flat'; capFlat?: number; intervalMs: number }
  | { kind: 'control'; chance: number; durationMs: number; bossFallbackJamMs: number }
  | { kind: 'extraReaction'; windowMs: number }
  | { kind: 'flag'; key: string; amount: number; max?: number }
  | { kind: 'wanted'; amount: number }
  | { kind: 'revealNodes'; amount: number }
  | { kind: 'repeatLastDigital'; coefficient: number }
  | { kind: 'spendFlagForDamage'; flag: string; perStack: number; maxStacks: number; onlyAtMax?: boolean }
  | { kind: 'packetMod'; penMultiplier?: number; damageMultiplier?: number; consumeShield?: number; requireShield?: number }
  | { kind: 'extendStatus'; status: StatusId; ms: number; stacks: number };

export interface TriggerEffect {
  type: 'trigger';
  id: string;
  event: TriggerEvent;
  action: TriggerAction;
  icdMs?: number;
  chance?: number;
  periodMs?: number;
  counterEvery?: number;
  skillFilter?: string[];
  damageTypeFilter?: DamageType[];
  requireDirect?: boolean;
  requireKillType?: DamageType;
  condition?: Condition;
  oncePerCombat?: boolean;
  oncePerDrone?: boolean;
  hpThreshold?: number;
  minAmount?: number;
  requireDrone?: boolean;
  desc: string;
}

export type EffectDef = StatEffect | TriggerEffect;

/* ---------------- Предметы ---------------- */

export interface WeaponBlock {
  damage: number;
  type: DamageType;
  intervalMs: number;
  packets?: { type: DamageType; amount: number; procWeight?: number }[];
  pelletCount?: number;
  pelletProcWeight?: number;
  windupMs?: number;
  procWeight?: number;
  heatPerAttack?: number;
  energyPerAttack?: number;
  sidearmOnly?: boolean;
}

export interface DroneBlock {
  hp: number;
  armor: number;
  shield: number;
  damage: number;
  intervalMs: number;
  type: DamageType;
  pellets?: number;
  role: 'mark' | 'shock' | 'medic' | 'emp' | 'bulwark' | 'swarm';
}

export interface ItemTemplate {
  id: string;
  name: string;
  category: ItemCategory;
  implantSlot?: ImplantSlotType;
  neuralCost?: number;
  tags: string[];
  weapon?: WeaponBlock;
  drone?: DroneBlock;
  armorBlock?: { hp: number; shield: number; armor: number };
  effects: EffectDef[];
  cargoUnits: number;
  desc: string;
  craftable: boolean;
  uniqueEffectId?: string;
  baseTemplateId?: string;
  biomes?: BiomeId[];
}

/* ---------------- Умения ---------------- */

export type SkillSpecial =
  | 'DETONATE' | 'VENT' | 'HEAL' | 'TEMP_SHIELD' | 'EMP' | 'SCAN' | 'OVERCLOCK' | 'GUARD'
  | 'DRONE_MARK' | 'DRONE_REPAIR' | 'DRONE_EMP' | 'SIDE_FIRE' | 'LEECH' | 'CHAIN_HEAT' | 'EXECUTE';

export interface SkillDef {
  id: string;
  name: string;
  channel: Channel;
  tags: SkillTag[];
  coefficient: number;
  hits: number;
  hitCoefficient?: number;
  energyCost: number;
  heatDelta: number;
  windupMs: number;
  recoveryMs: number;
  cooldownMs: number;
  targetMode: TargetMode;
  procWeight: number;
  basis: 'MAIN_K' | 'MAIN_ANY' | 'TECH_E' | 'TECH_D' | 'OFFHAND' | 'NONE';
  special?: SkillSpecial;
  extraEffects?: EffectDef[];
  splash?: { coefficient: number; targets: number; status?: StatusId };
  maxTargets?: number;
  requires?: string[];
  interruptible: boolean;
  desc: string;
}

export interface PassiveDef {
  id: string;
  name: string;
  effects: EffectDef[];
  desc: string;
}

/* ---------------- Дерево ---------------- */

export interface TreeNodeDef {
  id: string;
  branch: 'K' | 'H' | 'N' | 'D' | 'S' | 'R' | 'X';
  tier: 1 | 2 | 3 | 4;
  pos: 'A' | 'B' | 'C' | 'D' | 'X';
  name: string;
  keystone: boolean;
  effects: EffectDef[];
  desc: string;
  requires?: { branch: 'K' | 'H' | 'N' | 'D' | 'S' | 'R'; points: number }[];
}

/* ---------------- Враги ---------------- */

export type EnemyAbilityKind =
  | 'heavyAttack' | 'heal' | 'summon' | 'applyStatus' | 'heat' | 'shieldRestore' | 'mark'
  | 'deathBurst' | 'escape' | 'wantedBoost' | 'protectAlly' | 'jamPunish' | 'shieldBypass';

export interface EnemyAbility {
  id: string;
  kind: EnemyAbilityKind;
  firstAtMs: number;
  everyMs: number;
  windupMs: number;
  telegraphMs: number;
  interruptible: boolean;
  damage?: number;
  damageType?: DamageType;
  bypassShieldRatio?: number;
  status?: StatusId;
  statusDurationMs?: number;
  amount?: number;
  summonId?: string;
  summonCount?: number;
  desc: string;
}

export interface EnemyTemplate {
  id: string;
  name: string;
  hp: number;
  shield: number;
  armor: number;
  resE: number;
  resD: number;
  evasion: number;
  damage: number;
  intervalMs: number;
  type: DamageType;
  threatUnits: number;
  mechanical: boolean;
  healer: boolean;
  role: string;
  abilities: EnemyAbility[];
  passives?: EffectDef[];
  unlockDepth: number;
  biomes: BiomeId[];
  desc: string;
}

export interface BossPhaseTrigger {
  hpFraction: number;
  kind: 'summon' | 'attackSpeed' | 'castSpeed' | 'bypassUpgrade' | 'intervalReduce' | 'cleanse';
  summonId?: string;
  amount?: number;
  desc: string;
}

export interface BossTemplate extends EnemyTemplate {
  isBoss: true;
  phases: BossPhaseTrigger[];
  rotating?: EnemyAbility[];
  ambientHeatPerSec?: number;
  accuracy: number;
}

/* ---------------- Дорога / мир ---------------- */

export interface BiomeDef {
  id: BiomeId;
  name: string;
  desc: string;
  enemies: string[];
  lootTags: string[];
  uniques: string[];
  serviceBonus?: number;
  wantedElite?: number;
  creditsBonus?: number;
  repairCostMult?: number;
  turretBonus?: number;
  enemyDigitalBonus?: number;
  dataBonus?: number;
  coolingPenalty?: number;
  energyWeightBonus?: number;
  anomaly?: boolean;
  revealPenalty?: number;
}

export interface EventChoiceDef {
  id: 'A' | 'B';
  label: string;
  desc: string;
  cost?: { CREDITS?: number; SCRAP?: number; DATA?: number };
  gains?: { CREDITS?: number; SCRAP?: number; DATA?: number };
  scaled?: boolean;
  reputation?: Partial<Record<FactionId, number>>;
  wanted?: number;
  fuel?: number;
  hull?: number;
  healMissingFraction?: number;
  refillEnergy?: boolean;
  grantItem?: { templateId?: string; category?: ItemCategory; rarity?: Rarity; tag?: string; count?: number };
  grantMutation?: string;
  flag?: string;
  reveal?: number;
  nextCombat?: { alliedTurret?: boolean; extraHeat?: number; shieldBonus?: number; skip?: boolean; forceElite?: boolean; forceBounty?: boolean; bountyCredits?: number; extraRareRoll?: boolean };
  travelDelta?: number;
  questAdvance?: boolean;
  special?: string;
}

export interface GameEventDef {
  id: string;
  name: string;
  text: string;
  choices: [EventChoiceDef, EventChoiceDef];
  biomes?: BiomeId[];
}

export interface QuestStageDef {
  stage: 1 | 2 | 3;
  name: string;
  text: string;
  biome?: BiomeId;
  requirement?: { kind: 'killElite'; enemyId: string } | { kind: 'biomeCombat'; biome: BiomeId; count: number } | { kind: 'visitBiome'; biome: BiomeId } | { kind: 'anomaly' } | { kind: 'none' };
  choices: [EventChoiceDef, EventChoiceDef];
  deadlineSectors?: number;
}

export interface QuestDef {
  id: string;
  name: string;
  faction: FactionId;
  biome: BiomeId;
  minDepth: number;
  stages: [QuestStageDef, QuestStageDef, QuestStageDef];
  desc: string;
}

export interface MutationDef {
  id: string;
  name: string;
  benefit: string;
  cost: string;
  effects: EffectDef[];
  tags: string[];
  requires?: string[];
}

export interface ContractDef {
  id: string;
  kind: 'HUNT' | 'TECH' | 'ESCORT';
  name: string;
  desc: string;
  targetBiome: BiomeId;
  targetEnemy?: string;
  rewardCredits?: number;
  rewardData?: number;
  rewardReputation?: Partial<Record<FactionId, number>>;
  rewardItem?: { rarity: Rarity; tag?: string; category?: ItemCategory };
  rewardSchematic?: string;
}

export interface EscalationModDef {
  id: string;
  name: string;
  benefit: string;
  cost: string;
  effects: EffectDef[];
  worldFlags?: Record<string, number>;
}

export interface GarageObjectDef {
  id: string;
  name: string;
  levels: [string, string, string];
  desc: string;
  extraData?: number;
  gate?: { object: 'sector'; value: number }[];
}

export interface ShopOffer {
  itemId: string;
  templateId: string;
  techLevel: number;
  rarity: Rarity;
  price: number;
}

export interface LootSourceDef {
  credits: number;
  scrap: number;
  data: number;
  itemChance: number;
  extraChance: number;
  table: 'ORDINARY' | 'ELITE' | 'BOSS';
  xp: number;
  coreChance: number;
}

export type NodeThreatBand = 'low' | 'medium' | 'high' | 'boss';

export interface EncounterDef {
  id: string;
  nodeType: NodeType;
  depth: number;
  biome: BiomeId;
  enemies: { templateId: string; elite?: string; hpMult?: number }[];
  isBoss: boolean;
  seed: string;
}
