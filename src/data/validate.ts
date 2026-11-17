import { BIOMES, CAMPAIGN_BIOMES } from './biomes';
import { BOSSES, ENEMIES } from './enemies';
import { EVENTS } from './events';
import { ITEM_BY_ID, ITEM_TEMPLATES } from './items';
import { QUESTS } from './quests';
import { PASSIVE_BY_ID, PASSIVES, SKILL_BY_ID, SKILLS } from './skills';
import { TREE_BY_ID, TREE_NODES } from './tree';
import { UNIQUE_BY_ID, UNIQUE_TEMPLATE_BY_ID, UNIQUES } from './uniques';

/** Startup and CI checks for catalog identity and references used by the game. */
export function validateCatalog(): string[] {
  const issues: string[] = [];
  const catalogs = [
    ['items', ITEM_TEMPLATES], ['skills', SKILLS], ['passives', PASSIVES], ['tree', TREE_NODES],
    ['uniques', UNIQUES], ['enemies', ENEMIES], ['bosses', BOSSES], ['events', EVENTS], ['quests', QUESTS], ['biomes', BIOMES],
  ] as const;
  for (const [name, definitions] of catalogs) {
    const ids = definitions.map((definition) => definition.id);
    const unique = new Set(ids);
    if (unique.size !== ids.length) issues.push(`${name}: повторяются ID определений.`);
  }
  const enemyIds = new Set([...ENEMIES, ...BOSSES].map((enemy) => enemy.id));
  const itemIds = new Set([...Object.keys(ITEM_BY_ID), ...Object.keys(UNIQUE_TEMPLATE_BY_ID)]);
  const branchIds = new Set(['K', 'H', 'N', 'D', 'S', 'R']);

  for (const biome of BIOMES) {
    for (const id of biome.enemies) if (!enemyIds.has(id)) issues.push(`Биом ${biome.id}: неизвестный враг ${id}.`);
    for (const id of biome.uniques) if (!UNIQUE_BY_ID[id]) issues.push(`Биом ${biome.id}: неизвестный уникальный эффект ${id}.`);
  }
  for (const [depth, id] of Object.entries(CAMPAIGN_BIOMES)) {
    if (!BIOMES.some((biome) => biome.id === id)) issues.push(`Кампания, сектор ${depth}: неизвестный биом ${id}.`);
  }
  for (const enemy of ENEMIES) {
    for (const ability of enemy.abilities) {
      if (ability.summonId && !enemyIds.has(ability.summonId)) issues.push(`Враг ${enemy.id}: неизвестный призыв ${ability.summonId}.`);
    }
  }
  for (const boss of BOSSES) {
    for (const ability of [...boss.abilities, ...(boss.rotating ?? [])]) {
      if (ability.summonId && !enemyIds.has(ability.summonId)) issues.push(`Босс ${boss.id}: неизвестный призыв ${ability.summonId}.`);
    }
  }
  for (const item of ITEM_TEMPLATES) {
    if (item.uniqueEffectId && !UNIQUE_BY_ID[item.uniqueEffectId]) issues.push(`Предмет ${item.id}: неизвестный уникальный эффект ${item.uniqueEffectId}.`);
  }
  for (const event of EVENTS) {
    for (const choice of event.choices) {
      const id = choice.grantItem?.templateId;
      if (id && !itemIds.has(id)) issues.push(`Событие ${event.id}, выбор ${choice.id}: неизвестный предмет ${id}.`);
    }
  }
  for (const quest of QUESTS) {
    for (const stage of quest.stages) for (const choice of stage.choices) {
      const marker = choice.special?.match(/^(?:schematic|signalContract):(.+)$/)?.[1];
      if (marker && choice.special?.startsWith('signalContract:') && !UNIQUE_BY_ID[marker]) issues.push(`Квест ${quest.id}: неизвестный целевой уникальный эффект ${marker}.`);
    }
  }
  for (const node of TREE_NODES) {
    for (const requirement of node.requires ?? []) if (!branchIds.has(requirement.branch)) issues.push(`Узел ${node.id}: неизвестная ветвь ${requirement.branch}.`);
  }
  for (const id of ['SK_BURST', 'SK_SHIELD', 'SK_EMP']) if (!SKILL_BY_ID[id]) issues.push(`Отсутствует стартовое умение ${id}.`);
  for (const id of ['PP_ACCURACY', 'PP_SHIELD']) if (!PASSIVE_BY_ID[id]) issues.push(`Отсутствует стартовый пассив ${id}.`);
  for (const id of ['PISTOL_K1', 'OFF_SHIELD', 'ARM_CLOTH', 'IMP_ARMOR', 'IMP_REFLEX', 'DR_GUN', 'TR_ENGINE_1', 'TR_CHASSIS_1', 'TR_SCANNER_1', 'TR_SERVICE_1', 'TR_CARGO_1', 'TR_SUPPORT_1']) {
    if (!itemIds.has(id)) issues.push(`Отсутствует стартовый предмет ${id}.`);
  }
  return issues;
}
