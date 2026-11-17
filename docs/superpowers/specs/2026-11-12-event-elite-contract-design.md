# EV05 elite contract design

## Intent

Make EV05 A's hunt contract apply one guaranteed RARE item roll to the first later ELITE encounter, even if ordinary encounters happen before that ELITE.

## Approaches

1. Treat it as a generic next-combat modifier and consume it on any battle. That contradicts the event's authored target, the next ELITE.
2. Keep one run-scoped `extraRareOnElite` flag through ordinary combat attempts; grant one RARE roll and clear it when an ELITE encounter resolves. **Selected.**
3. Mutate every generated elite node in the graph. That creates multiple potential grants and modifies branches the player may not take.

## Behavior

- EV05 A persists a boolean `extraRareOnElite` in `pendingNextCombat`.
- Ordinary COMBAT, BOUNTY, or BOSS encounters do not consume it.
- The next ELITE victory gets one guaranteed RARE roll through the current deterministic `rollItem` reward path, then clears the flag.
- Defeat/timeout at an ELITE clears the contract without a reward; run termination also ends the pending flag.
- EV05 becomes eligible once its choices are supported; EV05 B retains its current scaled DATA reward.
- Older active runs default the flag to false.

## Out of scope

No forced elite spawn, reputation changes, or rarity effects on non-ELITE encounters.
