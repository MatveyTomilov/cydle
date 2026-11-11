import { describe, expect, it } from 'vitest';
import { createCombatState, simulateCombat, stepCombat } from '../../src/core/combat/engine';
import { createItem } from '../../src/core/items/items';
import { Rng, stateHash } from '../../src/core/rng';
import { resolveBuild } from '../../src/core/build/build';
import type { TacticalProfile } from '../../src/core/combat/types';

const item = (id: string, templateId: string) => createItem(new Rng('loot', id), {
  templateId, techLevel: 1, rarity: 'COMMON', secured: true, originGrantId: id, origin: 'test',
});

const build = () => resolveBuild({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: { MAIN: item('kernel-pistol', 'PISTOL_K1') },
  attributePointsEarned: 0,
  unlockedImplantSlots: 4,
  unlockedDroneSlots: 1,
});

const tactics: TacticalProfile = { id: 'test', name: 'test', rules: [] };

const config = (seed: string) => ({
  seed, depth: 1, biome: 'B01' as const, nodeType: 'COMBAT' as const,
  build: build(), enemies: [{ templateId: 'E01' }], tactics,
  maxDurationMs: 30000,
});

describe('deterministic combat kernel', () => {
  it('advances only fixed 100 ms ticks and regenerates resources once', () => {
    const state = createCombatState(config('tick'));
    const initialEnergy = state.operator.energy;
    const next = stepCombat(state);

    expect(next.timeMs).toBe(100);
    expect(next.operator.energy).toBe(initialEnergy + next.operator.baseSheet.energyRegen * 0.1);
    expect(state.timeMs).toBe(0);
  });

  it('uses deterministic attacks and resolves a combat to a terminal outcome', () => {
    const a = simulateCombat(config('repeatable'));
    const b = simulateCombat(config('repeatable'));

    expect(a.outcome).toBe('VICTORY');
    expect(a.metrics.damageDealt).toBeGreaterThan(0);
    expect(a.log.some((event) => event.kind === 'DAMAGE')).toBe(true);
    expect(stateHash(a)).toBe(stateHash(b));
  });

  it('refuses to initialize a build that failed resolver validation', () => {
    const invalid = build();
    invalid.valid = false;
    expect(() => createCombatState({ ...config('invalid'), build: invalid })).toThrow(/invalid/i);
  });
});
