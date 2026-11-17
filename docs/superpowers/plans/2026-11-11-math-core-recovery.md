# Mathematical Core Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Qwen's work, repair the recovered math/type layer, and pass golden tests for the CYDLE v2.0 formulas.

**Architecture:** Keep the existing pure TypeScript math modules. Correct the shield-specific damage partition in `core/math/damage.ts`, repair only type/configuration blockers, and preserve a typed `ResolvedBuild` boundary for the future build resolver. No second engine or combat placeholder is added.

**Tech Stack:** TypeScript 5.6, Vitest 2, Vite 5, Node type declarations.

**Spec:** `CYDLE_MASTER_SPEC.md`, sections 4–7, 22.1, 23.2, 26.1–26.3, and 27.1.

## Global Constraints

- TypeScript strict; core remains deterministic and contains no `Math.random`.
- The 100 ms simulation tick and master-spec damage order remain unchanged.
- Percentages and trace values remain unrounded inside the engine.
- The same math module will serve combat, Build Lab, and Simulation Lab.
- Do not claim a simulator, save system, UI, or gameplay feature exists until implemented.

## Review Focus

- Shield-only damage modifiers must not increase bypassed or HP damage; test shield overflow and bypass.
- Negative/zero defenses and resistances at their documented clamps must remain finite; test physical and elemental extremes.
- INCREASED modifiers in one group sum, while MORE multipliers multiply; test the exact 5 armor example and trace result.
- Equal seeds and serialized RNG state must replay the same rolls; test round-trip and independent stream behavior.
- Data tables must not silently contain duplicate or unresolved IDs; add structural assertions for the declared catalog counts and links.

---

### Task 1: Pin CYDLE math and recovery invariants

**Files:**
- Create: `tests/core/math.test.ts`
- Create: `tests/core/rng.test.ts`
- Test: `src/core/math/stats.ts`, `src/core/math/damage.ts`, `src/core/rng.ts`

**Interfaces:** Consume existing exported functions; no production API changes in this task.

- [x] Write tests for the 5 armor → 6.0 and `(5 + 2) × 1.20 × 1.10 = 9.24` trace examples.
- [x] Write tests for armor reduction, resistance/penetration caps, shield then HP partition, shield-only multipliers, and bypass.
- [x] Write tests for seeded RNG replay, serialization round-trip, and deterministic item identity per grant.
- [x] Run the focused tests and confirm the shield-only multiplier test fails against current code.

### Task 2: Correct the shield-only damage partition

**Files:**
- Modify: `src/core/math/damage.ts`
- Modify: `src/core/items/items.ts`
- Test: `tests/core/math.test.ts`

**Interfaces:** Keep `partitionDamage(incoming, pools, bypassShieldRatio, incomingShieldMultiplier)` and `PoolPartition` unchanged.

- [x] Apply `incomingShieldMultiplier` only to non-bypassed damage while it is absorbed by temporary and permanent shields.
- [x] Convert any shield overflow back into its equivalent incoming damage before applying it to HP.
- [x] Preserve stable temporary-shield ordering and exact trace attribution.
- [x] Derive item identity from its idempotent reward grant instead of wall-clock time.
- [x] Run focused math tests and then the full Vitest suite.

### Task 3: Repair compile blockers without adding fake mechanics

**Files:**
- Create: `src/core/build/build.ts` (typed resolved-build contract only)
- Modify: `src/core/types.ts`
- Modify: `src/data/affixes.ts`
- Modify: `vite.config.ts`
- Modify: `tsconfig.json`
- Modify: `package.json`, `package-lock.json`
- Test: all `src/**/*.ts`

**Interfaces:** `ResolvedBuild` exposes validated combat stats, equipment, active skill/passive definitions, selected tree-node IDs, effects, and validation issues. Its resolver is explicitly outside this task; no runtime code may pretend that a build has been resolved.

- [x] Define the contract with references to existing `StatSheet`, `ItemInstance`, `SkillDef`, `PassiveDef`, and `EffectDef` types.
- [x] Import `StatId` from its actual math-module export and add only the missing target-mode literals already used by definitions.
- [x] Resolve Vite's source directory with ESM-safe URL handling and include installed Node typings.
- [x] Run `npm run typecheck` and the full Vitest suite. `npm run build` typechecks but then reports the missing real `src/main.tsx` entry point; do not add a placeholder.
- [ ] Commit the verified recovery stage.
