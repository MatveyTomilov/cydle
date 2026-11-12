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
import { createCombatState } from '../src/core/combat/engine';

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
  enemies: combatConfig.enemies, options: { startEnergy: combatConfig.startEnergy, startHeat: combatConfig.startHeat, initialExtraHeat: combatConfig.initialExtraHeat, initialTempShield: combatConfig.initialTempShield },
  expected: {
    operator: combatActorView(combatState.operator),
    drones: combatState.drones.map(combatActorView),
    enemies: combatState.enemies.map(combatActorView),
  },
}, null, 2)}\n`, 'utf8');
console.log(`Exported combat actor initialization oracle to ${combatFixtureOutput}`);
