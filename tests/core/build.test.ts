import { describe, expect, it } from 'vitest';
import { createItem } from '../../src/core/items/items';
import { H } from '../../src/core/math/formula';
import { Rng } from '../../src/core/rng';
import { resolveBuild, type BuildLoadout } from '../../src/core/build/build';
import { tierForTech } from '../../src/data/affixes';

const makeItem = (templateId: string, grantId: string, techLevel = 1, rarity: 'COMMON' | 'UNIQUE' = 'COMMON') =>
  createItem(new Rng('loot', grantId), {
    templateId, techLevel, rarity, secured: true, originGrantId: grantId, origin: 'test',
  });

const starterLoadout = (): BuildLoadout & { equipment: NonNullable<BuildLoadout['equipment']> } => ({
  attributes: { POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 },
  equipment: {
    MAIN: makeItem('PISTOL_K1', 'starter-main'),
    OFFHAND: makeItem('OFF_SHIELD', 'starter-offhand'),
    ARMOR: makeItem('ARM_CLOTH', 'starter-armor'),
    IMP_2: makeItem('IMP_ARMOR', 'starter-implant-armor'),
    IMP_3: makeItem('IMP_REFLEX', 'starter-implant-reflex'),
  },
  skillIds: ['SK_BURST', 'SK_SHIELD', 'SK_EMP'],
  passiveIds: ['PP_ACCURACY', 'PP_SHIELD'],
  treeNodeIds: [],
  mutationIds: [],
  attributePointsEarned: 0,
  treePointsEarned: 0,
  unlockedImplantSlots: 4,
  unlockedDroneSlots: 1,
});

describe('resolveBuild', () => {
  it('preserves trigger source identity for equipped items and active skills', () => {
    const loadout = starterLoadout();
    loadout.equipment.DRONE_1 = makeItem('DR_ARC', 'arc-trigger-drone');
    loadout.skillIds = ['SK_NEURO'];
    const result = resolveBuild(loadout);
    const droneTrigger = result.triggerEffects.find((entry) => entry.effect.id === 'DR_ARC_shock');
    const skillTrigger = result.triggerEffects.find((entry) => entry.effect.id === 'SK_NEURO_virus');

    expect(droneTrigger).toMatchObject({ sourceId: loadout.equipment.DRONE_1!.itemId, sourceKind: 'item' });
    expect(skillTrigger).toMatchObject({ sourceId: 'SK_NEURO', sourceKind: 'skill' });
  });

  it('resolves the canonical starter equipment and exposes exact combat stats', () => {
    const input = starterLoadout();
    const before = structuredClone(input);
    const result = resolveBuild(input);

    expect(result.valid).toBe(true);
    expect(result.stats.maxHP).toBe(320);
    expect(result.stats.maxShield).toBe(120);
    expect(result.stats.armor).toBeCloseTo(8.4, 12);
    expect(result.stats.accuracy).toBe(115);
    expect(result.mainWeapon?.damage).toBe(34);
    expect(result.mainWeapon?.type).toBe('KINETIC');
    expect(result.stats.techPower).toBeCloseTo(0.65 * 34 + 0.35 * 30, 12);
    expect(result.equipment.MAIN?.itemId).toBe(input.equipment.MAIN!.itemId);
    expect(input).toEqual(before);
  });

  it('applies declared attribute deltas and SYN only to tagged implant modifiers', () => {
    const input = starterLoadout();
    input.attributes = { POW: 6, REF: 6, INT: 6, ENG: 6, SYN: 6 };
    input.attributePointsEarned = 5;
    const result = resolveBuild(input);

    expect(result.valid).toBe(true);
    expect(result.stats.kineticDamage).toBeCloseTo(2, 12);
    expect(result.stats.armorPen).toBe(0.5);
    expect(result.stats.attackSpeed).toBeCloseTo(13.68, 12);
    expect(result.stats.evasion).toBe(31.5);
    expect(result.stats.accuracy).toBeCloseTo(115.3, 12);
    expect(result.stats.digitalDamage).toBeCloseTo(2.5, 12);
    expect(result.stats.energyDamage).toBeCloseTo(1, 12);
    expect(result.stats.droneDamage).toBeCloseTo(2.5, 12);
    expect(result.stats.droneHP).toBeCloseTo(2, 12);
    expect(result.stats.repairPower).toBeCloseTo(1, 12);
    expect(result.stats.neuralCapacity).toBe(102);
    expect(result.stats.armor).toBeCloseTo(8.421, 12);
  });

  it('scales weapon damage by H(T) without mutating the item definition', () => {
    const item = makeItem('RIFLE_K2', 'rifle-T5', 5);
    const input = starterLoadout();
    input.equipment.MAIN = item;
    const result = resolveBuild(input);

    expect(result.mainWeapon?.damage).toBeCloseTo(52 * H(5), 12);
    expect(result.stats.techPower).toBeCloseTo(0.65 * 52 * H(5) + 0.35 * 30 * H(5), 12);
    expect(item.techLevel).toBe(5);
    expect(result.valid).toBe(true);
  });

  it('uses the exact H(T) and affix-tier boundaries at T4, T5, T12, and T13', () => {
    for (const techLevel of [4, 5, 12, 13]) {
      const input = starterLoadout();
      input.equipment.MAIN = makeItem('RIFLE_K2', `rifle-boundary-${techLevel}`, techLevel);
      const result = resolveBuild(input);
      expect(result.mainWeapon?.damage).toBeCloseTo(52 * H(techLevel), 12);
    }
    expect([4, 5, 8, 9, 12, 13].map(tierForTech)).toEqual([1, 2, 2, 3, 3, 4]);
  });

  it('applies the durability boundary at 25 without changing the original rolls', () => {
    const input = starterLoadout();
    const armor = input.equipment.ARMOR!;
    const weapon = input.equipment.MAIN!;
    armor.durability = 24;
    weapon.durability = 24;
    const at24 = resolveBuild(input);
    armor.durability = 25;
    weapon.durability = 25;
    const at25 = resolveBuild(input);

    expect(at24.stats.maxHP).toBe(320);
    expect(at24.stats.maxShield).toBe(117.5);
    expect(at24.stats.armor).toBeCloseTo(7.8, 12);
    expect(at24.stats.evasion).toBe(29);
    expect(at24.mainWeapon?.damage).toBeCloseTo(30.6, 12);
    expect(at25.stats.maxShield).toBe(120);
    expect(at25.stats.armor).toBeCloseTo(8.4, 12);
    expect(at25.stats.evasion).toBe(30);
    expect(at25.mainWeapon?.damage).toBe(34);
    expect(armor.durability).toBe(25);
  });

  it('keeps conditional item effects inactive until their combat flag is present', () => {
    const input = starterLoadout();
    input.equipment.MAIN = makeItem('RIFLE_K2', 'first-attack-rifle');
    const beforeAttack = resolveBuild(input);
    const firstAttack = resolveBuild({ ...input, context: { flags: { firstAttack: 1 } } });

    expect(beforeAttack.stats.armorPen).toBe(0);
    expect(firstAttack.stats.armorPen).toBe(10);
    expect(firstAttack.statResults.armorPen.trace.children?.some((x) => x.conditionActive)).toBe(true);
  });

  it('validates tree ownership independent of saved selection order', () => {
    const input = starterLoadout();
    input.treeNodeIds = ['K2A', 'K1B', 'K1A'];
    input.treePointsEarned = 3;
    const result = resolveBuild(input);

    expect(result.valid).toBe(true);
    expect(result.treeNodeIds).toEqual(['K2A', 'K1B', 'K1A']);
  });

  it('keeps explicit repair-cost penalties as negative reduction values', () => {
    const input = starterLoadout();
    input.equipment.CHASSIS = makeItem('TR_CHASSIS_2', 'repair-cost-chassis');
    const result = resolveBuild(input);

    expect(result.valid).toBe(true);
    expect(result.stats.repairCostLess).toBe(-10);
  });

  it('rejects incompatible or locked equipment and a missing main weapon', () => {
    const input = starterLoadout();
    input.equipment.IMP_1 = makeItem('IMP_ARMOR', 'wrong-head-slot');
    input.equipment.IMP_5 = makeItem('IMP_REGEN', 'locked-neural-slot');
    delete input.equipment.MAIN;
    const result = resolveBuild(input);

    expect(result.valid).toBe(false);
    expect(result.issues.map((x) => x.code)).toEqual(expect.arrayContaining(['INVALID_SLOT', 'LOCKED_SLOT', 'MISSING_MAIN']));
  });

  it('rejects skill/passive overflow and unknown IDs without dropping selections', () => {
    const input = starterLoadout();
    input.skillIds = ['SK_BURST', 'SK_SHIELD', 'SK_EMP', 'SK_GUARD', 'NO_SKILL'];
    input.passiveIds = ['PP_ARMOR', 'PP_ACCURACY', 'PP_AMMO', 'PP_HEAT'];
    const result = resolveBuild(input);

    expect(result.valid).toBe(false);
    expect(result.issues.map((x) => x.code)).toEqual(expect.arrayContaining(['UNKNOWN_SKILL', 'SKILL_LIMIT', 'PASSIVE_LIMIT']));
    expect(result.skillIds).toEqual(input.skillIds);
    expect(result.passiveIds).toEqual(input.passiveIds);
  });

  it('rejects an item set over neural capacity and preserves all selected implants', () => {
    const input = starterLoadout();
    input.equipment = {
      MAIN: makeItem('PISTOL_K1', 'capacity-main'),
      IMP_1: makeItem('IMP_VIRUS', 'capacity-head'),
      IMP_2: makeItem('IMP_ARMOR', 'capacity-chest'),
      IMP_3: makeItem('IMP_REFLEX', 'capacity-arms'),
      IMP_4: makeItem('IMP_HP', 'capacity-universal'),
      IMP_5: makeItem('U05', 'capacity-drone-matrix', 1, 'UNIQUE'),
      IMP_6: makeItem('U16', 'capacity-command-thread', 1, 'UNIQUE'),
    };
    input.unlockedImplantSlots = 6;
    input.treePointsEarned = 0;
    const result = resolveBuild(input);

    expect(result.valid).toBe(false);
    expect(result.issues.map((x) => x.code)).toContain('NEURAL_CAPACITY');
    expect(result.equipment.IMP_6?.templateId).toBe('U16');
  });

  it('rejects tree nodes without earned points and unmet branch prerequisites', () => {
    const input = starterLoadout();
    input.treeNodeIds = ['K1A', 'K2A'];
    input.treePointsEarned = 2;
    const result = resolveBuild(input);

    expect(result.valid).toBe(false);
    expect(result.issues.map((x) => x.code)).toContain('TREE_LOCKED');
    expect(result.treeNodeIds).toEqual(input.treeNodeIds);
  });

  it('reports the dedicated limit when a third keystone is selected', () => {
    const input = starterLoadout();
    const branchPrefix = (branch: string) => [
      ...['A', 'B', 'C', 'D'].map((position) => `${branch}1${position}`),
      ...['A', 'B', 'C', 'D'].map((position) => `${branch}2${position}`),
      `${branch}3A`, `${branch}3B`,
      `${branch}4C`,
    ];
    input.treeNodeIds = [
      ...branchPrefix('K'),
      ...branchPrefix('H'),
      ...branchPrefix('N'),
    ];
    input.treePointsEarned = input.treeNodeIds.length;
    const result = resolveBuild(input);

    expect(result.valid).toBe(false);
    expect(result.issues.map((x) => x.code)).toContain('KEYSTONE_LIMIT');
  });

  it('limits active mutations to two', () => {
    const input = starterLoadout();
    input.mutationIds = ['MUT_SAFE', 'MUT_HEAT', 'MUT_WARD'];
    const result = resolveBuild(input);

    expect(result.valid).toBe(false);
    expect(result.issues.map((x) => x.code)).toContain('MUTATION_LIMIT');
    expect(result.mutationIds).toEqual(input.mutationIds);
  });
});
