# EV05 elite contract Implementation Plan

> **For agentic workers:** Use the existing native implementation workflow. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply EV05 A's guaranteed RARE item roll to the next ELITE encountered during the run.

**Architecture:** Store a run-scoped elite-targeted boolean in pending encounter effects, preserve it across non-ELITE combat resolution, and consume it only when an ELITE attempt resolves.

**Tech Stack:** TypeScript, Zod, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-12-event-elite-contract-design.md`; normative event and loot rules are in `CYDLE_MASTER_SPEC.md` §20.1 and §19.1.

## Global Constraints

- Reuse deterministic loot RNG and `rollItem` with the authored ELITE reward table.
- Preserve EV05 target semantics: the first ELITE, not the next ordinary fight.
- Keep the state run-scoped and backward-compatible.

## Review Focus

- Ordinary combat does not consume or grant the elite contract.
- ELITE receives exactly one guaranteed RARE item, independent of ordinary ELITE loot chance.
- ELITE defeat/timeout consumes the contract without granting its item.

---

### Task 1: Implement the targeted elite contract

**Files:** `src/core/run/types.ts`, `src/core/run/schema.ts`, `src/core/run/run.ts`, `src/core/run/nodes.ts`, `src/core/run/graph.ts`, `src/core/run/combat.ts`, `tests/core/run-nodes.test.ts`, `tests/core/run-graph.test.ts`, `tests/core/run-combat.test.ts`.

- [x] Add failing tests for EV05 state/eligibility, persistence through ordinary combat, guaranteed RARE at ELITE, and clearing after the elite attempt.
- [x] Run focused tests and verify expected failures.
- [x] Add a backward-compatible `extraRareOnElite` pending field and interpret EV05 A's flag.
- [x] Apply/consume the reward only at ELITE; preserve the flag through other combat types.
- [x] Run focused tests, full suite, typecheck, validation, and build; update docs and commit code/docs separately.
