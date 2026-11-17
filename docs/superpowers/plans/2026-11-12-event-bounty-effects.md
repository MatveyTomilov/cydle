# Event BOUNTY effects Implementation Plan

> **For agentic workers:** Use the existing native implementation workflow. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement EV14 and EV21 forced BOUNTY choices and their authored rewards.

**Architecture:** Persist the target/reward parameters in the run's pending encounter state. Promote the next selected ordinary COMBAT to BOUNTY in route selection and apply bonus currency/RARE roll in the existing combat reward path.

**Tech Stack:** TypeScript, Zod, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-12-event-bounty-effects-design.md`; normative rules are in `CYDLE_MASTER_SPEC.md` §20.1 and §19.1.

## Global Constraints

- Preserve deterministic RNG and one-time reward IDs.
- Use existing `rollItem` tables and the BOUNTY reward path; do not add a second engine.
- Keep event effects run-scoped and backward-compatible with old active saves.

## Review Focus

- Forced BOUNTY only replaces the next selected ordinary COMBAT node.
- EV14 applies exactly the authored 25% credit modifier, including biome reward bonuses.
- EV21 targets E21 and grants exactly one guaranteed RARE item roll without XP.

---

### Task 1: Persist and resolve the two BOUNTY variants

**Files:** `src/core/run/types.ts`, `src/core/run/schema.ts`, `src/core/run/run.ts`, `src/core/run/nodes.ts`, `src/core/run/graph.ts`, `src/core/run/commands.ts`, `src/core/run/combat.ts`, `tests/core/run-nodes.test.ts`, `tests/core/run-graph.test.ts`, `tests/core/run-combat.test.ts`.

- [x] Add failing tests for EV14/EV21 event state, map eligibility, node promotion, target enemy, credit bonus, rare item and one-time consumption.
- [x] Run focused tests and confirm expected failures.
- [x] Extend pending encounter state and interpret authored flags only for the EV21 target.
- [x] Promote the selected node and apply reward modifiers in the existing deterministic reward path.
- [x] Run focused tests, full suite, typecheck, validation, and build; update handoff/changelog/roadmap and commit code and docs separately.
