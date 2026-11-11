import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { chooseRunNode } from '../../src/core/run/commands';

function activeSave(saveId: string) {
  const save = createInitialSave({ saveId, now: 100 });
  return { ...save, run: createInitialRun(save, `seed-${saveId}`) };
}

describe('run route commands', () => {
  it('moves only along a saved outgoing edge and charges its fuel and game time once', () => {
    const save = activeSave('route-once');
    const first = save.run!.graph.layers[0]![0]!;
    const command = { id: 'move-1', type: 'CHOOSE_NODE' as const, nodeId: first.id };
    const moved = chooseRunNode(save, command.id, command.nodeId);
    expect(moved.ok).toBe(true);
    if (!moved.ok) return;
    expect(moved.save.run).toMatchObject({ currentNodeId: first.id, phase: 'NODE', visitedNodeIds: [first.id], resources: { fuel: 23, gameTimeMs: 25_000 } });
    expect(chooseRunNode(moved.save, command.id, command.nodeId)).toMatchObject({ ok: true, save: moved.save, events: [] });
  });

  it('rejects an unconnected destination without changing any save data', () => {
    const save = activeSave('route-invalid');
    const command = { id: 'bad-move', type: 'CHOOSE_NODE' as const, nodeId: save.run!.graph.layers[2]![0]!.id };
    const result = chooseRunNode(save, command.id, command.nodeId);
    expect(result).toMatchObject({ ok: false, failureCode: 'INVALID_ROUTE' });
    expect(result.save).toBe(save);
  });

  it('does not go below zero fuel when a movement cannot be paid', () => {
    const original = activeSave('route-fuel');
    const save = { ...original, run: { ...original.run!, resources: { ...original.run!.resources, fuel: 0 } } };
    const first = save.run!.graph.layers[0]![0]!;
    const result = chooseRunNode(save, 'dry-move', first.id);
    expect(result).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_FUEL' });
    expect(result.save).toBe(save);
  });
});
