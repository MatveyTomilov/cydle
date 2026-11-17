# Combat expansion 2d — enemy AI, phases, and elites

## Intent

Make the current enemy and boss catalog behavior executable in the existing deterministic `stepCombat` engine. Combat actors should use the ability data already authored in `src/data/enemies.ts`, telegraph dangerous actions, respond to interrupts, and produce correct damage, statuses, summons, and outcomes.

## Goals

- Schedule enemy abilities using each definition's `firstAtMs` and `everyMs`; preserve stable actor/ability ordering.
- Reuse the existing `CastState`, event log, `applyHit`, `applyStatus`, deterministic RNG, and target/fallback rules.
- Connect `HitOptions.bypassShieldRatio` to `partitionDamage` and prove the boss digital attack's bypass behavior.
- Implement boss phase triggers once per threshold and the CORE rotating sequence.
- Apply the six declared elite modifiers, including their limits and side effects.
- Cover abilities with deterministic transition tests and retain the one combat engine.

## Non-goals for this stage

Drone active abilities and generic trigger-chain execution are separate 2e work. Campaign spawn composition, loot, full world/run state, persistence, and UI are later roadmap stages.

## Approaches

1. Duplicate a standalone enemy simulator: rejected because combat, UI replay, and headless results would diverge.
2. Infer behavior from enemy descriptions: rejected because typed catalog data already defines executable values and inference would make balance untestable.
3. Add scheduler/resolution to the existing `stepCombat` state machine: selected. This preserves the deterministic event order and reuses the existing cast/interrupt/damage/status paths.

## Constraints and assumptions

- `CYDLE_MASTER_SPEC.md` v2.0 sections 4, 6–8, 17–18, and 27 are normative.
- Abilities never reveal a hit's future RNG result. Telegraph is emitted at cast start; interruption cancels the pending resolution.
- A dead/lost target is reacquired using the documented stable fallback; no target produces a fizzle event.
- Boss thresholds are one-shot and processed when crossed, even when one hit crosses multiple thresholds; ties use descending HP threshold then stable ID.
- Summons obey the spec's separate active/summoned caps; phase or ability scheduling cannot spawn an unbounded loop.
- Balance semantics not fully represented by the data must be recorded as a ruling and surfaced in tests; don't silently invent hidden stats.

## Files and boundaries

- `src/core/combat/engine.ts`: schedule casts and resolve enemy abilities/phases/elites through existing state transitions.
- `src/core/combat/types.ts`: only add state fields needed for phase/elite idempotence or a clear event result.
- `tests/core/combat-ai.test.ts`: observable scheduler, telegraph, interrupt, targeting, phase, elite, and bypass behavior.
- `docs/ROADMAP.md`, the plan, and decisions ledger: completion and rulings.
