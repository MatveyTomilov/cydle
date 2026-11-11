import Dexie, { type Table } from 'dexie';
import { parseSave, parseSaveExport, saveChecksum, type SaveGame } from './schema';

interface SaveSnapshot {
  key?: string;
  saveId: string;
  revision: number;
  createdAt: number;
  checksum: string;
  save: unknown;
}
interface SaveHead { id: 'active'; saveId: string; revision: number; snapshotKey: string }

class CydleSaveDatabase extends Dexie {
  snapshots!: Table<SaveSnapshot, string>;
  control!: Table<SaveHead, string>;

  constructor() {
    super('cydle-save');
    this.version(1).stores({ snapshots: '&key, saveId, revision, createdAt', control: '&id' });
  }
}

const database = new CydleSaveDatabase();

export type LoadSaveResult =
  | { kind: 'empty' }
  | { kind: 'loaded'; save: SaveGame; recovered: boolean }
  | { kind: 'corrupt'; reason: string };

function checkedSnapshot(row: SaveSnapshot): SaveGame | null {
  const parsed = parseSave(row.save);
  if (!parsed.success || parsed.data.saveId !== row.saveId || parsed.data.revision !== row.revision) return null;
  // Verify the exact stored payload before returning a normalized legacy save.
  if (saveChecksum(row.save as SaveGame) !== row.checksum) return null;
  return parsed.data;
}

export async function loadSave(): Promise<LoadSaveResult> {
  const [head, all] = await Promise.all([
    database.control.get('active'),
    database.snapshots.orderBy('createdAt').reverse().toArray(),
  ]);
  if (!head && all.length === 0) return { kind: 'empty' };

  const candidates = head
    ? all.filter((row) => row.saveId === head.saveId).sort((a, b) => b.revision - a.revision)
    : all;
  for (const row of candidates) {
    const save = checkedSnapshot(row);
    if (save) {
      const recovered = !!head && row.key !== head.snapshotKey;
      if (recovered) await database.control.put({ id: 'active', saveId: row.saveId, revision: row.revision, snapshotKey: row.key! });
      return { kind: 'loaded', save, recovered };
    }
  }
  return { kind: 'corrupt', reason: 'Не найден ни один целый снимок сохранения. Исходные данные оставлены в IndexedDB.' };
}

/** Validate first, then atomically append a checksummed snapshot and advance the active head. */
export async function commitSave(input: unknown, now = Date.now(), options: { rebase?: boolean } = {}): Promise<SaveGame> {
  const parsed = parseSave(input);
  if (!parsed.success) throw new Error(`Сохранение не прошло проверку: ${parsed.error}`);
  const candidate = parsed.data;
  return database.transaction('rw', database.snapshots, database.control, async () => {
    const head = await database.control.get('active');
    if (head?.saveId === candidate.saveId && head.revision !== candidate.revision && !options.rebase) {
      throw new Error(`Конфликт сохранения: ожидалась ревизия ${candidate.revision}, активна ${head.revision}. Перечитайте сейв перед записью.`);
    }
    const revision = head?.saveId === candidate.saveId ? head.revision + 1 : candidate.revision;
    const save = { ...candidate, revision, updatedAt: Math.max(candidate.updatedAt, now) };
    const snapshot: SaveSnapshot = {
      key: `${save.saveId}:${String(revision).padStart(12, '0')}:${globalThis.crypto.randomUUID()}`,
      saveId: save.saveId,
      revision,
      createdAt: save.updatedAt,
      checksum: saveChecksum(save),
      save,
    };
    await database.snapshots.put(snapshot);
    await database.control.put({ id: 'active', saveId: save.saveId, revision, snapshotKey: snapshot.key! });
    const history = await database.snapshots.where('saveId').equals(save.saveId).sortBy('revision');
    const valid = history.filter((row) => checkedSnapshot(row)).sort((a, b) => a.revision - b.revision || a.createdAt - b.createdAt);
    const stale = valid.slice(0, Math.max(0, valid.length - 2));
    if (stale.length) await database.snapshots.bulkDelete(stale.map((row) => row.key!));
    return save;
  });
}

export function exportSaveText(save: SaveGame): string {
  const checked = parseSave(save);
  if (!checked.success) throw new Error(`Сохранение не прошло проверку: ${checked.error}`);
  return JSON.stringify({ format: 'CYDLE_SAVE_EXPORT_V1', checksum: saveChecksum(checked.data), save: checked.data }, null, 2);
}

export async function importSaveText(text: string): Promise<SaveGame> {
  let value: unknown;
  try { value = JSON.parse(text) as unknown; }
  catch { throw new Error('Файл не содержит корректный JSON.'); }
  const parsed = parseSaveExport(value);
  if (!parsed.success) throw new Error(parsed.error);
  return commitSave(parsed.data, Date.now(), { rebase: true });
}
