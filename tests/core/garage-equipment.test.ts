import { describe, expect, it } from 'vitest';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { createInitialRun } from '../../src/core/run/run';
import { createInitialSave } from '../../src/core/save/initial';
import { equipGarageItem, unequipGarageSlot } from '../../src/core/inventory/garage';

function saveWithOwnedRifle(saveId: string) {
  const save = createInitialSave({ saveId, now: 100 });
  const rifle = createItem(new Rng('garage', saveId), {
    templateId: 'RIFLE_K2', techLevel: 1, rarity: 'COMMON', secured: true,
    originGrantId: `garage:${saveId}`, origin: 'test', acquiredAt: 100,
  });
  save.meta.inventory.push(rifle);
  return { save, rifle };
}

describe('garage equipment ownership', () => {
  it('equips a secured owned item without removing it from inventory', () => {
    const { save, rifle } = saveWithOwnedRifle('garage-equip');
    const result = equipGarageItem(save, rifle.itemId, 'MAIN');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.meta.equipment.MAIN).toBe(rifle.itemId);
    expect(result.save.meta.inventory.some((item) => item.itemId === rifle.itemId && item.secured)).toBe(true);
    expect(result.save.meta.inventory).toHaveLength(13);
  });

  it('rejects an item that does not fit the requested slot and preserves the save', () => {
    const { save, rifle } = saveWithOwnedRifle('garage-invalid-slot');
    const result = equipGarageItem(save, rifle.itemId, 'OFFHAND');
    expect(result.ok).toBe(false);
    expect(result.save).toBe(save);
    expect(save.meta.equipment.MAIN).not.toBe(rifle.itemId);
  });

  it('rejects garage loadout edits while a run is active', () => {
    const { save, rifle } = saveWithOwnedRifle('garage-active-run');
    const active = { ...save, run: createInitialRun(save, 'garage-locked-run') };
    const result = equipGarageItem(active, rifle.itemId, 'MAIN');
    expect(result).toMatchObject({ ok: false, failureCode: 'RUN_ACTIVE' });
    expect(result.save.meta.equipment.MAIN).not.toBe(rifle.itemId);
  });

  it('cannot remove the required main weapon from the garage build', () => {
    const save = createInitialSave({ saveId: 'garage-main-required', now: 100 });
    const result = unequipGarageSlot(save, 'MAIN');
    expect(result).toMatchObject({ ok: false, failureCode: 'BUILD_INVALID' });
    expect(result.save.meta.equipment.MAIN).toBe(save.meta.equipment.MAIN);
  });
});
