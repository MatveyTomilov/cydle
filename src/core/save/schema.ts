import { z } from 'zod';
import { resolveBuild } from '../build/build';

export const SAVE_SCHEMA_VERSION = 1 as const;
export const BALANCE_VERSION = '1.0.0';
export const GAME_VERSION = '1.0.0';

const wallet = z.object({ CREDITS: z.number().finite().nonnegative(), SCRAP: z.number().finite().nonnegative(), DATA: z.number().finite().nonnegative() }).strict();
const attributeMap = z.object({ POW: z.number().int().min(1), REF: z.number().int().min(1), INT: z.number().int().min(1), ENG: z.number().int().min(1), SYN: z.number().int().min(1) }).strict();
const affixRoll = z.object({
  affixId: z.string().min(1), tier: z.union([z.literal(1), z.literal(2), z.literal(3), z.literal(4)]),
  value: z.number().finite(), rawRoll: z.number().finite(), tierBoosted: z.boolean(),
  center: z.number().finite(), min: z.number().finite(), max: z.number().finite(),
}).strict();
const itemInstance = z.object({
  itemId: z.string().min(1), templateId: z.string().min(1), techLevel: z.number().int().min(1),
  rarity: z.enum(['COMMON', 'MODIFIED', 'RARE', 'LEGENDARY', 'UNIQUE']), affixes: z.array(affixRoll),
  uniqueEffectIds: z.array(z.string()), neuralCost: z.number().finite().nonnegative(), durability: z.number().finite().min(0).max(100),
  secured: z.boolean(), originGrantId: z.string().min(1), rollSeed: z.string(), tr: z.number().finite(),
  coreGroup: z.number().int().optional(), acquiredAt: z.number().finite().nonnegative(), origin: z.string(), label: z.string().optional(),
}).strict();

const tacticCondition: z.ZodTypeAny = z.lazy(() => z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('always') }).strict(),
  ...(['hpBelow', 'hpAbove', 'shieldBelow', 'energyAtLeast', 'energyBelow', 'heatAtLeast', 'heatBelow', 'enemiesAtLeast', 'enemiesAtMost', 'timeAtLeast'] as const)
    .map((kind) => z.object({ kind: z.literal(kind), value: z.number().finite() }).strict()),
  z.object({ kind: z.literal('heatLocked') }).strict(),
  z.object({ kind: z.literal('enemyCasting'), interruptibleOnly: z.boolean().optional() }).strict(),
  z.object({ kind: z.literal('enemyType'), value: z.enum(['boss', 'healer', 'mechanical', 'elite']) }).strict(),
  z.object({ kind: z.literal('targetStatus'), status: z.string().min(1), minStacks: z.number().finite().optional() }).strict(),
  z.object({ kind: z.literal('droneAlive'), value: z.number().finite() }).strict(),
  z.object({ kind: z.literal('cooldownReady'), skillId: z.string().min(1) }).strict(),
  z.object({ kind: z.literal('effectUptime'), status: z.string().min(1) }).strict(),
  z.object({ kind: z.literal('not'), inner: tacticCondition }).strict(),
  z.object({ kind: z.literal('any'), inner: z.array(tacticCondition) }).strict(),
  z.object({ kind: z.literal('all'), inner: z.array(tacticCondition) }).strict(),
]));
const tacticRule = z.object({
  id: z.string().min(1), priority: z.number().finite(), enabled: z.boolean(), skillId: z.string().min(1),
  target: z.enum(['target', 'otherEnemy', 'nearest', 'lowestHPPercent', 'marked', 'healer', 'imminentCast', 'boss', 'infected', 'self', 'allEnemies', 'secondary', 'attacker']),
  conditions: z.array(tacticCondition), logic: z.enum(['AND', 'OR']), note: z.string().optional(),
}).strict();
const tacticalProfile = z.object({ id: z.string().min(1), name: z.string().min(1), rules: z.array(tacticRule).max(12) }).strict();
const garageLevels = z.object({
  WORKSHOP: z.number().int().min(1).max(3), NEUROLAB: z.number().int().min(1).max(3), SERVER: z.number().int().min(1).max(3), HANGAR: z.number().int().min(1).max(3),
  MARKET: z.number().int().min(1).max(3), INTEL: z.number().int().min(1).max(3), GARAGE_MED: z.number().int().min(1).max(3), CALIBRATOR: z.number().int().min(1).max(3),
}).strict();

export const SaveGameSchema = z.object({
  schemaVersion: z.literal(SAVE_SCHEMA_VERSION), balanceVersion: z.string().min(1), gameVersion: z.string().min(1),
  saveId: z.string().min(1), createdAt: z.number().finite().nonnegative(), updatedAt: z.number().finite().nonnegative(), revision: z.number().int().min(1),
  meta: z.object({
    operator: z.object({ level: z.number().int().min(1).max(999), xp: z.number().int().nonnegative(), attributes: attributeMap, attributePoints: z.number().int().nonnegative(), treePoints: z.number().int().nonnegative() }).strict(),
    transport: z.object({ fuel: z.number().finite().min(0), fuelMax: z.number().finite().min(0), hull: z.number().finite().min(0), hullMax: z.number().finite().min(0), cargoCapacity: z.number().finite().min(0) }).strict(),
    protectedBank: wallet, unsecuredWallet: wallet,
    inventory: z.array(itemInstance), equipment: z.record(z.enum(['MAIN', 'OFFHAND', 'ARMOR', 'IMP_1', 'IMP_2', 'IMP_3', 'IMP_4', 'IMP_5', 'IMP_6', 'DRONE_1', 'DRONE_2', 'ENGINE', 'CHASSIS', 'SCANNER', 'SERVICE', 'CARGO', 'SUPPORT']), z.string().min(1)),
    garage: garageLevels, unlockedForpost: z.number().int().min(0).max(12), unlockedBiomes: z.array(z.enum(['B01', 'B02', 'B03', 'B04', 'B05', 'B06'])),
    skillIds: z.array(z.string().min(1)).max(3), passiveIds: z.array(z.string().min(1)).max(3), treeNodeIds: z.array(z.string().min(1)),
    unlockedImplantSlots: z.number().int().min(4).max(6), unlockedDroneSlots: z.number().int().min(1).max(2),
    tactics: z.array(tacticalProfile).min(1), activeTacticId: z.string().min(1),
    autopilotProfiles: z.array(z.object({ id: z.string().min(1), name: z.string().min(1), startDepth: z.number().int().min(1).max(13), enabled: z.boolean() }).strict()).min(1),
  }).strict(),
  run: z.null(),
}).strict();

export type SaveGame = z.infer<typeof SaveGameSchema>;
export type SaveValidation = { success: true; data: SaveGame } | { success: false; error: string };

export function parseSave(value: unknown): SaveValidation {
  if (typeof value === 'object' && value !== null && 'schemaVersion' in value) {
    const version = (value as { schemaVersion?: unknown }).schemaVersion;
    if (typeof version === 'number' && version > SAVE_SCHEMA_VERSION) {
      return { success: false, error: `Сохранение использует будущую схему ${version}; поддерживается версия ${SAVE_SCHEMA_VERSION}. Исходные данные не изменены.` };
    }
  }
  const parsed = SaveGameSchema.safeParse(value);
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((issue) => `${issue.path.join('.') || 'save'}: ${issue.message}`).join('; ') };
  }
  const save = parsed.data;
  const itemIds = new Set(save.meta.inventory.map((item) => item.itemId));
  if (itemIds.size !== save.meta.inventory.length) return { success: false, error: 'inventory: повторяется ID экземпляра предмета.' };
  for (const [slot, itemId] of Object.entries(save.meta.equipment)) {
    if (!itemIds.has(itemId)) return { success: false, error: `equipment.${slot}: предмет ${itemId} отсутствует в инвентаре.` };
  }
  const tacticIds = new Set(save.meta.tactics.map((profile) => profile.id));
  if (tacticIds.size !== save.meta.tactics.length) return { success: false, error: 'tactics: повторяется ID профиля.' };
  if (!tacticIds.has(save.meta.activeTacticId)) return { success: false, error: 'activeTacticId: активный профиль тактики отсутствует.' };

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
  if (!build.valid) return { success: false, error: `build: ${build.issues.map((issue) => issue.message).join(' ')}` };
  return { success: true, data: save };
}

/** Stable FNV-1a checksum for corruption detection, not a security signature. */
export function saveChecksum(save: SaveGame): string {
  const canonical = JSON.stringify(save);
  let hash = 0x811c9dc5;
  for (let i = 0; i < canonical.length; i++) {
    hash ^= canonical.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

export function parseSaveExport(value: unknown): SaveValidation {
  if (typeof value !== 'object' || value === null) return { success: false, error: 'Файл сохранения должен содержать JSON-объект.' };
  const envelope = value as { format?: unknown; checksum?: unknown; save?: unknown };
  if (envelope.format !== 'CYDLE_SAVE_EXPORT_V1' || typeof envelope.checksum !== 'string') {
    return { success: false, error: 'Неизвестный формат файла сохранения.' };
  }
  const result = parseSave(envelope.save);
  if (!result.success) return result;
  if (saveChecksum(result.data) !== envelope.checksum) return { success: false, error: 'Контрольная сумма не совпадает: файл повреждён.' };
  return result;
}
