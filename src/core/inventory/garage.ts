import type { EquipSlotId } from '../types';
import { dismantleValue, repairCost, shopPrice, templateOf } from '../items/items';
import { parseSave, type SaveGame } from '../save/schema';
import { resolveRunBuild } from '../run/build';
import type { RunCommandResult } from '../run/types';

function fail(save: SaveGame, failureCode: string, reason: string): RunCommandResult {
  return { ok: false, save, failureCode, reason };
}

function canEditGarage(save: SaveGame): RunCommandResult | null {
  if (save.run && !['EXTRACTED', 'DEFEATED'].includes(save.run.phase)) {
    return fail(save, 'RUN_ACTIVE', 'Постоянную экипировку можно менять после завершения выезда.');
  }
  return null;
}

function commitGarageEquipment(save: SaveGame, equipment: Partial<Record<EquipSlotId, string>>, text: string): RunCommandResult {
  const next = structuredClone(save);
  next.meta.equipment = equipment;
  if (next.run) next.run.equipment = { ...equipment };
  const build = resolveRunBuild(next, null);
  if (!build.valid) return fail(save, 'BUILD_INVALID', build.issues.map((issue) => issue.message).join(' '));
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'GARAGE_LOADOUT_CHANGED', text }] };
}

export function equipGarageItem(save: SaveGame, itemId: string, slot: EquipSlotId): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const locked = canEditGarage(save);
  if (locked) return locked;
  const item = save.meta.inventory.find((candidate) => candidate.itemId === itemId && candidate.secured);
  if (!item) return fail(save, 'ITEM_NOT_OWNED', 'Для гаражной экипировки нужен предмет из защищённого склада.');
  const alreadyEquipped = Object.entries(save.meta.equipment).find(([, equippedId]) => equippedId === itemId)?.[0];
  if (alreadyEquipped) return fail(save, 'ITEM_ALREADY_EQUIPPED', `Предмет уже установлен в слот ${alreadyEquipped}.`);
  return commitGarageEquipment(save, { ...save.meta.equipment, [slot]: itemId }, `${item.templateId} установлен в гараже, слот ${slot}.`);
}

export function unequipGarageSlot(save: SaveGame, slot: EquipSlotId): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const locked = canEditGarage(save);
  if (locked) return locked;
  const itemId = save.meta.equipment[slot];
  if (!itemId) return fail(save, 'SLOT_EMPTY', `Слот ${slot} уже пуст.`);
  const equipment = { ...save.meta.equipment };
  delete equipment[slot];
  return commitGarageEquipment(save, equipment, `${itemId} снят в гараже и оставлен на защищённом складе.`);
}

export function dismantleGarageItem(save: SaveGame, itemId: string): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const locked = canEditGarage(save);
  if (locked) return locked;
  const item = save.meta.inventory.find((candidate) => candidate.itemId === itemId && candidate.secured);
  if (!item) return fail(save, 'ITEM_NOT_OWNED', 'Разобрать можно только предмет из защищённого склада.');
  if (templateOf(item).category === 'MATERIAL') return fail(save, 'ITEM_NOT_DISMANTLABLE', 'Материалы нельзя разбирать на ресурсы.');
  const slot = Object.entries(save.meta.equipment).find(([, equippedId]) => equippedId === itemId)?.[0];
  if (slot) return fail(save, 'ITEM_EQUIPPED', `Сначала снимите предмет со слота ${slot}.`);
  const value = dismantleValue(item);
  const next = structuredClone(save);
  next.meta.inventory = next.meta.inventory.filter((candidate) => candidate.itemId !== itemId);
  next.meta.protectedBank.SCRAP += value.scrap;
  next.meta.protectedBank.DATA += value.data;
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  const resources = [`${value.scrap} металлолома`, ...(value.data ? [`${value.data} данных`] : [])].join(' и ');
  return { ok: true, save: checked.data, events: [{ type: 'ITEM_DISMANTLED', text: `${templateOf(item).name} разобран. Получено: ${resources}.` }] };
}

export function garageRepairCost(item: SaveGame['meta']['inventory'][number]): number {
  const template = templateOf(item);
  const comparableTemplateId = template.baseTemplateId ?? item.templateId;
  return Math.min(repairCost(item), shopPrice(comparableTemplateId, item.techLevel, 'COMMON'));
}

export function repairGarageItem(save: SaveGame, itemId: string): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const locked = canEditGarage(save);
  if (locked) return locked;
  const item = save.meta.inventory.find((candidate) => candidate.itemId === itemId && candidate.secured);
  if (!item) return fail(save, 'ITEM_NOT_OWNED', 'Ремонтировать можно только предмет из защищённого склада.');
  if (item.durability >= 100) return fail(save, 'ITEM_FULLY_REPAIRED', 'У предмета уже полная прочность.');
  const template = templateOf(item);
  const cost = garageRepairCost(item);
  if (save.meta.protectedBank.SCRAP < cost) return fail(save, 'INSUFFICIENT_SCRAP', `Для ремонта нужно ${cost} металлолома; доступно ${save.meta.protectedBank.SCRAP}.`);
  const next = structuredClone(save);
  next.meta.protectedBank.SCRAP -= cost;
  next.meta.inventory = next.meta.inventory.map((candidate) => candidate.itemId === itemId ? { ...candidate, durability: 100 } : candidate);
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'ITEM_REPAIRED', text: `${template.name} отремонтирован до 100% прочности. Стоимость: ${cost} металлолома.` }] };
}
