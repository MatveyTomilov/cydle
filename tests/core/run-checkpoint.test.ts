import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { resolveRunCheckpoint, resolveRunEmergency } from '../../src/core/run/checkpoint';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';

function atCheckpoint(saveId: string) {
  const save = createInitialSave({ saveId, now: 100 });
  const run = createInitialRun(save, `checkpoint-${saveId}`);
  const checkpoint = run.graph.layers[5]![0]!;
  run.currentNodeId = checkpoint.id;
  run.visitedNodeIds.push(checkpoint.id);
  run.clearedNodeIds.push(checkpoint.id);
  run.phase = 'CHECKPOINT';
  run.runWallet = { CREDITS: 100, SCRAP: 20, DATA: 10 };
  run.unsecuredCargo.push(createItem(new Rng('loot', saveId), {
    templateId: 'PISTOL_K1', techLevel: 1, rarity: 'COMMON', secured: false,
    originGrantId: `loot:${saveId}`, origin: 'test', acquiredAt: 100,
  }));
  return { ...save, run };
}

describe('checkpoint settlement', () => {
  it('tow costs the run wallet, loses 30% currency and one deterministic cargo item, then secures the remainder', () => {
    const save = createInitialSave({ saveId: 'tow', now: 100 });
    const run = createInitialRun(save, 'tow-seed');
    const roadNode = run.graph.layers[0]![0]!;
    run.currentNodeId = roadNode.id;
    run.visitedNodeIds = [roadNode.id];
    run.phase = 'ROUTE';
    run.resources.fuel = 0;
    run.runWallet = { CREDITS: 100, SCRAP: 10, DATA: 10 };
    for (const [templateId, grantId] of [['PISTOL_K1', 'tow-item-1'], ['DR_GUN', 'tow-item-2']]) run.unsecuredCargo.push(createItem(new Rng('loot', grantId), {
      templateId, techLevel: 1, rarity: 'COMMON', secured: false, originGrantId: grantId, origin: 'test',
    }));
    const result = resolveRunEmergency({ ...save, run }, { id: 'tow-command', choice: 'REQUEST_TOW' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run).toMatchObject({ phase: 'TOWED', runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 }, unsecuredCargo: [] });
    expect(result.save.meta.protectedBank).toEqual({ CREDITS: 169, SCRAP: 37, DATA: 27 });
    const retained = result.save.meta.inventory.filter((item) => ['tow-item-1', 'tow-item-2'].includes(item.originGrantId));
    expect(retained).toHaveLength(1);
    expect(retained[0]?.secured).toBe(true);
  });

  it('abandons only on explicit choice, loses unsecured cargo and wears secured equipment by ten', () => {
    const save = createInitialSave({ saveId: 'abandon', now: 100 });
    const run = createInitialRun(save, 'abandon-seed');
    const roadNode = run.graph.layers[0]![0]!;
    run.currentNodeId = roadNode.id;
    run.visitedNodeIds = [roadNode.id];
    run.phase = 'ROUTE';
    run.resources.fuel = 0;
    run.unsecuredCargo.push(createItem(new Rng('loot', 'abandon-item'), {
      templateId: 'DR_GUN', techLevel: 1, rarity: 'COMMON', secured: false, originGrantId: 'abandon-item', origin: 'test',
    }));
    const equippedId = save.meta.equipment.MAIN!;
    const result = resolveRunEmergency({ ...save, run }, { id: 'abandon-command', choice: 'ABANDON_RUN' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run).toMatchObject({ phase: 'ABANDONED', runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 }, unsecuredCargo: [] });
    expect(result.save.meta.inventory.find((item) => item.originGrantId === 'abandon-item')).toBeUndefined();
    expect(result.save.meta.inventory.find((item) => item.itemId === equippedId)?.durability).toBe(90);
    expect(result.save.meta.protectedBank).toEqual(save.meta.protectedBank);
  });

  it('requires explicit protected-bank permission to pay the tow and refuses emergency exit when a route is affordable', () => {
    const save = createInitialSave({ saveId: 'tow-bank', now: 100 });
    const run = createInitialRun(save, 'tow-bank-seed');
    const roadNode = run.graph.layers[0]![0]!;
    run.currentNodeId = roadNode.id;
    run.visitedNodeIds = [roadNode.id];
    run.phase = 'ROUTE';
    run.resources.fuel = 0;
    run.runWallet = { CREDITS: 0, SCRAP: 0, DATA: 0 };
    const stranded = { ...save, run };
    const refused = resolveRunEmergency(stranded, { id: 'tow-refused', choice: 'REQUEST_TOW' });
    expect(refused).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_FUNDS', save: stranded });
    const paid = resolveRunEmergency(stranded, { id: 'tow-bank-ok', choice: 'REQUEST_TOW', spendProtected: true });
    expect(paid.ok).toBe(true);
    if (paid.ok) expect(paid.save.meta.protectedBank.CREDITS).toBe(90);

    const fueled = { ...stranded, run: { ...run, resources: { ...run.resources, fuel: 1 } } };
    const unnecessary = resolveRunEmergency(fueled, { id: 'tow-unneeded', choice: 'ABANDON_RUN' });
    expect(unnecessary).toMatchObject({ ok: false, failureCode: 'EMERGENCY_NOT_NEEDED', save: fueled });
  });

  it('evacuates all unsecured cargo and currencies exactly once', () => {
    const save = atCheckpoint('exit');
    const item = save.run!.unsecuredCargo[0]!;
    const result = resolveRunCheckpoint(save, { id: 'exit-checkpoint', choice: 'EXIT' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run?.phase).toBe('EXTRACTED');
    expect(result.save.run?.unsecuredCargo).toEqual([]);
    expect(result.save.meta.inventory.find((entry) => entry.itemId === item.itemId)?.secured).toBe(true);
    expect(result.save.meta.protectedBank).toEqual({ CREDITS: 220, SCRAP: 50, DATA: 30 });
    expect(result.save.meta.tutorial.firstSectorCompleted).toBe(true);
    expect(result.save.meta.maxSectorCleared).toBe(1);
    expect(resolveRunCheckpoint(result.save, { id: 'exit-checkpoint', choice: 'EXIT' })).toMatchObject({ ok: true, save: result.save, events: [] });
  });

  it('ships a bounded selection and half the run wallet once, keeping the run active', () => {
    const save = atCheckpoint('ship');
    const item = save.run!.unsecuredCargo[0]!;
    const result = resolveRunCheckpoint(save, { id: 'ship-checkpoint', choice: 'SHIP', cargoItemIds: [item.itemId], currencyShare: 0.5 });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run?.phase).toBe('CHECKPOINT');
    expect(result.save.run?.unsecuredCargo).toEqual([]);
    expect(result.save.run?.shippedCargo).toHaveLength(1);
    expect(result.save.run?.runWallet).toEqual({ CREDITS: 45, SCRAP: 10, DATA: 5 });
    expect(result.save.meta.protectedBank).toEqual({ CREDITS: 165, SCRAP: 40, DATA: 25 });
    expect(result.save.meta.inventory.find((entry) => entry.itemId === item.itemId)?.secured).toBe(true);
  });

  it('continues into a fresh deterministic next sector and unlocks the boss forpost', () => {
    const save = atCheckpoint('continue');
    save.run!.depth = 4;
    save.run!.biome = 'B01';
    save.run!.graph.depth = 4;
    save.run!.graph.biome = 'B01';
    const boss = { ...save.run!.graph.layers[5]![0]!, type: 'BOSS' as const };
    save.run!.graph.layers[5] = [boss];
    save.run!.currentNodeId = boss.id;
    save.run!.visitedNodeIds = [boss.id];
    save.run!.clearedNodeIds = [boss.id];
    const repeat = structuredClone(save);
    const result = resolveRunCheckpoint(save, { id: 'continue-checkpoint', choice: 'CONTINUE' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.meta.unlockedForpost).toBe(4);
    expect(result.save.meta.maxSectorCleared).toBe(4);
    expect(result.save.run).toMatchObject({ depth: 5, biome: 'B04', phase: 'ROUTE', currentNodeId: 'START', visitedNodeIds: [], clearedNodeIds: [] });
    const repeated = resolveRunCheckpoint(repeat, { id: 'continue-checkpoint', choice: 'CONTINUE' });
    expect(repeated.ok && repeated.save.run?.graph).toEqual(result.save.run?.graph);
  });

  it('rejects a second shipment at the same checkpoint without changing the save', () => {
    const save = atCheckpoint('ship-once');
    const item = save.run!.unsecuredCargo[0]!;
    const shipped = resolveRunCheckpoint(save, { id: 'ship-once-1', choice: 'SHIP', cargoItemIds: [item.itemId], currencyShare: 0 });
    expect(shipped.ok).toBe(true);
    if (!shipped.ok) return;
    const retry = resolveRunCheckpoint(shipped.save, { id: 'ship-once-2', choice: 'SHIP', currencyShare: 0 });
    expect(retry).toMatchObject({ ok: false, failureCode: 'SHIP_ALREADY_USED', save: shipped.save });
  });

  it('does not charge for an empty shipment', () => {
    const save = atCheckpoint('empty-ship');
    save.run!.unsecuredCargo = [];
    save.run!.runWallet = { CREDITS: 0, SCRAP: 0, DATA: 0 };
    const result = resolveRunCheckpoint(save, { id: 'empty-ship-command', choice: 'SHIP', cargoItemIds: [], currencyShare: 0 });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.failureCode).toBe('EMPTY_SHIPMENT');
      expect(result.save).toBe(save);
    }
  });
});
