# EV18 allied turret Implementation Plan

> **For agentic workers:** Use the existing native implementation workflow. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the EV18 allied turret choice to one following combat.

**Architecture:** Persist one pending run flag, create an E08 ally spec at half HP and damage, and pass it into the existing run-to-combat adapter. The combat engine already creates and simulates allies.

**Tech Stack:** TypeScript, Zod, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-12-event-allied-turret-design.md`; normative event rule is in `CYDLE_MASTER_SPEC.md` §20.1.

## Global Constraints

- Reuse the existing single combat simulator and ally mechanism.
- Pending event effects stay in RUN and default safely for older saves.
- Resolve the combat deterministically with no separate RNG stream.

## Review Focus

- EV18 A creates exactly one allied E08 at 50% HP/damage.
- EV18 B remains an ordinary supported currency/reputation choice.
- The turret is consumed after one combat result, including defeat/timeout.

---

### Task 1: Wire EV18 through the existing ally path

**Files:** `src/core/run/types.ts`, `src/core/run/schema.ts`, `src/core/run/run.ts`, `src/core/run/nodes.ts`, `src/core/run/graph.ts`, `src/core/run/combat.ts`, `src/core/combat/engine.ts`, `tests/core/run-nodes.test.ts`, `tests/core/run-graph.test.ts`, `tests/core/run-combat.test.ts`.

- [x] Add failing tests for event state, generated map eligibility, allied simulator input/log, and one-time consumption.
- [x] Run focused tests and confirm the intended failures.
- [x] Add backward-compatible pending flag and store it on EV18 A.
- [x] Pass the scaled E08 through `CombatConfig.allies`; include ally count in `COMBAT_START` data.
- [x] Permit EV18 only while both choices are supported; run full verification and update/commit feature and docs separately.
