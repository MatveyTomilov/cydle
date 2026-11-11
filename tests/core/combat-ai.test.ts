import { describe, expect, it } from 'vitest';
import { createCombatState, hasStatus, stepCombat, type CombatState } from '../../src/core/combat/engine';
import type { CombatConfig, TacticalProfile } from '../../src/core/combat/types';
import { resolveBuild } from '../../src/core/build/build';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';

const makeItem = (grantId: string, templateId = 'PISTOL_K1') => createItem(new Rng('loot', grantId), {
  templateId, techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: grantId, origin: 'test',
});

const makeBuild = (skillIds: string[] = [], includeDrone = false) => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: makeItem(`weapon-${skillIds.join('-') || 'auto'}`), ...(includeDrone ? { DRONE_1: makeItem('test-drone', 'DR_GUN') } : {}) },
  skillIds, attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
});

const config = (seed: string, templates: string | string[], skillIds: string[] = [], rules: TacticalProfile['rules'] = []): CombatConfig => {
  const enemyIds = Array.isArray(templates) ? templates : [templates];
  return {
  seed, depth: enemyIds.some((id) => id.startsWith('BOSS_')) ? 8 : 2, biome: 'B01', nodeType: 'COMBAT',
  build: makeBuild(skillIds), enemies: enemyIds.map((templateId) => ({ templateId })),
  tactics: { id: 'test', name: 'test', rules }, maxDurationMs: 30000,
  };
};

function until(state: CombatState, predicate: (value: CombatState) => boolean, limitMs = 20000): CombatState {
  while (!predicate(state) && state.timeMs < limitMs && !state.outcome) state = stepCombat(state);
  return state;
}

describe('enemy ability scheduler', () => {
  it('telegraphs E07 heavy attack and lets the reaction channel interrupt before resolve', () => {
    let state = createCombatState(config('e07-telegraph', 'E07', ['SK_EMP'], [{
      id: 'interrupt-heavy', priority: 10, enabled: true, skillId: 'SK_EMP', target: 'imminentCast', conditions: [], logic: 'AND',
    }]));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;

    state = until(state, (x) => x.log.some((event) => event.kind === 'TELEGRAPH' && event.actorId === 'enemy:0'));
    const telegraph = state.log.find((event) => event.kind === 'TELEGRAPH' && event.actorId === 'enemy:0')!;
    expect(telegraph.timestamp).toBe(5000);
    expect(state.enemies[0]!.cast?.interruptible).toBe(true);
    state = until(state, (x) => x.log.some((event) => event.kind === 'CAST_INTERRUPT'));

    expect(state.metrics.interrupts).toBe(1);
    expect(state.enemies[0]!.cast).toBeNull();
    expect(state.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0' && event.timestamp >= 7000)).toBe(false);
  });

  it('resolves the E02 windup at its authored timestamp', () => {
    let state = createCombatState(config('e02-windup', 'E02'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0'));
    const hit = state.log.find((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0')!;

    expect(hit.timestamp).toBe(5900);
    expect(hit.amountBeforeDefense).toBe(58);
    expect(state.log.find((event) => event.kind === 'TELEGRAPH' && event.actorId === 'enemy:0')?.timestamp).toBe(5000);
  });

  it('routes the BOSS_B 25% digital bypass directly to HP after defense', () => {
    let state = createCombatState(config('boss-bypass', 'BOSS_B'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.operator.hp = 300;
    state.operator.shield = 100;
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0' && event.data?.abilityId === 'BOSS_B_scalpel'));

    const hit = state.log.find((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0' && event.data?.abilityId === 'BOSS_B_scalpel');
    expect(hit).toBeTruthy();
    expect(hit!.bypassed).toBeCloseTo(23.75, 6);
    expect(hit!.shieldConsumed).toBeCloseTo(71.25, 6);
    expect(hit!.hpLost).toBeCloseTo(23.75, 6);
    expect(hasStatus(state.operator, 'SHIELD_LEAK')).toBe(true);
  });

  it('resolves timed enemy status, heat, mark, heal, and shield-restoration abilities', () => {
    let statusState = createCombatState(config('enemy-jam', 'E13'));
    statusState.operator.nextAttackAt = 30000;
    statusState.enemies[0]!.nextAttackAt = 30000;
    statusState = until(statusState, (x) => hasStatus(x.operator, 'JAM'));
    expect(hasStatus(statusState.operator, 'JAM')).toBe(true);

    let heatState = createCombatState(config('enemy-heat', 'E17'));
    heatState.operator.nextAttackAt = 30000;
    heatState.enemies[0]!.nextAttackAt = 30000;
    heatState = until(heatState, (x) => x.log.filter((event) => event.kind === 'HEAT' && event.actorId === 'enemy:0' && event.data?.abilityId === 'E17_heat').length >= 2);
    expect(heatState.operator.heat).toBeCloseTo(10, 6);
    const heatEvents = heatState.log.filter((event) => event.kind === 'HEAT' && event.actorId === 'enemy:0' && event.data?.abilityId === 'E17_heat');
    expect(heatEvents.map((event) => event.timestamp)).toEqual([6600, 12600]);
    expect(heatEvents[0]?.data?.amount).toBe(10);
    expect(heatEvents[0]?.amountAfterDefense).toBeUndefined();

    let markState = createCombatState(config('enemy-mark', 'E04'));
    markState.operator.nextAttackAt = 30000;
    markState.enemies[0]!.nextAttackAt = 30000;
    markState = until(markState, (x) => hasStatus(x.operator, 'MARK'));
    expect(hasStatus(markState.operator, 'MARK')).toBe(true);

    let shieldState = createCombatState(config('enemy-shield', 'E03'));
    shieldState.operator.nextAttackAt = 30000;
    shieldState.enemies[0]!.nextAttackAt = 30000;
    shieldState.enemies[0]!.shield = 0;
    shieldState = until(shieldState, (x) => x.enemies[0]!.shield > 0);
    expect(shieldState.enemies[0]!.shield).toBe(20);

    let healState = createCombatState(config('enemy-heal', ['E01', 'E09']));
    healState.operator.nextAttackAt = 30000;
    for (const enemy of healState.enemies) enemy.nextAttackAt = 30000;
    healState.enemies[0]!.hp = 20;
    healState = until(healState, (x) => x.log.some((event) => event.kind === 'HEAL' && event.data?.abilityId === 'E09_heal'));
    const heal = healState.log.find((event) => event.kind === 'HEAL' && event.data?.abilityId === 'E09_heal')!;
    expect(heal.targetId).toBe('enemy:0');
    expect(heal.data?.amount).toBe(30);
  });

  it('applies DRONE_JAM from a scheduled enemy ability to active drones', () => {
    const droneBuild = makeBuild([], true);
    expect(droneBuild.valid).toBe(true);
    let state = createCombatState({ ...config('drone-jam', 'E15'), build: droneBuild });
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state = until(state, (x) => hasStatus(x.drones[0]!, 'DRONE_JAM'));

    expect(hasStatus(state.drones[0]!, 'DRONE_JAM')).toBe(true);
    const applied = state.log.find((event) => event.kind === 'STATUS_APPLY' && event.statusId === 'DRONE_JAM')!;
    expect(applied.targetId).toBe('drone:0');
  });
});
