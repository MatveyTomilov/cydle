import { campaignBiome } from '../../data/biomes';
import { templateOf } from '../items/items';
import { R } from '../math/formula';
import { Rng } from '../rng';
import { parseSave, type SaveGame } from '../save/schema';
import type { RunCommandResult, RunState } from './types';
import { generateSectorGraph } from './graph';

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

function secureItem(save: SaveGame, item: RunState['unsecuredCargo'][number]): void {
  const existing = save.meta.inventory.find((candidate) => candidate.itemId === item.itemId || candidate.originGrantId === item.originGrantId);
  if (existing) existing.secured = true;
  else save.meta.inventory.push({ ...item, secured: true });
  if (item.templateId === 'IMP_HEAT' || item.templateId === 'IMP_VIRUS' || item.templateId === 'IMP_SHIELD') {
    save.meta.tutorial.starterPrototypeSecured = true;
  }
}

function checkpointNode(run: RunState) {
  return run.graph.layers.flat().find((node) => node.id === run.currentNodeId);
}

function recordSectorClear(save: SaveGame, run: RunState): void {
  save.meta.maxSectorCleared = Math.max(save.meta.maxSectorCleared ?? 0, run.depth);
  if (!save.meta.unlockedBiomes.includes(run.biome)) save.meta.unlockedBiomes.push(run.biome);
  save.meta.tutorial.firstSectorCompleted ||= run.depth === 1;
  const node = checkpointNode(run);
  if (node?.type === 'BOSS' && run.depth % 4 === 0) {
    save.meta.unlockedForpost = Math.max(save.meta.unlockedForpost, Math.min(12, run.depth));
  }
}

function mergeRunWallet(save: SaveGame, run: RunState, wallet = run.runWallet): void {
  save.meta.protectedBank = {
    CREDITS: save.meta.protectedBank.CREDITS + wallet.CREDITS,
    SCRAP: save.meta.protectedBank.SCRAP + wallet.SCRAP,
    DATA: save.meta.protectedBank.DATA + wallet.DATA,
  };
  run.runWallet = {
    CREDITS: run.runWallet.CREDITS - wallet.CREDITS,
    SCRAP: run.runWallet.SCRAP - wallet.SCRAP,
    DATA: run.runWallet.DATA - wallet.DATA,
  };
}

function finishRun(save: SaveGame, run: RunState): void {
  for (const item of run.unsecuredCargo) secureItem(save, item);
  run.unsecuredCargo = [];
  mergeRunWallet(save, run);
  save.meta.transport.fuel = run.resources.fuel;
  save.meta.transport.hull = run.resources.hull;
  save.meta.equipment = { ...run.equipment };
  run.phase = 'EXTRACTED';
}

function advanceSector(run: RunState): void {
  const depth = run.depth + 1;
  const world = Rng.fromSerialized(run.worldRng);
  const biome = campaignBiome(depth, world.next()) as RunState['biome'];
  const graphSeed = `${run.seed}:sector:${depth}:${world.nextUint32().toString(16)}`;
  const graph = generateSectorGraph({ seed: graphSeed, depth, biome, wanted: run.wanted, usedEventIds: run.eventsSeen });
  run.depth = depth;
  run.biome = biome;
  run.graph = graph;
  run.currentNodeId = graph.startNodeId;
  run.visitedNodeIds = [];
  run.clearedNodeIds = [];
  run.phase = 'ROUTE';
  run.combatResult = null;
  run.worldRng = world.serialize();
  run.resources.gameTimeMs += 8_000;
}

/** Resolves the checkpoint transaction. All mutations happen on a validated copy. */
export function resolveRunCheckpoint(
  save: SaveGame,
  command: { id: string; choice: 'EXIT' | 'SHIP' | 'CONTINUE'; cargoItemIds?: string[]; currencyShare?: number; spendProtected?: boolean },
): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!command.id.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(command.id)) return { ok: true, save, events: [] };
  const node = checkpointNode(run);
  if (run.phase !== 'CHECKPOINT' || !node || !['CHECKPOINT', 'BOSS'].includes(node.type)) {
    return fail(save, 'NOT_AT_CHECKPOINT', 'Решение доступно только после прохождения контрольного узла или босса.');
  }

  const next = markCommand(save, command.id);
  const nextRun = next.run!;
  const checkpointId = node.id;
  nextRun.resources.gameTimeMs += 8_000;
  recordSectorClear(next, nextRun);

  if (command.choice === 'EXIT') {
    finishRun(next, nextRun);
    const checked = parseSave(next);
    if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
    return { ok: true, save: checked.data, events: [{ type: 'RUN_EXTRACTED', text: `Выезд завершён. В склад доставлены груз и валюты сектора ${run.depth}.` }] };
  }

  if (command.choice === 'SHIP') {
    if (nextRun.shippedCheckpointIds.includes(checkpointId)) return fail(save, 'SHIP_ALREADY_USED', 'На этом контрольном узле отправка уже использована.');
    const itemIds = command.cargoItemIds ?? [];
    const share = command.currencyShare ?? 0;
    if (!Number.isFinite(share) || share < 0 || share > 0.5) return fail(save, 'INVALID_CURRENCY_SHARE', 'Можно отправить от 0 до 50% валют выезда.');
    if (new Set(itemIds).size !== itemIds.length) return fail(save, 'DUPLICATE_CARGO', 'Предмет нельзя выбрать для отправки дважды.');
    if (itemIds.length > 5) return fail(save, 'CARGO_LIMIT', 'За одну отправку можно выбрать не более пяти предметов.');
    const selected = itemIds.map((id) => nextRun.unsecuredCargo.find((item) => item.itemId === id));
    if (selected.some((item) => !item)) return fail(save, 'UNKNOWN_CARGO', 'Выбранный предмет не находится в незакреплённом грузе.');
    const units = selected.reduce((total, item) => total + templateOf(item!).cargoUnits, 0);
    if (units > 5) return fail(save, 'CARGO_UNIT_LIMIT', 'Выбранный груз превышает лимит пяти единиц вместимости.');
    const possibleShipment = ['CREDITS', 'SCRAP', 'DATA'].some((currency) => Math.floor(nextRun.runWallet[currency as keyof typeof nextRun.runWallet] * share) > 0);
    if (itemIds.length === 0 && !possibleShipment) return fail(save, 'EMPTY_SHIPMENT', 'Выберите предмет или ненулевую долю валюты для отправки.');
    const cost = Math.ceil(10 * R(nextRun.depth));
    const runCredits = nextRun.runWallet.CREDITS;
    const bankCredits = next.meta.protectedBank.CREDITS;
    if (runCredits + (command.spendProtected ? bankCredits : 0) < cost) return fail(save, 'INSUFFICIENT_FUNDS', `Отправка стоит ${cost} кредитов; разрешите оплату из защищённого банка или заработайте кредиты в выезде.`);
    const fromRun = Math.min(runCredits, cost);
    nextRun.runWallet.CREDITS -= fromRun;
    if (cost > fromRun) next.meta.protectedBank.CREDITS -= cost - fromRun;
    const walletShare = {
      CREDITS: Math.floor(nextRun.runWallet.CREDITS * share),
      SCRAP: Math.floor(nextRun.runWallet.SCRAP * share),
      DATA: Math.floor(nextRun.runWallet.DATA * share),
    };
    if (itemIds.length === 0 && Object.values(walletShare).every((amount) => amount === 0)) return fail(save, 'EMPTY_SHIPMENT', 'Выберите предмет или ненулевую долю валюты для отправки.');

    const chosen = new Set(itemIds);
    const shipped = nextRun.unsecuredCargo.filter((item) => chosen.has(item.itemId));
    for (const item of shipped) secureItem(next, item);
    nextRun.unsecuredCargo = nextRun.unsecuredCargo.filter((item) => !chosen.has(item.itemId));
    nextRun.shippedCargo.push(...shipped.map((item) => ({ ...item, secured: true })));
    mergeRunWallet(next, nextRun, walletShare);
    nextRun.shippedCheckpointIds = [...nextRun.shippedCheckpointIds, checkpointId];
    const checked = parseSave(next);
    if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
    return { ok: true, save: checked.data, events: [{ type: 'CARGO_SHIPPED', text: `На склад отправлено ${shipped.length} предметов и ${Math.round(share * 100)}% оставшейся валюты. Стоимость: ${cost} кредитов.` }] };
  }

  advanceSector(nextRun);
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'SECTOR_CONTINUED', text: `Сектор ${nextRun.depth - 1} завершён. Выезд продолжается в секторе ${nextRun.depth} (${nextRun.biome}).` }] };
}
