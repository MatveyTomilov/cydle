import { describe, expect, it } from 'vitest';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { createInitialRun } from '../../src/core/run/run';
import { createInitialSave } from '../../src/core/save/initial';
import { dismantleGarageItem } from '../../src/core/inventory/garage';

function saveWithSpareItem(saveId: string, secured = true) {
  const save = createInitialSave({ saveId, now: 100 });
  const item = createItem(new Rng('dismantle', saveId), {
    templateId: 'RIFLE_K2', techLevel: 1, rarity: 'COMMON', secured,
    originGrantId: `dismantle:${saveId}`, origin: 'test', acquiredAt: 100,
  });
  save.meta.inventory.push(item);
  return { save, item };
}

describe('protected inventory dismantling', () => {
  it('converts a spare secured item into one scrap grant and removes its ownership', () => {
    const { save, item } = saveWithSpareItem('dismantle-once');
    const result = dismantleGarageItem(save, item.itemId);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.meta.inventory.some((candidate) => candidate.itemId === item.itemId)).toBe(false);
    expect(result.save.meta.protectedBank.SCRAP).toBe(33);
    expect(dismantleGarageItem(result.save, item.itemId)).toMatchObject({ ok: false, failureCode: 'ITEM_NOT_OWNED' });
    expect(dismantleGarageItem(result.save, item.itemId).save.meta.protectedBank.SCRAP).toBe(33);
  });

  it('rejects an equipped item without changing inventory or resources', () => {
    const { save } = saveWithSpareItem('dismantle-equipped');
    const itemId = save.meta.equipment.MAIN!;
    const result = dismantleGarageItem(save, itemId);
    expect(result).toMatchObject({ ok: false, failureCode: 'ITEM_EQUIPPED' });
    expect(result.save).toBe(save);
    expect(save.meta.protectedBank.SCRAP).toBe(30);
  });

  it('rejects unsecured cargo and refuses dismantling during an active run', () => {
    const unsecured = saveWithSpareItem('dismantle-unsecured', false);
    expect(dismantleGarageItem(unsecured.save, unsecured.item.itemId)).toMatchObject({ ok: false, failureCode: 'ITEM_NOT_OWNED' });
    const protectedItem = saveWithSpareItem('dismantle-active-run');
    const active = { ...protectedItem.save, run: createInitialRun(protectedItem.save, 'dismantle-locked-run') };
    expect(dismantleGarageItem(active, protectedItem.item.itemId)).toMatchObject({ ok: false, failureCode: 'RUN_ACTIVE' });
  });
});
