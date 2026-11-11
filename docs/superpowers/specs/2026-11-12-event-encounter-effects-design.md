# EV16 encounter effects design

## Intent

Make both EV16 choices work end to end: payment skips one ordinary COMBAT encounter without battle rewards; the alternative promotes the next ordinary COMBAT node to ELITE and guarantees one extra item roll.

## Approaches

1. Rewrite future graph layers when the event is selected. The player's route is not yet known, so this can alter an unreachable branch and fail to affect the chosen route.
2. Persist a run-scoped pending encounter effect; when a chosen node is an ordinary COMBAT, promote that selected node before it is shown/resolved. Resolve skip through the existing run combat command and clear pending effects after the encounter. **Selected.**
3. Special-case event IDs inside the combat engine. This couples event content to the simulator and makes the effect hard to test outside combat.

## Behavior

- `pendingNextCombat` stores `skipOrdinary`, `forceElite`, and `extraItemRoll`; old saves default all values to false.
- EV16 A costs its authored 12 unsecured credits and skips the next ordinary COMBAT. Travel fuel/time still apply; no simulator, XP, or combat loot is granted.
- EV16 B promotes the next selected ordinary COMBAT to ELITE using `EL_PEN`, and guarantees one extra item roll from that encounter's reward table.
- Effects persist over service/checkpoint transitions until the next combat encounter. Combat attempts consume them; unsupported `nextCombat` fields remain excluded from map generation.
- Encounter promotion occurs on the selected route transition, so the saved map/UI reflects the actual node before combat.

## Out of scope

No BOUNTY forcing, allied turret, unique rare guarantee, reveal, mutation, or quest effects.
