import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { createInitialRun } from '../../src/core/run/run';
import { templateOf } from '../../src/core/items/items';
import { getRunShopStock, resolveRunCache, resolveRunService, resolveRunShop, resolveRunShopPurchase } from '../../src/core/run/nodes';

function nodeSave(type: 'CACHE' | 'REPAIR' | 'FUEL' | 'SHOP', saveId: string) {
  const save = createInitialSave({ saveId, now: 100 });
  const run = createInitialRun(save, `node-${saveId}`);
  if (type === 'SHOP' && !run.graph.layers.flat().some((candidate) => candidate.type === 'SHOP')) run.graph.layers[1]![0]!.type = 'SHOP';
  const node = run.graph.layers.flat().find((candidate) => candidate.type === type)!;
  return { ...save, run: { ...run, currentNodeId: node.id, visitedNodeIds: [node.id], phase: 'NODE' as const } };
}

describe('run caches and road services', () => {
  it('grants the selected tutorial prototype as at-risk cargo, not a permanent item', () => {
    const save = nodeSave('CACHE', 'cache-choice');
    const result = resolveRunCache(save, 'cache-open', 'IMP_VIRUS');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run!.unsecuredCargo).toHaveLength(1);
    expect(result.save.run!.unsecuredCargo[0]).toMatchObject({ templateId: 'IMP_VIRUS', techLevel: 1, rarity: 'MODIFIED', secured: false });
    expect(result.save.run!.runWallet).toEqual({ CREDITS: 8, SCRAP: 2, DATA: 0 });
    expect(result.save.meta.inventory).toHaveLength(save.meta.inventory.length);
    expect(result.save.meta.operator.xp).toBe(0);
    expect(resolveRunCache(result.save, 'cache-open', 'IMP_VIRUS')).toMatchObject({ ok: true, save: result.save, events: [] });
  });

  it('charges the unsecured wallet for repair and applies only the authored recovery', () => {
    const base = nodeSave('REPAIR', 'repair-node');
    const save = { ...base, run: { ...base.run!, resources: { ...base.run!.resources, hull: 50 }, runWallet: { CREDITS: 30, SCRAP: 0, DATA: 0 } } };
    const result = resolveRunService(save, { id: 'repair-hull', choice: 'REPAIR_HULL' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run!.resources).toMatchObject({ hull: 80, gameTimeMs: 8_000 });
    expect(result.save.run!.runWallet.CREDITS).toBe(15);
    expect(result.save.run!.phase).toBe('ROUTE');
    expect(resolveRunService(result.save, { id: 'repair-hull', choice: 'REPAIR_HULL' })).toMatchObject({ ok: true, save: result.save, events: [] });
  });

  it('does not spend protected money unless requested and never buys unavailable fuel', () => {
    const base = nodeSave('FUEL', 'fuel-node');
    const save = { ...base, run: { ...base.run!, resources: { ...base.run!.resources, fuel: 0 }, runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 } } };
    const refused = resolveRunService(save, { id: 'fuel-no-bank', choice: 'BUY_FUEL', currency: 'CREDITS' });
    expect(refused).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_FUNDS' });
    expect(refused.save).toBe(save);
    const bought = resolveRunService(save, { id: 'fuel-bank', choice: 'BUY_FUEL', currency: 'CREDITS', spendProtected: true });
    expect(bought.ok).toBe(true);
    if (!bought.ok) return;
    expect(bought.save.run!.resources.fuel).toBe(1);
    expect(bought.save.meta.protectedBank.CREDITS).toBe(117);
  });
});

describe('run shops', () => {
  it('offers a deterministic five-item biome stock and buys an item into at-risk cargo', () => {
    const base = nodeSave('SHOP', 'shop-stock');
    const node = base.run!.graph.layers.flat().find((candidate) => candidate.type === 'SHOP')!;
    const run = { ...base.run!, currentNodeId: node.id, visitedNodeIds: [node.id], phase: 'NODE' as const, runWallet: { CREDITS: 100_000, SCRAP: 0, DATA: 0 } };
    const save = { ...base, run };
    const stock = getRunShopStock(run);
    expect(stock).toHaveLength(5);
    expect(stock.map((entry) => entry.item.templateId)).toEqual(getRunShopStock(run).map((entry) => entry.item.templateId));
    expect(stock.map((entry) => templateOf(entry.item).category)).toEqual(['MAIN', 'MAIN', 'ARMOR', 'IMPLANT', 'DRONE']);

    const purchase = resolveRunShopPurchase(save, { id: 'shop-buy-0', stockIndex: 0 });
    expect(purchase.ok).toBe(true);
    if (!purchase.ok) return;
    expect(purchase.save.run!.runWallet.CREDITS).toBe(100_000 - stock[0]!.price);
    expect(purchase.save.run!.unsecuredCargo.at(-1)).toMatchObject({
      itemId: stock[0]!.item.itemId,
      templateId: stock[0]!.item.templateId,
      secured: false,
      origin: 'shop',
    });
    expect(purchase.save.meta.inventory).toHaveLength(save.meta.inventory.length);
    expect(resolveRunShopPurchase(purchase.save, { id: 'shop-buy-0', stockIndex: 0 })).toMatchObject({ ok: true, save: purchase.save, events: [] });
    expect(resolveRunShopPurchase(purchase.save, { id: 'shop-buy-again', stockIndex: 0 })).toMatchObject({ ok: false, failureCode: 'STOCK_SOLD' });
  });

  it('does not use protected credits and only closes the shop once', () => {
    const base = nodeSave('SHOP', 'shop-payment');
    const node = base.run!.graph.layers.flat().find((candidate) => candidate.type === 'SHOP')!;
    const save = { ...base, run: { ...base.run!, currentNodeId: node.id, visitedNodeIds: [node.id], phase: 'NODE' as const } };
    expect(resolveRunShopPurchase(save, { id: 'shop-no-funds', stockIndex: 0 })).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_FUNDS' });
    expect(resolveRunShopPurchase(save, { id: 'shop-invalid', stockIndex: 9 })).toMatchObject({ ok: false, failureCode: 'INVALID_STOCK' });

    const closed = resolveRunShop(save, 'shop-close');
    expect(closed.ok).toBe(true);
    if (!closed.ok) return;
    expect(closed.save.run).toMatchObject({ phase: 'ROUTE', clearedNodeIds: [node.id], resources: { gameTimeMs: 8_000 } });
    expect(resolveRunShop(closed.save, 'shop-close')).toMatchObject({ ok: true, save: closed.save, events: [] });
  });
});
