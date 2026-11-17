import { describe, expect, it } from 'vitest';
import { enumerateSectorPaths, generateSectorGraph } from '../../src/core/run/graph';

describe('deterministic sector graph', () => {
  it('places one shop node in each regular sector', () => {
    for (const depth of [2, 3, 5, 8, 12]) {
      const graph = generateSectorGraph({ seed: `shop-route-${depth}`, depth, biome: 'B01' });
      expect(graph.layers.flat().filter((node) => node.type === 'SHOP')).toHaveLength(1);
      expect(graph.layers.flat().find((node) => node.type === 'SHOP')?.lootHint).toContain('5 товаров');
    }
  });

  it('persists a deterministic real event on regular sector maps', () => {
    const input = { seed: 'event-map', depth: 2, biome: 'B03' as const };
    const graph = generateSectorGraph(input);
    const event = graph.layers.flat().find((node) => node.type === 'EVENT');
    expect(event?.eventId).toMatch(/^EV\d{2}$/);
    expect(generateSectorGraph(input)).toEqual(graph);
    const nextSector = generateSectorGraph({ ...input, seed: 'event-map-next', usedEventIds: [event!.eventId!] });
    expect(nextSector.layers.flat().find((node) => node.type === 'EVENT')?.eventId).not.toBe(event?.eventId);
  });

  it('can generate EV19 after its one-edge travel effects are supported', () => {
    const eventIds = new Set(Array.from({ length: 100 }, (_, index) => {
      const graph = generateSectorGraph({ seed: `ev19-availability-${index}`, depth: 2, biome: 'B03' });
      return graph.layers.flat().find((node) => node.type === 'EVENT')?.eventId;
    }));
    expect(eventIds.has('EV19')).toBe(true);
  });

  it('can generate EV05, EV14, EV16, EV17, EV18, EV21 and EV24 after their modeled effects are supported', () => {
    const eventIds = new Set(Array.from({ length: 120 }, (_, index) => {
      const graph = generateSectorGraph({ seed: `combat-event-availability-${index}`, depth: 2, biome: 'B03' });
      return graph.layers.flat().find((node) => node.type === 'EVENT')?.eventId;
    }));
    expect(eventIds.has('EV05')).toBe(true);
    expect(eventIds.has('EV14')).toBe(true);
    expect(eventIds.has('EV16')).toBe(true);
    expect(eventIds.has('EV17')).toBe(true);
    expect(eventIds.has('EV18')).toBe(true);
    expect(eventIds.has('EV21')).toBe(true);
    expect(eventIds.has('EV24')).toBe(true);
  });

  it('adds optional elite encounters and gates the single bounty option on wanted', () => {
    const quiet = Array.from({ length: 40 }, (_, index) => generateSectorGraph({ seed: `optional-${index}`, depth: 2, biome: 'B03' }));
    const hunted = Array.from({ length: 40 }, (_, index) => generateSectorGraph({ seed: `optional-${index}`, depth: 2, biome: 'B03', wanted: 60 }));
    expect(quiet.some((graph) => graph.layers.flat().some((node) => node.type === 'ELITE'))).toBe(true);
    expect(quiet.every((graph) => graph.layers.flat().every((node) => node.type !== 'BOUNTY'))).toBe(true);
    expect(hunted.some((graph) => graph.layers.flat().some((node) => node.type === 'BOUNTY'))).toBe(true);
    expect(hunted.every((graph) => graph.layers.flat().filter((node) => node.type === 'BOUNTY').length <= 1)).toBe(true);
  });

  it('keeps the authored first-sector tutorial sequence on every route', () => {
    const graph = generateSectorGraph({ seed: 'tutorial-pinned', depth: 1, biome: 'B01', tutorial: true });
    expect(graph.layers.map((layer) => layer.length)).toEqual([1, 2, 3, 3, 2, 1]);
    expect(graph.layers[0]![0]).toMatchObject({ type: 'COMBAT', enemies: [{ templateId: 'E01' }] });
    expect(graph.layers[1]!.every((node) => node.type === 'CACHE' && node.prototypeChoices?.length === 3)).toBe(true);
    expect(graph.layers[2]!.every((node) => node.type === 'COMBAT' && node.enemies.map((enemy) => enemy.templateId).join(',') === 'E01,E02')).toBe(true);
    expect(graph.layers[5]![0]?.type).toBe('CHECKPOINT');
    for (const path of enumerateSectorPaths(graph)) {
      expect(path.map((node) => node.type).slice(0, 3)).toEqual(['COMBAT', 'CACHE', 'COMBAT']);
    }
  });

  it('is reproducible for a seed and produces a reachable acyclic graph', () => {
    const input = { seed: 'same-seed', depth: 2, biome: 'B03' as const, tutorial: false };
    const graph = generateSectorGraph(input);
    expect(generateSectorGraph(input)).toEqual(graph);
    expect(generateSectorGraph({ ...input, seed: 'other-seed' })).not.toEqual(graph);
    expect(graph.layers.map((layer) => layer.length).slice(0, 3)).toEqual([1, 2, 3]);
    expect(graph.edges.every((edge) => edge.from === graph.startNodeId || edge.toLayer === edge.fromLayer + 1)).toBe(true);
    expect(graph.edges.filter((edge) => edge.from === graph.startNodeId).length).toBe(1);
    expect(graph.layers.flat().every((node) => graph.edges.some((edge) => edge.to === node.id))).toBe(true);
    expect(graph.layers.slice(0, -1).flat().every((node) => graph.edges.some((edge) => edge.from === node.id))).toBe(true);
    expect(graph.edges.reduce((max, edge) => Math.max(max, graph.edges.filter((out) => out.from === edge.from).length), 0)).toBeLessThanOrEqual(3);
  });

  it('guarantees combat and a resource opportunity on every reachable path', () => {
    for (const input of [
      { seed: 'a', depth: 1, biome: 'B01' as const, tutorial: true },
      { seed: 'b', depth: 2, biome: 'B03' as const, tutorial: false },
      { seed: 'c', depth: 4, biome: 'B01' as const, tutorial: false },
    ]) {
      const graph = generateSectorGraph(input);
      for (const path of enumerateSectorPaths(graph)) {
        expect(path.filter((node) => ['COMBAT', 'ELITE', 'BOUNTY', 'BOSS'].includes(node.type)).length).toBeGreaterThanOrEqual(2);
        expect(path.some((node) => ['REPAIR', 'FUEL', 'SHOP', 'CACHE'].includes(node.type))).toBe(true);
        expect(path.at(-1)?.type).toBe(input.depth % 4 === 0 ? 'BOSS' : 'CHECKPOINT');
      }
    }
  });
});
