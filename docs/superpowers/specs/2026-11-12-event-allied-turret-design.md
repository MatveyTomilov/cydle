# EV18 allied turret design

## Intent

Make EV18 A recruit an E08 turret for one following combat at 50% HP and damage. EV18 B already uses supported run currency effects.

## Approaches

1. Add turret logic to the combat engine. The engine already supports allies through `CombatConfig.allies`, so new engine behavior would duplicate an existing mechanism.
2. Store a run-scoped pending boolean and pass a scaled E08 ally through the current `simulateCombat` integration. **Selected.**
3. Add a persistent drone/equipment item. That would make a one-combat event reward permanent and alter loadout ownership.

## Behavior

- EV18 A stores `alliedTurret = true` in pending next-combat state.
- The next combat receives ally spec `{ templateId: 'E08', hpMult: 0.5, damageMult: 0.5 }` through `CombatConfig.allies`.
- `COMBAT_START` records ally count; the pending flag clears with the combat result, regardless of outcome.
- Legacy active saves default the new flag to false. EV18 remains unavailable until both choices validate.

## Out of scope

No permanent turret item, player control for the ally, changes to targeting, or modifications to the shared combat engine's ally rules.
