import { campaignBiome } from '../../data/biomes';
import { resolveBuild } from '../build/build';
import { Rng } from '../rng';
import type { SaveGame } from '../save/schema';
import { generateSectorGraph } from './graph';
import type { RunState } from './types';

export function createInitialRun(save: SaveGame, seed: string): RunState {
  if (save.run) throw new Error('A run is already active in this save.');
  if (!seed.trim()) throw new Error('Run seed cannot be empty.');
  const itemsById = new Map(save.meta.inventory.map((item) => [item.itemId, item]));
  const equipment = Object.fromEntries(Object.entries(save.meta.equipment).map(([slot, id]) => [slot, itemsById.get(id)]));
  const build = resolveBuild({
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
  if (!build.valid) throw new Error(`Нельзя начать выезд: ${build.issues.map((issue) => issue.message).join(' ')}`);

  const depth = Math.max(1, save.meta.unlockedForpost + 1);
  const worldRng = new Rng('world', seed);
  const biome = campaignBiome(depth, worldRng.next()) as SaveGame['meta']['unlockedBiomes'][number];
  const graph = generateSectorGraph({
    seed,
    depth,
    biome,
    tutorial: !save.meta.tutorial.firstSectorCompleted && !save.meta.tutorial.starterPrototypeSecured,
  });
  const stats = build.stats;
  return {
    seed,
    depth,
    biome,
    graph,
    equipment: { ...save.meta.equipment },
    currentNodeId: graph.startNodeId,
    visitedNodeIds: [],
    clearedNodeIds: [],
    phase: 'ROUTE',
    wanted: 0,
    revealLevel: 1,
    resources: {
      fuel: save.meta.transport.fuel,
      maxFuel: save.meta.transport.fuelMax,
      hull: save.meta.transport.hull,
      maxHull: save.meta.transport.hullMax,
      hp: stats.maxHP,
      maxHP: stats.maxHP,
      shield: stats.maxShield,
      maxShield: stats.maxShield,
      energy: stats.maxEnergy,
      heat: 0,
      gameTimeMs: 0,
    },
    runWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 },
    unsecuredCargo: [],
    shippedCargo: [],
    grantIds: [],
    commandIds: [],
    serviceScrapFuelCounts: {},
    shippedCheckpointIds: [],
    combatResult: null,
    lastCommandId: null,
    worldRng: worldRng.serialize(),
    lootRng: new Rng('loot', seed).serialize(),
  };
}
