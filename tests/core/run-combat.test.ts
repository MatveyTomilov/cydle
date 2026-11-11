import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { chooseRunNode } from '../../src/core/run/commands';
import { resolveCurrentCombat } from '../../src/core/run/combat';

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
    const save = combatSave('wrong-phase');
    const result = resolveCurrentCombat(save, 'fight');
    expect(result).toMatchObject({ ok: false, failureCode: 'NODE_NOT_COMBAT' });
    expect(result.save).toBe(save);
  });
});
