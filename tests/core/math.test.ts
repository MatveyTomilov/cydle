import { describe, expect, it } from 'vitest';
import { mitigatePacket, partitionDamage, ZERO_PEN } from '../../src/core/math/damage';
import { bundle, mod, resolveStats } from '../../src/core/math/stats';

const source = { id: 'test', name: 'Тест', kind: 'base' as const };

describe('CYDLE math contract', () => {
  it('keeps the published armor example exact and traceable', () => {
    const stats = resolveStats(bundle([mod('armor', 'INCREASED', 20, source)]));

    expect(stats.armor.value).toBe(6);
    expect(stats.armor.trace.exactValue).toBe(6);
  });

  it('matches the published flat, increased, and MORE armor example', () => {
    const stats = resolveStats(bundle([
      mod('armor', 'FLAT', 2, source),
      mod('armor', 'INCREASED', 20, { ...source, id: 'implant' }),
      mod('armor', 'MORE', 1.1, { ...source, id: 'more' }),
    ]));

    expect(stats.armor.value).toBeCloseTo(9.24, 12);
  });

  it('sums INCREASED in one group and multiplies independent MORE stages', () => {
    const stats = resolveStats(bundle([
      mod('armor', 'INCREASED', 20, { ...source, id: 'implant' }),
      mod('armor', 'INCREASED', 30, { ...source, id: 'tree' }),
      mod('armor', 'MORE', 1.2, { ...source, id: 'more-1' }),
      mod('armor', 'MORE', 1.3, { ...source, id: 'more-2' }),
    ]));

    expect(stats.armor.value).toBeCloseTo(5 * 1.5 * 1.2 * 1.3, 12);
  });

  it('applies kinetic armor reduction from the spec', () => {
    const result = mitigatePacket(100, 'KINETIC', { armor: 5, energyRes: 0, digitalRes: 0 }, ZERO_PEN);

    expect(result.afterDefense).toBeCloseTo(100 * (1 - 5 / 105), 12);
  });

  it('applies resistance penetration and the documented vulnerability cap', () => {
    const resisted = mitigatePacket(100, 'ENERGY', { armor: 0, energyRes: 50, digitalRes: 0 }, {
      ...ZERO_PEN, energyPenPercent: 50, energyPen: 5,
    });
    const vulnerable = mitigatePacket(100, 'DIGITAL', { armor: 0, energyRes: 0, digitalRes: -90 }, ZERO_PEN);

    expect(resisted.resistanceAfterPen).toBeCloseTo(0.2, 12);
    expect(resisted.afterDefense).toBeCloseTo(80, 12);
    expect(vulnerable.resistanceAfterPen).toBe(-0.5);
    expect(vulnerable.afterDefense).toBe(150);
  });

  it('spends ordinary shield before HP and logs the partition', () => {
    const result = partitionDamage(50, { hp: 200, shield: 30, temp: [] }, 0);

    expect(result.shieldConsumed).toBe(30);
    expect(result.hpLost).toBe(20);
    expect(result.trace.exactValue).toBe(50);
  });

  it('applies the shield-only multiplier to shield absorption and passes overflow to HP', () => {
    const result = partitionDamage(10, { hp: 100, shield: 10, temp: [] }, 0, 2);

    expect(result.shieldConsumed).toBe(10);
    expect(result.hpLost).toBe(5);
  });

  it('routes bypassed damage directly to HP before shield damage', () => {
    const result = partitionDamage(20, { hp: 100, shield: 10, temp: [] }, 0.25, 2);

    expect(result.bypassed).toBe(5);
    expect(result.shieldConsumed).toBe(10);
    expect(result.hpLost).toBe(15);
  });

  it('routes all non-bypassed damage through to HP when shields take zero damage', () => {
    const result = partitionDamage(10, { hp: 100, shield: 50, temp: [] }, 0, 0);

    expect(result.shieldConsumed).toBe(0);
    expect(result.hpLost).toBe(10);
  });
});
