import { describe, expect, it } from 'vitest';
import { createInitialSave } from '../../src/core/save/initial';
import { parseSave } from '../../src/core/save/schema';
import type { SaveGame } from '../../src/core/save/schema';
import { createInitialRun } from '../../src/core/run/run';
import { templateOf } from '../../src/core/items/items';
import { createItem } from '../../src/core/items/items';
import { Rng } from '../../src/core/rng';
import { runCargoCapacity, runCargoUnits } from '../../src/core/run/cargo';
import { chooseRunNode } from '../../src/core/run/commands';
import { getRunShopStock, resolveRunCache, resolveRunEvent, resolveRunService, resolveRunShop, resolveRunShopPurchase } from '../../src/core/run/nodes';

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

describe('run road nodes', () => {
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

  it('enforces cargo capacity using weighted item units and the equipped CARGO module', () => {
    const base = nodeSave('SHOP', 'cargo-capacity');
    const run = base.run!;
    const shop = run.graph.layers.flat().find((candidate) => candidate.type === 'SHOP')!;
    run.currentNodeId = shop.id;
    run.visitedNodeIds = [shop.id];
    run.phase = 'NODE';
    run.runWallet = { CREDITS: 100_000, SCRAP: 0, DATA: 0 };
    for (let index = 0; index < 10; index++) run.unsecuredCargo.push(createItem(new Rng('loot', `cargo-full-${index}`), {
      templateId: 'RAIL_K6', techLevel: 1, rarity: 'COMMON', secured: false,
      originGrantId: `cargo-full-${index}`, origin: 'test',
    }));
    const save = { ...base, run };
    expect(runCargoUnits(run.unsecuredCargo)).toBe(20);
    expect(runCargoCapacity(save)).toBe(20);
    const purchase = resolveRunShopPurchase(save, { id: 'cargo-full-buy', stockIndex: 0 });
    expect(purchase).toMatchObject({ ok: false, failureCode: 'CARGO_CAPACITY', save });
    shop.type = 'EVENT';
    shop.eventId = 'EV01';
    run.runWallet.SCRAP = 5;
    const eventChoice = resolveRunEvent(save, { id: 'cargo-full-event', choiceId: 'A' });
    expect(eventChoice).toMatchObject({ ok: false, failureCode: 'CARGO_CAPACITY', save });

    const expanded = createInitialSave({ saveId: 'cargo-expanded', now: 100 });
    const cargoModule = createItem(new Rng('loot', 'cargo-module'), {
      templateId: 'TR_CARGO_2', techLevel: 1, rarity: 'COMMON', secured: true,
      originGrantId: 'cargo-module', origin: 'test',
    });
    expanded.meta.inventory.push(cargoModule);
    expanded.meta.equipment.CARGO = cargoModule.itemId;
    const expandedRun = createInitialRun(expanded, 'cargo-expanded-seed');
    expect(runCargoCapacity({ ...expanded, run: expandedRun })).toBe(32);
  });

  it('resolves a data event once and persists its wanted and permanent faction reputation changes', () => {
    const base = createInitialSave({ saveId: 'event-choice', now: 100 });
    const run = createInitialRun(base, 'event-choice-seed');
    const eventNode = run.graph.layers[3]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV02';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const save = { ...base, run };

    const result = resolveRunEvent(save, { id: 'event-hack', choiceId: 'A' });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.save.run).toMatchObject({
      phase: 'ROUTE', clearedNodeIds: [eventNode.id], wanted: 10,
      runWallet: { CREDITS: 0, SCRAP: 0, DATA: 12 },
      resources: { gameTimeMs: 10_000 },
    });
    expect(result.save.meta.reputation.F_ECHO).toBe(5);
    expect(result.save.meta.campaignFlags).toContain('event:EV02:A');
    expect(resolveRunEvent(result.save, { id: 'event-hack', choiceId: 'A' })).toMatchObject({ ok: true, save: result.save, events: [] });
    expect(resolveRunEvent(result.save, { id: 'event-again', choiceId: 'A' })).toMatchObject({ ok: false, failureCode: 'NODE_NOT_EVENT' });
  });

  it('applies a travel event to exactly the next valid edge and then consumes it', () => {
    const base = createInitialSave({ saveId: 'event-travel', now: 100 });
    const run = createInitialRun(base, 'event-travel-seed');
    const eventNode = run.graph.layers[3]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV19';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const save = { ...base, run };

    const resolved = resolveRunEvent(save, { id: 'event-travel-choice', choiceId: 'A' });
    expect(resolved.ok).toBe(true);
    if (!resolved.ok) return;
    expect(resolved.save.run!.pendingTravelDeltaMs).toBe(15_000);
    const destination = resolved.save.run!.graph.edges.find((edge) => edge.from === eventNode.id)!.to;
    const adjusted = chooseRunNode(resolved.save, 'event-travel-edge', destination);
    const baselineSave = { ...resolved.save, run: { ...resolved.save.run!, pendingTravelDeltaMs: 0 } };
    const baseline = chooseRunNode(baselineSave, 'event-travel-baseline', destination);
    expect(adjusted.ok).toBe(true);
    expect(baseline.ok).toBe(true);
    if (!adjusted.ok || !baseline.ok) return;
    expect(adjusted.save.run!.resources.gameTimeMs - baseline.save.run!.resources.gameTimeMs).toBe(15_000);
    expect(adjusted.save.run!.pendingTravelDeltaMs).toBe(0);
  });

  it('does not consume pending travel time on invalid routes and clamps a negative adjustment at zero', () => {
    const base = createInitialSave({ saveId: 'event-travel-invalid', now: 100 });
    const run = createInitialRun(base, 'event-travel-invalid-seed');
    const startEdge = run.graph.edges.find((edge) => edge.from === 'START')!;
    const save = { ...base, run: { ...run, pendingTravelDeltaMs: -60_000 } };
    const invalid = chooseRunNode(save, 'event-travel-invalid', 'not-a-node');
    expect(invalid).toMatchObject({ ok: false, failureCode: 'INVALID_ROUTE', save });
    expect(save.run!.pendingTravelDeltaMs).toBe(-60_000);

    const entered = chooseRunNode(save, 'event-travel-zero', startEdge.to);
    expect(entered.ok).toBe(true);
    if (!entered.ok) return;
    expect(entered.save.run!.resources.gameTimeMs).toBe(0);
    expect(entered.save.run!.pendingTravelDeltaMs).toBe(0);
  });

  it('reads a legacy active run without pending travel time as zero', () => {
    const save = createInitialSave({ saveId: 'event-travel-legacy', now: 100 });
    const run = createInitialRun(save, 'event-travel-legacy-seed');
    const { pendingTravelDeltaMs: _ignoredTravel, ...legacyRun } = run;
    const parsed = parseSave({ ...save, run: legacyRun });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.run!.pendingTravelDeltaMs).toBe(0);
  });

  it('reads older active runs without deferred combat effects as zeroed', () => {
    const save = createInitialSave({ saveId: 'event-combat-legacy', now: 100 });
    const run = createInitialRun(save, 'event-combat-legacy-seed');
    const { pendingCombatEffects: _ignored, ...legacyRun } = run;
    const parsed = parseSave({ ...save, run: legacyRun });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.run!.pendingCombatEffects).toEqual({ initialTempShield: 0, extraHeat: 0 });
  });

  it('continues a legacy active run through route and event commands without new fields', () => {
    const base = createInitialSave({ saveId: 'event-legacy-commands', now: 100 });
    const run = createInitialRun(base, 'event-legacy-commands-seed');
    const { pendingTravelDeltaMs: _ignoredTravel, pendingCombatEffects: _ignoredCombat, ...legacyRun } = run;
    const routeSave = { ...base, run: legacyRun } as unknown as SaveGame;
    const startEdge = legacyRun.graph.edges.find((edge) => edge.from === 'START')!;
    const moved = chooseRunNode(routeSave, 'legacy-move', startEdge.to);
    expect(moved.ok).toBe(true);
    if (!moved.ok) return;
    expect(moved.save.run!.resources.gameTimeMs).toBeGreaterThan(0);
    expect(moved.save.run!.pendingTravelDeltaMs).toBe(0);
    expect(moved.save.run!.pendingCombatEffects).toEqual({ initialTempShield: 0, extraHeat: 0 });

    const eventNode = legacyRun.graph.layers[3]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV17';
    legacyRun.currentNodeId = eventNode.id;
    legacyRun.visitedNodeIds = [eventNode.id];
    legacyRun.phase = 'NODE';
    const eventSave = { ...base, run: legacyRun } as unknown as SaveGame;
    const event = resolveRunEvent(eventSave, { id: 'legacy-event', choiceId: 'A' });
    expect(event.ok).toBe(true);
    if (event.ok) expect(event.save.run!.pendingCombatEffects.extraHeat).toBe(10);
  });

  it('stores EV17 heat and EV24 shield bonuses as pending combat effects', () => {
    const base = createInitialSave({ saveId: 'event-combat-effects', now: 100 });
    const run = createInitialRun(base, 'event-combat-effects-seed');
    const eventNode = run.graph.layers[3]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV17';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const eventA = resolveRunEvent({ ...base, run }, { id: 'event-extra-heat', choiceId: 'A' });
    expect(eventA.ok).toBe(true);
    if (!eventA.ok) return;
    expect(eventA.save.run!.pendingCombatEffects).toEqual({ initialTempShield: 0, extraHeat: 10 });

    const secondRun = { ...createInitialRun(base, 'event-combat-shield-seed') };
    const secondNode = secondRun.graph.layers[3]![0]!;
    secondNode.type = 'EVENT';
    secondNode.eventId = 'EV24';
    secondRun.currentNodeId = secondNode.id;
    secondRun.visitedNodeIds = [secondNode.id];
    secondRun.phase = 'NODE';
    const eventB = resolveRunEvent({ ...base, run: secondRun }, { id: 'event-temp-shield', choiceId: 'B' });
    expect(eventB.ok).toBe(true);
    if (!eventB.ok) return;
    expect(eventB.save.run).toMatchObject({
      pendingTravelDeltaMs: 20_000,
      pendingCombatEffects: { initialTempShield: 20, extraHeat: 0 },
    });
  });

  it('rejects an unaffordable event choice without mutating the save', () => {
    const base = createInitialSave({ saveId: 'event-cost', now: 100 });
    const run = createInitialRun(base, 'event-cost-seed');
    const eventNode = run.graph.layers[3]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV03';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    const save = { ...base, run: { ...run, runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 } } };
    const result = resolveRunEvent(save, { id: 'event-fuel-cost', choiceId: 'A' });
    expect(result).toMatchObject({ ok: false, failureCode: 'INSUFFICIENT_FUNDS' });
    expect(result.save).toBe(save);
  });

  it('grants event items only as unsecured run cargo and handles the supported grey-dealer exchange', () => {
    const base = createInitialSave({ saveId: 'event-item', now: 100 });
    const run = createInitialRun(base, 'event-item-seed');
    const eventNode = run.graph.layers[3]![0]!;
    eventNode.type = 'EVENT';
    eventNode.eventId = 'EV01';
    run.currentNodeId = eventNode.id;
    run.visitedNodeIds = [eventNode.id];
    run.phase = 'NODE';
    run.runWallet = { CREDITS: 0, SCRAP: 5, DATA: 0 };
    const save = { ...base, run };
    const restored = resolveRunEvent(save, { id: 'event-restore', choiceId: 'A' });
    expect(restored.ok).toBe(true);
    if (!restored.ok) return;
    expect(restored.save.run!.unsecuredCargo).toMatchObject([{ templateId: 'DR_GUN', rarity: 'COMMON', secured: false, origin: 'event' }]);
    expect(restored.save.run!.runWallet.SCRAP).toBe(0);
    expect(restored.save.meta.inventory).toHaveLength(base.meta.inventory.length);

    const dealerRun = { ...createInitialRun(base, 'dealer-seed'), runWallet: { CREDITS: 100_000, SCRAP: 0, DATA: 100_000 } };
    const dealerNode = dealerRun.graph.layers[3]![0]!;
    dealerNode.type = 'EVENT';
    dealerNode.eventId = 'EV13';
    dealerRun.currentNodeId = dealerNode.id;
    dealerRun.visitedNodeIds = [dealerNode.id];
    dealerRun.phase = 'NODE';
    const dealer = resolveRunEvent({ ...base, run: dealerRun }, { id: 'event-exchange', choiceId: 'B' });
    if (!dealer.ok) throw new Error(dealer.reason);
    if (!dealer.ok) return;
    expect(dealer.save.run!.runWallet).toMatchObject({ CREDITS: 100_030, DATA: 100_000 - 10 });
  });
});
