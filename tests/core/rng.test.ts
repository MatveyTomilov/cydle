import { describe, expect, it } from 'vitest';
import { Rng, RngBank } from '../../src/core/rng';
import { createItem } from '../../src/core/items/items';

describe('deterministic random streams', () => {
  it('replays the same sequence for the same seed and stream', () => {
    const first = new Rng('combat', 'cydle-seed');
    const second = new Rng('combat', 'cydle-seed');

    expect(Array.from({ length: 20 }, () => first.next()))
      .toEqual(Array.from({ length: 20 }, () => second.next()));
  });

  it('continues from a serialized random state', () => {
    const rng = new Rng('loot', 'checkpoint');
    rng.next();
    rng.next();
    const restored = Rng.fromSerialized(rng.serialize());

    expect(Array.from({ length: 10 }, () => rng.next()))
      .toEqual(Array.from({ length: 10 }, () => restored.next()));
  });

  it('keeps named streams and keyed scenarios independent and reproducible', () => {
    const bank = new RngBank('root');
    const combat = bank.get('combat');
    const loot = bank.get('loot');
    const keyedA = bank.keyed('combat', 'scenario-4');
    const keyedB = bank.keyed('combat', 'scenario-4');

    expect(combat.next()).not.toBe(loot.next());
    expect(keyedA.next()).toBe(keyedB.next());
  });

  it('assigns the same item identity to the same reward grant on replay', () => {
    const makeItem = (grantId: string) => createItem(new Rng('loot', 'same-run'), {
      templateId: 'PISTOL_K1', techLevel: 1, rarity: 'COMMON', secured: false,
      originGrantId: grantId, origin: 'test',
    });

    expect(makeItem('grant-42').itemId).toBe(makeItem('grant-42').itemId);
    expect(makeItem('grant-42').itemId).not.toBe(makeItem('grant-43').itemId);
  });
});
