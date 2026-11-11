import type { SourceKind } from '../types';

/** Типизированный CalcTrace (раздел 23.2). Никакого округления внутри движка. */
export type TraceOperation =
  | 'BASE'
  | 'ADD'
  | 'SUM'
  | 'MULTIPLY'
  | 'DIVIDE'
  | 'CLAMP'
  | 'CONVERT'
  | 'CONDITIONAL'
  | 'ROUND_DISPLAY'
  | 'RANDOM_SAMPLE';

export interface TraceNode {
  id: string;
  operation: TraceOperation;
  stage: string;
  inputs: number[];
  exactValue: number;
  sourceId: string;
  sourceName: string;
  sourceKind: SourceKind;
  conditionPredicate?: string;
  conditionActive?: boolean;
  unit: string;
  tags?: string[];
  localizedExplanation: string;
  formulaVersion: string;
  children?: TraceNode[];
  snapshot?: boolean;
}

export const FORMULA_VERSION = 'cydle-math-1.0';

let traceCounter = 0;
export function nextTraceId(prefix = 't'): string {
  traceCounter = (traceCounter + 1) % 1_000_000;
  return `${prefix}${traceCounter}`;
}

export function node(
  operation: TraceOperation,
  stage: string,
  exactValue: number,
  opts: Partial<TraceNode> & { sourceId?: string; sourceName?: string; localizedExplanation?: string } = {},
): TraceNode {
  return {
    id: opts.id ?? nextTraceId(),
    operation,
    stage,
    inputs: opts.inputs ?? [],
    exactValue,
    sourceId: opts.sourceId ?? 'engine',
    sourceName: opts.sourceName ?? 'Движок',
    sourceKind: opts.sourceKind ?? 'base',
    conditionPredicate: opts.conditionPredicate,
    conditionActive: opts.conditionActive,
    unit: opts.unit ?? '',
    tags: opts.tags,
    localizedExplanation: opts.localizedExplanation ?? '',
    formulaVersion: FORMULA_VERSION,
    children: opts.children,
    snapshot: opts.snapshot,
  };
}

/** Форматирование для UI: по умолчанию 2 знака, точные значения — по кнопке. */
export function fmt(v: number, exact = false, decimals = 2): string {
  if (!Number.isFinite(v)) return '—';
  if (exact) return String(v);
  const r = Math.round(v * 10 ** decimals) / 10 ** decimals;
  return String(r);
}

export function pct(v: number, exact = false): string {
  return `${fmt(v * 100, exact)}%`;
}
