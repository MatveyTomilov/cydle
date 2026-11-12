import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { ITEM_TEMPLATES } from '../src/data/items';
import { AFFIXES, RARITY_AFFIX_COUNT, RARITY_PRICE_MULT, SLOT_GROUP_WEIGHTS, TR_RANGES } from '../src/data/affixes';
import { RARITY_TABLES, createItem, rollItem, rollRarity } from '../src/core/items/items';
import { Rng } from '../src/core/rng';
import type { CreateItemOptions, LootRollOptions } from '../src/core/items/items';
import { resolveBuild } from '../src/core/build/build';
import { SKILLS, PASSIVES } from '../src/data/skills';
import { TREE_NODES } from '../src/data/tree';
import { MUTATIONS } from '../src/data/progression';
import { createInitialSave } from '../src/core/save/initial';
import { UNIQUE_TEMPLATE_BY_ID } from '../src/data/uniques';
import { BOSSES, ELITE_MODS, ENEMIES } from '../src/data/enemies';
import { applyStatus, createCombatState, stepCombat } from '../src/core/combat/engine';
import { STATUS_DEFS } from '../src/core/combat/status';
import type { TacticalProfile } from '../src/core/combat/types';

const templates = [...ITEM_TEMPLATES, ...Object.values(UNIQUE_TEMPLATE_BY_ID)];
const ids = new Set(templates.map((template) => template.id));
if (ids.size !== templates.length) throw new Error('Duplicate item template ID in export.');

const output = resolve('game/data/catalog/item_templates.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify({ schemaVersion: 1, templates }, null, 2)}\n`, 'utf8');
console.log(`Exported ${templates.length} item templates to ${output}`);

const rulesOutput = resolve('game/data/catalog/item_rules.json');
writeFileSync(rulesOutput, `${JSON.stringify({
  schemaVersion: 1,
  affixes: AFFIXES,
  rarityAffixCount: RARITY_AFFIX_COUNT,
  trRanges: TR_RANGES,
  rarityPriceMultipliers: RARITY_PRICE_MULT,
  rarityTables: RARITY_TABLES,
  slotGroupWeights: SLOT_GROUP_WEIGHTS,
}, null, 2)}\n`, 'utf8');
console.log(`Exported ${AFFIXES.length} affix definitions to ${rulesOutput}`);

const fixtureCases: Array<{ name: string; seed: string; stream: string; options: CreateItemOptions }> = [
  { name: 'common', seed: 'item-factory-golden', stream: 'loot', options: { templateId: 'PISTOL_K1', techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: 'grant-common', origin: 'cache' } },
  { name: 'rare', seed: 'item-factory-golden', stream: 'loot', options: { templateId: 'ARM_CLOTH', techLevel: 7, rarity: 'RARE', secured: false, originGrantId: 'grant-rare', origin: 'combat', affixCount: 4, acquiredAt: 12345 } },
  { name: 'unique', seed: 'item-factory-golden', stream: 'loot', options: { templateId: 'U01', techLevel: 13, rarity: 'UNIQUE', secured: true, originGrantId: 'grant-unique', origin: 'boss', affixCount: 2 } },
];
const fixtureOutput = resolve('game/tests/fixtures/items/create_item_cases.json');
mkdirSync(dirname(fixtureOutput), { recursive: true });
const rarityCases: Array<{ name: string; seed: string; stream: string; table: 'ORDINARY' | 'ELITE' | 'BOSS'; rareShift: number }> = [
  { name: 'ordinary', seed: 'rarity-golden', stream: 'loot', table: 'ORDINARY', rareShift: 0 },
  { name: 'elite-shifted', seed: 'rarity-golden', stream: 'loot', table: 'ELITE', rareShift: 0.35 },
  { name: 'boss', seed: 'rarity-golden', stream: 'loot', table: 'BOSS', rareShift: 0 },
];
const lootCases: Array<{ name: string; seed: string; stream: string; options: LootRollOptions }> = [
  { name: 'ordinary-pool', seed: 'loot-golden', stream: 'loot', options: { depth: 5, biome: 'B01', table: 'ORDINARY', secured: false, grantId: 'loot-normal', origin: 'combat' } },
  { name: 'unique-biome', seed: 'loot-golden', stream: 'loot', options: { depth: 10, biome: 'B05', table: 'BOSS', secured: true, grantId: 'loot-unique', origin: 'boss', forceRarity: 'UNIQUE' } },
  { name: 'unique-fallback', seed: 'loot-golden', stream: 'loot', options: { depth: 2, biome: 'B01', table: 'ELITE', secured: false, grantId: 'loot-fallback', origin: 'elite', forceRarity: 'UNIQUE', forceTag: 'no-such-tag' } },
];
writeFileSync(fixtureOutput, `${JSON.stringify({
  cases: fixtureCases.map((entry) => ({
  name: entry.name,
  stream: entry.stream,
  seed: entry.seed,
  options: entry.options,
  expected: createItem(new Rng(entry.stream, entry.seed), entry.options),
  })),
  rarityCases: rarityCases.map((entry) => ({ ...entry, expected: rollRarity(new Rng(entry.stream, entry.seed), entry.table, entry.rareShift) })),
  lootCases: lootCases.map((entry) => ({ ...entry, expected: rollItem(new Rng(entry.stream, entry.seed), entry.options) })),
}, null, 2)}\n`, 'utf8');
console.log(`Exported ${fixtureCases.length} item, ${rarityCases.length} rarity, and ${lootCases.length} loot fixtures to ${fixtureOutput}`);

const buildFixtureCases = [
  {
    name: 'attribute-main',
    seed: 'build-fixture',
    attributes: { POW: 7, REF: 6, INT: 5, ENG: 5, SYN: 5 },
    attributePointsEarned: 3,
    skillIds: ['SK_BURST'],
    passiveIds: ['PP_ACCURACY'],
    treeNodeIds: ['K1A'],
    treePointsEarned: 1,
    equipment: { MAIN: { templateId: 'PISTOL_K1', techLevel: 5, rarity: 'COMMON' as const, secured: true, originGrantId: 'build-main', origin: 'garage' } },
  },
  {
    name: 'armor-implant-drone',
    seed: 'build-fixture',
    attributes: { POW: 5, REF: 5, INT: 5, ENG: 7, SYN: 8 },
    attributePointsEarned: 5,
    skillIds: ['SK_PLASMA', 'SK_DRONE_REPAIR'],
    passiveIds: ['PP_DRONE'],
    treeNodeIds: ['D1A', 'D1B', 'D2A'],
    treePointsEarned: 3,
    mutationIds: ['MUT_HEAT'],
    equipment: {
      MAIN: { templateId: 'PLASMA_E1', techLevel: 8, rarity: 'RARE' as const, secured: true, originGrantId: 'build-main-2', origin: 'garage', affixCount: 3 },
      ARMOR: { templateId: 'ARM_HEAVY', techLevel: 5, rarity: 'MODIFIED' as const, secured: true, originGrantId: 'build-armor', origin: 'garage', affixCount: 1 },
      IMP_2: { templateId: 'IMP_HP', techLevel: 5, rarity: 'COMMON' as const, secured: true, originGrantId: 'build-implant', origin: 'garage' },
      DRONE_1: { templateId: 'DR_MED', techLevel: 3, rarity: 'COMMON' as const, secured: true, originGrantId: 'build-drone', origin: 'garage' },
    },
  },
];
const buildFixtureOutput = resolve('game/tests/fixtures/items/build_cases.json');
const buildFixtureOutputData: Array<Record<string, unknown>> = [];
for (const entry of buildFixtureCases) {
  const equipment: Record<string, ReturnType<typeof createItem>> = {};
  for (const [slot, options] of Object.entries(entry.equipment)) {
    const item = createItem(new Rng('loot', `${entry.seed}:${slot}`), { ...options, techLevel: options.techLevel, secured: options.secured, originGrantId: options.originGrantId, origin: options.origin });
    if (slot === 'MAIN' && entry.name === 'armor-implant-drone') item.durability = 20;
    equipment[slot] = item;
  }
  const build = resolveBuild({ attributes: entry.attributes, attributePointsEarned: entry.attributePointsEarned, skillIds: entry.skillIds, passiveIds: entry.passiveIds, treeNodeIds: entry.treeNodeIds, treePointsEarned: entry.treePointsEarned, mutationIds: entry.mutationIds, equipment });
	buildFixtureOutputData.push({
		name: entry.name,
		seed: entry.seed,
		attributes: entry.attributes,
		attributePointsEarned: entry.attributePointsEarned,
		skillIds: entry.skillIds,
		passiveIds: entry.passiveIds,
		treeNodeIds: entry.treeNodeIds,
		treePointsEarned: entry.treePointsEarned,
		mutationIds: entry.mutationIds ?? [],
		equipment: Object.fromEntries(Object.entries(equipment).map(([slot, item]) => [slot, item])),
		expected: {
    valid: build.valid,
    attributes: build.attributes,
    stats: build.stats,
    mainWeapon: build.mainWeapon,
    sidearm: build.sidearm,
    drones: build.drones,
			modifiers: build.modifiers,
				effects: build.effects,
				triggerEffects: build.triggerEffects,
				skills: build.skills,
				skillIds: build.skillIds,
				passives: build.passives,
				passiveIds: build.passiveIds,
				treeNodes: build.treeNodes,
				treeNodeIds: build.treeNodeIds,
				mutationIds: build.mutationIds,
		},
	});
}
mkdirSync(dirname(buildFixtureOutput), { recursive: true });
writeFileSync(buildFixtureOutput, `${JSON.stringify({ cases: buildFixtureOutputData }, null, 2)}\n`, 'utf8');
console.log(`Exported ${buildFixtureCases.length} build resolver fixtures to ${buildFixtureOutput}`);

const buildDefinitionsOutput = resolve('game/data/catalog/build_definitions.json');
writeFileSync(buildDefinitionsOutput, `${JSON.stringify({ schemaVersion: 1, skills: SKILLS, passives: PASSIVES, treeNodes: TREE_NODES, mutations: MUTATIONS }, null, 2)}\n`, 'utf8');
console.log(`Exported ${SKILLS.length} skills, ${PASSIVES.length} passives, ${TREE_NODES.length} tree nodes, and ${MUTATIONS.length} mutations to ${buildDefinitionsOutput}`);

const initialSaveFixture = createInitialSave({ saveId: 'native-starter-oracle', now: 1700000000000 });
const initialSaveOutput = resolve('game/tests/fixtures/saves/initial_save.json');
mkdirSync(dirname(initialSaveOutput), { recursive: true });
writeFileSync(initialSaveOutput, `${JSON.stringify(initialSaveFixture, null, 2)}\n`, 'utf8');
console.log(`Exported deterministic initial-save fixture to ${initialSaveOutput}`);

const enemyCatalogOutput = resolve('game/data/catalog/enemy_definitions.json');
mkdirSync(dirname(enemyCatalogOutput), { recursive: true });
writeFileSync(enemyCatalogOutput, `${JSON.stringify({ schemaVersion: 1, enemies: ENEMIES, bosses: BOSSES, eliteMods: ELITE_MODS }, null, 2)}\n`, 'utf8');
console.log(`Exported ${ENEMIES.length} enemies, ${BOSSES.length} bosses, and ${ELITE_MODS.length} elite modifiers to ${enemyCatalogOutput}`);

const statusCatalogOutput = resolve('game/data/catalog/status_definitions.json');
writeFileSync(statusCatalogOutput, `${JSON.stringify({ schemaVersion: 1, statuses: Object.values(STATUS_DEFS) }, null, 2)}\n`, 'utf8');
console.log(`Exported ${Object.keys(STATUS_DEFS).length} status definitions to ${statusCatalogOutput}`);

const starterItemsById = new Map(initialSaveFixture.meta.inventory.map((item) => [item.itemId, item]));
const starterEquipment = Object.fromEntries(Object.entries(initialSaveFixture.meta.equipment).map(([slot, itemId]) => [slot, starterItemsById.get(itemId)!]));
const starterBuild = resolveBuild({
  attributes: initialSaveFixture.meta.operator.attributes,
  equipment: starterEquipment,
  skillIds: initialSaveFixture.meta.skillIds,
  passiveIds: initialSaveFixture.meta.passiveIds,
  treeNodeIds: initialSaveFixture.meta.treeNodeIds,
  attributePointsEarned: initialSaveFixture.meta.operator.attributePoints,
  treePointsEarned: initialSaveFixture.meta.operator.treePoints,
  unlockedImplantSlots: initialSaveFixture.meta.unlockedImplantSlots,
  unlockedDroneSlots: initialSaveFixture.meta.unlockedDroneSlots,
});
const combatConfig = {
  seed: 'combat-actor-golden', depth: 3, biome: 'B01' as const, nodeType: 'ELITE' as const, build: starterBuild,
  enemies: [{ templateId: 'E07', elite: 'EL_FAST', hpMult: 1.2, damageMult: 0.8 }],
  tactics: initialSaveFixture.meta.tactics[0]!, startEnergy: 30, startHeat: 10, initialExtraHeat: 5, initialTempShield: 12,
};
const combatState = createCombatState(combatConfig);
const combatActorView = (actor: typeof combatState.operator) => ({
  id: actor.id, kind: actor.kind, side: actor.side, templateId: actor.templateId, name: actor.name,
  positionTag: actor.positionTag, isBoss: actor.isBoss, isMechanical: actor.isMechanical, isHealer: actor.isHealer,
  hp: actor.hp, shield: actor.shield, tempShields: actor.tempShields, energy: actor.energy, heat: actor.heat,
  baseSheet: actor.baseSheet, attackDamage: actor.attackDamage, attackIntervalMs: actor.attackIntervalMs,
  attackType: actor.attackType, accuracyBase: actor.accuracyBase, threatUnits: actor.threatUnits,
  nextAttackAt: actor.nextAttackAt, flags: actor.flags, abilityNext: actor.abilityNext, ownerId: actor.ownerId ?? null,
  eliteMod: actor.eliteMod ?? null, noLoot: actor.noLoot ?? false, summoned: actor.summoned ?? false,
});
const combatFixtureOutput = resolve('game/tests/fixtures/combat/actor_initialization.json');
mkdirSync(dirname(combatFixtureOutput), { recursive: true });
writeFileSync(combatFixtureOutput, `${JSON.stringify({
  seed: combatConfig.seed, depth: combatConfig.depth, biome: combatConfig.biome, nodeType: combatConfig.nodeType,
  enemies: combatConfig.enemies, tactics: combatConfig.tactics,
  options: { startEnergy: combatConfig.startEnergy, startHeat: combatConfig.startHeat, initialExtraHeat: combatConfig.initialExtraHeat, initialTempShield: combatConfig.initialTempShield },
  expected: {
    operator: combatActorView(combatState.operator),
    drones: combatState.drones.map(combatActorView),
    enemies: combatState.enemies.map(combatActorView),
    state: {
      seed: combatState.seed, depth: combatState.depth, biome: combatState.biome, nodeType: combatState.nodeType,
      timeMs: combatState.timeMs, maxDurationMs: combatState.maxDurationMs, rng: combatState.rng,
      nextEventId: combatState.nextEventId, log: combatState.log, logTruncated: combatState.logTruncated,
      metrics: combatState.metrics, rulesHash: combatState.rulesHash,
    },
  },
}, null, 2)}\n`, 'utf8');
console.log(`Exported combat actor initialization oracle to ${combatFixtureOutput}`);

const starterMainId = initialSaveFixture.meta.equipment.MAIN;
if (!starterMainId) throw new Error('Starter save is missing its main weapon.');
const starterMain = starterItemsById.get(starterMainId)!;
const basicBuild = resolveBuild({
  attributes: initialSaveFixture.meta.operator.attributes,
  equipment: { MAIN: starterMain },
  skillIds: [], passiveIds: [], treeNodeIds: [], attributePointsEarned: 0, treePointsEarned: 0,
});
const basicTactics: TacticalProfile = { id: 'EMPTY', name: 'Empty', rules: [] };
const basicStateConfig = {
  seed: 'basic-auto-replay', depth: 1, biome: 'B01' as const, nodeType: 'COMBAT' as const,
  build: basicBuild, enemies: [{ templateId: 'E01' }], tactics: basicTactics, maxDurationMs: 3000,
};
let basicState = createCombatState(basicStateConfig);
const basicAutoFrames = [];
for (let tick = 0; tick < 15; tick++) {
  const previousLogLength = basicState.log.length;
  basicState = stepCombat(basicState);
  const actorFrame = (actor: typeof basicState.operator) => ({
    id: actor.id, hp: actor.hp, shield: actor.shield, energy: actor.energy, heat: actor.heat,
    nextAttackAt: actor.nextAttackAt, alive: actor.alive, flags: actor.flags, counters: actor.counters,
    damageDealt: actor.damageDealt, damageTaken: actor.damageTaken,
  });
  basicAutoFrames.push({
    timeMs: basicState.timeMs, rng: basicState.rng, nextEventId: basicState.nextEventId,
    metrics: basicState.metrics, outcome: basicState.outcome,
    operator: actorFrame(basicState.operator), enemies: basicState.enemies.map(actorFrame),
    events: basicState.log.slice(previousLogLength),
  });
}
const basicAutoFixtureOutput = resolve('game/tests/fixtures/combat/basic_auto_replay.json');
mkdirSync(dirname(basicAutoFixtureOutput), { recursive: true });
writeFileSync(basicAutoFixtureOutput, `${JSON.stringify({ config: { seed: basicStateConfig.seed, depth: basicStateConfig.depth, biome: basicStateConfig.biome, nodeType: basicStateConfig.nodeType, enemy: basicStateConfig.enemies[0], tactics: basicTactics, maxDurationMs: basicStateConfig.maxDurationMs }, frames: basicAutoFrames }, null, 2)}\n`, 'utf8');
console.log(`Exported ${basicAutoFrames.length} basic-auto combat replay frames to ${basicAutoFixtureOutput}`);

const weaponReplayTemplates = ['RIFLE_K2', 'PLASMA_E1', 'SPIKE_D2', 'DUAL_H1', 'SHOTGUN_K5'];
const weaponPacketReplays = weaponReplayTemplates.map((templateId) => {
  const item = createItem(new Rng('loot', `weapon-packet:${templateId}`), {
    templateId, techLevel: 1, rarity: 'COMMON', secured: true,
    originGrantId: `weapon-packet:${templateId}`, origin: 'fixture',
  });
  const build = resolveBuild({
    attributes: initialSaveFixture.meta.operator.attributes,
    equipment: { MAIN: item },
    skillIds: [], passiveIds: [], treeNodeIds: [], attributePointsEarned: 0, treePointsEarned: 0,
  });
  let replay = createCombatState({ ...basicStateConfig, build });
  const frames = [];
  for (let tick = 0; tick < 15; tick++) {
    const previousLogLength = replay.log.length;
    replay = stepCombat(replay);
    const actorFrame = (actor: typeof replay.operator) => ({
      id: actor.id, hp: actor.hp, shield: actor.shield, energy: actor.energy, heat: actor.heat,
      nextAttackAt: actor.nextAttackAt, alive: actor.alive, flags: actor.flags, counters: actor.counters,
      damageDealt: actor.damageDealt, damageTaken: actor.damageTaken,
    });
    frames.push({
      timeMs: replay.timeMs, rng: replay.rng, nextEventId: replay.nextEventId,
      metrics: replay.metrics, outcome: replay.outcome,
      operator: actorFrame(replay.operator), enemies: replay.enemies.map(actorFrame),
      events: replay.log.slice(previousLogLength),
    });
  }
  return { templateId, item, frames };
});
const weaponReplayOutput = resolve('game/tests/fixtures/combat/weapon_packet_replays.json');
writeFileSync(weaponReplayOutput, `${JSON.stringify(weaponPacketReplays, null, 2)}\n`, 'utf8');
console.log(`Exported ${weaponPacketReplays.length} multi-channel/packet combat replays to ${weaponReplayOutput}`);

let dotState = createCombatState(basicStateConfig);
applyStatus(dotState, dotState.operator, dotState.enemies[0]!, 'BLEED', { snapshot: 100 });
const dotFrames = [];
for (let tick = 0; tick < 40; tick++) {
  const previousLogLength = dotState.log.length;
  dotState = stepCombat(dotState);
  dotFrames.push({
    timeMs: dotState.timeMs, rng: dotState.rng, nextEventId: dotState.nextEventId,
    metrics: dotState.metrics, outcome: dotState.outcome,
    operator: { hp: dotState.operator.hp, shield: dotState.operator.shield, statuses: dotState.operator.statuses },
    enemies: dotState.enemies.map((actor) => ({ hp: actor.hp, shield: actor.shield, statuses: actor.statuses, damageTaken: actor.damageTaken })),
    events: dotState.log.slice(previousLogLength),
  });
}
const dotFixtureOutput = resolve('game/tests/fixtures/combat/dot_replay.json');
writeFileSync(dotFixtureOutput, `${JSON.stringify({
  config: { seed: basicStateConfig.seed, depth: basicStateConfig.depth, biome: basicStateConfig.biome, nodeType: basicStateConfig.nodeType, enemy: basicStateConfig.enemies[0], tactics: basicTactics, maxDurationMs: basicStateConfig.maxDurationMs },
  status: { id: 'BLEED', snapshot: 100 }, appliedEvent: dotState.log.find((event) => event.kind === 'STATUS_APPLY'), frames: dotFrames,
}, null, 2)}\n`, 'utf8');
console.log(`Exported ${dotFrames.length} DoT status replay frames to ${dotFixtureOutput}`);

const statusEffectCases: Array<{ id: string; target: string; stacks?: number }> = [
  { id: 'ARMOR_BREAK', target: 'enemy:0' }, { id: 'SHOCK', target: 'operator' },
  { id: 'DRONE_JAM', target: 'drone:0' },
  { id: 'SHIELD_LEAK', target: 'operator' }, { id: 'MARK', target: 'enemy:0' },
  { id: 'SCAN_MARK', target: 'enemy:0' }, { id: 'DRONE_MARK', target: 'enemy:0' },
  { id: 'CONTROLLED', target: 'enemy:0' }, { id: 'GUARD', target: 'operator' },
  { id: 'OVERCLOCK', target: 'operator' }, { id: 'ACC_BUFF', target: 'operator' },
  { id: 'EVASION_BUFF', target: 'operator' }, { id: 'SHIELD_REGEN_BUFF', target: 'operator' },
  { id: 'BERSERK', target: 'operator', stacks: 2 },
];
const starterDroneId = initialSaveFixture.meta.equipment.DRONE_1;
if (!starterDroneId) throw new Error('Starter save is missing its drone.');
const statusBuild = resolveBuild({
  attributes: initialSaveFixture.meta.operator.attributes,
  equipment: { MAIN: starterMain, DRONE_1: starterItemsById.get(starterDroneId)! },
  skillIds: [], passiveIds: [], treeNodeIds: [], attributePointsEarned: 0, treePointsEarned: 0,
});
const statusEffectReplays = statusEffectCases.map(({ id, target, stacks = 1 }) => {
  let replay = createCombatState({ ...basicStateConfig, build: statusBuild });
  const targetActor = target === 'operator' ? replay.operator : target === 'drone:0' ? replay.drones[0]! : replay.enemies[0]!;
  const sourceActor = targetActor.side === 'enemy' ? replay.operator : replay.enemies[0]!;
  if (id === 'SHIELD_LEAK' || id === 'SHIELD_REGEN_BUFF') {
    targetActor.shield = Math.max(0, targetActor.baseSheet.maxShield - 20);
    targetActor.flags.lastDamagedAt = -100000;
  }
  applyStatus(replay, sourceActor, targetActor, id as keyof typeof STATUS_DEFS, { stacks });
  for (let tick = 0; tick < 40; tick++) replay = stepCombat(replay);
  return {
    status: id, target, stacks, timeMs: replay.timeMs, rng: replay.rng, nextEventId: replay.nextEventId,
    metrics: replay.metrics, outcome: replay.outcome,
    operator: { hp: replay.operator.hp, shield: replay.operator.shield, statuses: replay.operator.statuses, nextAttackAt: replay.operator.nextAttackAt },
    drones: replay.drones.map((actor) => ({ hp: actor.hp, shield: actor.shield, statuses: actor.statuses, nextAttackAt: actor.nextAttackAt, damageTaken: actor.damageTaken })),
    enemies: replay.enemies.map((actor) => ({ hp: actor.hp, shield: actor.shield, statuses: actor.statuses, nextAttackAt: actor.nextAttackAt, damageTaken: actor.damageTaken })),
  };
});
const statusEffectOutput = resolve('game/tests/fixtures/combat/status_effect_replays.json');
writeFileSync(statusEffectOutput, `${JSON.stringify(statusEffectReplays, null, 2)}\n`, 'utf8');
console.log(`Exported ${statusEffectReplays.length} status effect replay checkpoints to ${statusEffectOutput}`);
