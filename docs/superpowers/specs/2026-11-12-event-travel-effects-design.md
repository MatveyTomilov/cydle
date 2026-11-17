# Event travel effect design

## Intent

Make EV19's route-time choice a real, deterministic effect in the existing road loop. The event must affect exactly one following edge, survive saving and loading, and remain scoped to the active run.

## Goals and constraints

- Apply the event's `travelDelta` after the canonical ENGINE travel adjustment.
- Clamp total edge travel time to zero or greater.
- Consume the effect only after a valid route choice succeeds.
- Keep existing v1 active-run saves readable when the new field is absent.
- Enable EV19 in generated road events only after both choices work.
- Keep travel computation in `chooseRunNode`; do not add another clock or simulation path.

## Approaches

1. Store the pending value in `meta.campaignFlags`. This avoids a run schema addition but mixes temporary run state with permanent campaign history and risks leaking the effect into later runs.
2. Store one signed millisecond delta in `RunState`, defaulting to zero when an older save is parsed. This keeps the effect run-scoped and lets the route transition consume it atomically. **Selected.**
3. Mutate every future edge in the generated graph. This makes effects visible in graph data but changes route structure and complicates exactly-once behavior.

## Behavior

Resolving an event with `travelDelta` adds it to `run.pendingTravelDeltaMs`. On a legal route choice, travel duration is `max(0, round(25000 × (1 - travelDurationLess / 100)) + pendingTravelDeltaMs)`, and the pending value resets to zero. Invalid route commands do not consume it. EV19 is added to the generated event pool because its other choice uses already-supported currency and reputation effects. Other events with unsupported effects remain filtered out.

## Out of scope

This step does not implement combat modifiers, node reveals, mutations, quest progress, or changing graph node types.

## Builder decisions

Use an integer `pendingTravelDeltaMs` field with schema default `0`; no save version bump is required for this additive field.
