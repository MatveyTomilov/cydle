import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { resolveRunCheckpoint } from '../../src/core/run/checkpoint';
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
