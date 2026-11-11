# Deterministic combat kernel

## Intent

Introduce the first executable combat path that uses `ResolvedBuild`, the existing damage/defense functions, and the existing combat RNG stream. This kernel gives combat, headless simulation, and later UI playback one transition function.

## Scope

This phase implements initial actor creation, fixed 100 ms logical steps, operator/enemy auto-attacks, hit/crit rolls, defense and shield/HP partitioning, energy/heat/shield regeneration, event logging, deterministic completion, and a bounded result. Active skills, tactical rules, statuses, drones, and enemy abilities remain the next combat phases; they must be added to this kernel instead of a parallel simulator.

## Design

- `createCombatState(config)` validates the resolved build and enemy templates and initializes actors and the combat RNG stream.
- `stepCombat(state)` is the only state transition and advances exactly one 100 ms tick, applying continuous resource changes once before resolving due attacks.
- Attacks due on the same tick are snapshotted before damage and resolved in stable actor ID order. Stable event IDs are allocated from the state, not process-global counters.
- The operator uses the equipped resolved main weapon. Enemies use their catalog attack values. Both use `pHit`, `pCrit`, `mitigatePacket`, and `partitionDamage` from existing math modules.
- Damage is never recalculated in UI or simulation wrappers. The state transition records every attack, miss, damage, and death event.
- `simulateCombat(config)` repeatedly calls the same step function until a side wins or the max duration is reached.

## Invariants

- Same config and seed produce byte-identical state hashes, event IDs, and logs.
- Time is integer milliseconds and advances only in 100 ms increments.
- Inputs and catalog definitions are not mutated.
- Invalid builds cannot start combat.
- No `Math.random`, floating wall clock, or global sequence counter in combat.
- Damage flows through existing defense and shield partition functions exactly once.

## Normative references

`CYDLE_MASTER_SPEC.md` v2.0 sections 2, 4, 6, 7, 8, and 23.2.
