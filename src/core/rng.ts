/**
 * Детерминированный PRNG. Никакого Math.random внутри core.
 * Алгоритм sfc32 с 128-битным состоянием, сериализуемый.
 * Потоки (combat/world/loot/quest) независимы: число бросков в одном
 * потоке не влияет на другие (common random numbers, раздел 24.3).
 */
export type RngState = [number, number, number, number];

export interface SerializedRng {
  stream: string;
  state: RngState;
  calls: number;
}

export const STREAMS = ['combat', 'world', 'loot', 'quest', 'sim'] as const;
export type StreamName = (typeof STREAMS)[number];

function hashSeed(str: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

export class Rng {
  readonly stream: string;
  private s: RngState;
  calls = 0;

  constructor(stream: string, seed: string | number) {
    this.stream = stream;
    const base = typeof seed === 'number' ? seed >>> 0 : hashSeed(String(seed));
    const a = (base ^ hashSeed(stream + ':a')) >>> 0;
    const b = (base ^ hashSeed(stream + ':b')) >>> 0;
    const c = (base ^ hashSeed(stream + ':c')) >>> 0;
    const d = (base ^ hashSeed(stream + ':d')) >>> 0;
    this.s = [a, b, c, d];
    for (let i = 0; i < 12; i++) this.next();
    this.calls = 0;
  }

  static fromSerialized(x: SerializedRng): Rng {
    const r = new Rng(x.stream, 0);
    r.s = [...x.state] as RngState;
    r.calls = x.calls;
    return r;
  }

  serialize(): SerializedRng {
    return { stream: this.stream, state: [...this.s] as RngState, calls: this.calls };
  }

  clone(): Rng {
    return Rng.fromSerialized(this.serialize());
  }

  /** uniform [0,1) */
  next(): number {
    this.calls++;
    let [a, b, c, d] = this.s;
    const t = (((a + b) | 0) + d) | 0;
    d = (d + 1) | 0;
    a = b ^ (b >>> 9);
    b = (c + (c << 3)) | 0;
    c = (c << 21) | (c >>> 11);
    c = (c + t) | 0;
    this.s = [a >>> 0, b >>> 0, c >>> 0, d >>> 0];
    return (t >>> 0) / 4294967296;
  }

  /** unsigned output for deterministic IDs that must not lose RNG entropy */
  nextUint32(): number {
    return Math.floor(this.next() * 4294967296) >>> 0;
  }

  /** целое в [min,max] включительно */
  int(min: number, max: number): number {
    if (max < min) return min;
    return min + Math.floor(this.next() * (max - min + 1));
  }

  range(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  chance(p: number): boolean {
    if (p <= 0) return false;
    if (p >= 1) return true;
    return this.next() < p;
  }

  pick<T>(arr: readonly T[]): T {
    if (arr.length === 0) throw new Error('Rng.pick: empty array');
    return arr[Math.floor(this.next() * arr.length)]!;
  }

  weighted<T>(entries: readonly { item: T; weight: number }[]): T {
    const total = entries.reduce((s, e) => s + Math.max(0, e.weight), 0);
    if (total <= 0) return entries[0]!.item;
    let roll = this.next() * total;
    for (const e of entries) {
      roll -= Math.max(0, e.weight);
      if (roll <= 0) return e.item;
    }
    return entries[entries.length - 1]!.item;
  }

  shuffle<T>(arr: T[]): T[] {
    const out = [...arr];
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(this.next() * (i + 1));
      const tmp = out[i]!;
      out[i] = out[j]!;
      out[j] = tmp;
    }
    return out;
  }
}

export class RngBank {
  private streams = new Map<string, Rng>();
  readonly rootSeed: string;

  constructor(rootSeed: string, serialized?: SerializedRng[]) {
    this.rootSeed = rootSeed;
    if (serialized) {
      for (const s of serialized) this.streams.set(s.stream, Rng.fromSerialized(s));
    }
  }

  get(stream: string): Rng {
    let r = this.streams.get(stream);
    if (!r) {
      r = new Rng(stream, this.rootSeed);
      this.streams.set(stream, r);
    }
    return r;
  }

  /** Сценарно-ключевой поток: одинаковый scenarioKey даёт одинаковые броски. */
  keyed(stream: string, key: string): Rng {
    return new Rng(`${stream}:${key}`, this.rootSeed);
  }

  serialize(): SerializedRng[] {
    return [...this.streams.values()].map((r) => r.serialize()).sort((a, b) => a.stream.localeCompare(b.stream));
  }

  clone(): RngBank {
    return new RngBank(this.rootSeed, this.serialize());
  }
}

export function seedToString(seed: number | string): string {
  return String(seed);
}

/** Стабильный числовой хеш состояния (FNV-1a по строке). */
export function hashString(str: string): string {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

export function stableStringify(value: unknown): string {
  return JSON.stringify(value, (_k, v) => {
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      const out: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) out[key] = (v as Record<string, unknown>)[key];
      return out;
    }
    return v;
  });
}

export function stateHash(value: unknown): string {
  return hashString(stableStringify(value));
}
