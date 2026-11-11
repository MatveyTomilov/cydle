# First persisted sector — design

## Intent

Turn the existing deterministic combat core and save boundary into the first real CYDLE play loop: begin a run, traverse a reproducible sector, resolve an encounter through the existing combat engine, retain at-risk rewards, and settle them at checkpoint or defeat.

## Scope

- Add a validated `RunState` stored in the current save schema while continuing to load existing v1 saves whose `run` is `null`.
- Generate and persist the sector graph and world PRNG state before the first choice; refresh must not reroll it.
- Implement validated start, route, node, combat, reward, checkpoint, evacuation, and defeat transitions.
- Make the first sector's tutorial sequence and one complete six-layer sector playable from the React shell.
- Persist state after each accepted command using the existing transactional snapshot store.

## Invariants and non-goals

- `stepCombat` remains the only combat simulation engine; world/run code only constructs `CombatConfig` and consumes its result.
- World generation and loot use serializable deterministic RNG streams; no `Math.random` or hidden future information.
- No negative fuel/currency, duplicated grant, or irreversible partial settlement. Every command is validated before a state commit.
- Failed commands return a stable reason and leave the save byte-for-byte unchanged.
- Keep the existing save schema version 1 because the app is unreleased and `run: null` remains a valid older shape; the run object itself is Zod-validated.
- This stage does not implement multi-sector campaign continuation, full item/shop economy, autopilot/offline, quests, or Simulation Lab. Exit/defeat and replayable sector state are in scope.

## Approaches considered

1. Put road generation and rewards into `combat/engine.ts`. Rejected: it mixes world persistence with the single battle transition and violates the current architecture.
2. Persist only combat and infer the road from the seed after reload. Rejected: rule/content changes could reroll visible choices and violate save/replay guarantees.
3. Add a world/run domain module that owns a saved graph, commands, combat snapshots, and settlement, while calling the existing `simulateCombat`. Chosen: it makes each world transition testable and durable without duplicating combat math.

## Architecture

- `src/core/run/` defines Zod-backed save-compatible run types, pure deterministic graph generation, command validation/transitions, reward grant IDs, and combat integration.
- The save remains the authority. A command returns either a failure with the original save or a new candidate save plus domain events; the application persists the candidate before presenting success.
- Node graph is a six-layer DAG with the master-spec base widths and bounded optional side nodes. The sector-one tutorial is an explicit authored exception for its first three visited steps: E01 combat, prototype cache, then E01+E02 combat; the remaining sector nodes use seeded generation and guarantee repair/shop alternatives before the checkpoint.
- The app displays the committed graph and current combat/result; it does not perform world or battle arithmetic.

## Acceptance evidence

- Identical seed and inputs produce identical graph and state hash; reload keeps node IDs and edges.
- Graph property checks prove acyclicity, reachability, bounded outgoing degree, and every reachable path has two combat encounters plus at least one resource/safe node.
- Invalid route, no fuel, invalid node action, stale command, and duplicate grant leave state unchanged.
- A pinned first-sector seed can complete E01, select a tutorial prototype, resolve E01+E02, reach checkpoint, and either evacuate with secured rewards or be defeated with unsecured rewards lost and permanent gear damaged.
- Full unit suite, typecheck, data validation, production build, and at least one browser E2E smoke pass before declaring this stage complete. E2E remains gated on adding a test harness.
