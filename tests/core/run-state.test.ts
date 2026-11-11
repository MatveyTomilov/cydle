import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { parseSave } from '../../src/core/save/schema';
import { createInitialRun } from '../../src/core/run/run';

describe('run save state', () => {
  it('starts from the protected operator profile with deterministic streams and the tutorial graph', () => {
    const save = createInitialSave({ saveId: 'run-test', now: 100 });
    expect(save.meta.tutorial.firstSectorCompleted).toBe(false);
    const run = createInitialRun(save, 'pinned-run');
    expect(run).toEqual(createInitialRun(save, 'pinned-run'));
    expect(run).toMatchObject({
      seed: 'pinned-run', depth: 1, biome: 'B01', currentNodeId: 'START', phase: 'ROUTE',
      resources: { fuel: 24, hull: 100, hp: 320, shield: 120, energy: 100, heat: 0, gameTimeMs: 0 },
      runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 },
      visitedNodeIds: [], clearedNodeIds: [], grantIds: [], commandIds: [], serviceScrapFuelCounts: {}, shippedCheckpointIds: [], combatResult: null,
    });
    expect(run.worldRng.stream).toBe('world');
    expect(run.lootRng.stream).toBe('loot');
    expect(parseSave({ ...save, run }).success).toBe(true);
  });

  it('rejects malformed run graphs and resource values from save imports', () => {
    const save = createInitialSave({ saveId: 'run-invalid', now: 100 });
    const run = createInitialRun(save, 'seed');
    expect(parseSave({ ...save, run: { ...run, resources: { ...run.resources, fuel: -1 } } }).success).toBe(false);
    expect(parseSave({ ...save, run: { ...run, graph: { ...run.graph, edges: [{ from: 'missing', to: 'node', fromLayer: 0, toLayer: 1, fuelCost: 1 }] } } }).success).toBe(false);
  });
});
