import type { ItemInstance } from '../items/items';
import type { StatResults, StatSheet } from '../math/stats';
import type { AttributeId, EquipSlotId } from '../types';
import type { EffectDef, PassiveDef, SkillDef, TreeNodeDef } from '../../data/types';

/** Stable input snapshot consumed by combat once the build resolver is implemented. */
export interface ResolvedBuild {
  valid: boolean;
  attributes: Record<AttributeId, number>;
  equipment: Partial<Record<EquipSlotId, ItemInstance>>;
  stats: StatSheet;
  statResults: StatResults;
  skills: SkillDef[];
  passives: PassiveDef[];
  treeNodes: TreeNodeDef[];
  effects: EffectDef[];
  issues: BuildIssue[];
}

export interface BuildIssue {
  code: 'UNKNOWN_ITEM' | 'INVALID_SLOT' | 'NEURAL_CAPACITY' | 'UNKNOWN_SKILL' | 'UNKNOWN_PASSIVE' | 'UNKNOWN_TREE_NODE' | 'TREE_LOCKED';
  message: string;
  sourceId?: string;
}
