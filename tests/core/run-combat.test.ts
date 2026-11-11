import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { chooseRunNode } from '../../src/core/run/commands';
import { resolveCurrentCombat } from '../../src/core/run/combat';
import { resolveRunEvent } from '../../src/core/run/nodes';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { runCargoCapacity, runCargoUnits } from '../../src/core/run/cargo';

function combatSave(saveId: string) {
  const save = createInitialSave({ saveId, now: 100 });
  return { ...save, run: createInitialRun(save, `combat-${saveId}`) };
}

describe('run combat integration', () => {
  it('resolves the current encounter through the shared simulator and grants its reward once', () => {
    const save = combatSave('victory');
    const firstNode = save.run!.graph.layers[0]![0]!;
    const entered = chooseRunNode(save, 'move', firstNode.id);
    if (!entered.ok) throw new Error(entered.reason);
    const result = resolveCurrentCombat(entered.save, 'fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run).toMatchObject({
      phase: 'ROUTE', clearedNodeIds: [firstNode.id], combatResult: { outcome: 'VICTORY', seed: `combat-victory:${firstNode.id}` },
      runWallet: { CREDITS: 12, SCRAP: 3, DATA: 1 },
    });
    expect(result.save.meta.operator.xp).toBe(22);
    expect(result.save.run!.grantIds).toContain(`xp:${firstNode.id}`);
    expect(resolveCurrentCombat(result.save, 'fight')).toMatchObject({ ok: true, save: result.save, events: [] });
  });

  it('produces identical combat and reward state for the same saved seed', () => {
    const runOnce = (saveId: string) => {
      const save = combatSave(saveId);
      const firstNode = save.run!.graph.layers[0]![0]!;
      const entered = chooseRunNode(save, 'move', firstNode.id);
      if (!entered.ok) throw new Error(entered.reason);
      return resolveCurrentCombat(entered.save, 'fight');
    };
    const first = runOnce('same-seed');
    const second = runOnce('same-seed');
    expect(first).toEqual(second);
  });

  it('does not resolve a combat command while the operator is still at a route choice', () => {
    const base = combatSave('wrong-phase');
    const save = { ...base, run: { ...base.run!, pendingCombatEffects: { initialTempShield: 20, extraHeat: 10 } } };
    const result = resolveCurrentCombat(save, 'fight');
    expect(result).toMatchObject({ ok: false, failureCode: 'NODE_NOT_COMBAT' });
    expect(result.save).toBe(save);
    expect(result.save.run!.pendingCombatEffects).toEqual({ initialTempShield: 20, extraHeat: 10 });
  });

  it('passes pending event effects to the shared combat and consumes them once', () => {
    const save = combatSave('event-combat-effects');
    const run = save.run!;
    const node = run.graph.layers[0]![0]!;
    node.enemies = [{ templateId: 'E01' }];
    run.currentNodeId = node.id;
    run.visitedNodeIds = [node.id];
    run.phase = 'NODE';
    run.pendingCombatEffects = { initialTempShield: 20, extraHeat: 10 };
    const result = resolveCurrentCombat(save, 'event-effect-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run!.combatResult!.log.find((event) => event.kind === 'COMBAT_START')?.data).toMatchObject({ initialTempShield: 20, initialExtraHeat: 10 });
    expect(result.save.run!.pendingCombatEffects).toEqual({ initialTempShield: 0, extraHeat: 0 });
  });

  it('runs a legacy active encounter that has no deferred combat-effects field', () => {
    const base = combatSave('legacy-combat-effects');
    const run = base.run!;
    const { pendingCombatEffects: _ignored, ...legacyRun } = run;
    const node = legacyRun.graph.layers[0]![0]!;
    legacyRun.currentNodeId = node.id;
    legacyRun.visitedNodeIds = [node.id];
    legacyRun.phase = 'NODE';
    const result = resolveCurrentCombat({ ...base, run: legacyRun } as unknown as typeof base, 'legacy-fight');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.save.run!.pendingCombatEffects).toEqual({ initialTempShield: 0, extraHeat: 0 });
  });

  it('skips the next ordinary combat without XP, currency, or loot after EV16 A', () => {
    const base = combatSave('event-skip-combat');
    const run = base.run!;
    const eventNode = run.graph.layers[1]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV16';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    run.runWallet.CREDITS = 12;
    const choice = resolveRunEvent({ ...base, run }, { id: 'event-skip-choice', choiceId: 'A' });
    expect(choice.ok).toBe(true);
    if (!choice.ok) return;
    const nextCombat = choice.save.run!.graph.layers[2]![0]!;
    const entered = chooseRunNode(choice.save, 'event-skip-enter', nextCombat.id);
    expect(entered.ok).toBe(true);
    if (!entered.ok) return;
    const skipped = resolveCurrentCombat(entered.save, 'event-skip-resolve');
    expect(skipped.ok).toBe(true);
    if (!skipped.ok) return;
    expect(skipped.events[0]?.type).toBe('COMBAT_SKIPPED');
    expect(skipped.save.run).toMatchObject({ phase: 'ROUTE', runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 }, pendingNextCombat: { skipOrdinary: false, forceElite: false, extraItemRoll: false } });
    expect(skipped.save.run!.clearedNodeIds).toContain(nextCombat.id);
    expect(skipped.save.run!.unsecuredCargo).toHaveLength(0);
    expect(skipped.save.meta.operator.xp).toBe(0);
  });

  it('promotes the next ordinary combat to elite and guarantees one extra item roll after EV16 B', () => {
    const base = combatSave('event-force-elite');
    const run = base.run!;
    const eventNode = run.graph.layers[1]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV16';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const choice = resolveRunEvent({ ...base, run }, { id: 'event-elite-choice', choiceId: 'B' });
    expect(choice.ok).toBe(true);
    if (!choice.ok) return;
    const nextCombat = choice.save.run!.graph.layers[2]![0]!;
    const entered = chooseRunNode(choice.save, 'event-elite-enter', nextCombat.id);
    expect(entered.ok).toBe(true);
    if (!entered.ok) return;
    expect(entered.save.run!.graph.layers[2]![0]).toMatchObject({ type: 'ELITE', threat: 'high', enemies: [{ elite: 'EL_PEN' }] });
    const result = resolveCurrentCombat(entered.save, 'event-elite-resolve');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run!.runWallet.CREDITS).toBe(28);
    expect(result.save.run!.unsecuredCargo.filter((item) => item.origin === 'combat').length).toBeGreaterThanOrEqual(2);
    expect(result.save.run!.pendingNextCombat).toMatchObject({ skipOrdinary: false, forceElite: false, extraItemRoll: false });
  });

  it('turns EV14 into a bounty and adds 25% credits to its reward', () => {
    const base = combatSave('event-bounty-bonus');
    const run = base.run!;
    const eventNode = run.graph.layers[1]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV14';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const choice = resolveRunEvent({ ...base, run }, { id: 'event-bounty-bonus-choice', choiceId: 'B' });
    expect(choice.ok).toBe(true);
    if (!choice.ok) return;
    const nextCombat = choice.save.run!.graph.layers[2]![0]!;
    nextCombat.enemies = [{ templateId: 'E01', hpMult: 0.1, damageMult: 0.1 }];
    const entered = chooseRunNode(choice.save, 'event-bounty-bonus-enter', nextCombat.id);
    expect(entered.ok).toBe(true);
    if (!entered.ok) return;
    expect(entered.save.run!.graph.layers[2]![0]).toMatchObject({ type: 'BOUNTY', threat: 'high' });
    const result = resolveCurrentCombat(entered.save, 'event-bounty-bonus-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run!.runWallet.CREDITS).toBe(44);
    expect(result.save.meta.operator.xp).toBe(0);
  });

  it('turns EV21 into an E21 bounty with one guaranteed RARE roll', () => {
    const base = combatSave('event-bounty-e21');
    const run = base.run!;
    const eventNode = run.graph.layers[1]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV21';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const choice = resolveRunEvent({ ...base, run }, { id: 'event-bounty-e21-choice', choiceId: 'B' });
    expect(choice.ok).toBe(true);
    if (!choice.ok) return;
    const nextCombat = choice.save.run!.graph.layers[2]![0]!;
    nextCombat.enemies = [{ templateId: 'E01', hpMult: 0.1, damageMult: 0.1 }];
    const entered = chooseRunNode(choice.save, 'event-bounty-e21-enter', nextCombat.id);
    expect(entered.ok).toBe(true);
    if (!entered.ok) return;
    expect(entered.save.run!.graph.layers[2]![0]).toMatchObject({ type: 'BOUNTY', enemies: [{ templateId: 'E21', elite: 'EL_PEN' }] });
    const result = resolveCurrentCombat(entered.save, 'event-bounty-e21-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run!.unsecuredCargo).toContainEqual(expect.objectContaining({ originGrantId: `combat:${run.seed}:${nextCombat.id}:event-extra-rare`, rarity: 'RARE' }));
    expect(result.save.meta.operator.xp).toBe(0);
  });

  it('applies elite rewards, corporate wanted, and biome wallet bonuses through the shared combat result', () => {
    const save = combatSave('elite-reward');
    const run = save.run!;
    const elite = run.graph.layers[1]![0]!;
    elite.type = 'ELITE';
    elite.enemies = [{ templateId: 'E01' }];
    run.biome = 'B02';
    run.graph.biome = 'B02';
    run.currentNodeId = elite.id;
    run.visitedNodeIds = [elite.id];
    run.phase = 'NODE';

    const result = resolveCurrentCombat(save, 'elite-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run).toMatchObject({ phase: 'ROUTE', runWallet: { CREDITS: 31, SCRAP: 7, DATA: 3 }, wanted: 7 });
    expect(result.save.meta.operator.xp).toBe(55);
    expect(result.save.run!.unsecuredCargo.length).toBeGreaterThanOrEqual(1);
    expect(result.save.run!.unsecuredCargo.every((item) => !item.secured)).toBe(true);
  });

  it('applies bounty rewards without unstated bounty XP and scales B04 data', () => {
    const save = combatSave('bounty-reward');
    const run = save.run!;
    const bounty = run.graph.layers[1]![1]!;
    bounty.type = 'BOUNTY';
    bounty.enemies = [{ templateId: 'E01' }];
    run.biome = 'B04';
    run.graph.biome = 'B04';
    run.currentNodeId = bounty.id;
    run.visitedNodeIds = [bounty.id];
    run.phase = 'NODE';

    const result = resolveCurrentCombat(save, 'bounty-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run).toMatchObject({ phase: 'ROUTE', runWallet: { CREDITS: 35, SCRAP: 5, DATA: 4 } });
    expect(result.save.meta.operator.xp).toBe(0);
    expect(result.save.run!.grantIds).not.toContain(`xp:${bounty.id}`);
  });

  it('does not exceed the hold when combat loot arrives at full capacity', () => {
    const save = combatSave('full-cargo-combat');
    const run = save.run!;
    const elite = run.graph.layers[0]![0]!;
    elite.type = 'ELITE';
    elite.enemies = [{ templateId: 'E01' }];
    for (let index = 0; index < 10; index++) run.unsecuredCargo.push(createItem(new Rng('loot', `combat-full-${index}`), {
      templateId: 'RAIL_K6', techLevel: 1, rarity: 'COMMON', secured: false,
      originGrantId: `combat-full-${index}`, origin: 'test',
    }));
    run.currentNodeId = elite.id;
    run.visitedNodeIds = [elite.id];
    run.phase = 'NODE';
    const capacity = runCargoCapacity(save);
    expect(runCargoUnits(run.unsecuredCargo)).toBe(capacity);

    const result = resolveCurrentCombat(save, 'full-cargo-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(runCargoUnits(result.save.run!.unsecuredCargo)).toBeLessThanOrEqual(capacity);
    expect(result.save.run!.unsecuredCargo.filter((item) => item.origin === 'combat')).toEqual([]);
  });
});
