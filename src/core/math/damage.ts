import type { DamageType } from '../types';
import { clamp } from './formula';
import { node, type TraceNode } from './trace';

export interface DefenseSnapshot {
  armor: number;
  energyRes: number; // percentage points
  digitalRes: number;
}

export interface PenetrationSnapshot {
  armorPen: number;
  armorPenPercent: number; // percentage points 0..100
  energyPen: number;
  energyPenPercent: number;
  digitalPen: number;
  digitalPenPercent: number;
}

export const ZERO_PEN: PenetrationSnapshot = {
  armorPen: 0, armorPenPercent: 0, energyPen: 0, energyPenPercent: 0, digitalPen: 0, digitalPenPercent: 0,
};

export function pHit(accuracy: number, evasion: number): number {
  const acc = Math.max(1e-9, accuracy);
  return clamp(acc / (acc + Math.max(0, evasion)), 0.05, 0.99);
}

export function pCrit(critChancePoints: number): number {
  return clamp(critChancePoints / 100, 0, 0.95);
}

export function armorEffective(armor: number, flatPen: number, percentPenPoints: number): number {
  return Math.max(0, (armor - flatPen) * (1 - clamp(percentPenPoints / 100, 0, 1)));
}

export function kineticReduction(armorEff: number): number {
  return Math.min(0.85, armorEff / (armorEff + 100));
}

export function resistanceAfterPen(resPoints: number, percentPenPoints: number, flatPenPoints: number): number {
  const res = resPoints / 100;
  const pct = clamp(percentPenPoints / 100, 0, 1);
  const after = res - Math.max(0, res) * pct - flatPenPoints / 100;
  return Math.max(-0.5, Math.min(0.75, after));
}

export interface MitigationResult {
  type: DamageType;
  raw: number;
  armorEff: number;
  reduction: number; // доля снятого (для K) или сопротивление (E/D)
  resistanceAfterPen: number;
  afterDefense: number;
  trace: TraceNode;
}

/** Защита одного пакета. Пробитие применяется ровно один раз. */
export function mitigatePacket(raw: number, type: DamageType, def: DefenseSnapshot, pen: PenetrationSnapshot): MitigationResult {
  let armorEff = 0;
  let reduction = 0;
  let resAfter = 0;
  if (type === 'KINETIC') {
    armorEff = armorEffective(def.armor, pen.armorPen, pen.armorPenPercent);
    reduction = kineticReduction(armorEff);
  } else if (type === 'ENERGY') {
    resAfter = resistanceAfterPen(def.energyRes, pen.energyPenPercent, pen.energyPen);
    reduction = resAfter;
  } else {
    resAfter = resistanceAfterPen(def.digitalRes, pen.digitalPenPercent, pen.digitalPen);
    reduction = resAfter;
  }
  const afterDefense = raw * (1 - reduction);
  const trace = node('MULTIPLY', 'защита', afterDefense, {
    sourceId: `defense:${type}`,
    sourceName: type === 'KINETIC' ? 'Броня цели' : type === 'ENERGY' ? 'Сопротивление энергии' : 'Сопротивление цифре',
    unit: 'ед.',
    inputs: [raw, armorEff, reduction, afterDefense],
    localizedExplanation:
      type === 'KINETIC'
        ? `armorEff = max(0,(${def.armor} − ${pen.armorPen}) × (1 − ${pen.armorPenPercent / 100})) = ${armorEff}; снижение = ${armorEff}/(${armorEff}+100) = ${reduction}; ${raw} × (1 − ${reduction}) = ${afterDefense}`
        : `res после пробития = ${resAfter}; ${raw} × (1 − ${resAfter}) = ${afterDefense}`,
    children: [
      node('DIVIDE', 'пробитие', type === 'KINETIC' ? armorEff : resAfter, {
        sourceId: 'pen', sourceName: 'Пробитие', unit: type === 'KINETIC' ? 'ед.' : 'доля',
        inputs: type === 'KINETIC' ? [def.armor, pen.armorPen, pen.armorPenPercent] : [type === 'ENERGY' ? def.energyRes : def.digitalRes, type === 'ENERGY' ? pen.energyPen : pen.digitalPen, type === 'ENERGY' ? pen.energyPenPercent : pen.digitalPenPercent],
        localizedExplanation: 'Пробитие применяется один раз к защите пакета',
      }),
    ],
  });
  return { type, raw, armorEff, reduction, resistanceAfterPen: resAfter, afterDefense, trace };
}

export interface TempShieldPool {
  sourceId: string;
  amount: number;
  cap: number;
  expiresAt: number;
}

export interface PoolPartition {
  shieldConsumed: number;
  tempConsumed: { sourceId: string; amount: number }[];
  hpLost: number;
  bypassed: number;
  overkill: number;
  trace: TraceNode;
}

/**
 * Распределение урона: bypass напрямую в HP, остальное сначала временные щиты
 * (по истечению — раньше), затем обычный щит, затем HP.
 */
export function partitionDamage(
  incoming: number,
  pools: { hp: number; shield: number; temp: TempShieldPool[] },
  bypassShieldRatio: number,
  incomingShieldMultiplier = 1,
): PoolPartition {
  const bypass = incoming * clamp(bypassShieldRatio, 0, 1);
  let remaining = incoming - bypass;
  const tempConsumed: { sourceId: string; amount: number }[] = [];
  let shieldConsumed = 0;

  const sorted = [...pools.temp].sort((a, b) => a.expiresAt - b.expiresAt || a.sourceId.localeCompare(b.sourceId));
  for (const p of sorted) {
    if (remaining <= 0) break;
    const take = Math.min(p.amount, remaining);
    if (take > 0) {
      tempConsumed.push({ sourceId: p.sourceId, amount: take * incomingShieldMultiplier > 0 ? take : take });
      remaining -= take;
      shieldConsumed += take;
    }
  }
  if (remaining > 0) {
    const take = Math.min(pools.shield, remaining);
    shieldConsumed += take;
    remaining -= take;
  }
  const hpDamage = bypass + remaining;
  const hpLost = Math.min(pools.hp, hpDamage);
  const overkill = Math.max(0, hpDamage - pools.hp);
  const trace = node('SUM', 'щиты/HP', incoming, {
    sourceId: 'partition', sourceName: 'Распределение урона', unit: 'ед.',
    inputs: [incoming, bypass, shieldConsumed, hpLost, overkill],
    localizedExplanation: `Обход щита ${bypass}, поглощено щитом ${shieldConsumed}, потеря HP ${hpLost}${overkill > 0 ? `, overkill ${overkill}` : ''}`,
  });
  return { shieldConsumed, tempConsumed, hpLost, bypassed: bypass, overkill, trace };
}

/** Теоретический EHP против одного типа урона (сценарный EHP считается симуляцией). */
export function simpleEHP(hp: number, shield: number, def: DefenseSnapshot, type: DamageType, pen: PenetrationSnapshot = ZERO_PEN): number {
  const m = mitigatePacket(1, type, def, pen);
  const factor = 1 - m.reduction;
  if (factor <= 0) return Infinity;
  return (hp + shield) / factor;
}
