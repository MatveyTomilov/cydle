import { createItem } from '../items/items';
import { Rng } from '../rng';
import { GAME_VERSION, BALANCE_VERSION, SAVE_SCHEMA_VERSION, type SaveGame } from './schema';

const STARTER_TEMPLATES: [string, string][] = [
  ['MAIN', 'PISTOL_K1'], ['OFFHAND', 'OFF_SHIELD'], ['ARMOR', 'ARM_CLOTH'],
  ['IMP_2', 'IMP_ARMOR'], ['IMP_3', 'IMP_REFLEX'], ['DRONE_1', 'DR_GUN'],
  ['ENGINE', 'TR_ENGINE_1'], ['CHASSIS', 'TR_CHASSIS_1'], ['SCANNER', 'TR_SCANNER_1'],
  ['SERVICE', 'TR_SERVICE_1'], ['CARGO', 'TR_CARGO_1'], ['SUPPORT', 'TR_SUPPORT_1'],
];

export function createInitialSave(options: { saveId?: string; now?: number } = {}): SaveGame {
  const now = options.now ?? Date.now();
  const saveId = options.saveId ?? globalThis.crypto.randomUUID();
  const loot = new Rng('loot', `CYDLE_STARTER_V1:${saveId}`);
  const inventory = STARTER_TEMPLATES.map(([slot, templateId]) => ({
    slot,
    item: createItem(loot, {
      templateId,
      techLevel: 1,
      rarity: 'COMMON',
      secured: true,
      originGrantId: `starter:${saveId}:${slot}`,
      origin: 'starter',
      acquiredAt: now,
    }),
  }));
  const equipment = Object.fromEntries(inventory.map(({ slot, item }) => [slot, item.itemId]));
  const itemInstances = inventory.map(({ item }) => item);

  return {
    schemaVersion: SAVE_SCHEMA_VERSION,
    balanceVersion: BALANCE_VERSION,
    gameVersion: GAME_VERSION,
    saveId,
    createdAt: now,
    updatedAt: now,
    revision: 1,
    meta: {
      operator: { level: 1, xp: 0, attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 }, attributePoints: 0, treePoints: 0 },
      tutorial: { firstSectorCompleted: false, starterPrototypeSecured: false },
      transport: { fuel: 24, fuelMax: 24, hull: 100, hullMax: 100, cargoCapacity: 20 },
      protectedBank: { CREDITS: 120, SCRAP: 30, DATA: 20 },
      unsecuredWallet: { CREDITS: 0, SCRAP: 0, DATA: 0 },
      inventory: itemInstances,
      equipment,
      garage: { WORKSHOP: 1, NEUROLAB: 1, SERVER: 1, HANGAR: 1, MARKET: 1, INTEL: 1, GARAGE_MED: 1, CALIBRATOR: 1 },
      unlockedForpost: 0,
      maxSectorCleared: 0,
      unlockedBiomes: ['B01'],
      skillIds: ['SK_BURST', 'SK_SHIELD', 'SK_EMP'],
      passiveIds: ['PP_ACCURACY', 'PP_SHIELD'],
      treeNodeIds: [],
      unlockedImplantSlots: 4,
      unlockedDroneSlots: 1,
      tactics: [{
        id: 'DEFAULT',
        name: 'Тактика по умолчанию',
        rules: [
          { id: 'starter-shield', priority: 3, enabled: true, skillId: 'SK_SHIELD', target: 'self', conditions: [{ kind: 'hpBelow', value: 45 }], logic: 'AND', note: 'Защита при низком HP' },
          { id: 'starter-emp', priority: 2, enabled: true, skillId: 'SK_EMP', target: 'imminentCast', conditions: [{ kind: 'enemyCasting', interruptibleOnly: true }], logic: 'AND', note: 'Прерывание опасного каста' },
          { id: 'starter-burst', priority: 1, enabled: true, skillId: 'SK_BURST', target: 'allEnemies', conditions: [{ kind: 'enemiesAtLeast', value: 2 }], logic: 'AND', note: 'Очередь по группе' },
          { id: 'starter-auto', priority: 0, enabled: true, skillId: 'AUTO', target: 'nearest', conditions: [{ kind: 'always' }], logic: 'AND', note: 'Базовая атака' },
        ],
      }],
      activeTacticId: 'DEFAULT',
      autopilotProfiles: [{ id: 'BALANCED', name: 'Сбалансированный', startDepth: 1, enabled: false }],
    },
    run: null,
  };
}
