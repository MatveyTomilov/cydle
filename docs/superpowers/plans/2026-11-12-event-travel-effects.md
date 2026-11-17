# Event travel effects Implementation Plan

> **For agentic workers:** Use the existing native implementation workflow. Steps use checkbox syntax for tracking.

**Goal:** Apply EV19's signed travel-time choice exactly once to the next valid road edge.

**Architecture:** Keep the effect in run-scoped state with a backward-compatible schema default. The event command stores it and `chooseRunNode` applies and clears it in the same validated transition.

**Tech Stack:** TypeScript, Zod, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-12-event-travel-effects-design.md`; normative design is `CYDLE_MASTER_SPEC.md` §20.1 and §16.

## Global Constraints

- Preserve deterministic behavior and existing active save compatibility.
- Travel duration changes must not alter combat time or fuel cost.
- Invalid commands must not mutate save state.

## Review Focus

- Old active-run save without the pending field parses as zero.
- Invalid route selection leaves the pending adjustment untouched.
- A large negative adjustment clamps travel time at zero.

---

### Task 1: Persist and apply the next-edge delta

**Files:** `src/core/run/types.ts`, `src/core/run/schema.ts`, `src/core/run/run.ts`, `src/core/run/nodes.ts`, `src/core/run/commands.ts`, `src/core/run/graph.ts`, `tests/core/run-nodes.test.ts`, `tests/core/run-graph.test.ts`.

- [x] Add failing tests for EV19 storing its delta, invalid route preserving it, successful route applying and consuming it, zero clamp, and legacy default.
- [x] Run the focused tests and confirm the intended failures.
- [x] Add `pendingTravelDeltaMs` with schema default zero; initialize it for new runs.
- [x] Apply and clear it atomically in `chooseRunNode`; enable EV19 in the eligible event filter.
- [x] Run focused tests, full unit suite, typecheck, validation, and build.
- [x] Update `HANDOFF.md`, `docs/ROADMAP.md`, and `CHANGELOG.md`; commit code, then documentation.
