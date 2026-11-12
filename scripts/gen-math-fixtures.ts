/**
 * Differential fixture generator for the CYDLE math core.
 *
 * Runs the frozen TypeScript oracle (src/core/math) and dumps comprehensive
 * input/output cases to game/tests/fixtures/math/*.json. The GDScript port is
 * replayed against these fixtures by game/tests/golden/math_differential_test.gd.
 *
 * Deterministic: a seeded PRNG drives randomized modifier bundles so the corpus
 * is reproducible. No balance values are invented — every expected output is
 * computed by the oracle itself.
 *
 * Run: npx tsx scripts/gen-math-fixtures.ts
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  STAT_REGISTRY, STAT_IDS, mod, bundle, computeStat, resolveStats, sheetOf,
  emptySheet, evalCondition, conditionText, conversionOrder,
  type StatId, type Modifier, type ConversionDef, type StatContext, type Condition,
} from '../src/core/math/stats';
import * as F from '../src/core/math/formula';
import * as D from '../src/core/math/damage';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', 'game', 'tests', 'fixtures', 'math');
mkdirSync(outDir, { recursive: true });

/* Reproducible PRNG (mulberry32). */
let seed = 0x9e3779b9;
function rnd(): number {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
function pick<T>(arr: T[]): T { return arr[Math.floor(rnd() * arr.length)]!; }
function range(lo: number, hi: number): number { return lo + rnd() * (hi - lo); }
function round2(v: number): number { return Math.round(v * 100) / 100; }

const KINDS = ['base', 'item', 'implant', 'attribute', 'tree', 'unique', 'skill', 'mutation', 'set'];
const OPS = ['BASE', 'FLAT', 'INCREASED', 'MORE', 'LESS', 'OVERRIDE', 'CAP', 'FLOOR'] as const;

function source(i: number) { return { id: `src${i}`, name: `Источник ${i}`, kind: pick(KINDS) as never }; }

/* ---------------- Conditions ---------------- */
const STATUS_IDS = ['BLEED', 'BURN', 'VIRUS', 'SHOCK', 'JAM', 'MARK', 'SCAN_MARK', 'DRONE_MARK', 'DRONE_JAM', 'GUARD', 'OVERCLOCK', 'ARMOR_BREAK', 'SHIELD_LEAK', 'BERSERK', 'CONTROLLED', 'STUN', 'ACC_BUFF', 'EVASION_BUFF', 'SHIELD_REGEN_BUFF'];

function randomCondition(depth = 0): Condition {
  const leaf: Condition[] = [
    { kind: 'always' },
    { kind: 'hpBelow', value: round2(range(0.1, 0.9)) },
    { kind: 'hpAbove', value: round2(range(0.1, 0.9)) },
    { kind: 'shieldBelow', value: round2(range(0.1, 0.9)) },
    { kind: 'energyAtLeast', value: round2(range(0, 100)) },
    { kind: 'energyBelow', value: round2(range(0, 100)) },
    { kind: 'heatAtLeast', value: round2(range(0, 100)) },
    { kind: 'heatAtMost', value: round2(range(0, 100)) },
    { kind: 'heatLockout' },
    { kind: 'targetStatus', status: pick(STATUS_IDS) as never, minStacks: Math.floor(range(1, 4)) },
    { kind: 'targetStatus', status: pick(STATUS_IDS) as never },
    { kind: 'targetNoStatus', status: pick(STATUS_IDS) as never },
    { kind: 'targetHpBelow', value: round2(range(0.1, 0.9)) },
    { kind: 'targetHpAbove', value: round2(range(0.1, 0.9)) },
    { kind: 'targetIsBoss' }, { kind: 'targetNotBoss' }, { kind: 'targetMechanical' }, { kind: 'targetAlone' },
    { kind: 'enemiesAtLeast', value: Math.floor(range(1, 5)) },
    { kind: 'dronesAlive', value: Math.floor(range(0, 3)) },
    { kind: 'otherDroneDead' }, { kind: 'bothDronesSameTarget' },
    { kind: 'firstSeconds', value: round2(range(1, 10)) },
    { kind: 'afterSeconds', value: round2(range(1, 10)) },
    { kind: 'flagAtLeast', key: pick(['hot', 'stacks', 'rage']), value: Math.floor(range(1, 5)) },
    { kind: 'flagTrue', key: pick(['hot', 'stacks', 'rage']) },
    { kind: 'hasUnique', id: pick(['U01', 'U04', 'U09', 'U12']) },
  ];
  if (depth < 2 && rnd() < 0.25) {
    const kind = pick(['not', 'all', 'any']);
    if (kind === 'not') return { kind: 'not', inner: randomCondition(depth + 1) };
    const inner = [randomCondition(depth + 1), randomCondition(depth + 1)];
    return { kind, inner } as Condition;
  }
  return pick(leaf);
}

function randomContext(): StatContext {
  const statuses: Record<string, number> = {};
  for (const s of STATUS_IDS) if (rnd() < 0.3) statuses[s] = Math.floor(range(0, 4));
  const tstatuses: Record<string, number> = {};
  for (const s of STATUS_IDS) if (rnd() < 0.3) tstatuses[s] = Math.floor(range(0, 4));
  return {
    self: { hp: round2(range(0, 300)), maxHP: 300, shield: round2(range(0, 75)), maxShield: 75, energy: round2(range(0, 100)), heat: round2(range(0, 100)), statuses: statuses as never, isDrone: rnd() < 0.2 },
    target: { hp: round2(range(0, 300)), maxHP: 300, shield: round2(range(0, 75)), maxShield: 75, energy: round2(range(0, 100)), heat: round2(range(0, 100)), statuses: tstatuses as never, isBoss: rnd() < 0.3, isMechanical: rnd() < 0.4 },
    enemiesAlive: Math.floor(range(0, 5)), dronesAlive: Math.floor(range(0, 3)),
    otherDroneDead: rnd() < 0.3, bothDronesSameTarget: rnd() < 0.3,
    timeMs: Math.floor(range(0, 12000)), heatLockout: rnd() < 0.3,
    flags: { hot: Math.floor(range(0, 5)), stacks: Math.floor(range(0, 5)), rage: Math.floor(range(0, 5)) },
    uniques: ['U01', 'U04', 'U09', 'U12'].filter(() => rnd() < 0.4),
  };
}

const conditionCases: unknown[] = [];
// Cover every leaf kind explicitly with a fixed context, plus randomized ones.
const fixedCtx: StatContext = {
  self: { hp: 40, maxHP: 100, shield: 10, maxShield: 50, energy: 25, heat: 90, statuses: { BURN: 2 } as never },
  target: { hp: 20, maxHP: 100, shield: 0, maxShield: 0, energy: 0, heat: 0, statuses: { BURN: 2, VIRUS: 0 } as never, isBoss: true, isMechanical: true },
  enemiesAlive: 1, dronesAlive: 2, otherDroneDead: true, bothDronesSameTarget: true,
  timeMs: 3000, heatLockout: true, flags: { hot: 3, stacks: 0, rage: 1 }, uniques: ['U01', 'U09'],
};
const explicitConditions: Condition[] = [
  { kind: 'always' }, { kind: 'hpBelow', value: 0.5 }, { kind: 'hpAbove', value: 0.5 },
  { kind: 'shieldBelow', value: 0.5 }, { kind: 'energyAtLeast', value: 25 }, { kind: 'energyBelow', value: 25 },
  { kind: 'heatAtLeast', value: 90 }, { kind: 'heatAtMost', value: 90 }, { kind: 'heatLockout' },
  { kind: 'targetStatus', status: 'BURN' as never, minStacks: 2 }, { kind: 'targetStatus', status: 'BURN' as never },
  { kind: 'targetStatus', status: 'VIRUS' as never, minStacks: 1 }, { kind: 'targetNoStatus', status: 'VIRUS' as never },
  { kind: 'targetNoStatus', status: 'BURN' as never }, { kind: 'targetHpBelow', value: 0.3 }, { kind: 'targetHpAbove', value: 0.3 },
  { kind: 'targetIsBoss' }, { kind: 'targetNotBoss' }, { kind: 'targetMechanical' }, { kind: 'targetAlone' },
  { kind: 'enemiesAtLeast', value: 1 }, { kind: 'dronesAlive', value: 2 }, { kind: 'otherDroneDead' }, { kind: 'bothDronesSameTarget' },
  { kind: 'firstSeconds', value: 3 }, { kind: 'afterSeconds', value: 3 }, { kind: 'flagAtLeast', key: 'hot', value: 3 },
  { kind: 'flagTrue', key: 'rage' }, { kind: 'flagTrue', key: 'stacks' }, { kind: 'hasUnique', id: 'U01' }, { kind: 'hasUnique', id: 'U04' },
  { kind: 'not', inner: { kind: 'hpBelow', value: 0.5 } },
  { kind: 'all', inner: [{ kind: 'hpBelow', value: 0.5 }, { kind: 'hasUnique', id: 'U01' }] },
  { kind: 'any', inner: [{ kind: 'hpAbove', value: 0.9 }, { kind: 'hasUnique', id: 'U09' }] },
];
for (const c of explicitConditions) {
  conditionCases.push({ condition: c, context: fixedCtx, expectedEval: evalCondition(c, fixedCtx), expectedText: conditionText(c) });
}
for (let i = 0; i < 160; i++) {
  const c = randomCondition();
  const ctx = randomContext();
  conditionCases.push({ condition: c, context: ctx, expectedEval: evalCondition(c, ctx), expectedText: conditionText(c) });
}

/* ---------------- Stat compute cases ---------------- */
// Trace IDs are process-global in TS but per-instance in GDScript and are
// excluded from canonical gameplay hashes, so strip them before comparing.
// JSON.stringify turns Infinity/NaN into null, so encode non-finite numbers as
// explicit sentinels to keep the computational trace contract verifiable.
function sanitizeTrace(node: unknown): unknown {
  if (Array.isArray(node)) return node.map(sanitizeTrace);
  if (node && typeof node === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(node as Record<string, unknown>)) {
      if (k === 'id') continue;
      out[k] = sanitizeTrace(v);
    }
    return out;
  }
  if (typeof node === 'number' && !Number.isFinite(node)) {
    if (Number.isNaN(node)) return 'NaN';
    return node > 0 ? 'Infinity' : '-Infinity';
  }
  return node;
}
function randomModifier(stat: StatId, i: number): Modifier {
  const d = STAT_REGISTRY[stat];
  let op = pick(OPS as unknown as string[]);
  // Bias toward operations meaningful for the stat type, but keep all ops represented.
  let value: number;
  switch (op) {
    case 'MORE': value = round2(range(0.5, 2.0)); break;
    case 'LESS': value = round2(range(0.0, 0.6)); break;
    case 'INCREASED': value = round2(range(-30, 80)); break;
    case 'OVERRIDE': value = round2(range(0, Math.max(10, d.base * 2))); break;
    case 'CAP': value = round2(range(0, Math.max(10, d.base * 3 + 50))); break;
    case 'FLOOR': value = round2(range(-10, Math.max(5, d.base))); break;
    case 'BASE': value = round2(range(-20, 60)); break;
    default: value = round2(range(-30, 80)); break; // FLAT
  }
  const extra: Partial<Modifier> = {};
  if (rnd() < 0.4) extra.condition = randomCondition();
  if (op === 'INCREASED' && rnd() < 0.5) extra.stackGroup = pick(['A', 'B', 'C', stat]);
  if (rnd() < 0.2) extra.synScalable = true;
  if (rnd() < 0.2) extra.note = 'тест';
  if (rnd() < 0.3) extra.stage = Math.floor(range(0, 3));
  return mod(stat, op as never, value, source(i), extra);
}

const statCases: unknown[] = [];
for (const stat of STAT_IDS) {
  // Empty bundle → base value.
  const baseResult = computeStat(stat, bundle([]));
  statCases.push({ name: `${stat}:base`, statId: stat, mods: [], conversions: [], context: {}, expectedValue: baseResult.value, expectedTrace: sanitizeTrace(baseResult.trace) });
  // Randomized bundles.
  for (let k = 0; k < 10; k++) {
    const n = 1 + Math.floor(rnd() * 5);
    const mods: Modifier[] = [];
    for (let i = 0; i < n; i++) mods.push(randomModifier(stat, i));
    const ctx = rnd() < 0.5 ? randomContext() : {};
    const b = bundle(mods);
    const r = computeStat(stat, b, ctx);
    statCases.push({ name: `${stat}:rand${k}`, statId: stat, mods, conversions: [], context: ctx, expectedValue: r.value, expectedTrace: sanitizeTrace(r.trace) });
  }
}
// Targeted edge cases: integer rounding, clamps, negative resistances, multiplier flats.
const edgeStats: Array<[StatId, Modifier[]]> = [
  ['bleedStackCap', [mod('bleedStackCap', 'FLAT', 2.6, source(0)), mod('bleedStackCap', 'FLAT', 1.4, source(1))]],
  ['scanRange', [mod('scanRange', 'FLAT', 1.5, source(0))]],
  ['energyRes', [mod('energyRes', 'FLAT', -80, source(0))]],
  ['energyRes', [mod('energyRes', 'FLAT', 200, source(0))]],
  ['critChance', [mod('critChance', 'FLAT', 200, source(0))]],
  ['moreKinetic', [mod('moreKinetic', 'MORE', 1.5, source(0)), mod('moreKinetic', 'LESS', 0.2, source(1)), mod('moreKinetic', 'FLAT', 0.3, source(2))]],
  ['maxHP', [mod('maxHP', 'OVERRIDE', 500, source(0)), mod('maxHP', 'FLAT', 50, source(1)), mod('maxHP', 'INCREASED', 20, source(2)), mod('maxHP', 'MORE', 1.1, source(3))]],
  ['armor', [mod('armor', 'CAP', 5, source(0)), mod('armor', 'FLAT', 100, source(1))]],
  ['armor', [mod('armor', 'FLOOR', 30, source(0)), mod('armor', 'FLAT', -100, source(1))]],
];
for (const [stat, mods] of edgeStats) {
  const r = computeStat(stat, bundle(mods));
  statCases.push({ name: `${stat}:edge${statCases.length}`, statId: stat, mods, conversions: [], context: {}, expectedValue: r.value, expectedTrace: sanitizeTrace(r.trace) });
}

/* ---------------- Conversion + full-sheet cases ---------------- */
function conv(from: StatId, to: StatId, ratio: number, i: number, policy: 'snapshot' | 'live' = 'live'): ConversionDef {
  return { id: `conv${i}`, from, to, ratio, sourceId: `csrc${i}`, sourceName: `Конверсия ${i}`, sourceKind: 'unique', policy, stage: 0 };
}
const conversionCases: unknown[] = [];
const convChains: ConversionDef[][] = [
  [conv('armor', 'evasion', 0.5, 0)],
  [conv('maxHP', 'maxShield', 0.1, 0), conv('maxShield', 'armor', 0.2, 1)],
  [conv('armor', 'evasion', 0.5, 0), conv('evasion', 'accuracy', 0.3, 1), conv('accuracy', 'critChance', 0.1, 2)],
  [conv('techPower', 'digitalDamage', 0.5, 0, 'snapshot')],
];
for (const conversions of convChains) {
  const mods = [mod('armor', 'FLAT', 20, source(0)), mod('maxHP', 'FLAT', 100, source(1)), mod('techPower', 'FLAT', 40, source(2))];
  const b = bundle(mods, conversions);
  const results = resolveStats(b);
  conversionCases.push({ name: `chain${conversionCases.length}`, mods, conversions, context: {}, expectedOrder: conversionOrder(conversions), expectedSheet: sheetOf(results) });
}
// Cycle rejection cases.
const cycles: ConversionDef[][] = [
  [conv('armor', 'evasion', 0.5, 0), conv('evasion', 'armor', 0.5, 1)],
  [conv('maxHP', 'maxShield', 0.1, 0), conv('maxShield', 'armor', 0.1, 1), conv('armor', 'maxHP', 0.1, 2)],
];
for (const conversions of cycles) {
  let error = '';
  try { conversionOrder(conversions); } catch (e) { error = (e as Error).message; }
  conversionCases.push({ name: `cycle${conversionCases.length}`, mods: [], conversions, context: {}, expectCycle: true, expectedErrorPrefix: 'Цикл конверсий' });
}
// A few randomized full-sheet cases for resolve_stats / sheet_of / empty_sheet parity.
for (let k = 0; k < 20; k++) {
  const mods: Modifier[] = [];
  for (let i = 0; i < 12; i++) mods.push(randomModifier(pick(STAT_IDS), i));
  const ctx = randomContext();
  const results = resolveStats(bundle(mods), ctx);
  conversionCases.push({ name: `sheet${k}`, mods, conversions: [], context: ctx, expectedSheet: sheetOf(results), expectedEmptySheet: emptySheet() });
}

/* ---------------- Formula cases ---------------- */
const formulaCases: unknown[] = [];
for (const t of [1, 2, 4, 8, 12, 20, 100, 1000, 0, -5, 1.5, 7.25]) {
  formulaCases.push({ fn: 'h_depth', args: [t], expected: F.H(t) });
  formulaCases.push({ fn: 'd_depth', args: [t], expected: F.D(t) });
  formulaCases.push({ fn: 'reward_scale', args: [t], expected: F.R(t) });
}
for (const lvl of [1, 2, 5, 10, 20, 50, 100, 0]) formulaCases.push({ fn: 'xp_required', args: [lvl], expected: F.xpRequired(lvl), integer: true });
for (const [w, t] of [[80, 4], [0, 1], [200, 12], [50.5, 8]] as const) formulaCases.push({ fn: 'tech_power', args: [w, t], expected: F.techPower(w, t) });
for (const [b, inc, more] of [[1000, 50, 1.2], [100, 0, 1], [1000, 0, 0], [500, 200, 2], [1000, -50, 1]] as const) formulaCases.push({ fn: 'attack_interval_ms', args: [b, inc, more], expected: F.attackIntervalMs(b, inc, more) });
for (const [b, r] of [[1000, 25], [100, 0], [5000, 80], [200, -50]] as const) formulaCases.push({ fn: 'cooldown_ms', args: [b, r], expected: F.cooldownMs(b, r) });
for (const [v, lo, hi] of [[5, 0, 10], [-5, 0, 10], [15, 0, 10], [0.5, 0, 1]] as const) formulaCases.push({ fn: 'clamp_value', args: [v, lo, hi], expected: F.clamp(v, lo, hi) });
for (const [s, n, z] of [[7, 10, 1.96], [0, 0, 1.96], [10, 10, 1.96], [3, 20, 2.576]] as const) { const r = F.wilsonInterval(s, n, z); formulaCases.push({ fn: 'wilson_interval', args: [s, n, z], expected: r }); }
for (const vals of [[9, 1, 5, 3], [1], [2, 4], []]) formulaCases.push({ fn: 'median', args: [vals], expected: F.median(vals) });
for (const [vals, q] of [[[0, 10, 20], 0.25], [[0, 10, 20], 0.5], [[5], 0.9], [[], 0.5]] as const) formulaCases.push({ fn: 'quantile', args: [vals, q], expected: F.quantile(vals as number[], q) });
for (const vals of [[2, 4, 8], [1], []]) formulaCases.push({ fn: 'mean', args: [vals], expected: F.mean(vals) });

/* ---------------- Damage cases ---------------- */
const damageCases: unknown[] = [];
for (const [acc, eva] of [[100, 20], [0, 0], [100, 0], [1, 1000], [500, 50], [-10, 20]] as const) damageCases.push({ fn: 'hit_probability', args: [acc, eva], expected: D.pHit(acc, eva) });
for (const c of [0, 5, 50, 95, 150, -10]) damageCases.push({ fn: 'crit_probability', args: [c], expected: D.pCrit(c) });
for (const [a, fp, pp] of [[100, 20, 0], [100, 0, 50], [10, 50, 0], [100, 20, 150], [0, 0, 0]] as const) damageCases.push({ fn: 'armor_effective', args: [a, fp, pp], expected: D.armorEffective(a, fp, pp) });
for (const ae of [0, 50, 100, 500, 5000]) damageCases.push({ fn: 'kinetic_reduction', args: [ae], expected: D.kineticReduction(ae) });
for (const [res, pp, fp] of [[50, 50, 5], [0, 0, 0], [-30, 0, 0], [75, 0, 100], [50, 150, 0], [20, 20, 50]] as const) damageCases.push({ fn: 'resistance_after_penetration', args: [res, pp, fp], expected: D.resistanceAfterPen(res, pp, fp) });

const defSets = [
  { armor: 100, energyRes: 50, digitalRes: 25 },
  { armor: 0, energyRes: 0, digitalRes: 0 },
  { armor: 500, energyRes: 75, digitalRes: -50 },
  { armor: 25, energyRes: -30, digitalRes: 60 },
];
const penSets = [
  D.ZERO_PEN,
  { armorPen: 20, armorPenPercent: 30, energyPen: 5, energyPenPercent: 50, digitalPen: 10, digitalPenPercent: 20 },
  { armorPen: 1000, armorPenPercent: 150, energyPen: 100, energyPenPercent: 200, digitalPen: 100, digitalPenPercent: 200 },
];
for (const type of ['KINETIC', 'ENERGY', 'DIGITAL'] as const) {
  for (const def of defSets) for (const pen of penSets) for (const raw of [100, 0, 55.5]) {
    const m = D.mitigatePacket(raw, type, def, pen);
    damageCases.push({ fn: 'mitigate_packet', args: [raw, type, def, pen], expected: { armorEff: m.armorEff, reduction: m.reduction, resistanceAfterPen: m.resistanceAfterPen, afterDefense: m.afterDefense, trace: sanitizeTrace(m.trace) } });
  }
}
const poolSets = [
  { hp: 100, shield: 10, temp: [{ sourceId: 'late', amount: 4, cap: 4, expiresAt: 20 }, { sourceId: 'early', amount: 5, cap: 5, expiresAt: 10 }] },
  { hp: 50, shield: 0, temp: [] },
  { hp: 0, shield: 100, temp: [] },
  { hp: 100, shield: 100, temp: [{ sourceId: 'b', amount: 10, cap: 10, expiresAt: 5 }, { sourceId: 'a', amount: 10, cap: 10, expiresAt: 5 }] },
  { hp: 200, shield: 50, temp: [{ sourceId: 'x', amount: 0, cap: 0, expiresAt: 1 }] },
];
for (const pools of poolSets) for (const bypass of [0, 0.25, 1, 1.5]) for (const mult of [1, 2, 0, 0.5]) for (const incoming of [20, 0, 500]) {
  const p = D.partitionDamage(incoming, pools, bypass, mult);
  damageCases.push({ fn: 'partition_damage', args: [incoming, pools, bypass, mult], expected: { shieldConsumed: p.shieldConsumed, hpLost: p.hpLost, bypassed: p.bypassed, overkill: p.overkill, tempConsumed: p.tempConsumed, trace: sanitizeTrace(p.trace) } });
}
for (const def of defSets) for (const type of ['KINETIC', 'ENERGY', 'DIGITAL'] as const) {
  damageCases.push({ fn: 'simple_ehp', args: [300, 75, def, type], expected: D.simpleEHP(300, 75, def, type) });
}

/* ---------------- Write ---------------- */
function write(name: string, data: unknown): void {
  const path = join(outDir, name);
  writeFileSync(path, JSON.stringify(data, null, 1));
  console.log(`wrote ${path} (${Array.isArray(data) ? data.length : '?'} cases)`);
}
write('condition_cases.json', conditionCases);
write('stat_cases.json', statCases);
write('conversion_cases.json', conversionCases);
write('formula_cases.json', formulaCases);
write('damage_cases.json', damageCases);
console.log(`registry: ${STAT_IDS.length} stats; MATH_VERSION=${F.TICK_MS}ms tick`);