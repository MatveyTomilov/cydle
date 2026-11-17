import { describe, expect, it } from 'vitest';
import { createItem } from '../../src/core/items/items';
import { tierForTech } from '../../src/data/affixes';
import { Rng } from '../../src/core/rng';
import { createInitialSave } from '../../src/core/save/initial';
import { craftGarageAffix } from '../../src/core/inventory/garage';

function saveWithRareWeapon(saveId: string, techLevel = 1) {
  const save = createInitialSave({ saveId, now: 100 });
  const item = createItem(new Rng('craft-item', saveId), {
    templateId: 'RIFLE_K2', techLevel, rarity: 'RARE', secured: true,
    originGrantId: `craft:${saveId}`, origin: 'test', acquiredAt: 100,
  });
  save.meta.inventory.push(item);
  return { save, item };
}

describe('protected affix crafting', () => {
  it('rerolls only the selected affix inside its existing tier and charges scrap plus TR', () => {
    const { save, item } = saveWithRareWeapon('craft-reroll');
    const before = item.affixes[0]!;
    const result = craftGarageAffix(save, { itemId: item.itemId, operation: 'REROLL', affixIndex: 0, seed: 'reroll-fixed-seed' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const updated = result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)!;
    expect(updated.affixes[0]?.affixId).toBe(before.affixId);
    expect(updated.affixes[0]?.tier).toBe(before.tier);
    expect(updated.affixes[0]?.value).not.toBe(before.value);
    expect(updated.affixes.slice(1)).toEqual(item.affixes.slice(1));
    expect(updated.tr).toBe(item.tr - 3);
    expect(result.save.meta.protectedBank.SCRAP).toBe(20);
  });

  it('raises one non-capped affix by one tier and charges the declared resources', () => {
    const { save, item } = saveWithRareWeapon('craft-tier-up', 1);
    // Calibration raises TechLevel without rewriting existing affix tiers.
    item.techLevel = 5;
    const index = item.affixes.findIndex((affix) => affix.tier < tierForTech(item.techLevel));
    expect(index).toBeGreaterThanOrEqual(0);
    const result = craftGarageAffix(save, { itemId: item.itemId, operation: 'TIER_UP', affixIndex: index, seed: 'tier-fixed-seed' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const updated = result.save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)!;
    expect(updated.affixes[index]?.tier).toBe(item.affixes[index]!.tier + 1);
    expect(updated.tr).toBe(item.tr - 6);
    expect(result.save.meta.protectedBank.SCRAP).toBe(2);
    expect(result.save.meta.protectedBank.DATA).toBe(13);
  });

  it('rejects an unaffordable operation without changing the item or wallet', () => {
    const { save, item } = saveWithRareWeapon('craft-insufficient');
    save.meta.protectedBank.SCRAP = 1;
    const result = craftGarageAffix(save, { itemId: item.itemId, operation: 'REROLL', affixIndex: 0, seed: 'no-funds-seed' });
    expect(result).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_RESOURCES' });
    expect(result.save).toBe(save);
    expect(save.meta.inventory.find((candidate) => candidate.itemId === item.itemId)?.affixes).toEqual(item.affixes);
    expect(save.meta.protectedBank.SCRAP).toBe(1);
  });

  it('rejects tier upgrades at the TechLevel cap and rerolls of fixed affixes', () => {
    const capped = saveWithRareWeapon('craft-capped');
    capped.item.affixes[0]!.tier = 4;
    expect(craftGarageAffix(capped.save, { itemId: capped.item.itemId, operation: 'TIER_UP', affixIndex: 0, seed: 'capped-seed' })).toMatchObject({ ok: false, failureCode: 'TIER_AT_CAP' });

    const scannerSave = createInitialSave({ saveId: 'craft-fixed-scan', now: 100 });
    const scanner = createItem(new Rng('craft-fixed-scan', 'scanner'), {
      templateId: 'TR_SCANNER_1', techLevel: 1, rarity: 'RARE', secured: true,
      originGrantId: 'craft-fixed-scan:scanner', origin: 'test', acquiredAt: 100,
    });
    scannerSave.meta.inventory.push(scanner);
    expect(scanner.affixes[0]?.affixId).toBe('AF_SCAN');
    expect(craftGarageAffix(scannerSave, { itemId: scanner.itemId, operation: 'REROLL', affixIndex: 0, seed: 'fixed-seed' })).toMatchObject({ ok: false, failureCode: 'FIXED_AFFIX' });
  });
});
