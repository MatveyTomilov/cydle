/** Общие доменные типы CYDLE. Только типы и константы — без логики. */

export type DamageType = 'KINETIC' | 'ENERGY' | 'DIGITAL';
export const DAMAGE_TYPES: DamageType[] = ['KINETIC', 'ENERGY', 'DIGITAL'];
export const DAMAGE_TYPE_RU: Record<DamageType, string> = { KINETIC: 'кинетика', ENERGY: 'энергия', DIGITAL: 'цифра' };
export const DAMAGE_TYPE_SHORT: Record<DamageType, string> = { KINETIC: 'К', ENERGY: 'Э', DIGITAL: 'Ц' };

export type Rarity = 'COMMON' | 'MODIFIED' | 'RARE' | 'LEGENDARY' | 'UNIQUE';
export const RARITIES: Rarity[] = ['COMMON', 'MODIFIED', 'RARE', 'LEGENDARY', 'UNIQUE'];
export const RARITY_RU: Record<Rarity, string> = {
  COMMON: 'Обычный',
  MODIFIED: 'Модифицированный',
  RARE: 'Редкий',
  LEGENDARY: 'Легендарный',
  UNIQUE: 'Уникальный',
};
export const RARITY_COLOR: Record<Rarity, string> = {
  COMMON: '#9FB2C8',
  MODIFIED: '#4CC99B',
  RARE: '#58A6FF',
  LEGENDARY: '#E7BC65',
  UNIQUE: '#C38EF2',
};

export type ItemCategory =
  | 'MAIN'
  | 'OFFHAND'
  | 'ARMOR'
  | 'IMPLANT'
  | 'DRONE'
  | 'ENGINE'
  | 'CHASSIS'
  | 'SCANNER'
  | 'SERVICE'
  | 'CARGO'
  | 'SUPPORT'
  | 'MATERIAL';

export type ImplantSlotType = 'HEAD' | 'ARMS' | 'CHEST' | 'NEURAL' | 'UNIVERSAL';

export type EquipSlotId =
  | 'MAIN'
  | 'OFFHAND'
  | 'ARMOR'
  | 'IMP_1'
  | 'IMP_2'
  | 'IMP_3'
  | 'IMP_4'
  | 'IMP_5'
  | 'IMP_6'
  | 'DRONE_1'
  | 'DRONE_2'
  | 'ENGINE'
  | 'CHASSIS'
  | 'SCANNER'
  | 'SERVICE'
  | 'CARGO'
  | 'SUPPORT';

export const IMPLANT_SLOTS: EquipSlotId[] = ['IMP_1', 'IMP_2', 'IMP_3', 'IMP_4', 'IMP_5', 'IMP_6'];
/** Типы посадочных мест по разделу 5: старт HEAD, CHEST, ARMS, UNIVERSAL; позже NEURAL, UNIVERSAL. */
export const IMPLANT_SLOT_TYPES: Record<string, ImplantSlotType> = {
  IMP_1: 'HEAD',
  IMP_2: 'CHEST',
  IMP_3: 'ARMS',
  IMP_4: 'UNIVERSAL',
  IMP_5: 'NEURAL',
  IMP_6: 'UNIVERSAL',
};

export type Channel = 'main' | 'reaction' | 'droneA' | 'droneB' | 'transport' | 'route';

export type StatusId =
  | 'BLEED'
  | 'BURN'
  | 'VIRUS'
  | 'ARMOR_BREAK'
  | 'JAM'
  | 'SHOCK'
  | 'DRONE_JAM'
  | 'SHIELD_LEAK'
  | 'STUN'
  | 'MARK'
  | 'PHASE'
  | 'SYNCHRONY'
  | 'CHARGE'
  | 'LONG_PULSE'
  | 'OVERCLOCK'
  | 'GUARD'
  | 'SCAN_MARK'
  | 'DRONE_MARK'
  | 'CONTROLLED'
  | 'BERSERK'
  | 'REGEN_BUFF'
  | 'EVASION_BUFF'
  | 'ACC_BUFF'
  | 'DMG_BUFF'
  | 'SHIELD_REGEN_BUFF';

export type AttributeId = 'POW' | 'REF' | 'INT' | 'ENG' | 'SYN';
export const ATTRIBUTES: AttributeId[] = ['POW', 'REF', 'INT', 'ENG', 'SYN'];
export const ATTRIBUTE_RU: Record<AttributeId, string> = {
  POW: 'Мощность',
  REF: 'Реакция',
  INT: 'Интеллект',
  ENG: 'Инженерия',
  SYN: 'Синхронизация',
};

export type Currency = 'CREDITS' | 'SCRAP' | 'DATA';
export const CURRENCIES: Currency[] = ['CREDITS', 'SCRAP', 'DATA'];
export const CURRENCY_RU: Record<Currency, string> = { CREDITS: 'Кредиты', SCRAP: 'Металлолом', DATA: 'Данные' };

export type NodeType =
  | 'COMBAT'
  | 'ELITE'
  | 'BOUNTY'
  | 'REPAIR'
  | 'FUEL'
  | 'SHOP'
  | 'CACHE'
  | 'ANOMALY'
  | 'EVENT'
  | 'QUEST'
  | 'BOSS'
  | 'CHECKPOINT'
  | 'START';

export const NODE_TYPE_RU: Record<NodeType, string> = {
  COMBAT: 'Бой',
  ELITE: 'Элита',
  BOUNTY: 'Охотник',
  REPAIR: 'Ремонт',
  FUEL: 'Топливо',
  SHOP: 'Магазин',
  CACHE: 'Тайник',
  ANOMALY: 'Аномалия',
  EVENT: 'Событие',
  QUEST: 'Квест',
  BOSS: 'Босс',
  CHECKPOINT: 'Checkpoint',
  START: 'Форпост',
};

export type BiomeId = 'B01' | 'B02' | 'B03' | 'B04' | 'B05' | 'B06';
export type FactionId = 'F_VANTA' | 'F_RUST' | 'F_CHOIR' | 'F_ECHO';
export const FACTIONS: FactionId[] = ['F_VANTA', 'F_RUST', 'F_CHOIR', 'F_ECHO'];
export const FACTION_RU: Record<FactionId, string> = {
  F_VANTA: 'VANTA',
  F_RUST: 'Ржавчина',
  F_CHOIR: 'Хор Нуля',
  F_ECHO: 'Протокол Эхо',
};

export type TreeBranch = 'K' | 'H' | 'N' | 'D' | 'S' | 'R';
export const TREE_BRANCHES: TreeBranch[] = ['K', 'H', 'N', 'D', 'S', 'R'];
export const TREE_BRANCH_RU: Record<TreeBranch, string> = {
  K: 'Кинетика',
  H: 'Нагрев / Энергия',
  N: 'Нетраннер',
  D: 'Дроны',
  S: 'Защита',
  R: 'Реакция / Тактика',
};

export type GarageObjectId =
  | 'WORKSHOP'
  | 'NEUROLAB'
  | 'SERVER'
  | 'HANGAR'
  | 'MARKET'
  | 'INTEL'
  | 'GARAGE_MED'
  | 'CALIBRATOR';

export type AutopilotState =
  | 'IDLE'
  | 'RUNNING'
  | 'PAUSED_FOR_DECISION'
  | 'PAUSED_FOR_RESOURCES'
  | 'EXTRACTING'
  | 'EXTRACTED'
  | 'DEFEATED'
  | 'OFFLINE_CAPPED'
  | 'SAFE_ERROR_STOP';

export type RunOutcome = 'ACTIVE' | 'EXTRACTED' | 'DEFEATED' | 'ABANDONED';

export type SourceKind =
  | 'base'
  | 'attribute'
  | 'item'
  | 'affix'
  | 'implant'
  | 'tree'
  | 'passive'
  | 'unique'
  | 'mutation'
  | 'status'
  | 'skill'
  | 'contract'
  | 'biome'
  | 'garage'
  | 'enemy'
  | 'elite'
  | 'transport';

export interface Wallet {
  CREDITS: number;
  SCRAP: number;
  DATA: number;
}

export const EMPTY_WALLET: Wallet = { CREDITS: 0, SCRAP: 0, DATA: 0 };

export type TargetMode =
  | 'nearest'
  | 'lowestHPPercent'
  | 'marked'
  | 'healer'
  | 'imminentCast'
  | 'boss'
  | 'infected'
  | 'self'
  | 'allEnemies'
  | 'secondary'
  | 'attacker';

export type SkillTag =
  | 'K'
  | 'E'
  | 'D'
  | 'TECH'
  | 'DIRECT'
  | 'MULTI'
  | 'REACTION'
  | 'DRONE'
  | 'ROUTE'
  | 'REQUIRES_SIDEARM'
  | 'REQUIRES_DR_MED'
  | 'REQUIRES_DR_EMP'
  | 'REQUIRES_VIRUS'
  | 'INTERRUPT';
