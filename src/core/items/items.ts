import type { AffixRoll } from '../../data/affixes';
import { AFFIX_BY_ID, affixEffect, RARITY_AFFIX_COUNT, TR_RANGES, tierForTech, SLOT_GROUP_WEIGHTS, affixesForSlot } from '../../data/affixes';
import { ITEM_BY_ID } from '../../data/items';
import { UNIQUE_TEMPLATE_BY_ID, UNIQUE_BY_ID, uniquesForBiome } from '../../data/uniques';
import type { ItemTemplate } from '../../data/types';
import { H, D, R, clamp } from '../math/formula';
import type { Rng } from '../rng';
import type { BiomeId, ItemCategory, Rarity } from '../types';

export interface ItemInstance {
  itemId: string;
  templateId: string;
  techLevel: number;
  rarity: Rarity;
  affixes: AffixRoll[];
  uniqueEffectIds: string[];
  neuralCost: number;
  durability: number;
  secured: boolean;
  originGrantId: string;
  rollSeed: string;
  tr: number;
  coreGroup?: number;
  acquiredAt: number;
  origin: string;
  /** Для ядер калибровки — технологическая группа. */
  label?: string;
}

export function templateOf(item: ItemInstance): ItemTemplate {
  return UNIQUE_TEMPLATE_BY_ID[item.templateId] ?? ITEM_BY_ID[item.templateId]!;
}

export function coreGroupForDepth(d: number): number {
  if (d <= 4) return 1;
  if (d <= 8) return 2;
  if (d <= 12) return 3;
  return 4;
}
export const CORE_GROUP_LABEL: Record<number, string> = { 1: '1–4', 2: '5–8', 3: '9–12', 4: '13+' };

export interface CreateItemOptions {
  templateId: string;
  techLevel: number;
  rarity: Rarity;
  secured: boolean;
  originGrantId: string;
  origin: string;
  acquiredAt?: number;
  affixCount?: number;
  forceAffixes?: string[];
}

/** Генерация экземпляра предмета: rarity → число аффиксов → tier → roll. */
export function createItem(rng: Rng, opts: CreateItemOptions): ItemInstance {
  const tpl = UNIQUE_TEMPLATE_BY_ID[opts.templateId] ?? ITEM_BY_ID[opts.templateId];
  if (!tpl) throw new Error(`Неизвестный шаблон предмета: ${opts.templateId}`);
  const T = Math.max(1, Math.round(opts.techLevel));
  const rarity = opts.rarity;
  const [minA, maxA] = RARITY_AFFIX_COUNT[rarity]!;
  let count = opts.affixCount ?? (minA === maxA ? minA : rng.chance(0.5) ? minA : maxA);
  if (rarity === 'COMMON') count = 0;
  const affixes: AffixRoll[] = [];
  if (count > 0) {
    const pool = affixesForSlot(tpl.category);
    const weights = SLOT_GROUP_WEIGHTS[tpl.category] ?? { offensive: 34, defensive: 33, resource: 33 };
    const used = new Set<string>();
    const boostedAllowed = rarity === 'RARE' || rarity === 'LEGENDARY';
    for (let i = 0; i < count; i++) {
      const candidates = pool.filter((a) => !used.has(a.id));
      if (!candidates.length) break;
      const chosen = rng.weighted(candidates.map((a) => ({ item: a, weight: weights[a.group] ?? 1 })));
      used.add(chosen.id);
      let tier = tierForTech(T);
      let boosted = false;
      if (boostedAllowed && tier < 4 && rng.chance(0.2)) {
        tier = (tier + 1) as 1 | 2 | 3 | 4;
        boosted = true;
      }
      const center = chosen.tiers[tier - 1]!;
      const raw = chosen.fixed ? 1 : rng.range(0.8, 1.2);
      let value = center * raw;
      value = chosen.integer ? Math.max(1, Math.round(value)) : Math.round(value * 100) / 100;
      affixes.push({
        affixId: chosen.id, tier, value, rawRoll: Math.round(raw * 10000) / 10000, tierBoosted: boosted,
        center, min: chosen.integer ? Math.max(1, Math.round(center * 0.8)) : Math.round(center * 0.8 * 100) / 100,
        max: chosen.integer ? Math.round(center * 1.2) : Math.round(center * 1.2 * 100) / 100,
      });
    }
  }
  const [trMin, trMax] = TR_RANGES[rarity]!;
  const tr = trMin === trMax ? trMin : rng.int(trMin, trMax);
  return {
    // Reward grants are idempotent; deriving identity from the grant keeps replays stable.
    itemId: `it:${encodeURIComponent(opts.originGrantId)}:${encodeURIComponent(opts.templateId)}`,
    templateId: opts.templateId,
    techLevel: T,
    rarity,
    affixes,
    uniqueEffectIds: tpl.uniqueEffectId ? [tpl.uniqueEffectId] : [],
    neuralCost: tpl.neuralCost ?? 0,
    durability: 100,
    secured: opts.secured,
    originGrantId: opts.originGrantId,
    rollSeed: `${rng.stream}:${rng.calls}`,
    tr,
    acquiredAt: opts.acquiredAt ?? 0,
    origin: opts.origin,
  };
}

export function createCore(rng: Rng, depth: number, grantId: string, secured: boolean): ItemInstance {
  const group = coreGroupForDepth(depth);
  const item = createItem(rng, { templateId: 'MAT_CORE', techLevel: depth, rarity: 'COMMON', secured, originGrantId: grantId, origin: 'core' });
  item.coreGroup = group;
  item.label = `Ядро группы ${CORE_GROUP_LABEL[group]}`;
  return item;
}

export const RARITY_TABLES: Record<'ORDINARY' | 'ELITE' | 'BOSS', [number, number, number, number, number]> = {
  ORDINARY: [60, 28, 10, 1.8, 0.2],
  ELITE: [30, 35, 25, 8.5, 1.5],
  BOSS: [10, 20, 38, 25, 7],
};

export function rollRarity(rng: Rng, table: 'ORDINARY' | 'ELITE' | 'BOSS', rareShift = 0): Rarity {
  const base = [...RARITY_TABLES[table]] as [number, number, number, number, number];
  if (rareShift > 0) {
    const shift = Math.min(base[0], rareShift * 100);
    base[0] -= shift;
    base[2] += shift;
  }
  const r = rng.next() * 100;
  let acc = 0;
  const order: Rarity[] = ['COMMON', 'MODIFIED', 'RARE', 'LEGENDARY', 'UNIQUE'];
  for (let i = 0; i < 5; i++) {
    acc += base[i]!;
    if (r < acc) return order[i]!;
  }
  return 'COMMON';
}

/** Пул предметов биома с весами по тегам. */
export function biomeItemPool(biome: BiomeId, energyWeightBonus = 0): { item: ItemTemplate; weight: number }[] {
  const tagsByBiome: Record<string, string[]> = {
    B01: ['weapon', 'speed', 'pistol', 'smg'],
    B02: ['armor', 'shield'],
    B03: ['drone', 'craft', 'transport'],
    B04: ['digital', 'virus'],
    B05: ['heat', 'energy'],
    B06: ['unique', 'conversion', 'hybrid', 'heavy'],
  };
  const tags = tagsByBiome[biome] ?? [];
  const all = Object.values(ITEM_BY_ID).filter((t) => t.craftable && t.category !== 'MATERIAL');
  return all.map((t) => {
    let w = 1;
    if (t.tags.some((x) => tags.includes(x))) w += 3;
    if (energyWeightBonus > 0 && t.tags.includes('energy')) w *= 1 + energyWeightBonus;
    return { item: t, weight: w };
  });
}

export interface LootRollOptions {
  depth: number;
  biome: BiomeId;
  table: 'ORDINARY' | 'ELITE' | 'BOSS';
  secured: boolean;
  grantId: string;
  origin: string;
  energyWeightBonus?: number;
  rareShift?: number;
  techOffsetOverride?: number;
  forceCategory?: ItemCategory;
  forceTag?: string;
  forceRarity?: Rarity;
  forceTemplateId?: string;
  discoveredUniques?: string[];
}

export interface LootResult {
  item: ItemInstance;
  fallbackFromUnique?: boolean;
  rarity: Rarity;
}

export function rollItem(rng: Rng, o: LootRollOptions): LootResult {
  let rarity = o.forceRarity ?? rollRarity(rng, o.table, o.rareShift ?? 0);
  let fallback = false;
  const offsetRoll = rng.next();
  const offset = o.techOffsetOverride ?? (offsetRoll < 0.2 ? -1 : offsetRoll < 0.85 ? 0 : 1);
  const T = Math.max(1, o.depth + offset);
  let templateId = o.forceTemplateId;
  if (!templateId) {
    if (rarity === 'UNIQUE') {
      let pool = uniquesForBiome(o.biome);
      if (o.forceTag) pool = pool.filter((u) => (UNIQUE_TEMPLATE_BY_ID[u.id]?.tags ?? []).includes(o.forceTag!));
      if (o.forceCategory) pool = pool.filter((u) => UNIQUE_TEMPLATE_BY_ID[u.id]?.category === o.forceCategory);
      if (!pool.length) {
        rarity = 'LEGENDARY';
        fallback = true;
      } else {
        templateId = rng.pick(pool).id;
      }
    }
    if (!templateId) {
      let pool = biomeItemPool(o.biome, o.energyWeightBonus ?? 0);
      if (o.forceCategory) pool = pool.filter((p) => p.item.category === o.forceCategory);
      if (o.forceTag) pool = pool.filter((p) => p.item.tags.includes(o.forceTag!));
      if (!pool.length) pool = biomeItemPool(o.biome);
      templateId = rng.weighted(pool).id;
    }
  }
  const item = createItem(rng, {
    templateId, techLevel: T, rarity, secured: o.secured, originGrantId: o.grantId, origin: o.origin,
  });
  return { item, fallbackFromUnique: fallback, rarity };
}

/** Цена покупки в магазине (раздел 19.2). */
export function shopPrice(templateId: string, T: number, rarity: Rarity): number {
  const mult = { COMMON: 1, MODIFIED: 1.3, RARE: 2, LEGENDARY: 4, UNIQUE: 10 }[rarity];
  return Math.ceil((25 + 7 * T) * mult * R(T));
}

export function sellValue(templateId: string, T: number, rarity: Rarity): number {
  return Math.floor(shopPrice(templateId, T, rarity) * 0.25);
}

export function dismantleValue(item: ItemInstance): { scrap: number; data: number } {
  const tpl = templateOf(item);
  const scrap = Math.ceil(3 * R(item.techLevel));
  const data = tpl.tags.includes('digital') ? 1 : 0;
  const craftScrap = Math.ceil(18 * R(item.techLevel));
  return { scrap: Math.min(scrap, Math.floor(craftScrap * 0.6)), data };
}

export function repairCost(item: ItemInstance, discountPct = 0): number {
  const raw = Math.ceil(((100 - item.durability) / 10) * (2 + item.techLevel / 5));
  return Math.max(item.durability >= 100 ? 0 : 1, Math.ceil(raw * (1 - clamp(discountPct, 0, 80) / 100)));
}

export function craftCost(T: number): { scrap: number; data: number } {
  return { scrap: Math.ceil(18 * R(T)), data: Math.ceil(10 * R(T)) };
}

export interface CalibrationCost {
  scrap: number;
  data: number;
  cores: number;
  coreGroup: number;
}

export function calibrationCost(item: ItemInstance, targetT: number, scrapDiscountPct = 0): CalibrationCost {
  const steps = Math.max(0, targetT - item.techLevel);
  const scrap = Math.ceil(Math.ceil(5 * steps * R(targetT)) * (1 - clamp(scrapDiscountPct, 0, 80) / 100));
  const data = Math.ceil(2 * steps * R(targetT));
  const cores = Math.ceil(steps / 4);
  return { scrap, data, cores, coreGroup: coreGroupForDepth(targetT) };
}

/** Операции крафта (раздел 12). */
export type CraftOperation = 'REROLL' | 'TIER_UP' | 'REPLACE' | 'ADD';

export const CRAFT_TR_COST: Record<CraftOperation, number> = { REROLL: 3, TIER_UP: 6, REPLACE: 8, ADD: 10 };

export function craftOperationCost(op: CraftOperation, T: number): { scrap: number; data: number; tr: number } {
  const tr = CRAFT_TR_COST[op];
  switch (op) {
    case 'REROLL': return { scrap: Math.ceil(10 * R(T)), data: 0, tr };
    case 'TIER_UP': return { scrap: Math.ceil(20 * R(T)), data: Math.ceil(5 * R(T)), tr };
    case 'REPLACE': return { scrap: 0, data: Math.ceil(12 * R(T)), tr };
    case 'ADD': return { scrap: Math.ceil(20 * R(T)), data: Math.ceil(10 * R(T)), tr };
  }
}

export function affixName(roll: AffixRoll): string {
  return AFFIX_BY_ID[roll.affixId]?.name ?? roll.affixId;
}

export function itemDisplayName(item: ItemInstance): string {
  const tpl = templateOf(item);
  return tpl.name;
}

export function itemStatEffects(item: ItemInstance) {
  const tpl = templateOf(item);
  return [...tpl.effects, ...item.affixes.map(affixEffect)];
}

export function uniqueDesc(item: ItemInstance): string | null {
  const id = item.uniqueEffectIds[0];
  return id ? UNIQUE_BY_ID[id]?.desc ?? null : null;
}

export { H, D, R };
