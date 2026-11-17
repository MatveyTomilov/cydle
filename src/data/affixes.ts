import type { ItemCategory } from '../core/types';
import type { StatId } from '../core/math/stats';
import type { StatEffect } from './types';

export type AffixGroup = 'offensive' | 'defensive' | 'resource' | 'utility';

export interface AffixDef {
  id: string;
  name: string;
  stat: StatId;
  tiers: [number, number, number, number];
  slots: ItemCategory[];
  group: AffixGroup;
  unit: string;
  integer?: boolean;
  scaleD?: boolean;
  fixed?: boolean;
  op?: 'FLAT' | 'INCREASED';
}

const A = (
  id: string, name: string, stat: StatId, tiers: [number, number, number, number],
  slots: ItemCategory[], group: AffixGroup, unit: string, extra: Partial<AffixDef> = {},
): AffixDef => ({ id, name, stat, tiers, slots, group, unit, op: 'FLAT', ...extra });

/** Раздел 12 — словарь механических аффиксов (значения = центр ролла tier). */
export const AFFIXES: AffixDef[] = [
  A('AF_HP', 'Резерв HP', 'maxHP', [20, 35, 55, 80], ['ARMOR', 'IMPLANT'], 'defensive', 'HP', { scaleD: true }),
  A('AF_SH', 'Ёмкость щита', 'maxShield', [10, 20, 30, 45], ['ARMOR', 'OFFHAND', 'IMPLANT'], 'defensive', 'щит', { scaleD: true }),
  A('AF_ARM', 'Бронепластины', 'armor', [2, 4, 6, 8], ['ARMOR', 'IMPLANT'], 'defensive', 'броня', { integer: true }),
  A('AF_ERE', 'Сопр. энергии', 'energyRes', [3, 5, 7, 10], ['ARMOR', 'OFFHAND'], 'defensive', 'п.п.'),
  A('AF_DRE', 'Сопр. цифры', 'digitalRes', [3, 5, 7, 10], ['ARMOR', 'OFFHAND'], 'defensive', 'п.п.'),
  A('AF_EVA', 'Уклонение', 'evasion', [4, 7, 10, 15], ['ARMOR', 'IMPLANT'], 'defensive', 'ед.', { integer: true }),
  A('AF_ACC', 'Точность', 'accuracy', [4, 8, 12, 16], ['MAIN', 'OFFHAND'], 'offensive', 'ед.', { integer: true }),
  A('AF_KDM', 'Кинетический урон', 'kineticDamage', [5, 9, 13, 18], ['MAIN', 'IMPLANT'], 'offensive', '%', { op: 'INCREASED' }),
  A('AF_EDM', 'Энергетический урон', 'energyDamage', [5, 9, 13, 18], ['MAIN', 'IMPLANT'], 'offensive', '%', { op: 'INCREASED' }),
  A('AF_DDM', 'Цифровой урон', 'digitalDamage', [5, 9, 13, 18], ['MAIN', 'IMPLANT'], 'offensive', '%', { op: 'INCREASED' }),
  A('AF_AS', 'Скорость атаки', 'attackSpeed', [3, 5, 8, 10], ['MAIN', 'IMPLANT'], 'offensive', '%', { op: 'INCREASED' }),
  A('AF_CR', 'Шанс крита', 'critChance', [2, 3, 4, 5], ['MAIN', 'OFFHAND'], 'offensive', 'п.п.'),
  A('AF_CM', 'Крит. множитель', 'critMultiplier', [5, 10, 15, 20], ['MAIN', 'OFFHAND'], 'offensive', 'п.п.'),
  A('AF_PEN', 'Пробитие брони', 'armorPen', [3, 6, 9, 12], ['MAIN', 'OFFHAND'], 'offensive', 'ед.'),
  A('AF_EPN', 'Пробитие энергии', 'energyPen', [2, 3, 5, 7], ['MAIN', 'OFFHAND'], 'offensive', 'п.п.'),
  A('AF_DPN', 'Пробитие цифры', 'digitalPen', [2, 3, 5, 7], ['MAIN', 'OFFHAND'], 'offensive', 'п.п.'),
  A('AF_ER', 'Регенерация энергии', 'energyRegen', [1, 2, 3, 4], ['IMPLANT', 'OFFHAND'], 'resource', '/с'),
  A('AF_COO', 'Охлаждение', 'heatCooling', [1, 2, 3, 4], ['IMPLANT', 'OFFHAND'], 'resource', '/с'),
  A('AF_NC', 'Нейроёмкость', 'neuralCapacity', [4, 8, 12, 16], ['IMPLANT'], 'resource', 'ед.', { integer: true }),
  A('AF_DRO', 'Урон дронов', 'droneDamage', [5, 10, 15, 20], ['IMPLANT', 'OFFHAND'], 'offensive', '%', { op: 'INCREASED' }),
  A('AF_DHP', 'HP дронов', 'droneHP', [5, 10, 15, 20], ['IMPLANT', 'OFFHAND'], 'defensive', '%', { op: 'INCREASED' }),
  A('AF_VIR', 'Урон VIRUS', 'virusDamage', [5, 9, 13, 18], ['MAIN', 'IMPLANT'], 'offensive', '%', { op: 'INCREASED' }),
  A('AF_DOT', 'Длительность DoT', 'dotDuration', [4, 7, 10, 15], ['IMPLANT'], 'utility', '%', { op: 'INCREASED' }),
  A('AF_HEA', 'Сила лечения', 'healing', [5, 10, 15, 20], ['ARMOR', 'IMPLANT'], 'defensive', '%', { op: 'INCREASED' }),
  A('AF_SR', 'Регенерация щита', 'shieldRegen', [1, 2, 3, 4], ['ARMOR', 'OFFHAND'], 'resource', '/с'),
  A('AF_CDR', 'Восстановление CD', 'cooldownRecovery', [3, 5, 7, 10], ['IMPLANT'], 'utility', '%', { op: 'INCREASED' }),
  A('AF_FUEL', 'Запас топлива', 'fuelMax', [2, 3, 4, 6], ['ENGINE'], 'resource', 'ед.', { integer: true }),
  A('AF_CARGO', 'Вместимость груза', 'cargoUnits', [2, 4, 6, 8], ['CARGO'], 'resource', 'ед.', { integer: true }),
  A('AF_SCAN', 'Дальность разведки', 'scanRange', [1, 1, 2, 2], ['SCANNER'], 'utility', 'слоёв', { integer: true, fixed: true }),
  A('AF_ROAD', 'Скорость переезда', 'travelDurationLess', [2, 4, 6, 8], ['ENGINE'], 'utility', '%'),
];

export const AFFIX_BY_ID: Record<string, AffixDef> = Object.fromEntries(AFFIXES.map((a) => [a.id, a]));

/** Веса групп аффиксов по слоту (раздел 12). */
export const SLOT_GROUP_WEIGHTS: Record<string, Partial<Record<AffixGroup, number>>> = {
  MAIN: { offensive: 55, resource: 30, utility: 15 },
  ARMOR: { defensive: 70, resource: 20, utility: 10 },
  IMPLANT: { offensive: 33, defensive: 33, resource: 34 },
  OFFHAND: { offensive: 40, defensive: 30, resource: 30 },
  DRONE: { offensive: 40, defensive: 30, resource: 30 },
  ENGINE: { resource: 50, utility: 50 },
  CHASSIS: { defensive: 60, resource: 40 },
  SCANNER: { utility: 100 },
  SERVICE: { resource: 50, defensive: 50 },
  CARGO: { resource: 100 },
  SUPPORT: { offensive: 40, resource: 60 },
};

/** Транспорт получает только явно объявленные для него аффиксы. */
export function affixesForSlot(category: ItemCategory): AffixDef[] {
  return AFFIXES.filter((a) => a.slots.includes(category));
}

export function tierForTech(T: number): 1 | 2 | 3 | 4 {
  if (T <= 4) return 1;
  if (T <= 8) return 2;
  if (T <= 12) return 3;
  return 4;
}

export interface AffixRoll {
  affixId: string;
  tier: 1 | 2 | 3 | 4;
  value: number;
  rawRoll: number;
  tierBoosted: boolean;
  center: number;
  min: number;
  max: number;
}

export function affixEffect(roll: AffixRoll): StatEffect {
  const def = AFFIX_BY_ID[roll.affixId]!;
  return {
    type: 'stat',
    stat: def.stat,
    op: def.op ?? 'FLAT',
    value: roll.value,
    note: `${def.name} T${roll.tier}${def.scaleD ? ' ×D(T)' : ''}`,
  };
}

/** Технологический ресурс предмета по редкости. */
export const TR_RANGES: Record<string, [number, number]> = {
  COMMON: [8, 12],
  MODIFIED: [12, 18],
  RARE: [18, 28],
  LEGENDARY: [12, 20],
  UNIQUE: [0, 0],
};

export const RARITY_AFFIX_COUNT: Record<string, [number, number]> = {
  COMMON: [0, 0],
  MODIFIED: [1, 2],
  RARE: [3, 4],
  LEGENDARY: [4, 5],
  UNIQUE: [0, 2],
};

export const RARITY_PRICE_MULT: Record<string, number> = {
  COMMON: 1, MODIFIED: 1.3, RARE: 2, LEGENDARY: 4, UNIQUE: 10,
};
