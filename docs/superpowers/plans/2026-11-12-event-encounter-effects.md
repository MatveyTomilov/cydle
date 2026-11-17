# EV16 encounter effects Implementation Plan

> **For agentic workers:** Use the existing native implementation workflow. Steps use checkbox syntax for tracking.

**Goal:** Implement both EV16 choices, including their deferred encounter behavior and rewards.

**Architecture:** Store a small pending encounter-effect record in RunState. Apply forced ELITE status to the selected ordinary combat node in `chooseRunNode`; resolve skip in `resolveCurrentCombat`; grant the extra item roll in the existing combat reward path.

**Tech Stack:** TypeScript, Zod, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-12-event-encounter-effects-design.md`; normative event rules are in `CYDLE_MASTER_SPEC.md` §20.1.

## Global Constraints

- Preserve deterministic RNG and one-time command/reward semantics.
- Reuse route selection, combat resolution, and `rollItem`.
- Keep pending effects within a run; older active saves default to no effect.

## Review Focus

- EV16 A spends unsecured currency and gives no skipped-combat rewards.
- EV16 B changes only the next selected ordinary COMBAT and adds exactly one guaranteed extra item roll.
- Other combat types consume the pending event after the encounter without being skipped or promoted.

---

### Task 1: Persist and resolve EV16 encounter effects

**Files:** `src/core/run/types.ts`, `src/core/run/schema.ts`, `src/core/run/run.ts`, `src/core/run/nodes.ts`, `src/core/run/graph.ts`, `src/core/run/commands.ts`, `src/core/run/combat.ts`, `tests/core/run-nodes.test.ts`, `tests/core/run-graph.test.ts`, `tests/core/run-combat.test.ts`.

- [x] Add failing tests for event effects, map eligibility, route promotion, reward roll, skipped battle, and legacy defaults.
- [x] Run focused tests and confirm expected failures.
- [x] Add `pendingNextCombat` with false defaults and populate it from authored EV16 choices.
- [x] Promote selected COMBAT nodes when required; implement reward-free skip and one deterministic extra item roll.
- [x] Consume effects at the next combat attempt and allow only supported keys in generated events.
- [x] Run focused tests, full suite, typecheck, validation, and build; update handoff/changelog/roadmap and commit code and docs separately.
