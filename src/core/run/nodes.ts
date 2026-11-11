import { createCore, createItem, rollItem, shopPrice, type ItemInstance } from '../items/items';
import { R } from '../math/formula';
import { Rng } from '../rng';
import { parseSave, type SaveGame } from '../save/schema';
import type { Currency } from '../types';
import type { RunCommandResult, RunState } from './types';

const zeroWallet = () => ({ CREDITS: 0, SCRAP: 0, DATA: 0 });

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

function currentNode(run: RunState) {
  return run.graph.layers.flat().find((node) => node.id === run.currentNodeId);
}

export function resolveRunCache(save: SaveGame, commandId: string, prototypeId?: string): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!commandId.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(commandId)) return { ok: true, save, events: [] };
  const node = currentNode(run);
  if (!node || node.type !== 'CACHE' || run.phase !== 'NODE' || run.clearedNodeIds.includes(node.id)) return fail(save, 'NODE_NOT_CACHE', 'Текущий узел не является доступным тайником.');
  if (node.prototypeChoices?.length && !prototypeId) return fail(save, 'PROTOTYPE_REQUIRED', 'Выберите один из трёх обучающих прототипов.');
  if (prototypeId && !node.prototypeChoices?.includes(prototypeId as never)) return fail(save, 'INVALID_PROTOTYPE', 'Этот прототип не предложен текущим тайником.');
  if (!prototypeId && node.prototypeChoices) return fail(save, 'PROTOTYPE_REQUIRED', 'Выберите один из трёх обучающих прототипов.');

  const next = markCommand(save, commandId);
  const nextRun = next.run!;
  const loot = Rng.fromSerialized(nextRun.lootRng);
  const items = [] as typeof nextRun.unsecuredCargo;
  const grants: string[] = [];
  if (prototypeId) {
    const grantId = `tutorial:${run.seed}:${node.id}:${prototypeId}`;
    items.push(createItem(loot, { templateId: prototypeId, techLevel: 1, rarity: 'MODIFIED', secured: false, originGrantId: grantId, origin: 'tutorial-cache', acquiredAt: run.resources.gameTimeMs, affixCount: 0 }));
    grants.push(grantId);
  }
  const cacheItemGrant = `cache:${run.seed}:${node.id}:item`;
  if (loot.chance(0.45)) {
    const rolled = rollItem(loot, { depth: run.depth, biome: run.biome, table: 'ORDINARY', secured: false, grantId: cacheItemGrant, origin: 'cache' });
    items.push(rolled.item);
    grants.push(cacheItemGrant);
  }
  const coreGrant = `cache:${run.seed}:${node.id}:core`;
  if (loot.chance(0.02)) {
    items.push(createCore(loot, run.depth, coreGrant, false));
    grants.push(coreGrant);
  }
  nextRun.runWallet = { CREDITS: nextRun.runWallet.CREDITS + Math.ceil(8 * R(run.depth)), SCRAP: nextRun.runWallet.SCRAP + Math.ceil(2 * R(run.depth)), DATA: nextRun.runWallet.DATA };
  nextRun.unsecuredCargo.push(...items);
  nextRun.grantIds.push(...grants);
  nextRun.lootRng = loot.serialize();
  nextRun.clearedNodeIds = [...nextRun.clearedNodeIds, node.id];
  nextRun.resources.gameTimeMs += 5_000;
  nextRun.phase = 'ROUTE';
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'CACHE_RESOLVED', text: `Тайник: +${Math.ceil(8 * R(run.depth))} кредитов, +${Math.ceil(2 * R(run.depth))} лома${prototypeId ? ` · выбран ${prototypeId} (не закреплён)` : ''}.` }] };
}

export interface RunShopStockEntry {
  index: number;
  grantId: string;
  item: ItemInstance;
  price: number;
}

/** Stock is derived from the run seed and stable node ID, so reloads never reroll a shop. */
export function getRunShopStock(run: RunState): RunShopStockEntry[] {
  const node = run.graph.layers.flat().find((candidate) => candidate.id === run.currentNodeId);
  if (!node || node.type !== 'SHOP') return [];
  const rng = new Rng('shop', `${run.seed}:${node.id}`);
  const categories = ['MAIN', 'MAIN', 'ARMOR', 'IMPLANT', 'DRONE'] as const;
  return categories.map((category, index) => {
    const grantId = `shop:${run.seed}:${node.id}:${index}`;
    const { item } = rollItem(rng, {
      depth: run.depth, biome: run.biome, table: 'ORDINARY', secured: false,
      grantId, origin: 'shop', forceCategory: category,
    });
    item.acquiredAt = run.resources.gameTimeMs;
    return { index, grantId, item, price: shopPrice(item.templateId, item.techLevel, item.rarity) };
  });
}

export function resolveRunShopPurchase(save: SaveGame, command: { id: string; stockIndex: number }): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!command.id.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(command.id)) return { ok: true, save, events: [] };
  const node = currentNode(run);
  if (!node || node.type !== 'SHOP' || run.phase !== 'NODE' || run.clearedNodeIds.includes(node.id)) return fail(save, 'NODE_NOT_SHOP', 'Покупки доступны только в открытом узле SHOP.');
  const entry = getRunShopStock(run).find((candidate) => candidate.index === command.stockIndex);
  if (!entry) return fail(save, 'INVALID_STOCK', 'Такого товара нет в ассортименте этого магазина.');
  if (run.grantIds.includes(entry.grantId)) return fail(save, 'STOCK_SOLD', 'Этот товар уже куплен в текущем выезде.');
  if (run.runWallet.CREDITS < entry.price) return fail(save, 'INSUFFICIENT_FUNDS', `Требуется ${entry.price} кредитов из незакреплённого кошелька.`);

  const next = markCommand(save, command.id);
  const nextRun = next.run!;
  nextRun.runWallet.CREDITS -= entry.price;
  nextRun.unsecuredCargo.push(entry.item);
  nextRun.grantIds.push(entry.grantId);
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'SHOP_PURCHASED', text: `${entry.item.templateId} добавлен в незакреплённый груз · −${entry.price} кредитов.` }] };
}

export function resolveRunShop(save: SaveGame, commandId: string): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!commandId.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(commandId)) return { ok: true, save, events: [] };
  const node = currentNode(run);
  if (!node || node.type !== 'SHOP' || run.phase !== 'NODE' || run.clearedNodeIds.includes(node.id)) return fail(save, 'NODE_NOT_SHOP', 'Закрыть можно только открытый узел SHOP.');
  const next = markCommand(save, commandId);
  const nextRun = next.run!;
  nextRun.clearedNodeIds = [...nextRun.clearedNodeIds, node.id];
  nextRun.resources.gameTimeMs += 8_000;
  nextRun.phase = 'ROUTE';
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'SHOP_RESOLVED', text: 'Магазин закрыт · потрачено 8 секунд.' }] };
}

function pay(save: SaveGame, run: RunState, currency: Currency, cost: number, spendProtected: boolean): boolean {
  const runBalance = run.runWallet[currency];
  const bankBalance = save.meta.protectedBank[currency];
  if (runBalance + (spendProtected ? bankBalance : 0) < cost) return false;
  const fromRun = Math.min(runBalance, cost);
  run.runWallet = { ...run.runWallet, [currency]: runBalance - fromRun };
  if (cost > fromRun) save.meta.protectedBank = { ...save.meta.protectedBank, [currency]: bankBalance - (cost - fromRun) };
  return true;
}

export function resolveRunService(
  save: SaveGame,
  command: { id: string; choice: 'REPAIR_HULL' | 'REPAIR_HP' | 'BUY_FUEL'; currency?: 'CREDITS' | 'SCRAP'; spendProtected?: boolean },
): RunCommandResult {
  const parsed = parseSave(save);
  if (!parsed.success) return fail(save, 'INVALID_SAVE', parsed.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!command.id.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(command.id)) return { ok: true, save, events: [] };
  const node = currentNode(run);
  if (!node || run.phase !== 'NODE' || run.clearedNodeIds.includes(node.id)) return fail(save, 'NODE_NOT_SERVICE', 'Нет доступного узла обслуживания.');
  if ((command.choice === 'BUY_FUEL' && node.type !== 'FUEL') || (command.choice !== 'BUY_FUEL' && node.type !== 'REPAIR')) return fail(save, 'NODE_NOT_SERVICE', 'Эта услуга недоступна в текущем узле.');

  const next = markCommand(save, command.id);
  const nextRun = next.run!;
  let text = '';
  if (command.choice === 'REPAIR_HULL') {
    const amount = Math.min(30, nextRun.resources.maxHull - nextRun.resources.hull);
    if (amount <= 0) return fail(save, 'RESOURCE_FULL', 'Корпус уже полностью восстановлен.');
    const cost = Math.ceil(15 * R(nextRun.depth));
    if (!pay(next, nextRun, 'CREDITS', cost, !!command.spendProtected)) return fail(save, 'INSUFFICIENT_FUNDS', `Требуется ${cost} кредитов; защищённый банк можно использовать только по явному разрешению.`);
    nextRun.resources.hull += amount;
    text = `Корпус +${amount} · −${cost} кредитов.`;
  } else if (command.choice === 'REPAIR_HP') {
    const amount = Math.min(nextRun.resources.maxHP - nextRun.resources.hp, nextRun.resources.maxHP * 0.3);
    if (amount <= 0) return fail(save, 'RESOURCE_FULL', 'Здоровье уже полностью восстановлено.');
    const cost = Math.ceil(10 * R(nextRun.depth));
    if (!pay(next, nextRun, 'CREDITS', cost, !!command.spendProtected)) return fail(save, 'INSUFFICIENT_FUNDS', `Требуется ${cost} кредитов; защищённый банк можно использовать только по явному разрешению.`);
    nextRun.resources.hp += amount;
    text = `HP +${Math.round(amount)} · −${cost} кредитов.`;
  } else {
    if (nextRun.resources.fuel >= nextRun.resources.maxFuel) return fail(save, 'RESOURCE_FULL', 'Бак уже заполнен.');
    const currency = command.currency ?? 'CREDITS';
    const cost = currency === 'SCRAP' ? 5 : Math.ceil(3 * R(nextRun.depth));
    if (currency === 'SCRAP' && (nextRun.serviceScrapFuelCounts[node.id] ?? 0) >= 4) return fail(save, 'SERVICE_LIMIT', 'На этом узле уже куплено максимальное количество топлива за лом.');
    if (!pay(next, nextRun, currency, cost, !!command.spendProtected)) return fail(save, 'INSUFFICIENT_FUNDS', `Для одной единицы топлива требуется ${cost} ${currency === 'SCRAP' ? 'лома' : 'кредитов'}.`);
    if (currency === 'SCRAP') nextRun.serviceScrapFuelCounts[node.id] = (nextRun.serviceScrapFuelCounts[node.id] ?? 0) + 1;
    nextRun.resources.fuel += 1;
    text = `Топливо +1 · −${cost} ${currency === 'SCRAP' ? 'лома' : 'кредитов'}.`;
  }

  nextRun.clearedNodeIds = [...nextRun.clearedNodeIds, node.id];
  nextRun.resources.gameTimeMs += 8_000;
  nextRun.phase = 'ROUTE';
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return { ok: true, save: checked.data, events: [{ type: 'SERVICE_RESOLVED', text }] };
}
