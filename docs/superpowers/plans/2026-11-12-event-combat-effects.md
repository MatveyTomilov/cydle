# Event combat effects Implementation Plan

> **For agentic workers:** Use the existing native implementation workflow. Steps use checkbox syntax for tracking.

**Goal:** Apply EV17 extra starting heat and EV24 temporary shield to the next combat exactly once.

**Architecture:** Store pending event values in a backward-compatible run-state object and pass them into the shared simulator's existing config fields. Clear the values only in the successful persisted result of a combat attempt.

**Tech Stack:** TypeScript, Zod, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-12-event-combat-effects-design.md`; normative event rules are in `CYDLE_MASTER_SPEC.md` §20.1.

## Global Constraints

- Keep event effects run-scoped and deterministic.
- Reuse the single shared combat simulator and its existing `initialExtraHeat` / `initialTempShield` configuration.
- Preserve old active-run saves by defaulting absent values to zero.

## Review Focus

- Invalid or duplicate combat commands do not consume effects.
- Effects are consumed after victory, defeat, and timeout alike.
- Unsupported deferred event values remain unavailable in generated event choices.

---

### Task 1: Persist and resolve the two authored combat effects

**Files:** `src/core/run/types.ts`, `src/core/run/schema.ts`, `src/core/run/run.ts`, `src/core/run/nodes.ts`, `src/core/run/graph.ts`, `src/core/run/combat.ts`, `src/core/combat/engine.ts`, `tests/core/run-nodes.test.ts`, `tests/core/run-graph.test.ts`, `tests/core/run-combat.test.ts`.

- [x] Add failing tests for event persistence, legacy defaults, eligible map generation, simulator input logging, and one-time consumption.
- [x] Run focused tests and confirm expected failures.
- [x] Add run-scoped pending values with zero defaults and store event-authored amounts.
- [x] Pass values into the existing simulator config, log applied values at combat start, and clear them in the combat result.
- [x] Permit only the supported deferred keys in generated event data.
- [x] Run focused tests, full suite, typecheck, validation, and build; update handoff/changelog/roadmap and commit code and docs separately.
