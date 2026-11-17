import { describe, expect, it } from 'vitest';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { createInitialRun } from '../../src/core/run/run';
import { createInitialSave } from '../../src/core/save/initial';
import { repairGarageItem } from '../../src/core/inventory/garage';

function saveWithDamagedItem(saveId: string, durability = 50) {
  const save = createInitialSave({ saveId, now: 100 });
  const item = createItem(new Rng('repair', saveId), {
    templateId: 'RIFLE_K2', techLevel: 1, rarity: 'COMMON', secured: true,
    originGrantId: `repair:${saveId}`, origin: 'test', acquiredAt: 100,
  });
  item.durability = durability;
  save.meta.inventory.push(item);
  return { save, item };
}

describe('protected item repair', () => {
  it('repairs one owned item to full durability for the specified scrap cost', () => {
    const { save, item } = saveWithDamagedItem('repair-cost');
    const result = repairGarageItem(save, item.itemId);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)?.durability).toBe(100);
    expect(result.save.meta.protectedBank.SCRAP).toBe(19);
    expect(result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)?.tr).toBe(item.tr);
  });

  it('rejects repair without enough protected scrap and preserves all state', () => {
    const { save, item } = saveWithDamagedItem('repair-poor');
    save.meta.protectedBank.SCRAP = 10;
    const result = repairGarageItem(save, item.itemId);
    expect(result).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_SCRAP' });
    expect(result.save).toBe(save);
    expect(save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)?.durability).toBe(50);
    expect(save.meta.protectedBank.SCRAP).toBe(10);
  });

  it('does not spend scrap on a full-durability item', () => {
    const { save, item } = saveWithDamagedItem('repair-full', 100);
    const result = repairGarageItem(save, item.itemId);
    expect(result).toMatchObject({ ok: false, failureCode: 'ITEM_FULLY_REPAIRED' });
    expect(result.save).toBe(save);
    expect(save.meta.protectedBank.SCRAP).toBe(30);
  });

  it('rejects unsecured items and refuses repairs during an active run', () => {
    const unsecured = saveWithDamagedItem('repair-unsecured');
    unsecured.item.secured = false;
    expect(repairGarageItem(unsecured.save, unsecured.item.itemId)).toMatchObject({ ok: false, failureCode: 'ITEM_NOT_OWNED' });
    const protectedItem = saveWithDamagedItem('repair-active-run');
    const active = { ...protectedItem.save, run: createInitialRun(protectedItem.save, 'repair-locked-run') };
    expect(repairGarageItem(active, protectedItem.item.itemId)).toMatchObject({ ok: false, failureCode: 'RUN_ACTIVE' });
  });
});
