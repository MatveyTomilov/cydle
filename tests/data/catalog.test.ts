import { describe, expect, it } from 'vitest';
import { AFFIXES } from '../../src/data/affixes';
import { BIOMES } from '../../src/data/biomes';
import { BOSSES, ENEMIES } from '../../src/data/enemies';
import { EVENTS } from '../../src/data/events';
import { ITEM_TEMPLATES } from '../../src/data/items';
import { QUESTS } from '../../src/data/quests';
import { SKILLS, PASSIVES } from '../../src/data/skills';
import { TREE_NODES } from '../../src/data/tree';
import { UNIQUES } from '../../src/data/uniques';

const assertUniqueIds = (ids: string[]) => expect(new Set(ids).size).toBe(ids.length);

describe('master-spec content catalog', () => {
  it('contains the declared minimum catalog counts with unique IDs', () => {
    expect(ITEM_TEMPLATES.length).toBeGreaterThanOrEqual(24);
    expect(SKILLS.length).toBeGreaterThanOrEqual(24);
    expect(PASSIVES).toHaveLength(10);
    expect(TREE_NODES).toHaveLength(100);
    expect(UNIQUES).toHaveLength(18);
    expect(ENEMIES).toHaveLength(24);
    expect(BOSSES).toHaveLength(6);
    expect(EVENTS).toHaveLength(24);
    expect(QUESTS).toHaveLength(6);
    expect(BIOMES).toHaveLength(6);

    for (const defs of [ITEM_TEMPLATES, SKILLS, PASSIVES, TREE_NODES, UNIQUES, ENEMIES, BOSSES, EVENTS, QUESTS, BIOMES, AFFIXES]) {
      assertUniqueIds(defs.map((x) => x.id));
    }
  });
});
