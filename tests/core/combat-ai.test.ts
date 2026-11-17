import { describe, expect, it } from 'vitest';
import { applyStatus, createCombatState, effectiveSheet, hasStatus, statusStacks, stepCombat, type CombatState } from '../../src/core/combat/engine';
import type { CombatConfig, TacticalProfile } from '../../src/core/combat/types';
import { resolveBuild } from '../../src/core/build/build';
import { createItem } from '../../src/core/items/items';
import { Rng, stateHash } from '../../src/core/rng';
import { D, H } from '../../src/core/math/formula';
import { mitigatePacket, ZERO_PEN } from '../../src/core/math/damage';
import { ENEMY_BY_ID } from '../../src/data/enemies';
import type { TriggerEffect } from '../../src/data/types';

const makeItem = (grantId: string, templateId = 'PISTOL_K1') => createItem(new Rng('loot', grantId), {
  templateId, techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: grantId, origin: 'test',
});

const makeBuild = (skillIds: string[] = [], includeDrone = false) => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: makeItem(`weapon-${skillIds.join('-') || 'auto'}`), ...(includeDrone ? { DRONE_1: makeItem('test-drone', 'DR_GUN') } : {}) },
  skillIds, attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
});

const makeBuildWithDrone = (templateId: string, skillIds: string[] = []) => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: makeItem(`weapon-drone-${templateId}`), DRONE_1: makeItem(`test-${templateId}`, templateId) },
  skillIds, attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
});

const droneConfig = (seed: string, templateId: string, enemyIds: string[] = ['E01'], skillIds: string[] = []): CombatConfig => ({
  ...config(seed, enemyIds), build: makeBuildWithDrone(templateId, skillIds),
});

const config = (seed: string, templates: string | string[], skillIds: string[] = [], rules: TacticalProfile['rules'] = [], maxDurationMs = 30000): CombatConfig => {
  const enemyIds = Array.isArray(templates) ? templates : [templates];
  return {
  seed, depth: enemyIds.some((id) => id.startsWith('BOSS_')) ? 8 : 2, biome: 'B01', nodeType: 'COMBAT',
  build: makeBuild(skillIds), enemies: enemyIds.map((templateId) => ({ templateId })),
  tactics: { id: 'test', name: 'test', rules }, maxDurationMs,
  };
};

const eliteConfig = (seed: string, templateId: string, elite: string): CombatConfig => {
  const result = config(seed, templateId);
  result.enemies[0]!.elite = elite;
  return result;
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

  it('fires crossed BOSS_A phase thresholds once and applies its attack-speed phase', () => {
    let state = createCombatState(config('boss-phases-a', 'BOSS_A'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.hp = state.enemies[0]!.baseSheet.maxHP * 0.34;
    state = stepCombat(state);
    state = stepCombat(state);

    const phases = state.log.filter((event) => event.kind === 'PHASE' && event.actorId === 'enemy:0');
    expect(phases.map((event) => event.data?.phaseIndex)).toEqual([0, 1]);
    expect(state.enemies.filter((enemy) => enemy.summoned && enemy.alive).map((enemy) => enemy.templateId)).toEqual(['E09']);
    expect(state.enemies[0]!.flags.bossAttackSpeedBonus).toBe(0.2);
  });

  it('cleanses BOSS_B once when its 30% threshold is crossed', () => {
    let state = createCombatState(config('boss-cleanse', 'BOSS_B'));
    const boss = state.enemies[0]!;
    applyStatus(state, boss, boss, 'JAM', { durationMs: 10000 });
    state.operator.nextAttackAt = 30000;
    boss.nextAttackAt = 30000;
    boss.hp = boss.baseSheet.maxHP * 0.29;
    state = stepCombat(state);

    expect(hasStatus(state.enemies[0]!, 'JAM')).toBe(false);
    expect(state.log.filter((event) => event.kind === 'PHASE' && event.data?.phaseIndex === 1)).toHaveLength(1);
  });

  it('reduces BOSS_D burst ability interval after its 25% phase', () => {
    let state = createCombatState(config('boss-d-interval', 'BOSS_D'));
    const boss = state.enemies[0]!;
    boss.hp = boss.baseSheet.maxHP * 0.24;
    boss.flags['bossPhase:0'] = 1;
    boss.nextAttackAt = 30000;
    state.operator.hp = 10000;
    boss.baseSheet.accuracy = 1e9;

    state = until(state, (x) => x.log.some((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'BOSS_D_burst'));
    const telegraph = state.log.find((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'BOSS_D_burst')!;
    expect(telegraph.timestamp).toBe(10000);
  });

  it('rotates BOSS_CORE telegraphs in stable 12/24/36 second order', () => {
    let state = createCombatState(config('core-rotation', 'BOSS_CORE', [], [], 60000));
    state.operator.nextAttackAt = 60000;
    state.enemies[0]!.nextAttackAt = 60000;
    state = until(state, (x) => x.log.filter((event) => event.kind === 'TELEGRAPH' && event.actorId === 'enemy:0').length >= 3, 40000);
    const waves = state.log.filter((event) => event.kind === 'TELEGRAPH' && event.actorId === 'enemy:0');

    expect(waves.slice(0, 3).map((event) => [event.data?.abilityId, event.timestamp])).toEqual([
      ['CORE_rail', 12000], ['CORE_jam', 24000], ['CORE_suppress', 36000],
    ]);
  });

  it('upgrades BOSS_CORE digital wave to 25% shield bypass after the 40% phase', () => {
    let state = createCombatState(config('core-phase-bypass', 'BOSS_CORE', [], [], 30000));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.hp = state.enemies[0]!.baseSheet.maxHP * 0.39;
    state.enemies[0]!.flags['bossPhase:0'] = 1;
    state.enemies[0]!.baseSheet.accuracy = 1e9;
    state.operator.hp = 10000;
    state.operator.shield = 100;
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'CORE_jam'), 30000);
    const hit = state.log.find((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'CORE_jam')!;

    expect(hit.bypassed).toBeCloseTo(20, 6);
    expect(hit.shieldConsumed).toBe(0);
    expect(hit.hpLost).toBeCloseTo(80, 6);
  });

  it('shortens BOSS_CORE cast windup by its 15% phase', () => {
    let state = createCombatState(config('core-cast-speed', 'BOSS_CORE', [], [], 20000));
    const boss = state.enemies[0]!;
    boss.hp = boss.baseSheet.maxHP * 0.1;
    boss.flags['bossPhase:0'] = 1;
    boss.flags['bossPhase:1'] = 1;
    boss.nextAttackAt = 30000;
    boss.baseSheet.accuracy = 1e9;
    state.operator.hp = 10000;

    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'CORE_rail'), 16000);
    const hit = state.log.find((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'CORE_rail')!;
    expect(hit.timestamp).toBe(13300);
    expect(state.enemies[0]!.flags.bossCastSpeedIncrease).toBe(0.2);
  });

  it('applies elite base multipliers and EL_FAST tradeoffs', () => {
    const state = createCombatState(eliteConfig('elite-fast', 'E01', 'EL_FAST'));
    const elite = state.enemies[0]!;

    expect(elite.hp).toBeCloseTo(elite.baseSheet.maxHP, 6);
    expect(elite.baseSheet.maxHP).toBeCloseTo(ENEMY_BY_ID['E01']!.hp * H(2) * 1.75 * 0.9, 6);
    expect(elite.attackDamage).toBeCloseTo(ENEMY_BY_ID['E01']!.damage * 1.25 * D(2), 6);
    expect(elite.attackIntervalMs).toBeCloseTo(ENEMY_BY_ID['E01']!.intervalMs / 1.2, 6);
  });

  it('restores EL_SHIELD once after crossing below half HP', () => {
    let state = createCombatState(eliteConfig('elite-shield', 'E03', 'EL_SHIELD'));
    const elite = state.enemies[0]!;
    expect(elite.baseSheet.maxShield).toBeCloseTo(ENEMY_BY_ID['E03']!.shield * H(2) * 1.3, 6);
    elite.shield = 0;
    elite.hp = elite.baseSheet.maxHP * 0.5002;
    state.operator.nextAttackAt = 100;
    state.operator.baseSheet.accuracy = 1e9;
    state.build.mainWeapon!.damage = 1;
    state = stepCombat(state);
    expect(state.enemies[0]!.shield).toBe(20);
    state = stepCombat(state);
    expect(state.enemies[0]!.shield).toBe(20);
  });

  it('EL_VIRUS adds digital resistance and applies VIRUS on every third hit', () => {
    let state = createCombatState(eliteConfig('elite-virus', 'E01', 'EL_VIRUS'));
    const elite = state.enemies[0]!;
    expect(elite.baseSheet.digitalRes).toBe(ENEMY_BY_ID['E01']!.resD + 10);
    state.operator.hp = 10000;
    state.operator.baseSheet.evasion = 0;
    elite.baseSheet.accuracy = 1e9;
    elite.attackIntervalMs = 100;
    elite.nextAttackAt = 100;
    state = until(state, (x) => x.metrics.hits >= 3, 1000);

    expect(hasStatus(state.operator, 'VIRUS')).toBe(true);
    expect(state.enemies[0]!.flags.virusDirectHitCount).toBe(3);
  });

  it('E14 applies VIRUS on every third successful hit', () => {
    let state = createCombatState(config('e14-third-hit', 'E14'));
    state.operator.hp = 10000;
    state.operator.baseSheet.evasion = 0;
    state.enemies[0]!.baseSheet.accuracy = 1e9;
    state.enemies[0]!.attackIntervalMs = 100;
    state.enemies[0]!.nextAttackAt = 100;
    state = until(state, (x) => x.metrics.hits >= 3, 1000);

    expect(hasStatus(state.operator, 'VIRUS')).toBe(true);
    expect(state.enemies[0]!.flags.virusDirectHitCount).toBe(3);
  });

  it('EL_ANTI_DRONE telegraphs and applies its timed drone jam', () => {
    const combatConfig = eliteConfig('elite-anti-drone', 'E01', 'EL_ANTI_DRONE');
    const droneBuild = makeBuild([], true);
    let state = createCombatState({ ...combatConfig, build: droneBuild });
    state.operator.hp = 10000;
    state.operator.nextAttackAt = 30000;
    state.drones.forEach((drone) => { drone.nextAttackAt = 30000; });
    state.enemies[0]!.nextAttackAt = 30000;
    state = until(state, (x) => hasStatus(x.drones[0]!, 'DRONE_JAM'), 11000);

    const telegraph = state.log.find((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'EL_ANTI_DRONE_jam')!;
    expect(telegraph.timestamp).toBe(8000);
    expect(state.log.find((event) => event.kind === 'STATUS_APPLY' && event.statusId === 'DRONE_JAM')?.timestamp).toBe(9200);
  });

  it('EL_PEN adds armor penetration and a 200 ms basic-attack windup', () => {
    let state = createCombatState(eliteConfig('elite-pen', 'E01', 'EL_PEN'));
    const elite = state.enemies[0]!;
    state.operator.hp = 10000;
    state.operator.baseSheet.armor = 30;
    elite.baseSheet.accuracy = 1e9;
    elite.nextAttackAt = 100;
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0'), 1000);
    const cast = state.log.find((event) => event.kind === 'CAST_START' && event.actorId === 'enemy:0')!;
    const hit = state.log.find((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0')!;

    expect(cast.data?.windupMs).toBe(200);
    expect(hit.timestamp).toBe(300);
    const expected = mitigatePacket(hit.amountBeforeDefense!, 'KINETIC', { armor: 30, energyRes: 0, digitalRes: 0 }, { ...ZERO_PEN, armorPen: 10 }).afterDefense;
    expect(hit.amountAfterDefense!).toBeCloseTo(expected, 6);
  });

  it('EL_SPLIT creates exactly two half-HP E20 summons with no loot', () => {
    let state = createCombatState(eliteConfig('elite-split', 'E01', 'EL_SPLIT'));
    state.enemies[0]!.hp = 0;
    state = stepCombat(state);
    const splits = state.enemies.filter((enemy) => enemy.summoned && enemy.templateId === 'E20');

    expect(splits).toHaveLength(2);
    expect(splits.every((enemy) => enemy.noLoot && enemy.hp === enemy.baseSheet.maxHP * 0.5)).toBe(true);
    expect(state.log.filter((event) => event.kind === 'SUMMON' && event.actorId === 'enemy:0')).toHaveLength(2);
  });

  it('E18 applies SHIELD_LEAK on its first successful direct hit', () => {
    let state = createCombatState(config('e18-first-hit', 'E18'));
    state.operator.hp = 10000;
    state.operator.baseSheet.evasion = 0;
    state.enemies[0]!.baseSheet.accuracy = 1e9;
    state.enemies[0]!.nextAttackAt = 100;
    state = until(state, (x) => hasStatus(x.operator, 'SHIELD_LEAK'), 2000);
    expect(state.log.filter((event) => event.kind === 'STATUS_APPLY' && event.statusId === 'SHIELD_LEAK')).toHaveLength(1);
  });

  it('E23 gains one capped BERSERK stack when an enemy ally dies', () => {
    let state = createCombatState(config('e23-ally-death', ['E23', 'E01']));
    state.enemies[1]!.hp = 0;
    state = stepCombat(state);
    expect(statusStacks(state.enemies[0]!, 'BERSERK')).toBe(1);
  });

  it('E19 retains its telegraphed death burst until resolution', () => {
    let state = createCombatState(config('e19-death-burst', 'E19', [], [], 10000));
    state.operator.hp = 10000;
    state.operator.baseSheet.evasion = 0;
    state.enemies[0]!.hp = 0;
    state = stepCombat(state);
    expect(state.outcome).toBeNull();
    expect(state.log.findIndex((event) => event.kind === 'DEATH' && event.actorId === 'enemy:0'))
      .toBeLessThan(state.log.findIndex((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'E19_death'));
    expect(state.log.find((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'E19_death')?.timestamp).toBe(100);
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'E19_death'), 2000);
    expect(state.log.findIndex((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'E19_death'))
      .toBeLessThan(state.log.findIndex((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'E19_death'));
    expect(state.log.find((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'E19_death')?.timestamp).toBe(1300);
  });

  it('E24 punishes three consecutive casts of the same program with JAM', () => {
    let state = createCombatState(config('e24-repeat-program', 'E24', ['SK_BURST'], [{
      id: 'repeat-burst', priority: 1, enabled: true, skillId: 'SK_BURST', target: 'nearest', conditions: [], logic: 'AND',
    }]));
    state.operator.nextAttackAt = 100;
    state.operator.hp = 10000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.hp = 10000;

    while (state.log.filter((event) => event.kind === 'CAST_START' && event.skillId === 'SK_BURST').length < 3 && state.timeMs < 3000) {
      if (state.operator.cast?.skillId === 'SK_BURST') state.operator.cooldowns.SK_BURST = state.timeMs;
      state = stepCombat(state);
    }

    expect(state.log.filter((event) => event.kind === 'CAST_START' && event.skillId === 'SK_BURST')).toHaveLength(3);
    expect(hasStatus(state.operator, 'JAM')).toBe(true);
    expect(state.log.find((event) => event.kind === 'STATUS_APPLY' && event.statusId === 'JAM')?.timestamp).toBe(900);
  });

  it('lets a reaction interrupt an enemy cast on the exact resolve tick', () => {
    let state = createCombatState(config('interrupt-resolve-tick', 'E07', ['SK_EMP']));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.baseSheet.accuracy = 1e9;
    state = until(state, (x) => x.log.some((event) => event.kind === 'TELEGRAPH' && event.actorId === 'enemy:0'));
    const resolveAt = state.enemies[0]!.cast!.resolveAt;
    while (state.timeMs < resolveAt - 100) state = stepCombat(state);
    state.operator.reactionCast = {
      actionId: 'operator:skill:SK_EMP:resolve-tick', skillId: 'SK_EMP', startedAt: state.timeMs,
      resolveAt, endAt: resolveAt, targetId: 'enemy:0', interruptible: false, telegraph: false, channel: 'reaction',
    };
    state = stepCombat(state);

    expect(state.log.find((event) => event.kind === 'CAST_INTERRUPT')?.timestamp).toBe(resolveAt);
    expect(state.log.some((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'E07_shell')).toBe(false);
  });

  it('retargets a boss ability to a living drone if the telegraphed operator target is lost', () => {
    const combatConfig = config('boss-target-loss', 'BOSS_B');
    combatConfig.build = makeBuild([], true);
    let state = createCombatState(combatConfig);
    state.operator.hp = 10000;
    state.operator.nextAttackAt = 30000;
    state.drones.forEach((drone) => { drone.nextAttackAt = 30000; });
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.baseSheet.accuracy = 1e9;
    state = until(state, (x) => x.log.some((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'BOSS_B_scalpel'), 12000);
    state.enemies[0]!.cast!.targetId = 'lost-target';
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'BOSS_B_scalpel'), 14000);

    expect(state.log.find((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'BOSS_B_scalpel')?.targetId).toBe('drone:0');
  });

  it('enforces the two-living-summon cap when a boss phase summons', () => {
    let state = createCombatState(config('boss-summon-cap', ['BOSS_A', 'E20', 'E20']));
    state.enemies[0]!.hp = state.enemies[0]!.baseSheet.maxHP * 0.69;
    state.enemies[0]!.nextAttackAt = 30000;
    for (const summon of state.enemies.slice(1)) {
      summon.summoned = true;
      summon.noLoot = true;
      summon.nextAttackAt = 30000;
    }
    state.operator.nextAttackAt = 30000;
    state = stepCombat(state);

    expect(state.enemies.filter((enemy) => enemy.alive && enemy.summoned)).toHaveLength(2);
    expect(state.log.filter((event) => event.kind === 'CAST_FIZZLE' && event.reason === 'summon_cap')).toHaveLength(1);
  });

  it('keeps enemy AI deterministic and does not mutate an input snapshot', () => {
    const initial = createCombatState(config('enemy-ai-purity', 'E14'));
    const untouched = structuredClone(initial);
    let first = initial;
    let second = initial;
    for (let i = 0; i < 120; i++) {
      first = stepCombat(first);
      second = stepCombat(second);
    }

    expect(initial).toEqual(untouched);
    expect(stateHash(first)).toBe(stateHash(second));
    expect(first.log).toEqual(second.log);
  });
});

describe('drone combat roles', () => {
  it('fires all three DR_SWARM pellets as one scheduled attack', () => {
    let state = createCombatState(droneConfig('drone-swarm-pellets', 'DR_SWARM'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state = until(state, (x) => x.log.filter((event) => event.kind === 'DAMAGE' && event.actorId === 'drone:0').length >= 3, 2000);

    const hits = state.log.filter((event) => event.kind === 'DAMAGE' && event.actorId === 'drone:0');
    expect(hits).toHaveLength(3);
    expect(new Set(hits.map((event) => event.actionId)).size).toBe(1);
    expect(hits.map((event) => event.amountBeforeDefense)).toEqual([8, 8, 8]);
  });

  it('DR_GUN prioritizes the marked enemy', () => {
    let state = createCombatState(droneConfig('drone-mark-priority', 'DR_GUN', ['E01', 'E02']));
    state.operator.nextAttackAt = 30000;
    state.enemies.forEach((enemy) => { enemy.nextAttackAt = 30000; });
    applyStatus(state, state.operator, state.enemies[1]!, 'DRONE_MARK', { durationMs: 5000 });
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'drone:0'), 2000);

    expect(state.log.find((event) => event.kind === 'DAMAGE' && event.actorId === 'drone:0')?.targetId).toBe('enemy:1');
  });

  it('DR_ARC applies SHOCK on its fifth attack', () => {
    let state = createCombatState(droneConfig('drone-arc-shock', 'DR_ARC'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state = until(state, (x) => x.log.some((event) => event.kind === 'STATUS_APPLY' && event.actorId === 'drone:0' && event.statusId === 'SHOCK'), 6000);

    const shock = state.log.find((event) => event.kind === 'STATUS_APPLY' && event.actorId === 'drone:0' && event.statusId === 'SHOCK');
    expect(shock?.timestamp).toBe(4300);
    expect(statusStacks(state.enemies[0]!, 'SHOCK')).toBe(1);
  });

  it('DR_MED restores 18 operator shield every ten seconds', () => {
    let state = createCombatState(droneConfig('drone-med-periodic', 'DR_MED'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.operator.shield = 0;
    state = until(state, (x) => x.log.some((event) => event.kind === 'SHIELD_GAIN' && event.actorId === 'drone:0'), 11000);

    const gain = state.log.find((event) => event.kind === 'SHIELD_GAIN' && event.actorId === 'drone:0');
    expect(gain?.timestamp).toBe(10000);
    expect(state.operator.shield).toBe(18);
  });

  it('DR_EMP interrupts an enemy cast on its fourteen-second cycle', () => {
    let state = createCombatState(droneConfig('drone-emp-interrupt', 'DR_EMP', ['E07']));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.hp = 1000;
    state.enemies[0]!.abilityNext.E07_shell = 13000;
    state = until(state, (x) => x.log.some((event) => event.kind === 'CAST_INTERRUPT' && event.actorId === 'drone:0'), 15000);

    const interrupt = state.log.find((event) => event.kind === 'CAST_INTERRUPT' && event.actorId === 'drone:0');
    expect(interrupt?.timestamp).toBe(14000);
    expect(state.enemies[0]!.cast).toBeNull();
  });

  it('DR_BULWARK diverts at most 20 raw damage from the operator per hit', () => {
    const state = createCombatState(droneConfig('drone-bulwark-redirect', 'DR_BULWARK'));
    state.operator.nextAttackAt = 30000;
    state.drones[0]!.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 1100;
    state.enemies[0]!.attackDamage = 500;
    const result = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0'), 1300);
    const operatorHit = result.log.find((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0' && event.targetId === 'operator');
    const redirectedHit = result.log.find((event) => event.kind === 'DAMAGE' && event.actorId === 'enemy:0' && event.targetId === 'drone:0');

    expect(redirectedHit?.amountBeforeDefense).toBe(20);
    expect(operatorHit?.amountBeforeDefense).toBe(480);
    expect(result.drones[0]!.shield).toBeLessThan(result.drones[0]!.baseSheet.maxShield);
  });

  it('SK_DRONE_REPAIR restores the medic drone and operator shield through droneA', () => {
    let state = createCombatState(droneConfig('drone-repair-skill', 'DR_MED', ['E01'], ['SK_DRONE_REPAIR']));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.drones[0]!.nextAttackAt = 30000;
    state.drones[0]!.hp = 70;
    state.operator.shield = 0;
    state = until(state, (x) => x.log.some((event) => event.kind === 'HEAL' && event.actorId === 'drone:0'), 1000);

    expect(state.drones[0]!.hp).toBe(95);
    expect(state.operator.shield).toBe(20);
    expect(state.log.some((event) => event.kind === 'SKILL_USE' && event.actorId === 'drone:0' && event.skillId === 'SK_DRONE_REPAIR')).toBe(true);
  });

  it('SK_DRONE_EMP damages and jams the target while interrupting its cast', () => {
    let state = createCombatState(droneConfig('drone-emp-skill', 'DR_EMP', ['E07'], ['SK_DRONE_EMP']));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.hp = 1000;
    state.enemies[0]!.abilityNext.E07_shell = 13000;
    state = until(state, (x) => x.log.some((event) => event.kind === 'CAST_INTERRUPT' && event.actorId === 'drone:0'), 15000);

    expect(hasStatus(state.enemies[0]!, 'JAM')).toBe(true);
    expect(state.log.some((event) => event.kind === 'DAMAGE' && event.actorId === 'drone:0' && event.skillId === 'SK_DRONE_EMP')).toBe(true);
    expect(state.log.some((event) => event.kind === 'SKILL_USE' && event.skillId === 'SK_DRONE_EMP')).toBe(true);
  });

  it('bounds recursive secondary-hit procs by depth and child-event budget', () => {
    let state = createCombatState(config('proc-chain-bounds', ['E01', 'E02', 'E03', 'E04', 'E05', 'E06']));
    state.enemies.forEach((enemy) => { enemy.hp = 10000; enemy.nextAttackAt = 30000; });
    state.operator.nextAttackAt = 1000;
    const recursiveProc: TriggerEffect = {
      type: 'trigger', id: 'test_recursive_secondary', event: 'ON_HIT', chance: 1, allowSecondary: true,
      action: { kind: 'secondaryDamage', basis: 'flat', coefficient: 1, damageType: 'DIGITAL', targeting: 'allEnemies', maxTargets: 6, canProc: true },
      desc: 'test bounded recursive proc',
    };
    state.build.triggerEffects.push({ effect: recursiveProc, sourceId: 'test-recursive', sourceName: 'test', sourceKind: 'unique' });
    state = until(state, (x) => x.metrics.chainLimitHits > 0, 3000);

    const chainEvents = state.log.filter((event) => event.kind === 'TRIGGER' && event.originActionId?.startsWith('operator:atk:'));
    expect(state.metrics.chainLimitHits).toBeGreaterThan(0);
    expect(Math.max(...chainEvents.map((event) => event.chainDepth))).toBeLessThanOrEqual(8);
    expect(chainEvents.length).toBeLessThanOrEqual(32);
  });

  it('stops sibling proc effects after 32 children from one attack origin', () => {
    let state = createCombatState(config('proc-child-budget', 'E01'));
    state.operator.nextAttackAt = 1000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.baseSheet.evasion = 0;
    state.enemies[0]!.hp = 10000;
    for (let i = 0; i < 40; i++) {
      const effect: TriggerEffect = {
        type: 'trigger', id: `test_child_${i}`, event: 'ON_HIT', chance: 1,
        action: { kind: 'flag', key: `child_${i}`, amount: 1 }, desc: `child ${i}`,
      };
      state.build.triggerEffects.push({ effect, sourceId: 'test-child-source', sourceName: 'test', sourceKind: 'unique' });
    }
    state = until(state, (x) => x.metrics.chainLimitHits > 0, 1500);

    const childEvents = state.log.filter((event) => event.kind === 'TRIGGER' && event.originActionId === 'operator:atk:1');
    expect(childEvents).toHaveLength(32);
    expect(state.metrics.chainLimitHits).toBe(1);
    expect(state.log.find((event) => event.kind === 'CHAIN_LIMIT')?.reason).toBe('max_child_events');
  });

  it('runs a direct ON_KILL secondary proc after the lethal event', () => {
    let state = createCombatState(config('kill-trigger-order', ['E01', 'E02']));
    state.operator.nextAttackAt = 1000;
    state.enemies[0]!.hp = 1;
    state.enemies[1]!.hp = 1000;
    state.enemies[0]!.baseSheet.evasion = 0;
    state.enemies.forEach((enemy) => { enemy.nextAttackAt = 30000; });
    const killProc: TriggerEffect = {
      type: 'trigger', id: 'test_kill_echo', event: 'ON_KILL', requireDirect: true,
      requireKillType: 'KINETIC', chance: 1,
      action: { kind: 'secondaryDamage', basis: 'flat', coefficient: 12, damageType: 'DIGITAL', targeting: 'secondary', canProc: false },
      desc: 'test direct kill echo',
    };
    state.build.triggerEffects.push({ effect: killProc, sourceId: 'test-kill-source', sourceName: 'test', sourceKind: 'unique' });
    state = until(state, (x) => x.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_kill_echo')), 1500);

    const killTrigger = state.log.find((event) => event.kind === 'TRIGGER' && event.text.includes('test_kill_echo'))!;
    const killEcho = state.log.find((event) => ['DAMAGE', 'MISS'].includes(event.kind) && event.actionId?.includes('test_kill_echo'));
    expect(killEcho?.targetId).toBe('enemy:1');
    expect(state.log.findIndex((event) => event.kind === 'DEATH' && event.actorId === 'enemy:0')).toBeLessThan(state.log.indexOf(killTrigger));
  });

  it('dispatches skill-filtered ON_CAST triggers to the road result deltas', () => {
    let state = createCombatState(config('scan-catalog-triggers', 'E01', ['SK_SCAN'], [{
      id: 'scan', priority: 1, enabled: true, skillId: 'SK_SCAN', target: 'target', conditions: [], logic: 'AND',
    }]));
    state.operator.energy = 100;
    const trigger = (id: string, action: TriggerEffect['action']): TriggerEffect => ({
      type: 'trigger', id, event: 'ON_CAST', skillFilter: ['SK_SCAN'], chance: 1, action, desc: id,
    });
    state.build.triggerEffects.push(
      { effect: trigger('test_scan_reveal', { kind: 'revealNodes', amount: 1 }), sourceId: 'test-scan-source', sourceName: 'test', sourceKind: 'unique' },
      { effect: trigger('test_scan_wanted', { kind: 'wanted', amount: 2 }), sourceId: 'test-scan-source', sourceName: 'test', sourceKind: 'unique' },
    );
    state = until(state, (x) => x.revealDelta === 1, 2000);

    expect(state.wantedDelta).toBe(2);
    expect(state.log.some((event) => event.kind === 'TRIGGER' && event.skillId === 'SK_SCAN')).toBe(true);
  });

  it('matches status-expiry trigger filters and reduces the named cooldown', () => {
    let state = createCombatState(config('jam-expiry-trigger', 'E01', ['SK_EMP']));
    state.operator.cooldowns.SK_EMP = 10000;
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    const effect: TriggerEffect = {
      type: 'trigger', id: 'test_jam_expiry', event: 'ON_STATUS_EXPIRE', statusFilter: ['JAM'],
      icdMs: 5000, action: { kind: 'reduceCooldown', skillId: 'SK_EMP', amountMs: 2000 }, desc: 'test JAM expiry',
    };
    state.build.triggerEffects.push({ effect, sourceId: 'test-status-source', sourceName: 'test', sourceKind: 'unique' });
    applyStatus(state, state.operator, state.enemies[0]!, 'JAM', { durationMs: 1000 });
    state = until(state, (x) => x.enemies[0]!.statuses.JAM === undefined, 1100);

    expect(state.operator.cooldowns.SK_EMP).toBe(8000);
    expect(state.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_jam_expiry'))).toBe(true);
  });

  it('dispatches ON_DRONE_DEATH to operator equipment and uses the dead drone basis', () => {
    let state = createCombatState(droneConfig('drone-death-trigger', 'DR_GUN', ['E01', 'E02']));
    state.drones[0]!.hp = 0;
    state.operator.nextAttackAt = 30000;
    state.enemies.forEach((enemy) => { enemy.nextAttackAt = 30000; enemy.baseSheet.evasion = 0; });
    const effect: TriggerEffect = {
      type: 'trigger', id: 'test_drone_death_emp', event: 'ON_DRONE_DEATH', oncePerDrone: true,
      action: { kind: 'secondaryDamage', basis: 'droneTech', coefficient: 0.5, damageType: 'DIGITAL', targeting: 'allEnemies', canProc: false },
      desc: 'test drone death EMP',
    };
    state.build.triggerEffects.push({ effect, sourceId: 'test-drone-unique', sourceName: 'test', sourceKind: 'unique' });
    state = stepCombat(state);

    expect(state.metrics.droneDeaths).toBe(1);
    expect(state.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_drone_death_emp'))).toBe(true);
    expect(state.log.filter((event) => event.kind === 'DAMAGE' && event.actorId === 'operator' && event.damageType === 'DIGITAL'))
      .toHaveLength(2);
  });

  it('transfers bounded VIRUS stacks on a kill without resetting their remaining ticks', () => {
    let state = createCombatState(config('virus-kill-transfer', ['E01', 'E02']));
    state.operator.nextAttackAt = 1000;
    state.enemies.forEach((enemy) => { enemy.nextAttackAt = 30000; });
    state.enemies[0]!.hp = 1;
    state.enemies[0]!.baseSheet.evasion = 0;
    applyStatus(state, state.operator, state.enemies[0]!, 'VIRUS', { stacks: 2, durationMs: 5000, snapshot: 100 });
    const originalExpiry = state.enemies[0]!.statuses.VIRUS!.map((entry) => entry.expiresAt);
    const effect: TriggerEffect = {
      type: 'trigger', id: 'test_virus_transfer', event: 'ON_KILL', allowStatusTick: true,
      action: { kind: 'transferVirus', stacks: 2 }, desc: 'test virus transfer',
    };
    state.build.triggerEffects.push({ effect, sourceId: 'test-virus-source', sourceName: 'test', sourceKind: 'unique' });
    state = until(state, (x) => !x.enemies[0]!.alive, 1500);

    expect(statusStacks(state.enemies[1]!, 'VIRUS')).toBe(2);
    expect(state.enemies[1]!.statuses.VIRUS!.map((entry) => entry.expiresAt)).toEqual(originalExpiry);
    expect(state.enemies[0]!.statuses.VIRUS).toBeUndefined();
  });

  it('applies ON_BEFORE_HIT packet modifiers before mitigation', () => {
    const make = (withProc: boolean) => {
      let state = createCombatState(config('packet-modifier', 'E01'));
      state.build = resolveBuild({
        attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
        equipment: { MAIN: makeItem('packet-modifier-shotgun', 'SHOTGUN_K5') },
        attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
      });
      state.build.mainWeapon!.pelletProcWeight = 1;
      state.operator = createCombatState({ ...config('packet-modifier-rebuilt', 'E01'), build: state.build }).operator;
      state.operator.nextAttackAt = 1600;
      state.enemies[0]!.nextAttackAt = 30000;
      state.enemies[0]!.baseSheet.evasion = 0;
      state.enemies[0]!.baseSheet.armor = 0;
      state.enemies[0]!.hp = 10000;
      if (withProc) state.build.triggerEffects.push({
        effect: { type: 'trigger', id: 'test_packet_double', event: 'ON_BEFORE_HIT', requireDirect: true, damageTypeFilter: ['KINETIC'], action: { kind: 'packetMod', damageMultiplier: 2 }, desc: 'test packet modifier' },
        sourceId: 'test-packet-source', sourceName: 'test', sourceKind: 'unique',
      });
      return until(state, (next) => next.log.filter((event) => event.kind === 'DAMAGE' && event.actorId === 'operator').length >= 4, 3000);
    };
    const baseline = make(false);
    const modified = make(true);
    const raw = (state: CombatState) => state.log.filter((event) => event.kind === 'DAMAGE' && event.actorId === 'operator').slice(0, 4).map((event) => event.amountBeforeDefense!);

    expect(raw(modified)).toHaveLength(4);
    raw(modified).forEach((amount, index) => expect(amount).toBeCloseTo(raw(baseline)[index]! * 2, 6));
  });

  it('fires heat-full effects and prevents lockout when shield is discharged', () => {
    let state = createCombatState(config('heat-full-trigger', 'E01'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.operator.heat = 99;
    state.operator.shield = 100;
    state.ambientHeatPerSec = 1000;
    state.build.triggerEffects.push({
      effect: { type: 'trigger', id: 'test_discharge', event: 'ON_HEAT_FULL', action: { kind: 'consumeShieldForDamage', fraction: 0.25, maxMultiplier: 2, windowMs: 5000 }, desc: 'test discharge' },
      sourceId: 'test-discharge-source', sourceName: 'test', sourceKind: 'unique',
    });
    state = stepCombat(state);

    expect(state.operator.shield).toBe(75);
    expect(state.operator.heatLockout).toBe(false);
    expect(state.log.some((event) => event.kind === 'HEAT_LOCKOUT')).toBe(false);
    expect(state.operator.flags.u01EnergyMultiplier).toBeCloseTo(1.25, 6);
  });

  it('dispatches interrupt triggers and grants a temporary reaction window', () => {
    let state = createCombatState(config('interrupt-trigger', 'E07', ['SK_EMP'], [{
      id: 'interrupt-heavy', priority: 10, enabled: true, skillId: 'SK_EMP', target: 'imminentCast', conditions: [], logic: 'AND',
    }]));
    state.operator.shield = 0;
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.build.triggerEffects.push({
      effect: { type: 'trigger', id: 'test_interrupt_window', event: 'ON_INTERRUPT', action: { kind: 'extraReaction', windowMs: 2000 }, desc: 'test extra reaction' },
      sourceId: 'test-interrupt-source', sourceName: 'test', sourceKind: 'unique',
    });
    state = until(state, (x) => x.log.some((event) => event.kind === 'CAST_INTERRUPT'));

    expect(state.operator.flags.extraReactionUntil).toBeGreaterThan(0);
    expect(state.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_interrupt_window'))).toBe(true);
  });

  it('dispatches combat-start triggers before the first simulation tick', () => {
    const build = makeBuild();
    build.triggerEffects.push({
      effect: { type: 'trigger', id: 'test_emergency_start', event: 'ON_COMBAT_START', oncePerCombat: true, action: { kind: 'flag', key: 'emergencyReaction', amount: 1, max: 1 }, desc: 'test combat-start flag' },
      sourceId: 'test-start-source', sourceName: 'test', sourceKind: 'tree',
    });
    const combat = config('combat-start-trigger', 'E01');
    combat.build = build;

    const state = createCombatState(combat);
    expect(state.operator.flags.emergencyReaction).toBe(1);
    expect(state.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_emergency_start'))).toBe(true);
  });

  it('dispatches enemy telegraphs to operator buffs', () => {
    let state = createCombatState(config('enemy-telegraph-trigger', 'E07'));
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.build.triggerEffects.push({
      effect: { type: 'trigger', id: 'test_telegraph_evasion', event: 'ON_ENEMY_TELEGRAPH', action: { kind: 'buff', mods: [{ type: 'stat', stat: 'evasion', op: 'FLAT', value: 20 }], durationMs: 1000 }, desc: 'test telegraph evasion' },
      sourceId: 'test-telegraph-source', sourceName: 'test', sourceKind: 'tree',
    });
    state = until(state, (next) => next.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_telegraph_evasion')), 6000);

    expect(state.operator.buffs.some((buff) => buff.mods.some((modifier) => modifier.stat === 'evasion'))).toBe(true);
  });

  it('releases accumulated charge as a non-proccing secondary energy packet', () => {
    let state = createCombatState(config('charge-release', 'E01'));
    state.operator.nextAttackAt = 1000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.baseSheet.evasion = 0;
    state.enemies[0]!.baseSheet.armor = 0;
    state.enemies[0]!.hp = 10000;
    state.operator.flags.charge = 25;
    state.build.triggerEffects.push({
      effect: { type: 'trigger', id: 'test_charge_release', event: 'ON_BEFORE_HIT', requireDirect: true, action: { kind: 'spendFlagForDamage', flag: 'charge', perStack: 1, maxStacks: 1, intervalMs: 4000 }, desc: 'test charge release' },
      sourceId: 'test-charge-source', sourceName: 'test', sourceKind: 'unique',
    });
    state = until(state, (next) => next.log.some((event) => event.kind === 'DAMAGE' && event.actionId?.includes('test_charge_release:charge')), 1500);

    const chargeHit = state.log.find((event) => event.kind === 'DAMAGE' && event.actionId?.includes('test_charge_release:charge'))!;
    expect(chargeHit.damageType).toBe('ENERGY');
    expect(chargeHit.amountBeforeDefense).toBe(25);
    expect(state.operator.flags.charge).toBe(0);
  });

  it('repeats the last available DIGITAL program without spending energy or applying its proc effects', () => {
    let state = createCombatState(config('repeat-digital', 'E01', ['SK_NEURO']));
    state.operator.lastDigitalSkill = { skillId: 'SK_NEURO', targetId: 'enemy:0' };
    state.operator.nextAttackAt = 30000;
    state.enemies[0]!.nextAttackAt = 30000;
    state.enemies[0]!.baseSheet.evasion = 0;
    state.enemies[0]!.hp = 10000;
    const beforeEnergySpent = state.metrics.energySpent;
    const effect: TriggerEffect = {
      type: 'trigger', id: 'test_repeat_digital', event: 'PERIODIC', periodMs: 12000,
      action: { kind: 'repeatLastDigital', coefficient: 0.5 }, desc: 'test repeat digital',
    };
    state.build.triggerEffects.push({ effect, sourceId: 'test-repeat-source', sourceName: 'test', sourceKind: 'unique' });
    state.operator.abilityNext['trigger:test-repeat-source:test_repeat_digital'] = 100;
    state = stepCombat(state);

    const repeated = state.log.find((event) => event.kind === 'DAMAGE' && event.skillId === 'SK_NEURO');
    expect(repeated?.amountBeforeDefense).toBeGreaterThan(0);
    expect(state.metrics.energySpent).toBe(beforeEnergySpent);
    expect(state.enemies[0]!.statuses.VIRUS).toBeUndefined();
  });

  it('fires HP-threshold triggers only on crossing the configured boundary', () => {
    let state = createCombatState(config('hp-threshold-trigger', 'E02'));
    state.operator.nextAttackAt = 30000;
    state.operator.shield = 0;
    state.operator.hp = state.operator.baseSheet.maxHP * 0.3;
    state.enemies[0]!.nextAttackAt = 30000;
    state.build.triggerEffects.push({
      effect: { type: 'trigger', id: 'test_hp_panic', event: 'ON_HP_THRESHOLD', hpThreshold: 0.2, oncePerCombat: true, action: { kind: 'tempShield', amount: 80, cap: 80, durationMs: 5000, scaleWithArmorT: true }, desc: 'test HP threshold' },
      sourceId: 'test-hp-source', sourceName: 'test', sourceKind: 'tree',
    });
    state = until(state, (next) => next.log.some((event) => event.kind === 'TRIGGER' && event.text.includes('test_hp_panic')), 8000);

    expect(state.operator.buffs).toHaveLength(0);
    expect(state.operator.tempShields.some((shield) => shield.amount > 0)).toBe(true);
  });

  it('resolves target-status stat conditions against the actual hit target', () => {
    const combat = config('target-condition', 'E01');
    combat.build = resolveBuild({
      attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
      equipment: { MAIN: makeItem('target-condition-blade', 'BLADE_K4') },
      attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
    });
    const state = createCombatState(combat);
    const target = state.enemies[0]!;
    const before = effectiveSheet(state, state.operator, target).kineticDamage;
    applyStatus(state, state.operator, target, 'BLEED', { durationMs: 5000, snapshot: 0 });
    const after = effectiveSheet(state, state.operator, target).kineticDamage;

    expect(after - before).toBeCloseTo(10, 6);
  });
});
