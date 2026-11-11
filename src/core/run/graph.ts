import { BIOME_BY_ID } from '../../data/biomes';
import { EVENTS } from '../../data/events';
import { BOSSES, ENEMY_BY_ID } from '../../data/enemies';
import { Rng } from '../rng';
import type { BiomeId, NodeType } from '../types';
import type { NodeThreatBand } from '../../data/types';
import type { EncounterEnemySpec } from '../combat/types';
import type { RoadEdge, RoadGraph, RoadNode } from './types';

const BASE_WIDTHS = [1, 2, 3, 3, 2, 1] as const;
const supportedNextCombatKeys = new Set(['shieldBonus', 'extraHeat', 'skip', 'forceElite', 'extraRareRoll']);
const ROAD_EVENTS = EVENTS.filter((event) => !event.choices.some((choice) =>
  choice.flag || choice.reveal || choice.grantMutation
  || Object.keys(choice.nextCombat ?? {}).some((key) => !supportedNextCombatKeys.has(key))
  || (choice.special && choice.special !== 'greyDealer' && choice.special !== 'dataForCredits')));
function threatFor(type: NodeType): NodeThreatBand {
  if (type === 'BOSS') return 'boss';
  if (type === 'ELITE' || type === 'BOUNTY' || type === 'ANOMALY') return 'high';
  if (type === 'COMBAT' || type === 'EVENT' || type === 'QUEST') return 'medium';
  return 'low';
}

function enemyFor(biome: BiomeId, depth: number, rng: Rng): string {
  const pool = BIOME_BY_ID[biome]!.enemies.filter((id) => ENEMY_BY_ID[id] && ENEMY_BY_ID[id]!.unlockDepth <= depth);
  return pool.length ? rng.pick(pool) : 'E01';
}

function makeNode(seed: string, depth: number, layer: number, index: number, type: NodeType, enemies: EncounterEnemySpec[] = [], extras: Partial<RoadNode> = {}): RoadNode {
  return {
    id: `d${depth}-l${layer}-n${index}-${seed.slice(0, 5)}`,
    layer,
    type,
    threat: threatFor(type),
    enemies,
    revealLevel: 1,
    lootHint: type === 'COMBAT' || type === 'ELITE' || type === 'BOUNTY' || type === 'BOSS' ? 'добыча после боя' : type === 'CACHE' ? 'три прототипа' : type === 'REPAIR' || type === 'FUEL' ? 'восстановление ресурсов' : type === 'SHOP' ? '5 товаров по биому' : 'неизвестно',
    ...extras,
  };
}

function bossForDepth(depth: number): string {
  return BOSSES.filter((boss) => boss.unlockDepth <= depth).at(-1)?.id ?? 'CORE_12';
}

function nodeTypeFor(rng: Rng, types: readonly NodeType[]): NodeType {
  return rng.pick(types);
}

function createNode(
  rng: Rng,
  seed: string,
  depth: number,
  biome: BiomeId,
  layer: number,
  index: number,
  type: NodeType,
  fixedEnemies?: string[],
  extras: Partial<RoadNode> = {},
): RoadNode {
  const enemies: EncounterEnemySpec[] = (fixedEnemies ?? []).map((templateId) => ({ templateId }));
  if (type === 'COMBAT' && enemies.length === 0) enemies.push({ templateId: enemyFor(biome, depth, rng) });
  if (type === 'ELITE') enemies.splice(0, enemies.length, { templateId: fixedEnemies?.[0] ?? enemyFor(biome, depth, rng), elite: rng.pick(['EL_SHIELD', 'EL_FAST', 'EL_VIRUS', 'EL_ANTI_DRONE', 'EL_PEN', 'EL_SPLIT']) });
  if (type === 'BOUNTY') enemies.splice(0, enemies.length, { templateId: fixedEnemies?.[0] ?? enemyFor(biome, depth, rng), elite: 'EL_PEN' });
  if (type === 'BOSS') enemies.push({ templateId: bossForDepth(depth) });
  return makeNode(seed, depth, layer, index, type, enemies, extras);
}

function linkLayers(rng: Rng, layers: RoadNode[][]): RoadEdge[] {
  const edges: RoadEdge[] = [];
  const add = (from: RoadNode, to: RoadNode, fromLayer: number, toLayer: number) => {
    if (edges.some((edge) => edge.from === from.id && edge.to === to.id)) return;
    edges.push({ from: from.id, to: to.id, fromLayer, toLayer, fuelCost: fromLayer >= 2 && rng.chance(0.08) ? 2 : 1 });
  };

  for (const node of layers[0]!) add({ id: 'START' } as RoadNode, node, -1, 0);
  for (let layerIndex = 0; layerIndex < layers.length - 1; layerIndex++) {
    const from = layers[layerIndex]!;
    const to = layers[layerIndex + 1]!;
    for (let destinationIndex = 0; destinationIndex < to.length; destinationIndex++) {
      const sourceIndex = Math.floor(destinationIndex * from.length / to.length);
      add(from[sourceIndex]!, to[destinationIndex]!, layerIndex, layerIndex + 1);
    }
    for (let sourceIndex = 0; sourceIndex < from.length; sourceIndex++) {
      const destinationIndex = Math.floor(sourceIndex * to.length / from.length);
      add(from[sourceIndex]!, to[destinationIndex]!, layerIndex, layerIndex + 1);
      if (to.length > 1) add(from[sourceIndex]!, to[(destinationIndex + 1) % to.length]!, layerIndex, layerIndex + 1);
    }
  }
  return edges;
}

export function generateSectorGraph(input: { seed: string; depth: number; biome: BiomeId; tutorial?: boolean; wanted?: number; usedEventIds?: string[] }): RoadGraph {
  if (!Number.isInteger(input.depth) || input.depth < 1) throw new Error('Sector depth must be a positive integer.');
  if (!BIOME_BY_ID[input.biome]) throw new Error(`Unknown biome ${input.biome}.`);
  const rng = new Rng('world', input.seed);
  const tutorial = input.depth === 1 && input.tutorial === true;
  const widths: number[] = [...BASE_WIDTHS];
  if (!tutorial) widths[3] = widths[3]! + rng.int(0, 3);

  const layers: RoadNode[][] = widths.map((width, layer) => Array.from({ length: width }, (_, index) => {
    let type: NodeType;
    let fixed: string[] | undefined;
    let extras: Partial<RoadNode> = {};
    if (tutorial && layer === 0) { type = 'COMBAT'; fixed = ['E01']; }
    else if (tutorial && layer === 1) {
      type = 'CACHE';
      extras = { prototypeChoices: ['IMP_HEAT', 'IMP_VIRUS', 'IMP_SHIELD'] };
    }
    else if (tutorial && layer === 2) { type = 'COMBAT'; fixed = ['E01', 'E02']; }
    else if (layer === 5) type = input.depth % 4 === 0 ? 'BOSS' : 'CHECKPOINT';
    else if (layer === 0 || layer === 2) { type = 'COMBAT'; fixed = [enemyFor(input.biome, input.depth, rng)]; }
    else if (layer === 4) type = index % 2 === 0 ? 'REPAIR' : 'FUEL';
    else if (!tutorial && layer === 3 && index === 0) {
      const availableEvents = ROAD_EVENTS.filter((event) => !input.usedEventIds?.includes(event.id));
      if (availableEvents.length) { type = 'EVENT'; extras = { eventId: rng.pick(availableEvents).id }; }
      else type = 'CACHE';
    }
    else if (!tutorial && layer === 3 && index === 1) type = 'SHOP';
    else if (!tutorial && layer === 1 && index === 0 && rng.chance(0.22)) type = 'ELITE';
    else if (!tutorial && layer === 1 && index === 1 && (input.wanted ?? 0) >= 50 && rng.chance(0.25)) type = 'BOUNTY';
    else if (tutorial && layer === 3) type = (['REPAIR', 'FUEL', 'COMBAT'] as const)[index]!;
    else if (tutorial && layer === 4) type = index === 0 ? 'FUEL' : 'REPAIR';
    else {
      const pool: NodeType[] = ['COMBAT', 'REPAIR', 'FUEL', 'CACHE'];
      type = nodeTypeFor(rng, pool);
    }
    return createNode(rng, input.seed, input.depth, input.biome, layer, index, type, fixed, extras);
  }));
  const edges = linkLayers(rng, layers);
  return { seed: input.seed, depth: input.depth, biome: input.biome, startNodeId: 'START', layers, edges };
}

export function enumerateSectorPaths(graph: RoadGraph): RoadNode[][] {
  const nodes = new Map(graph.layers.flat().map((node) => [node.id, node]));
  const outgoing = new Map<string, string[]>();
  for (const edge of graph.edges) outgoing.set(edge.from, [...(outgoing.get(edge.from) ?? []), edge.to]);
  const paths: RoadNode[][] = [];
  const walk = (nodeId: string, path: RoadNode[]) => {
    const next = outgoing.get(nodeId) ?? [];
    if (!next.length) { paths.push(path); return; }
    for (const id of next) {
      const node = nodes.get(id);
      if (node) walk(id, [...path, node]);
    }
  };
  walk(graph.startNodeId, []);
  return paths;
}
