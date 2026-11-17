import { templateOf, type ItemInstance } from '../items/items';
import { resolveRunBuild } from './build';
import type { SaveGame } from '../save/schema';
import type { RunState } from './types';

export function runCargoUnits(items: readonly ItemInstance[]): number {
  return items.reduce((total, item) => total + templateOf(item).cargoUnits, 0);
}

/** Cargo capacity is a resolved road stat, including CARGO modules and cargo affixes. */
export function runCargoCapacity(save: SaveGame, run: RunState | null | undefined = save.run): number {
  const build = resolveRunBuild(save, run);
  return build.valid ? Math.max(0, Math.floor(build.stats.cargoUnits)) : 0;
}

export function canCarryRunItems(save: SaveGame, additions: readonly ItemInstance[], run: RunState | null | undefined = save.run): boolean {
  const capacity = runCargoCapacity(save, run);
  return runCargoUnits([...(run?.unsecuredCargo ?? []), ...additions]) <= capacity;
}

/** Keep rewards in deterministic order and return only items that fit in the remaining hold. */
export function fitRunCargo(save: SaveGame, run: RunState, additions: readonly ItemInstance[]): { accepted: ItemInstance[]; rejected: ItemInstance[] } {
  const capacity = runCargoCapacity(save, run);
  let used = runCargoUnits(run.unsecuredCargo);
  const accepted: ItemInstance[] = [];
  const rejected: ItemInstance[] = [];
  for (const item of additions) {
    const units = templateOf(item).cargoUnits;
    if (used + units <= capacity) {
      accepted.push(item);
      used += units;
    } else rejected.push(item);
  }
  return { accepted, rejected };
}
