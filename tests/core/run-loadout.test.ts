import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { equipRunItem, unequipRunSlot } from '../../src/core/run/inventory';
import { resolveRunBuild } from '../../src/core/run/build';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { resolveRunCheckpoint } from '../../src/core/run/checkpoint';
import { chooseRunNode } from '../../src/core/run/commands';
import { resolveCurrentCombat } from '../../src/core/run/combat';

function saveWithRun(saveId: string) {
  const save = createInitialSave({ saveId, now: 100 });
  const run = createInitialRun(save, `loadout-${saveId}`);
  const item = createItem(new Rng('loot', saveId), {
    templateId: 'RIFLE_K2', techLevel: 1, rarity: 'COMMON', secured: false,
    originGrantId: `loot:${saveId}`, origin: 'test', acquiredAt: 100,
  });
  run.unsecuredCargo.push(item);
  return { ...save, run };
}

describe('run equipment ownership', () => {
  it('lets a cargo item modify the live run build while keeping its unsecured ownership', () => {
    const save = saveWithRun('cargo-equip');
    const cargo = save.run!.unsecuredCargo[0]!;
    const oldMain = save.run!.equipment.MAIN;
    const result = equipRunItem(save, { id: 'equip-rifle', itemId: cargo.itemId, slot: 'MAIN' });
    if (!result.ok) throw new Error(result.reason);
    expect(result.save.run?.equipment.MAIN).toBe(cargo.itemId);
    expect(result.save.run?.unsecuredCargo.find((item) => item.itemId === cargo.itemId)?.secured).toBe(false);
    expect(result.save.meta.equipment.MAIN).toBe(save.meta.equipment.MAIN);
    expect(resolveRunBuild(result.save).mainWeapon?.damage).toBeGreaterThan(resolveRunBuild(save).mainWeapon!.damage);
    expect(unequipRunSlot(result.save, { id: 'remove-main', slot: 'MAIN' })).toMatchObject({ ok: false, failureCode: 'BUILD_INVALID' });
    expect(oldMain).not.toBe(cargo.itemId);
  });

  it('rejects incompatible slots and leaves the original save untouched', () => {
    const save = saveWithRun('wrong-slot');
    const item = save.run!.unsecuredCargo[0]!;
    const result = equipRunItem(save, { id: 'wrong-slot', itemId: item.itemId, slot: 'OFFHAND' });
    expect(result).toMatchObject({ ok: false, failureCode: 'BUILD_INVALID' });
    expect(result.save).toBe(save);
  });

  it('prevents a run CARGO module swap from shrinking the hold below carried items', () => {
    const save = saveWithRun('cargo-module-limit');
    const run = save.run!;
    run.unsecuredCargo = Array.from({ length: 16 }, (_, index) => createItem(new Rng('loot', `hold-${index}`), {
      templateId: 'RAIL_K6', techLevel: 1, rarity: 'COMMON', secured: false,
      originGrantId: `hold:${index}`, origin: 'test',
    }));
    const larger = createItem(new Rng('loot', 'large-cargo'), {
      templateId: 'TR_CARGO_2', techLevel: 1, rarity: 'COMMON', secured: true,
      originGrantId: 'cargo:large', origin: 'test',
    });
    save.meta.inventory.push(larger);
    run.equipment.CARGO = larger.itemId;
    const smaller = save.meta.inventory.find((item) => item.templateId === 'TR_CARGO_1')!;

    const result = equipRunItem(save, { id: 'shrink-cargo', itemId: smaller.itemId, slot: 'CARGO' });
    expect(result).toMatchObject({ ok: false, failureCode: 'CARGO_OVER_CAPACITY', save });
  });

  it('secures the active run loadout during exit without duplicating the item', () => {
    const save = saveWithRun('exit-equipped');
    const cargo = save.run!.unsecuredCargo[0]!;
    const equipped = equipRunItem(save, { id: 'equip-before-exit', itemId: cargo.itemId, slot: 'MAIN' });
    if (!equipped.ok) throw new Error(equipped.reason);
    const checkpoint = equipped.save.run!.graph.layers[5]![0]!;
    const atGate = structuredClone(equipped.save);
    atGate.run!.currentNodeId = checkpoint.id;
    atGate.run!.visitedNodeIds.push(checkpoint.id);
    atGate.run!.clearedNodeIds.push(checkpoint.id);
    atGate.run!.phase = 'CHECKPOINT';
    const result = resolveRunCheckpoint(atGate, { id: 'exit-after-equip', choice: 'EXIT' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.meta.equipment.MAIN).toBe(cargo.itemId);
    expect(result.save.meta.inventory.filter((item) => item.itemId === cargo.itemId)).toHaveLength(1);
    expect(result.save.meta.inventory.find((item) => item.itemId === cargo.itemId)?.secured).toBe(true);
  });

  it('loses an unsecured equipped item on death and resets to damaged protected gear', () => {
    const save = saveWithRun('death-equipped');
    const cargo = save.run!.unsecuredCargo[0]!;
    const equipped = equipRunItem(save, { id: 'equip-before-death', itemId: cargo.itemId, slot: 'MAIN' });
    if (!equipped.ok) throw new Error(equipped.reason);
    const vulnerable = structuredClone(equipped.save);
    vulnerable.run!.resources.hp = 0;
    vulnerable.run!.resources.shield = 0;
    const first = vulnerable.run!.graph.layers[0]![0]!;
    const entered = chooseRunNode(vulnerable, 'death-route', first.id);
    if (!entered.ok) throw new Error(entered.reason);
    const result = resolveCurrentCombat(entered.save, 'death-fight');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run?.phase).toBe('DEFEATED');
    expect(result.save.meta.inventory.some((item) => item.itemId === cargo.itemId)).toBe(false);
    expect(result.save.run?.unsecuredCargo).toEqual([]);
    expect(result.save.run?.equipment.MAIN).toBe(result.save.meta.equipment.MAIN);
    expect(result.save.meta.inventory.find((item) => item.itemId === result.save.meta.equipment.MAIN)?.durability).toBe(80);
  });
});
