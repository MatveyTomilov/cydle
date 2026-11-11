import { describe, expect, it } from 'vitest';
import {
  applyStatus, createCombatState, effectiveSheet, hasStatus, statusStacks, stepCombat, type CombatState,
} from '../../src/core/combat/engine';
import { createItem } from '../../src/core/items/items';
import { Rng, stateHash } from '../../src/core/rng';
import { resolveBuild } from '../../src/core/build/build';
import type { TacticalProfile } from '../../src/core/combat/types';

const item = (id: string, templateId: string) => createItem(new Rng('loot', id), {
  templateId, techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: id, origin: 'test',
});

const build = () => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: item('kernel-pistol', 'PISTOL_K1') },
  attributePointsEarned: 0,
  unlockedImplantSlots: 4,
  unlockedDroneSlots: 1,
});

const tactics: TacticalProfile = { id: 'test', name: 'test', rules: [] };

// Босс с большим HP — цель не погибает от автоатак за время наблюдения DoT.
const bossConfig = (seed: string) => ({
  seed, depth: 1, biome: 'B01' as const, nodeType: 'BOSS' as const,
  build: build(), enemies: [{ templateId: 'BOSS_A' }], tactics,
  maxDurationMs: 60000,
});

function steps(state: CombatState, n: number): CombatState {
  let s = state;
  for (let i = 0; i < n; i++) s = stepCombat(s);
  return s;
}

const dotTicks = (s: CombatState, statusId: string) =>
  s.log.filter((e) => e.kind === 'DOT_TICK' && e.statusId === statusId);

describe('combat statuses and DoT (stage 2a)', () => {
  it('BLEED ticks once per second from its snapshot and expires after its duration', () => {
    let s = createCombatState(bossConfig('bleed'));
    applyStatus(s, s.operator, s.enemies[0]!, 'BLEED', { snapshot: 100 });
    expect(statusStacks(s.enemies[0]!, 'BLEED')).toBe(1);

    s = steps(s, 39); // 3900 ms → тики на 1000/2000/3000
    expect(s.timeMs).toBe(3900);
    expect(dotTicks(s, 'BLEED')).toHaveLength(3);
    expect(hasStatus(s.enemies[0]!, 'BLEED')).toBe(true);

    s = steps(s, 2); // 4000 (финальный тик + истечение), 4100
    expect(s.timeMs).toBe(4100);
    expect(dotTicks(s, 'BLEED')).toHaveLength(4);
    expect(hasStatus(s.enemies[0]!, 'BLEED')).toBe(false);

    const first = dotTicks(s, 'BLEED')[0]!;
    expect(first.amountBeforeDefense).toBeCloseTo(3, 6); // 100 × 0.03
    expect(first.damageType).toBe('KINETIC');
    expect(s.metrics.statusTicks).toBeGreaterThanOrEqual(4);
  });

  it('VIRUS snapshots the source TechPower at application time', () => {
    let s = createCombatState(bossConfig('virus'));
    const techPower = s.operator.baseSheet.techPower;
    expect(techPower).toBeGreaterThan(0);
    applyStatus(s, s.operator, s.enemies[0]!, 'VIRUS', {});
    s = steps(s, 10); // 1000 ms → первый тик
    const tick = dotTicks(s, 'VIRUS')[0]!;
    expect(tick).toBeTruthy();
    expect(tick.amountBeforeDefense).toBeCloseTo(techPower * 0.06, 6);
    expect(tick.damageType).toBe('DIGITAL');
  });

  it('ARMOR_BREAK lowers effective armor by 10 per stack through the unified pipeline', () => {
    const s = createCombatState(bossConfig('armor-break'));
    const boss = s.enemies[0]!;
    const baseArmor = boss.baseSheet.armor;
    applyStatus(s, s.operator, boss, 'ARMOR_BREAK', { stacks: 2 });
    expect(statusStacks(boss, 'ARMOR_BREAK')).toBe(2);
    expect(effectiveSheet(s, boss).armor).toBe(baseArmor - 20);
  });

  it('STUN applies boss half-duration and a 3 s internal cooldown', () => {
    const s = createCombatState(bossConfig('stun'));
    const boss = s.enemies[0]!;
    applyStatus(s, s.operator, boss, 'STUN', {});
    expect(boss.statuses.STUN![0]!.expiresAt).toBe(400); // 800 × 0.5
    expect(boss.icds.STUN).toBe(3000);
    applyStatus(s, s.operator, boss, 'STUN', {}); // заблокировано ICD
    expect(boss.statuses.STUN!).toHaveLength(1);
    expect(boss.statuses.STUN![0]!.expiresAt).toBe(400);
  });

  it('caps independent BLEED stacks at 10', () => {
    const s = createCombatState(bossConfig('cap'));
    const boss = s.enemies[0]!;
    for (let i = 0; i < 12; i++) applyStatus(s, s.operator, boss, 'BLEED', { snapshot: 10 });
    expect(boss.statuses.BLEED!).toHaveLength(10);
    expect(statusStacks(boss, 'BLEED')).toBe(10);
  });

  it('keeps status application and DoT fully deterministic for a shared build', () => {
    const shared = build();
    const cfg = {
      seed: 'det', depth: 1, biome: 'B01' as const, nodeType: 'BOSS' as const,
      build: shared, enemies: [{ templateId: 'BOSS_A' }], tactics, maxDurationMs: 60000,
    };
    const run = () => {
      let s = createCombatState(cfg);
      applyStatus(s, s.operator, s.enemies[0]!, 'BLEED', { snapshot: 80 });
      applyStatus(s, s.operator, s.enemies[0]!, 'VIRUS', {});
      return steps(s, 50);
    };
    const a = run();
    const b = run();
    expect(a.metrics.statusTicks).toBeGreaterThan(0);
    expect(stateHash(a)).toBe(stateHash(b));
  });

  it('does not mutate the input state when applying statuses or stepping', () => {
    const s = createCombatState(bossConfig('purity'));
    const before = stateHash(s);
    const next = stepCombat(s);
    expect(stateHash(s)).toBe(before);
    expect(next.timeMs).toBe(100);
    expect(s.timeMs).toBe(0);
  });
});