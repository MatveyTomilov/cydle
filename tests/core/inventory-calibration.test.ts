import { describe, expect, it } from 'vitest';
import { createCore, createItem } from '../../src/core/items/items';
import { AFFIX_BY_ID } from '../../src/data/affixes';
import { Rng } from '../../src/core/rng';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { calibrateGarageItem, craftGarageAffix } from '../../src/core/inventory/garage';

function makeItem(saveId: string, rarity: 'MODIFIED' | 'RARE', affixCount?: number) {
  return createItem(new Rng('calibration-item', saveId), {
    templateId: 'RIFLE_K2', techLevel: 1, rarity, secured: true,
    originGrantId: `calibration:${saveId}`, origin: 'test', acquiredAt: 100, affixCount,
  });
}

describe('protected craft and TechLevel calibration', () => {
  it('replaces only the selected affix and spends the declared data and TR', () => {
    const save = createInitialSave({ saveId: 'craft-replace', now: 100 });
    const item = makeItem('craft-replace', 'RARE');
    save.meta.inventory.push(item);
    const replacement = ['AF_ACC', 'AF_KDM', 'AF_EDM', 'AF_AS', 'AF_CR', 'AF_CM', 'AF_PEN', 'AF_EPN', 'AF_DPN', 'AF_VIR'].find((id) => !item.affixes.some((affix) => affix.affixId === id))!;
    const result = craftGarageAffix(save, { itemId: item.itemId, operation: 'REPLACE', affixIndex: 0, replacementAffixId: replacement, seed: 'replace-seed' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const updated = result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)!;
    expect(updated.affixes[0]?.affixId).toBe(replacement);
    expect(updated.affixes.slice(1)).toEqual(item.affixes.slice(1));
    expect(updated.tr).toBe(item.tr - 8);
    expect(result.save.meta.protectedBank.DATA).toBe(8);
  });

  it('adds one compatible affix into a free rarity slot and charges scrap, data, and TR', () => {
    const save = createInitialSave({ saveId: 'craft-add', now: 100 });
    const item = makeItem('craft-add', 'MODIFIED', 1);
    save.meta.inventory.push(item);
    const affixId = ['AF_ACC', 'AF_KDM', 'AF_EDM', 'AF_AS', 'AF_CR', 'AF_CM', 'AF_PEN', 'AF_EPN', 'AF_DPN', 'AF_VIR'].find((id) => !item.affixes.some((affix) => affix.affixId === id))!;
    const result = craftGarageAffix(save, { itemId: item.itemId, operation: 'ADD', affixId, seed: 'add-seed' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const updated = result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)!;
    expect(updated.affixes).toHaveLength(2);
    expect(updated.affixes[1]?.affixId).toBe(affixId);
    expect(updated.tr).toBe(item.tr - 10);
    expect(result.save.meta.protectedBank.SCRAP).toBe(10);
    expect(result.save.meta.protectedBank.DATA).toBe(10);
  });

  it('calibrates a secured item in place with the matching core group and exact cost', () => {
    const save = createInitialSave({ saveId: 'tech-calibration', now: 100 });
    save.meta.unlockedForpost = 8;
    const item = makeItem('tech-calibration', 'RARE');
    save.meta.inventory.push(item);
    const core = createCore(new Rng('calibration-core', 'seed'), 5, 'core:group-2', true);
    save.meta.inventory.push(core);
    const result = calibrateGarageItem(save, item.itemId, 5);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const updated = result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)!;
    expect(updated.techLevel).toBe(5);
    expect(updated.itemId).toBe(item.itemId);
    expect(updated.affixes).toEqual(item.affixes);
    expect(updated.tr).toBe(item.tr);
    expect(result.save.meta.inventory.some((candidate) => candidate.itemId === core.itemId)).toBe(false);
    expect(result.save.meta.protectedBank.SCRAP).toBe(2);
    expect(result.save.meta.protectedBank.DATA).toBe(9);
  });

  it('does not allow an affix from another item category', () => {
    const save = createInitialSave({ saveId: 'craft-slot', now: 100 });
    const item = makeItem('craft-slot', 'MODIFIED', 1);
    save.meta.inventory.push(item);
    const invalid = Object.keys(AFFIX_BY_ID).find((id) => !AFFIX_BY_ID[id]!.slots.includes('MAIN'))!;
    expect(craftGarageAffix(save, { itemId: item.itemId, operation: 'REPLACE', affixIndex: 0, replacementAffixId: invalid, seed: 'bad-slot-seed' })).toMatchObject({ ok: false, failureCode: 'INVALID_AFFIX_SLOT' });
  });

  it('requires the unlocked TechLevel range and matching calibration core group', () => {
    const save = createInitialSave({ saveId: 'tech-range', now: 100 });
    const item = makeItem('tech-range', 'RARE');
    save.meta.inventory.push(item);
    expect(calibrateGarageItem(save, item.itemId, 5)).toMatchObject({ ok: false, failureCode: 'TECHLEVEL_LOCKED' });
    save.meta.unlockedForpost = 8;
    save.meta.inventory.push(createCore(new Rng('wrong-core', 'seed'), 1, 'core:group-1', true));
    expect(calibrateGarageItem(save, item.itemId, 5)).toMatchObject({ ok: false, failureCode: 'MISSING_CALIBRATION_CORE' });
    expect(save.meta.protectedBank.SCRAP).toBe(30);
    expect(save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)?.techLevel).toBe(1);
  });

  it('blocks adding affixes during an active run and when rarity slots are full', () => {
    const fullSave = createInitialSave({ saveId: 'craft-full', now: 100 });
    const fullItem = makeItem('craft-full', 'MODIFIED', 2);
    fullSave.meta.inventory.push(fullItem);
    expect(craftGarageAffix(fullSave, { itemId: fullItem.itemId, operation: 'ADD', affixId: 'AF_AS', seed: 'full-seed' })).toMatchObject({ ok: false, failureCode: 'NO_AFFIX_SLOT' });

    const activeSave = createInitialSave({ saveId: 'craft-active', now: 100 });
    const item = makeItem('craft-active', 'MODIFIED', 1);
    activeSave.meta.inventory.push(item);
    const active = { ...activeSave, run: createInitialRun(activeSave, 'craft-active-seed') };
    expect(craftGarageAffix(active, { itemId: item.itemId, operation: 'ADD', affixId: 'AF_AS', seed: 'active-seed' })).toMatchObject({ ok: false, failureCode: 'RUN_ACTIVE' });
  });
});
