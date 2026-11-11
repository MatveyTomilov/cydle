import { describe, expect, it } from 'vitest';
import {
  createCombatState, effectiveSheet, hasStatus, simulateCombat, stepCombat, type CombatState,
} from '../../src/core/combat/engine';
import type { CombatConfig, EncounterEnemySpec, TacticCondition, TacticRule, TacticalProfile } from '../../src/core/combat/types';
import type { ResolvedBuild } from '../../src/core/build/build';
import { resolveBuild } from '../../src/core/build/build';
import { createItem } from '../../src/core/items/items';
import { Rng, stateHash } from '../../src/core/rng';
import type { TargetMode } from '../../src/core/types';

const item = (id: string, templateId: string) => createItem(new Rng('loot', id), {
  templateId, techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: id, origin: 'test',
});

const buildWith = (skillIds: string[]): ResolvedBuild => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: item('kernel-pistol', 'PISTOL_K1') },
  skillIds,
  attributePointsEarned: 0,
  unlockedImplantSlots: 4,
  unlockedDroneSlots: 1,
});

const rule = (id: string, skillId: string, target: TargetMode, priority = 10, conditions: TacticCondition[] = [], logic: 'AND' | 'OR' = 'AND'): TacticRule =>
  ({ id, priority, enabled: true, skillId, target, conditions, logic });

const profile = (rules: TacticRule[]): TacticalProfile => ({ id: 'test', name: 'test', rules });

const cfg = (build: ResolvedBuild, seed: string, enemies: EncounterEnemySpec[], tactics: TacticalProfile, extra: Partial<CombatConfig> = {}): CombatConfig =>
  ({ seed, depth: 1, biome: 'B01', nodeType: 'COMBAT', build, enemies, tactics, maxDurationMs: 60000, ...extra });

const boss = (): EncounterEnemySpec[] => [{ templateId: 'BOSS_A' }];

function steps(s: CombatState, n: number): CombatState {
  for (let i = 0; i < n; i++) s = stepCombat(s);
  return s;
}

function stepUntil(s: CombatState, pred: (s: CombatState) => boolean, maxMs = 12000): CombatState {
  while (!pred(s) && s.timeMs < maxMs && !s.outcome) s = stepCombat(s);
  return s;
}

const reactions = (s: CombatState, skillId: string) =>
  s.log.filter((e) => e.kind === 'REACTION' && e.skillId === skillId);

const skillPackets = (s: CombatState, skillId: string) =>
  s.log.filter((e) => (e.kind === 'DAMAGE' || e.kind === 'MISS') && e.skillId === skillId);

/** Ручной прерываемый каст врага — как applyStatus в тестах статусов, до AI этапа 2d. */
function enemyCast(s: CombatState, index = 0): void {
  s.enemies[index]!.cast = {
    actionId: `enemy:${index}:ability:heavy`, skillId: null, startedAt: 0,
    resolveAt: 5000, endAt: 5000, targetId: 'operator',
    interruptible: true, telegraph: true, dangerTag: 'heavy', channel: 'main', abilityId: 'TEST_HEAVY',
  };
}

describe('reaction channel and interrupts (stage 2c)', () => {
  it('SK_SHIELD fires below 45% HP on the reaction channel and grants a capped temp shield', () => {
    const b = buildWith(['SK_SHIELD']);
    let s = createCombatState(cfg(b, 'shield', boss(), profile([
      rule('r1', 'SK_SHIELD', 'self', 10, [{ kind: 'hpBelow', value: 0.45 }]),
    ]), { startHpFraction: 0.4, startEnergy: 100 }));
    s = stepUntil(s, (x) => reactions(x, 'SK_SHIELD').length > 0);
    const react = reactions(s, 'SK_SHIELD')[0]!;
    expect(react.actorId).toBe('operator');
    const pool = s.operator.tempShields.find((p) => p.sourceId === 'SK_SHIELD')!;
    expect(pool.amount).toBe(60);
    expect(pool.cap).toBe(90);
    expect(pool.expiresAt).toBe(react.timestamp + 5000);
    expect(s.metrics.skillUses.SK_SHIELD).toBe(1);
    expect(s.log.some((e) => e.kind === 'SHIELD_GAIN')).toBe(true);
    const castStart = s.log.find((e) => e.kind === 'CAST_START' && e.skillId === 'SK_SHIELD')!;
    expect(s.operator.cooldowns.SK_SHIELD).toBe(castStart.timestamp + 20000);
    expect(s.metrics.energySpent).toBeGreaterThanOrEqual(30);
  });

  it('SK_SHIELD temp shield does not double-accumulate past its 90 cap', () => {
    const b = buildWith(['SK_SHIELD']);
    let s = createCombatState(cfg(b, 'shield-cap', boss(), profile([
      rule('r1', 'SK_SHIELD', 'self', 10, [{ kind: 'hpBelow', value: 0.45 }]),
    ]), { startHpFraction: 0.4, startEnergy: 100 }));
    s = stepUntil(s, (x) => reactions(x, 'SK_SHIELD').length >= 1);
    expect(s.operator.tempShields.find((p) => p.sourceId === 'SK_SHIELD')!.amount).toBe(60);
    s.operator.cooldowns.SK_SHIELD = 0;
    s.operator.energy = 100;
    s.operator.hp = 0.4 * s.operator.baseSheet.maxHP;
    s = stepUntil(s, (x) => reactions(x, 'SK_SHIELD').length >= 2);
    const pool = s.operator.tempShields.find((p) => p.sourceId === 'SK_SHIELD')!;
    expect(pool.amount).toBe(90);
    expect(pool.cap).toBe(90);
  });

  it('SK_GUARD applies GUARD that reduces effective incoming kinetic by 20%', () => {
    const b = buildWith(['SK_GUARD']);
    let s = createCombatState(cfg(b, 'guard', boss(), profile([rule('r1', 'SK_GUARD', 'self')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => hasStatus(x.operator, 'GUARD'));
    expect(hasStatus(s.operator, 'GUARD')).toBe(true);
    expect(effectiveSheet(s, s.operator).incomingKinetic).toBeCloseTo(0.8, 6);
    const apply = s.log.find((e) => e.kind === 'STATUS_APPLY' && e.statusId === 'GUARD')!;
    expect(apply.data?.durationMs).toBe(2000);
  });

  it('SK_VENT cools heat and releases heat lockout', () => {
    const b = buildWith(['SK_VENT']);
    let s = createCombatState(cfg(b, 'vent', boss(), profile([
      rule('r1', 'SK_VENT', 'self', 10, [{ kind: 'heatLocked' }]),
    ]), { startHeat: 100, startEnergy: 100 }));
    s.operator.heatLockout = true;
    s = stepUntil(s, (x) => reactions(x, 'SK_VENT').length > 0);
    expect(s.operator.heatLockout).toBe(false);
    expect(s.operator.heat).toBeLessThan(100);
    expect(s.log.some((e) => e.kind === 'HEAT_LOCKOUT_END')).toBe(true);
    expect(s.log.some((e) => e.kind === 'HEAT')).toBe(true);
  });

  it('SK_HEAL restores the capped 30 + 10% maxHP amount', () => {
    const b = buildWith(['SK_HEAL']);
    let s = createCombatState(cfg(b, 'heal', boss(), profile([
      rule('r1', 'SK_HEAL', 'self', 10, [{ kind: 'hpBelow', value: 0.9 }]),
    ]), { startHpFraction: 0.5, startEnergy: 100 }));
    s = stepUntil(s, (x) => reactions(x, 'SK_HEAL').length > 0);
    const maxHP = effectiveSheet(s, s.operator).maxHP;
    const expected = Math.min(30 + 0.10 * maxHP, 0.22 * maxHP);
    const heal = s.log.find((e) => e.kind === 'HEAL' && e.skillId === undefined)!;
    expect(heal).toBeTruthy();
    expect(heal.data?.amount).toBeCloseTo(expected, 6);
    expect(s.metrics.healingDone).toBeCloseTo(expected, 6);
  });

  it('SK_DRONE_MARK marks the boss for drones for 5 seconds', () => {
    const b = resolveBuild({
      attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
      equipment: { MAIN: item('kernel-pistol', 'PISTOL_K1'), DRONE_1: item('drone-gun', 'DR_GUN') },
      skillIds: ['SK_DRONE_MARK'],
      attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
    });
    let s = createCombatState(cfg(b, 'dmark', boss(), profile([rule('r1', 'SK_DRONE_MARK', 'boss')]), { startEnergy: 100 }));
    expect(s.drones).toHaveLength(1);
    s = stepUntil(s, (x) => hasStatus(x.enemies[0]!, 'DRONE_MARK'));
    expect(hasStatus(s.enemies[0]!, 'DRONE_MARK')).toBe(true);
    const apply = s.log.find((e) => e.kind === 'STATUS_APPLY' && e.statusId === 'DRONE_MARK')!;
    expect(apply.targetId).toBe('enemy:0');
    expect(apply.data?.durationMs).toBe(5000);
  });

  it('SK_EMP interrupts an interruptible enemy cast and deals digital damage', () => {
    const b = buildWith(['SK_EMP']);
    let s = createCombatState(cfg(b, 'emp', boss(), profile([rule('r1', 'SK_EMP', 'imminentCast')]), { startEnergy: 100 }));
    enemyCast(s);
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'CAST_INTERRUPT'));
    expect(s.enemies[0]!.cast).toBeNull();
    expect(s.metrics.interrupts).toBe(1);
    const interrupt = s.log.find((e) => e.kind === 'CAST_INTERRUPT')!;
    expect(interrupt.targetId).toBe('enemy:0');
    expect(reactions(s, 'SK_EMP')).toHaveLength(1);
    expect(skillPackets(s, 'SK_EMP').length).toBeGreaterThanOrEqual(1);
    expect(skillPackets(s, 'SK_EMP')[0]!.damageType).toBe('DIGITAL');
  });

  it('SK_EMP records no_interruptible when no enemy is casting', () => {
    const b = buildWith(['SK_EMP']);
    let s = createCombatState(cfg(b, 'emp-none', boss(), profile([rule('r1', 'SK_EMP', 'imminentCast')]), { startEnergy: 100 }));
    s = steps(s, 5);
    expect(s.metrics.ruleFailures.some((f) => f.ruleId === 'r1' && f.reason === 'no_interruptible')).toBe(true);
    expect(reactions(s, 'SK_EMP')).toHaveLength(0);
  });

  it('runs reaction and main channels independently (both casts active at once)', () => {
    const b = buildWith(['SK_BURST', 'SK_SHIELD']);
    let s = createCombatState(cfg(b, 'indep', boss(), profile([
      rule('rs', 'SK_SHIELD', 'self', 20, [{ kind: 'hpBelow', value: 0.45 }]),
      rule('rm', 'SK_BURST', 'nearest', 10),
    ]), { startHpFraction: 0.4, startEnergy: 100 }));
    s.operator.nextAttackAt = 0;
    s = stepCombat(s);
    expect(s.operator.reactionCast?.skillId).toBe('SK_SHIELD');
    expect(s.operator.cast?.skillId).toBe('SK_BURST');
  });

  it('records an energy failure and does not fire the reaction when energy is insufficient', () => {
    const b = buildWith(['SK_SHIELD']);
    let s = createCombatState(cfg(b, 'shield-energy', boss(), profile([
      rule('r1', 'SK_SHIELD', 'self', 10, [{ kind: 'hpBelow', value: 0.45 }]),
    ]), { startHpFraction: 0.4, startEnergy: 0 }));
    s = steps(s, 5);
    expect(s.metrics.ruleFailures.some((f) => f.ruleId === 'r1' && f.reason === 'energy')).toBe(true);
    expect(reactions(s, 'SK_SHIELD')).toHaveLength(0);
  });

  it('keeps reaction combat deterministic for a shared build', () => {
    const shared = buildWith(['SK_SHIELD', 'SK_EMP', 'SK_BURST']);
    const tactics = profile([
      rule('rs', 'SK_SHIELD', 'self', 30, [{ kind: 'hpBelow', value: 0.45 }]),
      rule('re', 'SK_EMP', 'imminentCast', 20),
      rule('rm', 'SK_BURST', 'nearest', 10),
    ]);
    const c = cfg(shared, 'det-react', boss(), tactics, { startHpFraction: 0.4, startEnergy: 100 });
    const a = simulateCombat(c);
    const b = simulateCombat(c);
    expect(Object.keys(a.metrics.skillUses).length).toBeGreaterThan(0);
    expect(stateHash(a)).toBe(stateHash(b));
  });

  it('does not mutate the input state when stepping a reaction combat', () => {
    const b = buildWith(['SK_SHIELD']);
    const s = createCombatState(cfg(b, 'purity-react', boss(), profile([
      rule('r1', 'SK_SHIELD', 'self', 10, [{ kind: 'hpBelow', value: 0.45 }]),
    ]), { startHpFraction: 0.4, startEnergy: 100 }));
    const before = stateHash(s);
    const next = stepCombat(s);
    expect(stateHash(s)).toBe(before);
    expect(next.timeMs).toBe(100);
    expect(s.timeMs).toBe(0);
  });
});