import { describe, expect, it } from 'vitest';
import { applyStatus, createCombatState, hasStatus, statusStacks, stepCombat, type CombatState } from '../../src/core/combat/engine';
import type { CombatConfig, TacticalProfile } from '../../src/core/combat/types';
import { resolveBuild } from '../../src/core/build/build';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { D, H } from '../../src/core/math/formula';
import { mitigatePacket, ZERO_PEN } from '../../src/core/math/damage';
import { ENEMY_BY_ID } from '../../src/data/enemies';

const makeItem = (grantId: string, templateId = 'PISTOL_K1') => createItem(new Rng('loot', grantId), {
  templateId, techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: grantId, origin: 'test',
});

const makeBuild = (skillIds: string[] = [], includeDrone = false) => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: makeItem(`weapon-${skillIds.join('-') || 'auto'}`), ...(includeDrone ? { DRONE_1: makeItem('test-drone', 'DR_GUN') } : {}) },
  skillIds, attributePointsEarned: 0, unlockedImplantSlots: 4, unlockedDroneSlots: 1,
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
    expect(state.log.find((event) => event.kind === 'TELEGRAPH' && event.data?.abilityId === 'E19_death')?.timestamp).toBe(100);
    state = until(state, (x) => x.log.some((event) => event.kind === 'DAMAGE' && event.data?.abilityId === 'E19_death'), 2000);
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
});
