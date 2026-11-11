import { describe, expect, it } from 'vitest';
import {
  applyStatus, createCombatState, effectiveSheet, hasStatus, simulateCombat, statusStacks, stepCombat, type CombatState,
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

const skillPackets = (s: CombatState, skillId: string) =>
  s.log.filter((e) => (e.kind === 'DAMAGE' || e.kind === 'MISS') && e.skillId === skillId);

describe('active skills and tactical rules (stage 2b)', () => {
  it('fires a main skill through windup → resolve → recovery with cooldown from cast start', () => {
    const b = buildWith(['SK_BURST']);
    let s = createCombatState(cfg(b, 'burst', boss(), profile([rule('r1', 'SK_BURST', 'nearest')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'CAST_START'));
    const castStart = s.log.find((e) => e.kind === 'CAST_START')!;
    expect(castStart.skillId).toBe('SK_BURST');
    const t0 = castStart.timestamp;
    expect(s.operator.cast?.skillId).toBe('SK_BURST');
    expect(s.operator.cooldowns.SK_BURST).toBe(t0 + 900);
    expect(s.operator.nextAttackAt).toBe(t0 + 180 + 220);

    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'SKILL_USE' && e.skillId === 'SK_BURST'));
    expect(skillPackets(s, 'SK_BURST')).toHaveLength(3); // 3 пакета очереди
    expect(s.operator.cast).toBeTruthy(); // ещё recovery

    s = stepUntil(s, (x) => x.operator.cast === null);
    expect(s.timeMs).toBeGreaterThanOrEqual(t0 + 400);
  });

  it('selects the highest-priority rule and breaks ties by stable ruleId', () => {
    const b = buildWith(['SK_BURST', 'SK_PIERCE']);
    let hi = createCombatState(cfg(b, 'prio', boss(), profile([
      rule('rA', 'SK_BURST', 'nearest', 5), rule('rB', 'SK_PIERCE', 'nearest', 10),
    ]), { startEnergy: 100 }));
    hi = stepUntil(hi, (x) => x.log.some((e) => e.kind === 'CAST_START'));
    expect(hi.log.find((e) => e.kind === 'CAST_START')!.skillId).toBe('SK_PIERCE');

    let tie = createCombatState(cfg(b, 'tie', boss(), profile([
      rule('bbb', 'SK_PIERCE', 'nearest', 10), rule('aaa', 'SK_BURST', 'nearest', 10),
    ]), { startEnergy: 100 }));
    tie = stepUntil(tie, (x) => x.log.some((e) => e.kind === 'CAST_START'));
    expect(tie.log.find((e) => e.kind === 'CAST_START')!.skillId).toBe('SK_BURST');
  });

  it('records condition failures and falls back to auto-attack', () => {
    const b = buildWith(['SK_BURST']);
    const r = rule('r1', 'SK_BURST', 'nearest', 10, [{ kind: 'energyAtLeast', value: 999 }]);
    let s = createCombatState(cfg(b, 'cond', boss(), profile([r])));
    s = steps(s, 30);
    expect(s.log.some((e) => e.kind === 'CAST_START')).toBe(false);
    expect(s.metrics.ruleFailures.some((f) => f.ruleId === 'r1' && f.reason === 'conditions')).toBe(true);
    expect(s.metrics.damageDealt).toBeGreaterThan(0);
  });

  it('records an energy failure before the operator can afford the skill', () => {
    const b = buildWith(['SK_PIERCE']);
    let s = createCombatState(cfg(b, 'energy', boss(), profile([rule('r1', 'SK_PIERCE', 'nearest')]), { startEnergy: 0 }));
    s = stepUntil(s, (x) => x.metrics.ruleFailures.some((f) => f.reason === 'energy'));
    expect(s.metrics.ruleFailures.some((f) => f.ruleId === 'r1' && f.reason === 'energy')).toBe(true);
  });

  it('keeps SK_PIERCE penetration per-cast (not a permanent build stat) and charges energy', () => {
    const b = buildWith(['SK_PIERCE']);
    expect(b.stats.armorPen).toBe(0); // POW 5 → нет постоянного +20 пробития
    let s = createCombatState(cfg(b, 'pierce', boss(), profile([rule('r1', 'SK_PIERCE', 'nearest')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'SKILL_USE' && e.skillId === 'SK_PIERCE'));
    expect(s.metrics.energySpent).toBeGreaterThanOrEqual(12);
    expect(s.metrics.skillUses.SK_PIERCE).toBe(1);
  });

  it('targets the lowest-HP-percent enemy', () => {
    const b = buildWith(['SK_BURST']);
    let s = createCombatState(cfg(b, 'target', [{ templateId: 'E01' }, { templateId: 'E07' }], profile([rule('r1', 'SK_BURST', 'lowestHPPercent')]), { startEnergy: 100 }));
    s.enemies[1]!.hp = 5;
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'DAMAGE' && e.skillId === 'SK_BURST'));
    expect(s.log.find((e) => e.kind === 'DAMAGE' && e.skillId === 'SK_BURST')!.targetId).toBe('enemy:1');
  });

  it('SK_NEURO applies VIRUS on hit', () => {
    const b = buildWith(['SK_NEURO']);
    let s = createCombatState(cfg(b, 'neuro', boss(), profile([rule('r1', 'SK_NEURO', 'nearest')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => statusStacks(x.enemies[0]!, 'VIRUS') >= 1);
    expect(statusStacks(s.enemies[0]!, 'VIRUS')).toBeGreaterThanOrEqual(1);
  });

  it('SK_BREAK applies ARMOR_BREAK that lowers effective armor', () => {
    const b = buildWith(['SK_BREAK']);
    let s = createCombatState(cfg(b, 'break', boss(), profile([rule('r1', 'SK_BREAK', 'nearest')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => statusStacks(x.enemies[0]!, 'ARMOR_BREAK') >= 1);
    const stacks = statusStacks(s.enemies[0]!, 'ARMOR_BREAK');
    expect(effectiveSheet(s, s.enemies[0]!).armor).toBe(s.enemies[0]!.baseSheet.armor - 10 * stacks);
  });

  it('SK_BLADE applies BLEED with a positive snapshot on the last hit', () => {
    const b = buildWith(['SK_BLADE']);
    let s = createCombatState(cfg(b, 'blade', boss(), profile([rule('r1', 'SK_BLADE', 'nearest')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => statusStacks(x.enemies[0]!, 'BLEED') >= 1);
    expect(s.enemies[0]!.statuses.BLEED![0]!.snapshot).toBeGreaterThan(0);
  });

  it('SK_DETONATE requires VIRUS and consumes up to 3 stacks as immediate damage', () => {
    const b = buildWith(['SK_DETONATE']);
    let empty = createCombatState(cfg(b, 'det0', boss(), profile([rule('r1', 'SK_DETONATE', 'infected')]), { startEnergy: 100 }));
    empty = steps(empty, 20);
    expect(empty.metrics.ruleFailures.some((f) => f.reason === 'requirement')).toBe(true);
    expect(empty.log.some((e) => e.kind === 'SKILL_USE' && e.skillId === 'SK_DETONATE')).toBe(false);

    let s = createCombatState(cfg(b, 'det1', boss(), profile([rule('r1', 'SK_DETONATE', 'infected')]), { startEnergy: 100 }));
    applyStatus(s, s.operator, s.enemies[0]!, 'VIRUS', { stacks: 3 });
    expect(statusStacks(s.enemies[0]!, 'VIRUS')).toBe(3);
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'DAMAGE' && e.skillId === 'SK_DETONATE'));
    expect(s.log.some((e) => e.kind === 'DAMAGE' && e.skillId === 'SK_DETONATE')).toBe(true);
    expect(statusStacks(s.enemies[0]!, 'VIRUS')).toBeLessThan(3);
  });

  it('SK_OVR grants OVERCLOCK and raises effective attack speed', () => {
    const b = buildWith(['SK_OVR']);
    let s = createCombatState(cfg(b, 'ovr', boss(), profile([rule('r1', 'SK_OVR', 'self')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => hasStatus(x.operator, 'OVERCLOCK'));
    expect(hasStatus(s.operator, 'OVERCLOCK')).toBe(true);
    expect(effectiveSheet(s, s.operator).attackSpeed).toBeCloseTo(20, 6);
  });

  it('SK_KINETIC hits up to maxTargets distinct enemies', () => {
    const b = buildWith(['SK_KINETIC']);
    const enemies: EncounterEnemySpec[] = Array.from({ length: 5 }, () => ({ templateId: 'E01' }));
    let s = createCombatState(cfg(b, 'kinetic', enemies, profile([rule('r1', 'SK_KINETIC', 'allEnemies')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'SKILL_USE' && e.skillId === 'SK_KINETIC'));
    s = steps(s, 2);
    const targets = new Set(skillPackets(s, 'SK_KINETIC').map((e) => e.targetId));
    expect(targets.size).toBe(4);
  });

  it('SK_ARC splashes SHOCK onto secondary targets', () => {
    const b = buildWith(['SK_ARC']);
    const enemies: EncounterEnemySpec[] = Array.from({ length: 3 }, () => ({ templateId: 'E01' }));
    let s = createCombatState(cfg(b, 'arc', enemies, profile([rule('r1', 'SK_ARC', 'nearest')]), { startEnergy: 100 }));
    s = stepUntil(s, (x) => x.log.some((e) => e.kind === 'SKILL_USE' && e.skillId === 'SK_ARC'));
    s = steps(s, 3);
    expect(s.enemies.filter((e) => hasStatus(e, 'SHOCK')).length).toBeGreaterThanOrEqual(1);
  });

  it('ignores disabled rules and auto-attacks instead', () => {
    const b = buildWith(['SK_BURST']);
    const r: TacticRule = { ...rule('r1', 'SK_BURST', 'nearest'), enabled: false };
    let s = createCombatState(cfg(b, 'disabled', boss(), profile([r])));
    s = steps(s, 30);
    expect(s.log.some((e) => e.kind === 'CAST_START')).toBe(false);
    expect(s.metrics.damageDealt).toBeGreaterThan(0);
  });

  it('keeps skill combat deterministic for a shared build', () => {
    const shared = buildWith(['SK_BURST', 'SK_NEURO', 'SK_BREAK']);
    const tactics = profile([
      rule('r1', 'SK_BURST', 'nearest', 30), rule('r2', 'SK_NEURO', 'nearest', 20), rule('r3', 'SK_BREAK', 'nearest', 10),
    ]);
    const c = cfg(shared, 'det-skills', boss(), tactics, { startEnergy: 100 });
    const a = simulateCombat(c);
    const b = simulateCombat(c);
    expect(Object.keys(a.metrics.skillUses).length).toBeGreaterThan(0);
    expect(stateHash(a)).toBe(stateHash(b));
  });

  it('does not mutate the input state when stepping a skill combat', () => {
    const b = buildWith(['SK_BURST']);
    const s = createCombatState(cfg(b, 'purity', boss(), profile([rule('r1', 'SK_BURST', 'nearest')]), { startEnergy: 100 }));
    const before = stateHash(s);
    const next = stepCombat(s);
    expect(stateHash(s)).toBe(before);
    expect(next.timeMs).toBe(100);
    expect(s.timeMs).toBe(0);
  });
});