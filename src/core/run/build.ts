import { resolveBuild, type ResolvedBuild } from '../build/build';
import type { SaveGame } from '../save/schema';
import type { RunState } from './types';

/** Resolve the battle/build snapshot from the selected run loadout and all items it can legally use. */
export function resolveRunBuild(save: SaveGame, run: RunState | null | undefined = save.run): ResolvedBuild {
  const available = new Map([...save.meta.inventory, ...(run?.unsecuredCargo ?? [])].map((item) => [item.itemId, item]));
  const itemIdsBySlot = run?.equipment ?? save.meta.equipment;
  const equipment = Object.fromEntries(Object.entries(itemIdsBySlot).map(([slot, itemId]) => [slot, available.get(itemId)]));
  return resolveBuild({
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
}
