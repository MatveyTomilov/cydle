import 'fake-indexeddb/auto';
import Dexie from 'dexie';
import { describe, expect, it } from 'vitest';
import { resolveBuild } from '../../src/core/build/build';
import { createInitialSave } from '../../src/core/save/initial';
import { commitSave, exportSaveText, importSaveText, loadSave } from '../../src/core/save/storage';
import { parseSave, parseSaveExport, saveChecksum } from '../../src/core/save/schema';

describe('save boundary', () => {
  it('creates the canonical equipped level-one operator without random variation', () => {
    const first = createInitialSave({ saveId: 'save-test', now: 1234 });
    const second = createInitialSave({ saveId: 'save-test', now: 1234 });
    expect(first).toEqual(second);
    expect(first.meta.inventory).toHaveLength(12);
    expect(first.meta.protectedBank).toEqual({ CREDITS: 120, SCRAP: 30, DATA: 20 });
    expect(first.meta.operator.attributes).toEqual({ POW: 5, REF: 5, INT: 5, ENG: 5, SYN: 5 });
    expect(first.meta.operator.attributePoints).toBe(0);
    expect(first.meta.operator.treePoints).toBe(0);
    expect(first.meta.transport).toEqual({ fuel: 24, fuelMax: 24, hull: 100, hullMax: 100, cargoCapacity: 20 });

    const byId = new Map(first.meta.inventory.map((item) => [item.itemId, item]));
    const equipment = Object.fromEntries(
      Object.entries(first.meta.equipment).map(([slot, itemId]) => [slot, byId.get(itemId)!]),
    );
    const build = resolveBuild({
      attributes: first.meta.operator.attributes,
      equipment,
      skillIds: first.meta.skillIds,
      passiveIds: first.meta.passiveIds,
      unlockedImplantSlots: first.meta.unlockedImplantSlots,
      unlockedDroneSlots: first.meta.unlockedDroneSlots,
      attributePointsEarned: first.meta.operator.attributePoints,
      treePointsEarned: first.meta.operator.treePoints,
    });
    expect(build.valid).toBe(true);
    expect(build.issues).toEqual([]);
  });

  it('validates imported data and rejects incompatible schema versions', () => {
    const save = createInitialSave({ saveId: 'save-test', now: 1234 });
    expect(parseSave(save).success).toBe(true);
    expect(parseSave({ ...save, schemaVersion: 2 }).success).toBe(false);
    expect(parseSave({ ...save, meta: { ...save.meta, protectedBank: { ...save.meta.protectedBank, CREDITS: -1 } } }).success).toBe(false);
    expect(parseSave({ ...save, meta: { ...save.meta, equipment: { ...save.meta.equipment, MAIN: 'missing-item' } } }).success).toBe(false);
    expect(parseSave({ ...save, meta: { ...save.meta, activeTacticId: 'missing-profile' } }).success).toBe(false);
    const envelope = { format: 'CYDLE_SAVE_EXPORT_V1', checksum: saveChecksum(save), save };
    expect(parseSaveExport(envelope).success).toBe(true);
    expect(parseSaveExport({ ...envelope, checksum: '00000000' }).success).toBe(false);
  });

  it('produces a stable checksum for exported save payloads', () => {
    const save = createInitialSave({ saveId: 'save-test', now: 1234 });
    expect(saveChecksum(save)).toBe(saveChecksum(structuredClone(save)));
    expect(saveChecksum(save)).not.toBe(saveChecksum({ ...save, revision: save.revision + 1 }));
  });

  it('commits atomically, keeps a valid fallback, and imports only verified exports', async () => {
    const saveId = `storage-${globalThis.crypto.randomUUID()}`;
    const first = await commitSave(createInitialSave({ saveId, now: 100 }), 100);
    expect(first.revision).toBe(1);

    const second = await commitSave({
      ...first,
      meta: { ...first.meta, protectedBank: { ...first.meta.protectedBank, CREDITS: 135 } },
    }, 200);
    expect(second.revision).toBe(2);
    expect(await loadSave()).toMatchObject({ kind: 'loaded', save: { revision: 2, meta: { protectedBank: { CREDITS: 135 } } }, recovered: false });

    const raw = new Dexie('cydle-save');
    raw.version(1).stores({ snapshots: '&key, saveId, revision, createdAt', control: '&id' });
    await raw.open();
    const latest = (await raw.table('snapshots').where('saveId').equals(saveId).toArray()).find((row: { revision: number }) => row.revision === 2);
    expect(latest).toBeDefined();
    await raw.table('snapshots').put({ ...latest, save: { ...latest.save, schemaVersion: 9 } });
    raw.close();

    const recovered = await loadSave();
    expect(recovered).toMatchObject({ kind: 'loaded', save: { revision: 1 }, recovered: true });
    if (recovered.kind !== 'loaded') throw new Error('Expected previous valid snapshot');
    const resumed = await commitSave(recovered.save, 300);
    expect(resumed.revision).toBe(2);
    expect(await loadSave()).toMatchObject({ kind: 'loaded', save: { revision: 2, meta: { protectedBank: { CREDITS: 120 } } }, recovered: false });

    const imported = await importSaveText(exportSaveText(resumed));
    expect(imported.revision).toBe(3);
    await expect(importSaveText(exportSaveText(resumed).replace('CYDLE_SAVE_EXPORT_V1', 'BAD_FORMAT'))).rejects.toThrow('Неизвестный формат');
  });
});
