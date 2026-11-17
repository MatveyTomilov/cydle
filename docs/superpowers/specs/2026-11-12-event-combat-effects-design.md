# Event combat effects design

## Intent

Apply the two currently modeled `nextCombat` values that already have matching simulator inputs: EV17's +10 starting heat and EV24's +20 temporary shield. Enable those events only after both choices in each event are supported.

## Approaches

1. Change combat rules to apply bonuses from campaign flags. This mixes permanent progress with per-run temporary state and duplicates effect lookup inside the engine.
2. Persist a small run-scoped pending-effects object, pass its values through the existing `CombatConfig.initialExtraHeat` and `initialTempShield` inputs, and clear it after one combat attempt. **Selected.**
3. Modify the saved encounter or build stats. This risks changing reusable graph/build data and does not represent temporary one-combat state cleanly.

## Behavior and constraints

- `pendingCombatEffects` stores nonnegative `initialTempShield` and `extraHeat`; older active-run saves default both to zero.
- Event choices accumulate only authored `shieldBonus` and `extraHeat` values.
- `resolveCurrentCombat` sends these values to the existing simulator and clears them in the same persisted result, including defeat and timeout outcomes. Invalid combat commands do not consume them.
- `COMBAT_START` records the applied values so the combat log/replay explains the starting state.
- The generated-event filter permits these two `nextCombat` keys only; unsupported keys remain excluded.

## Out of scope

No forceElite/forceBounty, skip, allied turret, reward-roll, or other deferred effects are implemented here.
