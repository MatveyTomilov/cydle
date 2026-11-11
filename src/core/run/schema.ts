import { z } from 'zod';

const rngState = z.object({ stream: z.string().min(1), state: z.tuple([z.number().int().min(0).max(0xffffffff), z.number().int().min(0).max(0xffffffff), z.number().int().min(0).max(0xffffffff), z.number().int().min(0).max(0xffffffff)]), calls: z.number().int().nonnegative() }).strict();
const encounterEnemy = z.object({ templateId: z.string().min(1), elite: z.string().optional(), hpMult: z.number().finite().positive().optional(), damageMult: z.number().finite().positive().optional(), summoned: z.boolean().optional(), noLoot: z.boolean().optional() }).strict();
const node = z.object({
  id: z.string().min(1), layer: z.number().int().min(0).max(5),
  type: z.enum(['COMBAT', 'ELITE', 'BOUNTY', 'REPAIR', 'FUEL', 'SHOP', 'CACHE', 'ANOMALY', 'EVENT', 'QUEST', 'BOSS', 'CHECKPOINT', 'START']),
  threat: z.enum(['low', 'medium', 'high', 'boss']), enemies: z.array(encounterEnemy), eventId: z.string().min(1).optional(),
  prototypeChoices: z.tuple([z.string(), z.string(), z.string()]).optional(),
  revealLevel: z.number().int().min(0).max(2), lootHint: z.string(),
}).strict();
const edge = z.object({ from: z.string().min(1), to: z.string().min(1), fromLayer: z.number().int().min(-1).max(4), toLayer: z.number().int().min(0).max(5), fuelCost: z.union([z.literal(1), z.literal(2)]) }).strict();
const roadGraph = z.object({
  seed: z.string().min(1), depth: z.number().int().min(1), biome: z.enum(['B01', 'B02', 'B03', 'B04', 'B05', 'B06']),
  startNodeId: z.literal('START'), layers: z.array(z.array(node).min(1).max(6)).length(6), edges: z.array(edge).min(6).max(120),
}).strict().superRefine((graph, context) => {
  const nodes = graph.layers.flat();
  const nodeById = new Map(nodes.map((entry) => [entry.id, entry]));
  if (nodeById.size !== nodes.length) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Повторяется ID дорожного узла.', path: ['layers'] });
  if (graph.layers.some((layer, index) => layer.some((entry) => entry.layer !== index))) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Уровень узла не соответствует слою.', path: ['layers'] });
  const outgoing = new Map<string, number>();
  const incoming = new Map<string, number>();
  for (const connection of graph.edges) {
    if (connection.from !== 'START' && !nodeById.has(connection.from)) context.addIssue({ code: z.ZodIssueCode.custom, message: `Неизвестный источник ребра ${connection.from}.`, path: ['edges'] });
    if (!nodeById.has(connection.to)) context.addIssue({ code: z.ZodIssueCode.custom, message: `Неизвестная цель ребра ${connection.to}.`, path: ['edges'] });
    if (connection.toLayer !== connection.fromLayer + 1) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Ребро должно вести только в следующий слой.', path: ['edges'] });
    outgoing.set(connection.from, (outgoing.get(connection.from) ?? 0) + 1);
    incoming.set(connection.to, (incoming.get(connection.to) ?? 0) + 1);
  }
  if ([...outgoing.values()].some((count) => count > 3)) context.addIssue({ code: z.ZodIssueCode.custom, message: 'У узла больше трёх исходящих путей.', path: ['edges'] });
  if (nodes.some((entry) => !incoming.has(entry.id))) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Обнаружен недостижимый узел без входящего пути.', path: ['edges'] });
  if (graph.layers.at(-1)?.some((entry) => (outgoing.get(entry.id) ?? 0) !== 0)) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Финальный слой не должен иметь исходящих путей.', path: ['edges'] });
  const visited = new Set<string>();
  const queue = ['START'];
  for (let i = 0; i < queue.length; i++) {
    const id = queue[i]!;
    if (id !== 'START') visited.add(id);
    for (const connection of graph.edges) if (connection.from === id && !visited.has(connection.to)) queue.push(connection.to);
  }
  if (nodes.some((entry) => !visited.has(entry.id))) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Граф содержит недостижимый узел.', path: ['edges'] });
});

const damageTypeMap = z.object({ KINETIC: z.number().finite(), ENERGY: z.number().finite(), DIGITAL: z.number().finite() }).strict();
const combatEvent = z.object({
  eventId: z.number().int().nonnegative(), timestamp: z.number().finite(), kind: z.enum(['COMBAT_START', 'COMBAT_END', 'ATTACK', 'HIT', 'MISS', 'CRIT', 'DAMAGE', 'DOT_TICK', 'STATUS_APPLY', 'STATUS_EXPIRE', 'HEAL', 'SHIELD_GAIN', 'SHIELD_EXPIRE', 'ENERGY', 'HEAT', 'HEAT_LOCKOUT', 'HEAT_LOCKOUT_END', 'CAST_START', 'CAST_INTERRUPT', 'CAST_FIZZLE', 'SKILL_USE', 'REACTION', 'DEATH', 'SUMMON', 'RULE_FAIL', 'TRIGGER', 'CHAIN_LIMIT', 'PHASE', 'ESCAPE', 'TELEGRAPH', 'BUFF', 'CONTROL', 'REVIVE', 'WANTED']), actorId: z.string().min(1),
  targetId: z.string().optional(), actionId: z.string().optional(), skillId: z.string().optional(), damageType: z.enum(['KINETIC', 'ENERGY', 'DIGITAL']).optional(),
  amountBeforeDefense: z.number().finite().optional(), amountAfterDefense: z.number().finite().optional(), shieldConsumed: z.number().finite().optional(), hpLost: z.number().finite().optional(), bypassed: z.number().finite().optional(),
  incomingTags: z.array(z.string()), producedTags: z.array(z.string()), causeId: z.number().int().optional(), originActionId: z.string().optional(),
  chainDepth: z.number().int().nonnegative(), text: z.string(), reason: z.string().optional(), roll: z.number().finite().optional(), crit: z.boolean().optional(), statusId: z.enum(['BLEED', 'BURN', 'VIRUS', 'ARMOR_BREAK', 'JAM', 'SHOCK', 'DRONE_JAM', 'SHIELD_LEAK', 'STUN', 'MARK', 'PHASE', 'SYNCHRONY', 'CHARGE', 'LONG_PULSE', 'OVERCLOCK', 'GUARD', 'SCAN_MARK', 'DRONE_MARK', 'CONTROLLED', 'BERSERK', 'REGEN_BUFF', 'EVASION_BUFF', 'ACC_BUFF', 'DMG_BUFF', 'SHIELD_REGEN_BUFF']).optional(),
  data: z.record(z.union([z.number().finite(), z.string(), z.boolean()])).optional(),
}).strict();
const combatMetrics = z.object({
  damageDealt: z.number().finite(), damageTaken: z.number().finite(), damageByType: damageTypeMap,
  damageBySource: z.record(z.number().finite()), takenBySource: z.record(z.number().finite()),
  hits: z.number().int().nonnegative(), misses: z.number().int().nonnegative(), crits: z.number().int().nonnegative(), dodgesTaken: z.number().int().nonnegative(), kills: z.number().int().nonnegative(),
  skillUses: z.record(z.number().int().nonnegative()), ruleFailures: z.array(z.object({ ruleId: z.string(), reason: z.string(), count: z.number().int().nonnegative(), firstAt: z.number().finite() }).strict()),
  energySpent: z.number().finite(), energyStarvedMs: z.number().finite(), heatLockouts: z.number().int().nonnegative(), heatLockoutMs: z.number().finite(),
  shieldAbsorbed: z.number().finite(), hpLost: z.number().finite(), healingDone: z.number().finite(), statusTicks: z.number().int().nonnegative(), procsTriggered: z.number().int().nonnegative(),
  interrupts: z.number().int().nonnegative(), chainLimitHits: z.number().int().nonnegative(), ttk: z.array(z.object({ enemyId: z.string(), name: z.string(), ms: z.number().finite() }).strict()),
  droneDeaths: z.number().int().nonnegative(), escaped: z.array(z.string()), lowestHpFraction: z.number().finite(), timeWithoutShieldMs: z.number().finite(),
}).strict();
const deathReport = z.object({
  lethalCause: z.string(), lethalSource: z.string(), lastEvents: z.array(combatEvent), shieldAbsorbed: z.number().finite(), missedInterrupts: z.number().int(),
  energyStarvedMs: z.number().finite(), heatLockoutMs: z.number().finite(), bySource: z.array(z.object({ source: z.string(), damage: z.number().finite() }).strict()),
}).strict();
const combatResult = z.object({
  outcome: z.enum(['VICTORY', 'DEFEAT', 'TIMEOUT']), durationMs: z.number().finite().nonnegative(), seed: z.string(), metrics: combatMetrics,
  log: z.array(combatEvent).max(5000), logTruncated: z.boolean(), operator: z.object({ hp: z.number().finite(), maxHP: z.number().finite(), shield: z.number().finite(), energy: z.number().finite(), heat: z.number().finite() }).strict(),
  drones: z.array(z.object({ itemId: z.string(), hp: z.number().finite(), maxHP: z.number().finite(), alive: z.boolean() }).strict()),
  enemiesKilled: z.array(z.string()), bossKilled: z.boolean(), wantedDelta: z.number().finite(), revealDelta: z.number().finite(), usedSkills: z.array(z.string()),
  rngState: z.array(rngState), rulesHash: z.string(), deathReport: deathReport.optional(),
}).strict();

export function createRunStateSchema(itemSchema: z.ZodTypeAny) {
  const wallet = z.object({ CREDITS: z.number().finite().nonnegative(), SCRAP: z.number().finite().nonnegative(), DATA: z.number().finite().nonnegative() }).strict();
  const run = z.object({
    seed: z.string().min(1), depth: z.number().int().min(1), biome: z.enum(['B01', 'B02', 'B03', 'B04', 'B05', 'B06']),
    graph: roadGraph, equipment: z.record(z.enum(['MAIN', 'OFFHAND', 'ARMOR', 'IMP_1', 'IMP_2', 'IMP_3', 'IMP_4', 'IMP_5', 'IMP_6', 'DRONE_1', 'DRONE_2', 'ENGINE', 'CHASSIS', 'SCANNER', 'SERVICE', 'CARGO', 'SUPPORT']), z.string().min(1)), currentNodeId: z.string().min(1), visitedNodeIds: z.array(z.string()), clearedNodeIds: z.array(z.string()), eventsSeen: z.array(z.string()).default([]),
    phase: z.enum(['ROUTE', 'NODE', 'CHECKPOINT', 'EXTRACTED', 'TOWED', 'ABANDONED', 'DEFEATED', 'SAFE_ERROR_STOP']),
    wanted: z.number().finite().min(0).max(100), revealLevel: z.number().int().min(0).max(2), pendingTravelDeltaMs: z.number().int().min(-60_000).max(60_000).default(0),
    pendingCombatEffects: z.object({ initialTempShield: z.number().finite().nonnegative().max(200), extraHeat: z.number().finite().nonnegative().max(100) }).strict().default({ initialTempShield: 0, extraHeat: 0 }),
    pendingNextCombat: z.object({ skipOrdinary: z.boolean(), forceElite: z.boolean(), extraItemRoll: z.boolean() }).strict().default({ skipOrdinary: false, forceElite: false, extraItemRoll: false }),
    resources: z.object({ fuel: z.number().finite().nonnegative(), maxFuel: z.number().finite().nonnegative(), hull: z.number().finite().nonnegative(), maxHull: z.number().finite().nonnegative(), hp: z.number().finite().nonnegative(), maxHP: z.number().finite().nonnegative(), shield: z.number().finite().nonnegative(), maxShield: z.number().finite().nonnegative(), energy: z.number().finite().nonnegative(), heat: z.number().finite().nonnegative(), gameTimeMs: z.number().finite().nonnegative() }).strict(),
    runWallet: wallet, unsecuredCargo: z.array(itemSchema), shippedCargo: z.array(itemSchema), grantIds: z.array(z.string()), commandIds: z.array(z.string()).max(128), serviceScrapFuelCounts: z.record(z.number().int().min(0).max(4)), shippedCheckpointIds: z.array(z.string()),
    combatResult: combatResult.nullable(), lastCommandId: z.string().nullable(), worldRng: rngState, lootRng: rngState,
  }).strict().superRefine((value, context) => {
    const nodeIds = new Set(value.graph.layers.flat().map((entry) => entry.id));
    if (value.graph.depth !== value.depth || value.graph.biome !== value.biome) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Граф и запуск должны иметь общие сектор и биом.', path: ['graph'] });
    if (value.currentNodeId !== value.graph.startNodeId && !nodeIds.has(value.currentNodeId)) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Текущий узел отсутствует на карте.', path: ['currentNodeId'] });
    if (value.resources.fuel > value.resources.maxFuel || value.resources.hull > value.resources.maxHull || value.resources.hp > value.resources.maxHP || value.resources.shield > value.resources.maxShield) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Текущее значение ресурса превышает максимум.', path: ['resources'] });
    if (new Set(value.commandIds).size !== value.commandIds.length || new Set(value.grantIds).size !== value.grantIds.length) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Повторяется ID команды или награды.', path: ['commandIds'] });
  });
  return run;
}
