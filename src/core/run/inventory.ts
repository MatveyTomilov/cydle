import type { EquipSlotId } from '../types';
import { parseSave, type SaveGame } from '../save/schema';
import { resolveRunBuild } from './build';
import { runCargoUnits } from './cargo';
import type { RunCommandResult } from './types';

function fail(save: SaveGame, failureCode: string, reason: string): RunCommandResult {
  return { ok: false, save, failureCode, reason };
}

function canChangeLoadout(save: SaveGame): RunCommandResult | null {
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!['ROUTE', 'NODE', 'CHECKPOINT'].includes(run.phase)) return fail(save, 'LOADOUT_LOCKED', 'Сборку можно менять только между боями.');
  const node = run.graph.layers.flat().find((candidate) => candidate.id === run.currentNodeId);
  if (run.phase === 'NODE' && node && ['COMBAT', 'ELITE', 'BOUNTY', 'BOSS'].includes(node.type) && !run.clearedNodeIds.includes(node.id)) {
    return fail(save, 'LOADOUT_LOCKED', 'Сборку нельзя менять перед ещё не разрешённым боем.');
  }
  return null;
}

function markCommand(save: SaveGame, id: string): SaveGame {
  const next = structuredClone(save);
  const run = next.run!;
  run.commandIds = [...run.commandIds, id].slice(-128);
  run.lastCommandId = id;
  return next;
}

function validateCommand(save: SaveGame, id: string): RunCommandResult | null {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  if (!save.run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!id.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (save.run!.commandIds.includes(id)) return { ok: true, save, events: [] };
  const unlocked = canChangeLoadout(save);
  if (unlocked) return unlocked;
  return null;
}

function commitLoadout(save: SaveGame, id: string, equipment: Partial<Record<EquipSlotId, string>>, text: string): RunCommandResult {
  const next = markCommand(save, id);
  next.run!.equipment = equipment;
  const build = resolveRunBuild(next);
  if (!build.valid) return fail(save, 'BUILD_INVALID', build.issues.map((issue) => issue.message).join(' '));
  if (runCargoUnits(next.run!.unsecuredCargo) > Math.floor(build.stats.cargoUnits)) return fail(save, 'CARGO_OVER_CAPACITY', 'Смена модуля CARGO превысит вместимость уже перевозимого груза.');
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'LOADOUT_CHANGED', text }] };
}

export function equipRunItem(save: SaveGame, command: { id: string; itemId: string; slot: EquipSlotId }): RunCommandResult {
  const invalid = validateCommand(save, command.id);
  if (invalid) return invalid;
  const run = save.run!;
  const item = save.meta.inventory.find((candidate) => candidate.itemId === command.itemId)
    ?? run.unsecuredCargo.find((candidate) => candidate.itemId === command.itemId);
  if (!item) return fail(save, 'ITEM_NOT_OWNED', 'Предмет отсутствует в защищённом инвентаре и грузе выезда.');
  const equippedSlot = Object.entries(run.equipment).find(([, itemId]) => itemId === item.itemId)?.[0];
  if (equippedSlot) return fail(save, 'ITEM_ALREADY_EQUIPPED', `Предмет уже установлен в слот ${equippedSlot}.`);
  return commitLoadout(save, command.id, { ...run.equipment, [command.slot]: item.itemId }, `${item.templateId} установлен в ${command.slot}. Владение предметом не изменилось.`);
}

export function unequipRunSlot(save: SaveGame, command: { id: string; slot: EquipSlotId }): RunCommandResult {
  const invalid = validateCommand(save, command.id);
  if (invalid) return invalid;
  const run = save.run!;
  if (!run.equipment[command.slot]) return fail(save, 'SLOT_EMPTY', `Слот ${command.slot} уже пуст.`);
  const equipment = { ...run.equipment };
  const itemId = equipment[command.slot];
  delete equipment[command.slot];
  return commitLoadout(save, command.id, equipment, `${itemId} снят со слота ${command.slot}. Предмет остаётся в своей текущей собственности.`);
}
