/** Базовые скалярные функции мастер-ТЗ (разделы 9, 19). */

/** H(T) — масштаб урона оружия/программ/дронов и HP врагов глубины. */
export function H(T: number): number {
  return Math.pow(1 + 0.14 * Math.max(0, T - 1), 1.7);
}

/** D(T) — масштаб базовых HP/щитов носителя и урона врагов глубины. */
export function D(T: number): number {
  return Math.pow(1 + 0.08 * Math.max(0, T - 1), 1.5);
}

/** R(d) — масштаб кредитных/материальных наград. */
export function R(d: number): number {
  return Math.pow(1 + 0.06 * Math.max(0, d - 1), 1.4);
}

export function xpRequired(level: number): number {
  return Math.round(100 * Math.pow(level, 1.35));
}

/** TechPower активных программ (раздел 9). */
export function techPower(weaponBaseDamageAtT: number, T: number): number {
  return 0.65 * weaponBaseDamageAtT + 0.35 * 30 * H(T);
}

export const MIN_ATTACK_INTERVAL_MS = 150;
export const MIN_COOLDOWN_MS = 250;
export const TICK_MS = 100;
export const MAX_OFFLINE_MS = 12 * 60 * 60 * 1000;

export function attackIntervalMs(baseInterval: number, increasedPct: number, moreProduct: number): number {
  const v = baseInterval / (1 + increasedPct / 100) / Math.max(1e-9, moreProduct);
  return Math.max(MIN_ATTACK_INTERVAL_MS, v);
}

export function cooldownMs(baseCooldown: number, recoveryRatePct: number): number {
  return Math.max(MIN_COOLDOWN_MS, baseCooldown / (1 + recoveryRatePct / 100));
}

export function clamp(v: number, min: number, max: number): number {
  if (!Number.isFinite(v)) return min;
  return v < min ? min : v > max ? max : v;
}

export function finite(v: number, fallback = 0): number {
  return Number.isFinite(v) ? v : fallback;
}

/** Wilson score interval для доли (используется Simulation Lab). */
export function wilsonInterval(successes: number, n: number, z = 1.96): [number, number] {
  if (n === 0) return [0, 1];
  const p = successes / n;
  const denom = 1 + (z * z) / n;
  const centre = p + (z * z) / (2 * n);
  const margin = z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n));
  return [clamp((centre - margin) / denom, 0, 1), clamp((centre + margin) / denom, 0, 1)];
}

export function median(values: number[]): number {
  if (!values.length) return 0;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

export function quantile(values: number[], q: number): number {
  if (!values.length) return 0;
  const s = [...values].sort((a, b) => a - b);
  const pos = clamp(q, 0, 1) * (s.length - 1);
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return s[lo]! + (s[hi]! - s[lo]!) * (pos - lo);
}

export function mean(values: number[]): number {
  if (!values.length) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}
