import type { BiomeId, EquipSlotId, NodeType, Wallet } from '../types';
import type { NodeThreatBand } from '../../data/types';
import type { EncounterEnemySpec, CombatResult } from '../combat/types';

export interface RoadNode {
  id: string;
  layer: number;
  type: NodeType;
  threat: NodeThreatBand;
  enemies: EncounterEnemySpec[];
  prototypeChoices?: [string, string, string];
  revealLevel: number;
  lootHint: string;
}

export interface RoadEdge {
  from: string;
  to: string;
  fromLayer: number;
  toLayer: number;
  fuelCost: 1 | 2;
}

export interface RoadGraph {
  seed: string;
  depth: number;
  biome: BiomeId;
  startNodeId: 'START';
  layers: RoadNode[][];
  edges: RoadEdge[];
}

export type RunPhase = 'ROUTE' | 'NODE' | 'CHECKPOINT' | 'EXTRACTED' | 'DEFEATED' | 'SAFE_ERROR_STOP';

export interface RunResources {
  fuel: number;
  maxFuel: number;
  hull: number;
  maxHull: number;
  hp: number;
  maxHP: number;
  shield: number;
  maxShield: number;
  energy: number;
  heat: number;
  gameTimeMs: number;
}

export interface RunState {
  seed: string;
  depth: number;
  biome: BiomeId;
  graph: RoadGraph;
  equipment: Partial<Record<EquipSlotId, string>>;
  currentNodeId: string;
  visitedNodeIds: string[];
  clearedNodeIds: string[];
  phase: RunPhase;
  resources: RunResources;
  runWallet: Wallet;
  unsecuredCargo: import('../items/items').ItemInstance[];
  shippedCargo: import('../items/items').ItemInstance[];
  grantIds: string[];
  commandIds: string[];
  serviceScrapFuelCounts: Record<string, number>;
  shippedCheckpointIds: string[];
  wanted: number;
  revealLevel: number;
  combatResult: CombatResult | null;
  lastCommandId: string | null;
  worldRng: import('../rng').SerializedRng;
  lootRng: import('../rng').SerializedRng;
}

export type RunCommand =
  | { id: string; type: 'CHOOSE_NODE'; nodeId: string }
  | { id: string; type: 'RESOLVE_COMBAT' }
  | { id: string; type: 'BUY_SHOP_ITEM'; stockIndex: number }
  | { id: string; type: 'RESOLVE_SHOP' }
  | { id: string; type: 'CHOOSE_PROTOTYPE'; templateId: string }
  | { id: string; type: 'EQUIP_ITEM'; itemId: string; slot: EquipSlotId }
  | { id: string; type: 'UNEQUIP_ITEM'; slot: EquipSlotId }
  | { id: string; type: 'RESOLVE_SERVICE'; choice: 'REPAIR_HULL' | 'REPAIR_HP' | 'BUY_FUEL'; currency?: 'CREDITS' | 'SCRAP'; spendProtected?: boolean }
  | { id: string; type: 'CHECKPOINT'; choice: 'EXIT' | 'SHIP' | 'CONTINUE'; cargoItemIds?: string[]; currencyShare?: number; spendProtected?: boolean };

export type RunCommandResult =
  | { ok: true; save: import('../save/schema').SaveGame; events: { type: string; text: string }[] }
  | { ok: false; save: import('../save/schema').SaveGame; failureCode: string; reason: string };
