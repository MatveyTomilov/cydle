import type { EquipSlotId } from '../types';
import { calibrationCost, craftOperationCost, coreGroupForDepth, dismantleValue, repairCost, shopPrice, templateOf } from '../items/items';
import { AFFIX_BY_ID, RARITY_AFFIX_COUNT, tierForTech, type AffixRoll } from '../../data/affixes';
import { Rng } from '../rng';
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

function rollAffix(affixId: string, tier: AffixRoll['tier'], rng: Rng, tierBoosted: boolean): AffixRoll {
  const definition = AFFIX_BY_ID[affixId]!;
  const center = definition.tiers[tier - 1]!;
  const rawRoll = definition.fixed ? 1 : rng.range(0.8, 1.2);
  let value = center * rawRoll;
  value = definition.integer ? Math.max(1, Math.round(value)) : Math.round(value * 100) / 100;
  return {
    affixId,
    tier,
    value,
    rawRoll: Math.round(rawRoll * 10000) / 10000,
    tierBoosted,
    center,
    min: definition.integer ? Math.max(1, Math.round(center * 0.8)) : Math.round(center * 0.8 * 100) / 100,
    max: definition.integer ? Math.round(center * 1.2) : Math.round(center * 1.2 * 100) / 100,
  };
}

export function craftGarageAffix(save: SaveGame, command: {
  itemId: string;
  operation: 'REROLL' | 'TIER_UP' | 'REPLACE' | 'ADD';
  affixIndex?: number;
  replacementAffixId?: string;
  affixId?: string;
  seed: string;
}): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const locked = canEditGarage(save);
  if (locked) return locked;
  if (!command.seed.trim()) return fail(save, 'INVALID_CRAFT_SEED', 'Операции нужен уникальный seed.');
  const item = save.meta.inventory.find((candidate) => candidate.itemId === command.itemId && candidate.secured);
  if (!item) return fail(save, 'ITEM_NOT_OWNED', 'Калибровать можно только предмет из защищённого склада.');
  const template = templateOf(item);
  const selected = command.operation === 'ADD' ? undefined : item.affixes[command.affixIndex ?? -1];
  if (command.operation !== 'ADD' && (!selected || !Number.isInteger(command.affixIndex))) return fail(save, 'AFFIX_NOT_FOUND', 'Выбранный аффикс отсутствует на предмете.');
  if (command.operation === 'REROLL' && AFFIX_BY_ID[selected!.affixId]?.fixed) return fail(save, 'FIXED_AFFIX', 'Этот аффикс имеет фиксированное значение и не перекатывается.');
  if (command.operation === 'TIER_UP' && selected!.tier >= tierForTech(item.techLevel)) return fail(save, 'TIER_AT_CAP', 'Аффикс уже достиг предела для текущего TechLevel.');
  let targetAffixId = selected?.affixId;
  if (command.operation === 'REPLACE') {
    targetAffixId = command.replacementAffixId;
    const target = targetAffixId ? AFFIX_BY_ID[targetAffixId] : undefined;
    if (!target || !target.slots.includes(template.category)) return fail(save, 'INVALID_AFFIX_SLOT', 'Новый аффикс несовместим с этим предметом.');
    if (targetAffixId === selected!.affixId || item.affixes.some((affix, index) => index !== command.affixIndex && affix.affixId === targetAffixId)) return fail(save, 'DUPLICATE_AFFIX', 'Этот аффикс уже есть на предмете.');
  }
  if (command.operation === 'ADD') {
    targetAffixId = command.affixId;
    const target = targetAffixId ? AFFIX_BY_ID[targetAffixId] : undefined;
    if (!target || !target.slots.includes(template.category)) return fail(save, 'INVALID_AFFIX_SLOT', 'Новый аффикс несовместим с этим предметом.');
    if (item.affixes.some((affix) => affix.affixId === targetAffixId)) return fail(save, 'DUPLICATE_AFFIX', 'Этот аффикс уже есть на предмете.');
    if (item.affixes.length >= RARITY_AFFIX_COUNT[item.rarity]![1]) return fail(save, 'NO_AFFIX_SLOT', 'У предмета нет свободного слота аффикса.');
  }
  const cost = craftOperationCost(command.operation, item.techLevel);
  if (item.tr < cost.tr) return fail(save, 'INSUFFICIENT_TR', `Операции требуется ${cost.tr} TR; доступно ${item.tr}.`);
  if (save.meta.protectedBank.SCRAP < cost.scrap || save.meta.protectedBank.DATA < cost.data) {
    return fail(save, 'INSUFFICIENT_RESOURCES', `Операция требует ${cost.scrap} металлолома и ${cost.data} данных.`);
  }
  const rng = new Rng('item-craft', command.seed);
  const tier = command.operation === 'TIER_UP' ? (selected!.tier + 1) as AffixRoll['tier']
    : command.operation === 'ADD' ? tierForTech(item.techLevel)
      : selected!.tier;
  const nextAffix = rollAffix(targetAffixId!, tier, rng, command.operation === 'REROLL' && selected!.tierBoosted);
  const next = structuredClone(save);
  const nextItem = next.meta.inventory.find((candidate) => candidate.itemId === command.itemId)!;
  if (command.operation === 'ADD') nextItem.affixes.push(nextAffix);
  else nextItem.affixes[command.affixIndex!] = nextAffix;
  nextItem.tr -= cost.tr;
  nextItem.rollSeed = `craft:${command.seed}`;
  next.meta.protectedBank.SCRAP -= cost.scrap;
  next.meta.protectedBank.DATA -= cost.data;
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  const action = command.operation === 'REROLL' ? 'изменён roll' : command.operation === 'TIER_UP' ? 'повышен tier' : command.operation === 'REPLACE' ? 'заменён аффикс' : 'добавлен аффикс';
  const oldName = selected ? `${AFFIX_BY_ID[selected.affixId]?.name ?? selected.affixId} → ` : '';
  return { ok: true, save: checked.data, events: [{ type: 'ITEM_AFFIX_CRAFTED', text: `${template.name}: ${oldName}${AFFIX_BY_ID[targetAffixId!]?.name ?? targetAffixId} ${action} (${nextAffix.value}, T${nextAffix.tier}). Потрачено ${cost.tr} TR, ${cost.scrap} металлолома, ${cost.data} данных.` }] };
}

export function calibrateGarageItem(save: SaveGame, itemId: string, targetTechLevel: number): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const locked = canEditGarage(save);
  if (locked) return locked;
  const item = save.meta.inventory.find((candidate) => candidate.itemId === itemId && candidate.secured);
  if (!item || templateOf(item).category === 'MATERIAL') return fail(save, 'ITEM_NOT_OWNED', 'Калибровать можно только предмет из защищённого склада.');
  if (!Number.isInteger(targetTechLevel) || targetTechLevel <= item.techLevel) return fail(save, 'INVALID_TECHLEVEL', 'Новый TechLevel должен быть целым числом выше текущего.');
  const maxTechLevel = Math.max(4, save.meta.unlockedForpost);
  if (targetTechLevel > maxTechLevel) return fail(save, 'TECHLEVEL_LOCKED', `Открыта калибровка только до T${maxTechLevel}.`);
  const cost = calibrationCost(item, targetTechLevel);
  const cores = save.meta.inventory.filter((candidate) => candidate.secured && templateOf(candidate).category === 'MATERIAL' && candidate.coreGroup === cost.coreGroup).slice(0, cost.cores);
  if (cores.length < cost.cores) return fail(save, 'MISSING_CALIBRATION_CORE', `Нужно ${cost.cores} калибровочное ядро группы ${coreGroupForDepth(targetTechLevel)}.`);
  if (save.meta.protectedBank.SCRAP < cost.scrap || save.meta.protectedBank.DATA < cost.data) return fail(save, 'INSUFFICIENT_RESOURCES', `Калибровка требует ${cost.scrap} металлолома и ${cost.data} данных.`);
  const next = structuredClone(save);
  next.meta.protectedBank.SCRAP -= cost.scrap;
  next.meta.protectedBank.DATA -= cost.data;
  const coreIds = new Set(cores.map((core) => core.itemId));
  next.meta.inventory = next.meta.inventory.filter((candidate) => !coreIds.has(candidate.itemId)).map((candidate) => candidate.itemId === itemId ? { ...candidate, techLevel: targetTechLevel } : candidate);
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'ITEM_CALIBRATED', text: `${templateOf(item).name} повышен до T${targetTechLevel}. Потрачено ${cost.cores} ядро группы ${cost.coreGroup}, ${cost.scrap} металлолома и ${cost.data} данных.` }] };
}
