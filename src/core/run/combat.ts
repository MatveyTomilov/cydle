import { BIOME_BY_ID } from '../../data/biomes';
import { createCore, rollItem, type ItemInstance } from '../items/items';
import { simulateCombat } from '../combat/engine';
import { resolveBuild } from '../build/build';
import { R, xpRequired } from '../math/formula';
import { Rng } from '../rng';
import { parseSave, type SaveGame } from '../save/schema';
import type { CombatResult } from '../combat/types';
import type { RunCommandResult, RunState } from './types';

const zeroWallet = () => ({ CREDITS: 0, SCRAP: 0, DATA: 0 });

function fail(save: SaveGame, failureCode: string, reason: string): RunCommandResult {
  return { ok: false, save, failureCode, reason };
}

function makeBuild(save: SaveGame) {
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

function grantExperience(save: SaveGame, run: RunState, amount: number, grantId: string): void {
  if (run.grantIds.includes(grantId)) return;
  run.grantIds.push(grantId);
  let xp = save.meta.operator.xp + amount;
  let level = save.meta.operator.level;
  let attributePoints = save.meta.operator.attributePoints;
  let treePoints = save.meta.operator.treePoints;
  while (level < 61 && xp >= xpRequired(level)) {
    xp -= xpRequired(level);
    level++;
    treePoints++;
    if (level <= 60 && level % 5 === 0) attributePoints++;
  }
  save.meta.operator = { ...save.meta.operator, xp, level, attributePoints, treePoints };
}

function rewardForNode(nodeType: string, depth: number) {
  const scale = R(depth);
  if (nodeType === 'BOSS') return { credits: Math.ceil(85 * scale), scrap: Math.ceil(18 * scale), data: Math.ceil(8 * scale), xp: Math.ceil(160 * scale), itemChance: 1, extraItemChance: 0.5, coreChance: 1, table: 'BOSS' as const };
  if (nodeType === 'ELITE') return { credits: Math.ceil(28 * scale), scrap: Math.ceil(7 * scale), data: Math.ceil(3 * scale), xp: Math.ceil(55 * scale), itemChance: 1, extraItemChance: 0.25, coreChance: 0.15, table: 'ELITE' as const };
  if (nodeType === 'BOUNTY') return { credits: Math.ceil(35 * scale), scrap: Math.ceil(5 * scale), data: Math.ceil(3 * scale), xp: Math.ceil(55 * scale), itemChance: 0.9, extraItemChance: 0, coreChance: 0.08, table: 'ELITE' as const };
  return { credits: Math.ceil(12 * scale), scrap: Math.ceil(3 * scale), data: Math.ceil(1 * scale), xp: Math.ceil(22 * scale), itemChance: 0.7, extraItemChance: 0, coreChance: 0, table: 'ORDINARY' as const };
}

function makeBattleReward(run: RunState, nodeId: string, nodeType: string): { wallet: ReturnType<typeof zeroWallet>; items: ItemInstance[]; grantIds: string[]; rng: Rng; xp: number } {
  const spec = rewardForNode(nodeType, run.depth);
  const wallet = { CREDITS: spec.credits, SCRAP: spec.scrap, DATA: spec.data };
  const rng = Rng.fromSerialized(run.lootRng);
  const items: ItemInstance[] = [];
  const grantIds: string[] = [];
  const grants = [spec.itemChance, spec.extraItemChance];
  grants.forEach((chance, index) => {
    const grantId = `combat:${run.seed}:${nodeId}:item:${index}`;
    if (chance <= 0 || !rng.chance(chance)) return;
    const rolled = rollItem(rng, { depth: run.depth, biome: run.biome, table: spec.table, secured: false, grantId, origin: 'combat' });
    items.push(rolled.item);
    grantIds.push(grantId);
  });
  const coreGrant = `combat:${run.seed}:${nodeId}:core`;
  if (spec.coreChance >= 1 || rng.chance(spec.coreChance)) {
    items.push(createCore(rng, run.depth, coreGrant, false));
    grantIds.push(coreGrant);
  }
  return { wallet, items, grantIds, rng, xp: spec.xp };
}

function finishDefeat(save: SaveGame, run: RunState, result: CombatResult): void {
  const build = makeBuild(save);
  const maxHP = build.valid ? build.stats.maxHP : 1;
  const maxShield = build.valid ? build.stats.maxShield : 0;
  const paid = save.meta.protectedBank.CREDITS >= 10;
  if (paid) save.meta.protectedBank.CREDITS -= 10;
  save.meta.transport.fuel = run.resources.fuel;
  save.meta.transport.hull = run.resources.hull;
  const shippedIds = new Set(run.shippedCargo.map((item) => item.itemId));
  const knownGrants = new Set(save.meta.inventory.map((item) => item.originGrantId));
  for (const item of run.shippedCargo) {
    if (!knownGrants.has(item.originGrantId)) save.meta.inventory.push({ ...item, secured: true });
  }
  const equippedIds = new Set(Object.values(save.meta.equipment));
  save.meta.inventory = save.meta.inventory.map((item) => shippedIds.has(item.itemId) ? { ...item, secured: true } : equippedIds.has(item.itemId) ? { ...item, durability: Math.max(0, item.durability - 20) } : item);
  run.phase = 'DEFEATED';
  run.combatResult = result;
  run.resources = {
    ...run.resources,
    hp: paid ? maxHP : maxHP * 0.5,
    maxHP,
    shield: paid ? maxShield : 0,
    maxShield,
  };
  run.runWallet = zeroWallet();
  run.unsecuredCargo = [];
  run.shippedCargo = [];
}

/** Resolves one saved encounter with the canonical combat engine and applies one-time run rewards. */
export function resolveCurrentCombat(save: SaveGame, commandId: string): RunCommandResult {
  const current = parseSave(save);
  if (!current.success) return fail(save, 'INVALID_SAVE', current.error);
  const run = save.run;
  if (!run) return fail(save, 'NO_ACTIVE_RUN', 'Нет активного выезда.');
  if (!commandId.trim()) return fail(save, 'INVALID_COMMAND_ID', 'Команде требуется стабильный идентификатор.');
  if (run.commandIds.includes(commandId)) return { ok: true, save, events: [] };
  if (run.phase !== 'NODE') return fail(save, 'NODE_NOT_COMBAT', 'Бой нельзя начать в текущем состоянии дороги.');
  const node = run.graph.layers.flat().find((candidate) => candidate.id === run.currentNodeId);
  if (!node || !['COMBAT', 'ELITE', 'BOUNTY', 'BOSS'].includes(node.type)) return fail(save, 'NODE_NOT_COMBAT', 'Текущий узел не является боевым.');
  if (run.clearedNodeIds.includes(node.id)) return fail(save, 'NODE_ALREADY_CLEARED', 'Этот боевой узел уже пройден.');
  const build = makeBuild(save);
  if (!build.valid) return fail(save, 'INVALID_BUILD', build.issues.map((issue) => issue.message).join(' '));
  const tactic = save.meta.tactics.find((profile) => profile.id === save.meta.activeTacticId);
  if (!tactic) return fail(save, 'NO_TACTIC_PROFILE', 'Активный профиль тактики отсутствует.');

  const result = simulateCombat({
    seed: `${run.seed}:${node.id}`,
    depth: run.depth,
    biome: run.biome,
    nodeType: node.type,
    build,
    enemies: node.enemies,
    tactics: tactic,
    startHpFraction: run.resources.maxHP > 0 ? run.resources.hp / run.resources.maxHP : 1,
    startShieldFraction: run.resources.maxShield > 0 ? run.resources.shield / run.resources.maxShield : 1,
    startEnergy: run.resources.energy,
    startHeat: run.resources.heat,
    wanted: run.wanted,
    extraEnemyDigitalBonus: BIOME_BY_ID[run.biome]?.enemyDigitalBonus ?? 0,
    coolingPenalty: BIOME_BY_ID[run.biome]?.coolingPenalty ?? 0,
  });

  const next = structuredClone(save);
  const nextRun = next.run!;
  nextRun.commandIds = [...nextRun.commandIds, commandId].slice(-128);
  nextRun.lastCommandId = commandId;
  nextRun.combatResult = result;
  nextRun.resources = {
    ...nextRun.resources,
    hp: result.operator.hp,
    maxHP: result.operator.maxHP,
    shield: result.operator.shield,
    maxShield: build.stats.maxShield,
    energy: result.operator.energy,
    heat: result.operator.heat,
    gameTimeMs: nextRun.resources.gameTimeMs + result.durationMs,
  };
  nextRun.wanted = Math.min(100, Math.max(0, nextRun.wanted + result.wantedDelta));
  nextRun.revealLevel = Math.max(0, Math.min(2, nextRun.revealLevel + result.revealDelta)) as 0 | 1 | 2;

  if (result.outcome === 'DEFEAT') {
    finishDefeat(next, nextRun, result);
    const checked = parseSave(next);
    if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
    return { ok: true, save: checked.data, events: [{ type: 'RUN_DEFEATED', text: 'Оператор потерял сознание. Незакреплённый груз и валюта потеряны; эвакуированные грузы сохранены.' }] };
  }
  if (result.outcome === 'TIMEOUT') {
    nextRun.phase = 'SAFE_ERROR_STOP';
    const checked = parseSave(next);
    if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
    return { ok: true, save: checked.data, events: [{ type: 'COMBAT_TIMEOUT', text: 'Бой достиг лимита симуляции. Выезд остановлен безопасно; награды не выданы.' }] };
  }

  const reward = makeBattleReward(nextRun, node.id, node.type);
  grantExperience(next, nextRun, reward.xp, `xp:${node.id}`);
  nextRun.runWallet = {
    CREDITS: nextRun.runWallet.CREDITS + reward.wallet.CREDITS,
    SCRAP: nextRun.runWallet.SCRAP + reward.wallet.SCRAP,
    DATA: nextRun.runWallet.DATA + reward.wallet.DATA,
  };
  nextRun.unsecuredCargo.push(...reward.items);
  nextRun.grantIds.push(...reward.grantIds);
  nextRun.lootRng = reward.rng.serialize();
  nextRun.clearedNodeIds = [...nextRun.clearedNodeIds, node.id];
  nextRun.phase = node.layer === 5 ? 'CHECKPOINT' : 'ROUTE';
  const checked = parseSave(next);
  if (!checked.success) return fail(save, 'INVALID_RESULT', checked.error);
  return {
    ok: true,
    save: checked.data,
    events: [{ type: 'COMBAT_VICTORY', text: `Бой завершён: +${reward.wallet.CREDITS} кредитов, +${reward.wallet.SCRAP} лома, +${reward.wallet.DATA} данных, +${Math.ceil(rewardForNode(node.type, run.depth).xp)} XP.` }],
  };
}
