# Build Resolver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve and validate one CYDLE loadout through the existing stat engine and produce the exact data combat and Build Lab need.

**Architecture:** A pure `resolveBuild()` collects typed effects from the current catalog, adds declared attribute/equipment scaling, validates loadout constraints, then calls `resolveStats()` once. Definitions and input items stay immutable; no UI or combat-specific math is introduced.

**Tech Stack:** TypeScript 5.6, Vitest 2, current CYDLE data modules.

**Spec:** `CYDLE_MASTER_SPEC.md`, sections 5, 6, 9, 10, 11, 12, 14, 15, 22.1, 23.2, 26, 27.1.

## Global Constraints

- The only balance source is `CYDLE_MASTER_SPEC.md` v2.0.
- Do not round internal values or mutate source data.
- Runtime formulas go through `resolveStats()` and return its CalcTrace.
- A build with any issue cannot be used to start combat.
- No hard-coded copies of catalog effects or second damage/stat engine.

## Review Focus

- A tiered item at T4/T5/T13 uses the correct D/H and affix tier boundaries; pin both sides of each boundary.
- Durability 24 and 25 exercise the exact equipment-penalty boundary; verify item IDs and original rolls stay unchanged.
- An implant over neural capacity, or a compatible item in a locked slot, is rejected with stable reason codes.
- Tree allocations presented in an invalid order or with unmet cross-branch prerequisites are rejected without deleting the user's selection.
- Conditional effects without a target/runtime context remain inactive and visible in CalcTrace rather than silently becoming unconditional.

---

### Task 1: Specify the loadout resolver with red tests

**Files:**
- Create: `tests/core/build.test.ts`
- Modify: `src/core/build/build.ts`

**Interfaces:** `resolveBuild(input: BuildLoadout): ResolvedBuild`; `BuildLoadout` contains equipment by slot, base attributes, skill/passive/tree/mutation IDs, earned point totals, unlocked implant/drone counts, and optional `StatContext`.

- [x] Test the canonical starter build: HP 320, shield 120, armor 8.4, known weapon damage/type, and no input mutation.
- [x] Test attribute deltas (POW, REF, INT, ENG, SYN), including SYN scaling of only tagged implant effects.
- [x] Test T-level scaling, affix tier boundaries, armor durability 24/25, and a shield-specific shield penalty.
- [x] Test invalid slot, duplicate item ID, missing MAIN, neural over-capacity, unknown IDs, skill/passive caps, tree prerequisites/points/keystone cap, and mutation cap.
- [x] Confirm representative tests fail before implementation for the missing resolver.

### Task 2: Implement pure stat and equipment resolution

**Files:**
- Modify: `src/core/build/build.ts`
- Test: `tests/core/build.test.ts`

- [x] Add explicit item-slot compatibility and item-definition lookup with typed issues.
- [x] Gather base armor pools and weapon/drone blocks with H(T)/D(T), source names, and durability rules.
- [x] Collect stat and trigger effects from items, affixes, selected skills/passives/tree nodes/mutations, preserving provenance.
- [x] Apply the five attributes, D/H note scaling, implant SYN scaling, and selected context flags.
- [x] Resolve stats once; validate neural capacity against the resolved capacity and return CalcTrace.
- [x] Run the build tests and the entire Vitest suite.

### Task 3: Verify the resolver boundary

**Files:**
- Modify: `docs/superpowers/plans/2026-11-11-build-resolver.md`
- Test: full project test/typecheck

- [x] Run `npm test`, `npm run typecheck`, and `npm run build`; report the known missing `src/main.tsx` blocker for Vite build.
- [x] Review source mutation, contextual conditions, reference validation, and math provenance.
- [ ] Commit the verified build-resolver stage.
