import { NODE_TYPE_RU } from '../types';
import { resolveBuild } from '../build/build';
import { parseSave, type SaveGame } from '../save/schema';
import type { RunCommandResult } from './types';

function fail(save: SaveGame, failureCode: string, reason: string): RunCommandResult {
  return { ok: false, save, failureCode, reason };
}

function markCommand(save: SaveGame, commandId: string): SaveGame {
  const next = structuredClone(save);
  const run = next.run!;
  run.commandIds = [...run.commandIds, commandId].slice(-128);
  run.lastCommandId = commandId;
  return next;
}

function buildFor(save: SaveGame) {
  const items = new Map(save.meta.inventory.map((item) => [item.itemId, item]));
  const equipment = Object.fromEntries(Object.entries(save.meta.equipment).map(([slot, id]) => [slot, items.get(id)]));
  return resolveBuild({
    attributes: save.meta.operator.attributes,
    equipment,
    skillIds: save.meta.skillIds,
    passiveIds: save.meta.passiveIds,
    treeNodeIds: save.meta.treeNodeIds,
    attributePointsEarned: save.meta.operator.attributePoints,
    treePointsEarned: save.meta.operator.treePoints,
    unlockedImplantSlots: save.meta.unlockedImplantSlots,
    unlockedDroneSlots: save.meta.unlockedDroneSlots,
  });
}

/** Pure, idempotent route transition. Persistence is performed by the application after success. */
export function chooseRunNode(save: SaveGame, commandId: string, nodeId: string): RunCommandResult {
  const current = parseSave(save);
  if (!current.success) return fail(save, 'INVALID_SAVE', current.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!commandId.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(commandId)) return { ok: true, save, events: [] };
  if (run.phase !== 'ROUTE') return fail(save, 'RUN_NOT_AT_ROUTE', 'Переход доступен только между узлами.');
  const edge = run.graph.edges.find((candidate) => candidate.from === run.currentNodeId && candidate.to === nodeId);
  if (!edge) return fail(save, 'INVALID_ROUTE', 'Этот узел не соединён с текущей позицией.');
  if (run.resources.fuel < edge.fuelCost) return fail(save, 'INSUFFICIENT_FUEL', `Для перехода требуется ${edge.fuelCost} ед. топлива; доступно ${run.resources.fuel}.`);
  const node = run.graph.layers.flat().find((candidate) => candidate.id === nodeId);
  if (!node || run.visitedNodeIds.includes(nodeId)) return fail(save, 'INVALID_NODE', 'Узел неизвестен или уже посещён.');
  const build = buildFor(save);
  if (!build.valid) return fail(save, 'INVALID_BUILD', build.issues.map((issue) => issue.message).join(' '));

  const next = markCommand(save, commandId);
  const updatedRun = next.run!;
  const travelMs = Math.max(0, Math.round(25_000 * (1 - build.stats.travelDurationLess / 100)));
  updatedRun.currentNodeId = nodeId;
  updatedRun.visitedNodeIds = [...updatedRun.visitedNodeIds, nodeId];
  updatedRun.resources = { ...updatedRun.resources, fuel: updatedRun.resources.fuel - edge.fuelCost, gameTimeMs: updatedRun.resources.gameTimeMs + travelMs };
  updatedRun.phase = node.type === 'CHECKPOINT' ? 'CHECKPOINT' : 'NODE';

  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'NODE_ENTERED', text: `Переезд ${Math.ceil(travelMs / 1000)} с · топливо −${edge.fuelCost} · узел: ${NODE_TYPE_RU[node.type]}.` }] };
}
