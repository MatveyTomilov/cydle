import { AFFIX_BY_ID, affixEffect } from '../../data/affixes';
import { ITEM_BY_ID } from '../../data/items';
import { MUTATION_BY_ID } from '../../data/progression';
import { PASSIVE_BY_ID, SKILL_BY_ID } from '../../data/skills';
import { TREE_BY_ID, keystoneCount, nodeLockReason } from '../../data/tree';
import type { EffectDef, ItemTemplate, PassiveDef, SkillDef, StatEffect, TreeNodeDef, WeaponBlock, DroneBlock, TriggerEffect } from '../../data/types';
import { UNIQUE_TEMPLATE_BY_ID } from '../../data/uniques';
import { D, H, techPower } from '../math/formula';
import { bundle, mod, resolveStats, sheetOf, type Modifier, type StatContext, type StatResults, type StatSheet } from '../math/stats';
import type { AttributeId, EquipSlotId, ImplantSlotType, ItemCategory, SourceKind } from '../types';
import type { ItemInstance } from '../items/items';
import { IMPLANT_SLOT_TYPES } from '../types';

export interface BuildLoadout {
  attributes?: Partial<Record<AttributeId, number>>;
  equipment?: Partial<Record<EquipSlotId, ItemInstance>>;
  skillIds?: string[];
  passiveIds?: string[];
  treeNodeIds?: string[];
  mutationIds?: string[];
  attributePointsEarned?: number;
  treePointsEarned?: number;
  unlockedImplantSlots?: number;
  unlockedDroneSlots?: number;
  context?: StatContext;
}

export interface BuildIssue {
  code:
    | 'UNKNOWN_ITEM' | 'INVALID_SLOT' | 'LOCKED_SLOT' | 'MISSING_MAIN' | 'MISSING_WEAPON_BLOCK'
    | 'NEURAL_CAPACITY' | 'NEURAL_COST_MISMATCH' | 'DUPLICATE_ITEM' | 'INVALID_AFFIX'
    | 'INVALID_TECH_LEVEL' | 'INVALID_DURABILITY' | 'UNKNOWN_SKILL' | 'UNKNOWN_PASSIVE'
    | 'UNKNOWN_TREE_NODE' | 'UNKNOWN_MUTATION' | 'TREE_LOCKED' | 'SKILL_REQUIREMENT'
    | 'SKILL_LIMIT' | 'PASSIVE_LIMIT' | 'MUTATION_LIMIT' | 'ATTRIBUTE_POINTS'
    | 'ATTRIBUTE_POINTS_CAP' | 'INVALID_ATTRIBUTE' | 'TREE_POINTS' | 'TREE_POINTS_CAP'
    | 'DUPLICATE_SELECTION' | 'DUPLICATE_TREE_NODE' | 'KEYSTONE_LIMIT' | 'INVALID_AFFIX_GROUP';
  message: string;
  sourceId?: string;
}

export interface ResolvedWeapon extends Omit<WeaponBlock, 'damage' | 'packets'> {
  itemId: string;
  templateId: string;
  techLevel: number;
  damage: number;
  packets?: { type: WeaponBlock['type']; amount: number; procWeight?: number }[];
}

export interface ResolvedDrone extends Omit<DroneBlock, 'hp' | 'shield' | 'damage'> {
  itemId: string;
  templateId: string;
  techLevel: number;
  hp: number;
  shield: number;
  damage: number;
}

export interface ResolvedTriggerEffect {
  effect: TriggerEffect;
  sourceId: string;
  sourceName: string;
  sourceKind: SourceKind;
}

/**
 * Resolved combat snapshot. `valid` must be checked before starting a fight;
 * `statResults` preserves every exact result and CalcTrace used for `stats`.
 */
export interface ResolvedBuild {
  valid: boolean;
  attributes: Record<AttributeId, number>;
  equipment: Partial<Record<EquipSlotId, ItemInstance>>;
  stats: StatSheet;
  statResults: StatResults;
  mainWeapon?: ResolvedWeapon;
  sidearm?: ResolvedWeapon;
  drones: ResolvedDrone[];
  skills: SkillDef[];
  skillIds: string[];
  passives: PassiveDef[];
  passiveIds: string[];
  treeNodes: TreeNodeDef[];
  treeNodeIds: string[];
  mutationIds: string[];
  effects: EffectDef[];
  triggerEffects: ResolvedTriggerEffect[];
  modifiers: Modifier[];
  issues: BuildIssue[];
}

const ATTRIBUTE_IDS: AttributeId[] = ['POW', 'REF', 'INT', 'ENG', 'SYN'];
const EQUIPMENT_SLOTS: EquipSlotId[] = [
  'MAIN', 'OFFHAND', 'ARMOR', 'IMP_1', 'IMP_2', 'IMP_3', 'IMP_4', 'IMP_5', 'IMP_6',
  'DRONE_1', 'DRONE_2', 'ENGINE', 'CHASSIS', 'SCANNER', 'SERVICE', 'CARGO', 'SUPPORT',
];
const SLOT_CATEGORY: Record<EquipSlotId, ItemCategory> = {
  MAIN: 'MAIN', OFFHAND: 'OFFHAND', ARMOR: 'ARMOR',
  IMP_1: 'IMPLANT', IMP_2: 'IMPLANT', IMP_3: 'IMPLANT', IMP_4: 'IMPLANT', IMP_5: 'IMPLANT', IMP_6: 'IMPLANT',
  DRONE_1: 'DRONE', DRONE_2: 'DRONE',
  ENGINE: 'ENGINE', CHASSIS: 'CHASSIS', SCANNER: 'SCANNER', SERVICE: 'SERVICE', CARGO: 'CARGO', SUPPORT: 'SUPPORT',
};

function templateFor(id: string): ItemTemplate | undefined {
  return UNIQUE_TEMPLATE_BY_ID[id] ?? ITEM_BY_ID[id];
}

function addIssue(issues: BuildIssue[], code: BuildIssue['code'], message: string, sourceId?: string): void {
  issues.push({ code, message, sourceId });
}

function selectedIds(ids: string[], label: string, code: BuildIssue['code'], issues: BuildIssue[]): void {
  if (new Set(ids).size !== ids.length) addIssue(issues, 'DUPLICATE_SELECTION', `Повторяется выбор ${label}.`);
  if (ids.length > 0 && ids.some((x) => !x)) addIssue(issues, code, `В списке ${label} есть пустой ID.`);
}

function slotAllows(slot: EquipSlotId, template: ItemTemplate): boolean {
  if (SLOT_CATEGORY[slot] !== template.category) return false;
  if (!slot.startsWith('IMP_')) return true;
  const socket = IMPLANT_SLOT_TYPES[slot] as ImplantSlotType;
  const implant = template.implantSlot;
  return !!implant && (socket === 'UNIVERSAL' || implant === 'UNIVERSAL' || implant === socket);
}

function statModifier(
  effect: StatEffect,
  source: { id: string; name: string; kind: SourceKind },
  value: number,
  id: string,
): Modifier {
  return mod(effect.stat, effect.op, value, source, {
    id,
    condition: effect.condition,
    stackGroup: effect.stackGroup,
    synScalable: effect.synScalable,
    note: effect.note,
  });
}

function scaleItemEffect(effect: StatEffect, template: ItemTemplate, item: ItemInstance, syn: number): number {
  let value = effect.value;
  if (effect.note?.includes('×D(T)')) value *= D(item.techLevel);
  if (effect.note?.includes('×H(T)')) value *= H(item.techLevel);
  if (template.category === 'IMPLANT' && effect.synScalable) value *= Math.max(0, 1 + 0.015 * (syn - 5));
  if (item.durability < 25) value *= 0.9;
  return value;
}

function checkAttributeInput(input: BuildLoadout, attributes: Record<AttributeId, number>, issues: BuildIssue[]): void {
  const earned = input.attributePointsEarned ?? 0;
  const allocated = ATTRIBUTE_IDS.reduce((total, id) => total + Math.max(0, attributes[id] - 5), 0);
  if (!Number.isInteger(earned) || earned < 0) addIssue(issues, 'ATTRIBUTE_POINTS', 'Число полученных очков атрибутов должно быть целым и неотрицательным.');
  if (earned > 12) addIssue(issues, 'ATTRIBUTE_POINTS_CAP', 'За уровни доступно не более 12 очков атрибутов.');
  if (allocated > earned) addIssue(issues, 'ATTRIBUTE_POINTS', `Распределено ${allocated} очков атрибутов, получено ${earned}.`);
  for (const id of ATTRIBUTE_IDS) {
    if (!Number.isFinite(attributes[id]) || attributes[id] < 1) addIssue(issues, 'INVALID_ATTRIBUTE', `Атрибут ${id} должен быть конечным числом не меньше 1.`, id);
  }
}

function addAttributeModifiers(attributes: Record<AttributeId, number>, modifiers: Modifier[]): void {
  const add = (attribute: AttributeId, stat: StatEffect['stat'], op: StatEffect['op'], amountPerPoint: number) => {
    const delta = attributes[attribute] - 5;
    if (delta !== 0) modifiers.push(mod(stat, op, delta * amountPerPoint, {
      id: `attribute:${attribute}`, name: attribute, kind: 'attribute',
    }));
  };
  add('POW', 'kineticDamage', 'INCREASED', 2);
  add('POW', 'armorPen', 'FLAT', 0.5);
  add('REF', 'attackSpeed', 'INCREASED', 1.5);
  add('REF', 'evasion', 'FLAT', 1.5);
  add('REF', 'accuracy', 'FLAT', 0.3);
  add('INT', 'digitalDamage', 'INCREASED', 2.5);
  add('INT', 'energyDamage', 'INCREASED', 1);
  add('INT', 'digitalPenPercent', 'FLAT', 0.5);
  add('ENG', 'droneDamage', 'INCREASED', 2.5);
  add('ENG', 'droneHP', 'INCREASED', 2);
  add('ENG', 'repairPower', 'INCREASED', 1);
  add('SYN', 'neuralCapacity', 'FLAT', 2);
}

function resolveWeapon(item: ItemInstance, template: ItemTemplate): ResolvedWeapon | undefined {
  const weapon = template.weapon;
  if (!weapon) return undefined;
  const scale = H(item.techLevel) * (item.durability < 25 ? 0.9 : 1);
  return {
    ...weapon,
    itemId: item.itemId,
    templateId: item.templateId,
    techLevel: item.techLevel,
    damage: weapon.damage * scale,
    packets: weapon.packets?.map((packet) => ({ ...packet, amount: packet.amount * scale })),
  };
}

function resolveDrone(item: ItemInstance, template: ItemTemplate): ResolvedDrone | undefined {
  const drone = template.drone;
  if (!drone) return undefined;
  const dScale = D(item.techLevel) * (item.durability < 25 ? 0.9 : 1);
  const hScale = H(item.techLevel) * (item.durability < 25 ? 0.9 : 1);
  return {
    ...drone,
    itemId: item.itemId,
    templateId: item.templateId,
    techLevel: item.techLevel,
    hp: drone.hp * dScale,
    shield: drone.shield * dScale,
    damage: drone.damage * hScale,
  };
}

/** Resolve legality and exact numerical effects for the same loadout used by combat and Build Lab. */
export function resolveBuild(input: BuildLoadout): ResolvedBuild {
  const issues: BuildIssue[] = [];
  const equipment = { ...(input.equipment ?? {}) };
  const skillIds = [...(input.skillIds ?? [])];
  const passiveIds = [...(input.passiveIds ?? [])];
  const treeNodeIds = [...(input.treeNodeIds ?? [])];
  const mutationIds = [...(input.mutationIds ?? [])];
  const attributes = Object.fromEntries(ATTRIBUTE_IDS.map((id) => [id, input.attributes?.[id] ?? 5])) as Record<AttributeId, number>;
  checkAttributeInput(input, attributes, issues);
  selectedIds(skillIds, 'умений', 'UNKNOWN_SKILL', issues);
  selectedIds(passiveIds, 'пассивных протоколов', 'UNKNOWN_PASSIVE', issues);
  selectedIds(mutationIds, 'мутаций', 'UNKNOWN_MUTATION', issues);
  if (skillIds.length > 3) addIssue(issues, 'SKILL_LIMIT', 'Можно установить не более трёх активных умений.');
  if (passiveIds.length > 3) addIssue(issues, 'PASSIVE_LIMIT', 'Можно установить не более трёх пассивных протоколов.');
  if (mutationIds.length > 2) addIssue(issues, 'MUTATION_LIMIT', 'Одновременно доступны не более двух мутаций.');

  const unlockedImplants = Math.max(0, Math.min(6, input.unlockedImplantSlots ?? 4));
  const unlockedDrones = Math.max(0, Math.min(2, input.unlockedDroneSlots ?? 1));
  const itemIds = new Set<string>();
  const validTemplates = new Map<EquipSlotId, ItemTemplate>();
  for (const slot of EQUIPMENT_SLOTS) {
    const item = equipment[slot];
    if (!item) continue;
    const template = templateFor(item.templateId);
    if (!template) {
      addIssue(issues, 'UNKNOWN_ITEM', `Неизвестный шаблон предмета ${item.templateId}.`, item.itemId);
      continue;
    }
    validTemplates.set(slot, template);
    if (itemIds.has(item.itemId)) addIssue(issues, 'DUPLICATE_ITEM', `Предмет ${item.itemId} установлен более одного раза.`, item.itemId);
    itemIds.add(item.itemId);
    if (!slotAllows(slot, template)) addIssue(issues, 'INVALID_SLOT', `${template.name} нельзя установить в слот ${slot}.`, item.itemId);
    if (slot.startsWith('IMP_') && Number(slot.slice(4)) > unlockedImplants) addIssue(issues, 'LOCKED_SLOT', `Слот ${slot} ещё не открыт.`, item.itemId);
    if (slot.startsWith('DRONE_') && Number(slot.slice(6)) > unlockedDrones) addIssue(issues, 'LOCKED_SLOT', `Слот ${slot} ещё не открыт.`, item.itemId);
    if (!Number.isInteger(item.techLevel) || item.techLevel < 1) addIssue(issues, 'INVALID_TECH_LEVEL', 'TechLevel должен быть целым числом не меньше 1.', item.itemId);
    if (!Number.isFinite(item.durability) || item.durability < 0 || item.durability > 100) addIssue(issues, 'INVALID_DURABILITY', 'Износ должен находиться в диапазоне 0–100.', item.itemId);
    if (item.neuralCost !== (template.neuralCost ?? 0)) addIssue(issues, 'NEURAL_COST_MISMATCH', 'Нейростоимость экземпляра не совпадает с шаблоном.', item.itemId);
    const affixGroups = new Set<string>();
    for (const roll of item.affixes) {
      const affix = AFFIX_BY_ID[roll.affixId];
      if (!affix) {
        addIssue(issues, 'INVALID_AFFIX', `Неизвестный аффикс ${roll.affixId}.`, item.itemId);
        continue;
      }
      if (!affix.slots.includes(template.category) || roll.tier < 1 || roll.tier > 4 || !Number.isFinite(roll.value)) {
        addIssue(issues, 'INVALID_AFFIX', `Аффикс ${roll.affixId} несовместим с предметом или содержит неверный ролл.`, item.itemId);
      }
      if (affixGroups.has(affix.group)) addIssue(issues, 'INVALID_AFFIX_GROUP', `Повторяется группа аффиксов ${affix.group}.`, item.itemId);
      affixGroups.add(affix.group);
    }
  }
  if (!equipment.MAIN) addIssue(issues, 'MISSING_MAIN', 'Для боя требуется основное оружие.');
  if (equipment.MAIN && !validTemplates.get('MAIN')?.weapon) addIssue(issues, 'MISSING_WEAPON_BLOCK', 'У основного предмета отсутствуют параметры оружия.', equipment.MAIN.itemId);

  const skills: SkillDef[] = [];
  for (const id of skillIds) {
    const skill = SKILL_BY_ID[id];
    if (!skill) {
      addIssue(issues, 'UNKNOWN_SKILL', `Неизвестное умение ${id}.`, id);
      continue;
    }
    skills.push(skill);
    for (const requirement of skill.requires ?? []) {
      const satisfied = requirement === 'MAIN_K'
        ? validTemplates.get('MAIN')?.weapon?.type === 'KINETIC'
        : requirement === 'SIDEARM'
          ? validTemplates.get('OFFHAND')?.weapon?.sidearmOnly === true
          : requirement === 'DR_MED'
            ? ['DRONE_1', 'DRONE_2'].some((slot) => validTemplates.get(slot as EquipSlotId)?.drone?.role === 'medic')
            : requirement === 'DR_EMP'
              ? ['DRONE_1', 'DRONE_2'].some((slot) => validTemplates.get(slot as EquipSlotId)?.drone?.role === 'emp')
              : requirement === 'VIRUS'
                ? true // Target status is checked by combat at cast time.
                : false;
      if (!satisfied) addIssue(issues, 'SKILL_REQUIREMENT', `${skill.name}: не выполнено требование ${requirement}.`, id);
    }
  }
  const passives: PassiveDef[] = [];
  for (const id of passiveIds) {
    const passive = PASSIVE_BY_ID[id];
    if (!passive) addIssue(issues, 'UNKNOWN_PASSIVE', `Неизвестный пассивный протокол ${id}.`, id);
    else passives.push(passive);
  }
  const mutations = mutationIds.map((id) => MUTATION_BY_ID[id]).filter((x) => {
    if (!x) addIssue(issues, 'UNKNOWN_MUTATION', 'Неизвестная мутация.');
    return !!x;
  });

  const earnedTreePoints = input.treePointsEarned ?? 0;
  if (!Number.isInteger(earnedTreePoints) || earnedTreePoints < 0) addIssue(issues, 'TREE_POINTS', 'Полученные очки дерева должны быть целыми и неотрицательными.');
  if (earnedTreePoints > 60) addIssue(issues, 'TREE_POINTS_CAP', 'Нельзя получить более 60 силовых очков дерева.');
  if (treeNodeIds.length > 60 || treeNodeIds.length > earnedTreePoints) addIssue(issues, 'TREE_POINTS', `Распределено ${treeNodeIds.length} узлов при ${earnedTreePoints} полученных очках.`);
  if (new Set(treeNodeIds).size !== treeNodeIds.length) addIssue(issues, 'DUPLICATE_TREE_NODE', 'Узел дерева указан более одного раза.');
  const pendingTree = [...new Set(treeNodeIds)];
  const selectedTree: string[] = [];
  const unresolvedTree = new Set<string>();
  for (const id of pendingTree) if (!TREE_BY_ID[id]) {
    addIssue(issues, 'UNKNOWN_TREE_NODE', `Неизвестный узел дерева ${id}.`, id);
    unresolvedTree.add(id);
  }
  let treeProgress = true;
  while (treeProgress) {
    treeProgress = false;
    for (const id of pendingTree) {
      if (selectedTree.includes(id) || unresolvedTree.has(id)) continue;
      const reason = nodeLockReason(id, selectedTree, earnedTreePoints - selectedTree.length);
      if (!reason) {
        selectedTree.push(id);
        treeProgress = true;
      }
    }
  }
  for (const id of pendingTree) if (!selectedTree.includes(id) && !unresolvedTree.has(id)) {
    const reason = nodeLockReason(id, selectedTree, earnedTreePoints - selectedTree.length);
    if (TREE_BY_ID[id]?.keystone && keystoneCount(selectedTree) >= 2) {
      addIssue(issues, 'KEYSTONE_LIMIT', `${id}: ${reason ?? 'достигнут лимит двух keystone'}.`, id);
    } else {
      addIssue(issues, 'TREE_LOCKED', `${id}: ${reason ?? 'не выполнены требования дерева'}.`, id);
    }
  }
  if (keystoneCount(selectedTree) > 2) addIssue(issues, 'KEYSTONE_LIMIT', 'Можно изучить не более двух keystone узлов.');
  const treeNodes = selectedTree.map((id) => TREE_BY_ID[id]!);

  const modifiers: Modifier[] = [];
  const effects: EffectDef[] = [];
  const triggerEffects: ResolvedTriggerEffect[] = [];
  const addEffect = (effect: EffectDef, source: { id: string; name: string; kind: SourceKind }, id: string, valueOverride?: number) => {
    effects.push(effect);
    if (effect.type === 'trigger') triggerEffects.push({ effect, sourceId: source.id, sourceName: source.name, sourceKind: source.kind });
    if (effect.type === 'stat') modifiers.push(statModifier(effect, source, valueOverride ?? effect.value, id));
  };
  addAttributeModifiers(attributes, modifiers);

  const mainItem = equipment.MAIN;
  const mainTemplate = mainItem ? validTemplates.get('MAIN') : undefined;
  const mainWeapon = mainItem && mainTemplate ? resolveWeapon(mainItem, mainTemplate) : undefined;
  if (mainWeapon) modifiers.push(mod('techPower', 'FLAT', techPower(mainWeapon.damage, mainWeapon.techLevel), {
    id: `${mainWeapon.itemId}:tech-power`, name: mainTemplate!.name, kind: 'item',
  }));
  const sidearmItem = equipment.OFFHAND;
  const sidearmTemplate = sidearmItem ? validTemplates.get('OFFHAND') : undefined;
  const sidearm = sidearmItem && sidearmTemplate?.weapon?.sidearmOnly ? resolveWeapon(sidearmItem, sidearmTemplate) : undefined;
  const drones: ResolvedDrone[] = [];

  for (const slot of EQUIPMENT_SLOTS) {
    const item = equipment[slot];
    const template = validTemplates.get(slot);
    if (!item || !template) continue;
    const sourceKind: SourceKind = template.uniqueEffectId ? 'unique' : 'item';
    const source = { id: item.itemId, name: template.name, kind: sourceKind };
    if (slot === 'ARMOR' && template.armorBlock) {
      const condition = item.durability < 25 ? 0.75 : 1;
      modifiers.push(mod('maxHP', 'FLAT', template.armorBlock.hp * D(item.techLevel), source, { id: `${item.itemId}:armor-hp` }));
      modifiers.push(mod('maxShield', 'FLAT', template.armorBlock.shield * D(item.techLevel) * condition, source, { id: `${item.itemId}:armor-shield` }));
      modifiers.push(mod('armor', 'FLAT', template.armorBlock.armor * condition, source, { id: `${item.itemId}:armor-flat` }));
    }
    const baseEffects = template.effects;
    for (const [i, effect] of baseEffects.entries()) {
      const value = effect.type === 'stat' ? scaleItemEffect(effect, template, item, attributes.SYN) : undefined;
      addEffect(effect, source, `${item.itemId}:effect:${i}`, value);
    }
    for (const roll of item.affixes) {
      const definition = AFFIX_BY_ID[roll.affixId];
      if (!definition) continue;
      const effect = affixEffect(roll);
      const affixSource = { id: `${item.itemId}:${roll.affixId}`, name: definition.name, kind: 'affix' as const };
      const value = scaleItemEffect(effect, template, item, attributes.SYN);
      addEffect(effect, affixSource, `${affixSource.id}:${roll.tier}`, value);
    }
    if (template.category === 'DRONE') {
      const resolvedDrone = resolveDrone(item, template);
      if (resolvedDrone) drones.push(resolvedDrone);
      else addIssue(issues, 'MISSING_WEAPON_BLOCK', `У дрона ${template.name} отсутствуют параметры.`, item.itemId);
    }
  }

  for (const skill of skills) {
    // Эффекты активных умений применяются покадрово при касте (пробитие «только
    // этот удар», баффы длительности, ON_HIT-триггеры), а не как постоянные статы.
    for (const effect of skill.extraEffects ?? []) {
      effects.push(effect);
      if (effect.type === 'trigger') triggerEffects.push({ effect, sourceId: skill.id, sourceName: skill.name, sourceKind: 'skill' });
    }
  }
  for (const passive of passives) {
    const source = { id: passive.id, name: passive.name, kind: 'passive' as const };
    for (const [i, effect] of passive.effects.entries()) addEffect(effect, source, `${passive.id}:effect:${i}`);
  }
  for (const treeNode of treeNodes) {
    const source = { id: treeNode.id, name: treeNode.name, kind: 'tree' as const };
    for (const [i, effect] of treeNode.effects.entries()) addEffect(effect, source, `${treeNode.id}:effect:${i}`);
  }
  for (const mutation of mutations) {
    const source = { id: mutation.id, name: mutation.name, kind: 'mutation' as const };
    for (const [i, effect] of mutation.effects.entries()) addEffect(effect, source, `${mutation.id}:effect:${i}`);
  }

  const flagContext: StatContext = {
    ...input.context,
    flags: {
      ...(input.context?.flags ?? {}),
      mainKinetic: mainTemplate?.weapon?.type === 'KINETIC' ? 1 : 0,
      weaponShotgun: mainTemplate?.tags.includes('shotgun') ? 1 : 0,
    },
    uniques: [...new Set([
      ...(input.context?.uniques ?? []),
      ...Object.values(equipment).flatMap((item) => item?.uniqueEffectIds ?? []),
    ])],
  };
  const statResults = resolveStats(bundle(modifiers), flagContext);
  const stats = sheetOf(statResults);
  const implantCost = Object.entries(equipment)
    .filter(([slot]) => slot.startsWith('IMP_'))
    .reduce((sum, [, item]) => sum + (item?.neuralCost ?? 0), 0);
  if (implantCost > stats.neuralCapacity) addIssue(issues, 'NEURAL_CAPACITY', `Импланты требуют ${implantCost} нейроёмкости при лимите ${stats.neuralCapacity}.`);

  return {
    valid: issues.length === 0,
    attributes,
    equipment,
    stats,
    statResults,
    mainWeapon,
    sidearm,
    drones,
    skills,
    skillIds,
    passives,
    passiveIds,
    treeNodes,
    treeNodeIds,
    mutationIds,
    effects,
    triggerEffects,
    modifiers,
    issues,
  };
}
