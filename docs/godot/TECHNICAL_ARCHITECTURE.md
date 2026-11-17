# CYDLE Godot Technical Architecture

**Status:** approved project direction; the native Godot app has an integrated garage-to-expedition loop with road, combat, rewards and checkpoint continuation. Campaign/endgame acceptance and several broader systems remain incomplete.
**Target:** standalone Windows game, with an architecture that can be exported to Steam and used on Steam Deck.
**Reviewed:** 2026-11-12.

## Engine and language

- Pin development and CI to **Godot 4.7.2 stable**. Upgrade only to a newer stable patch/minor after the import, headless, golden, and Windows export checks pass. Do not use beta or development builds for release work.
- Use GDScript with explicit types on fields, parameters, return values, loop variables, and collections wherever Godot supports them. Treat untyped declarations, unsafe casts, and warnings in domain code as defects; any deliberate exception needs a local explanation.
- Use the built-in 2D, scene, animation, shader, particle, input, and UI systems. Do not add Rust or a GDExtension without a reproducible profile showing a material bottleneck.
- Keep the existing TypeScript application in the repository as frozen legacy/reference material. The playable product is `game/project.godot`; do not extend React/Vite/PixiJS as the product.

Godot's official archive lists 4.7.2 as stable, while 4.8 is beta as of this review. The GDScript typing guide documents typed custom classes, collections, and warnings: [release archive](https://godotengine.org/download/archive/), [static typing](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html).

## Project layout

```text
game/
  project.godot
  scenes/                 # composition and presentation only
    app/
    garage/
    road/
    combat/
    shared/
  scripts/
    app/                  # command dispatch and state projection
    core/                 # deterministic, headless rules
      math/ combat/ items/ builds/ progression/ world/ road/
      events/ quests/ economy/ autopilot/ simulation/ persistence/
    presentation/        # scene adapters, animation, sound, VFX
  data/                   # versioned typed resources and localization
  assets/                 # imported game assets; see ASSET_PIPELINE.md
  tests/                  # headless unit, golden, replay, integration tests
  tools/                  # validation, catalog conversion, asset checks
```

The root `src/`, `tests/`, `package.json`, and TypeScript configuration remain the legacy/reference implementation. `docs/archive/CYDLE_MASTER_SPEC_v1.3.md` also remains historical. Neither is the product entry point.

## Runtime boundaries

### Deterministic domain core

The domain core owns all outcomes: stats and CalcTrace, item rolls, build validation, combat, status and trigger resolution, road generation, node choices, rewards, progression, autopilot decisions, and offline simulation. Core operations accept typed state/commands/configuration and return new state plus domain events and failures. They do not read wall-clock time, input devices, scene nodes, animation progress, audio state, or global mutable singletons.

Combat uses the existing 100 ms logical step and authored integer millisecond timestamps. Presentation may run at any render FPS, pause, play at ×1/×2/×4, or skip animation without changing the simulated result. A headless `simulate_combat()` and an animated combat scene call the same core transition.

Port the current `src/core/rng.ts` algorithm and stream separation into a typed `DeterministicRng`. Preserve explicit 32-bit masks and serialized stream state; do not substitute `RandomNumberGenerator` for gameplay randomness. Golden tests compare fixed inputs, seeds, intermediate values, final hashes, and domain events with the legacy reference. Changes to balance or PRNG algorithm require a versioned decision.

### Application and persistence

An application/command layer validates user intent, applies one domain command, computes a stable state hash, commits the result, and then publishes events to the UI. UI signals never mutate domain objects directly. Commands and grants are idempotent across duplicate signals and process restarts.

`SaveRepository` owns local slots under Godot's platform user-data directory (`user://`), schema/balance versions, validation, checksums, temporary writes, last-good backups, import/export, and recovery. It stores plain versioned data, not scene trees or Node paths. A failed parse/write preserves the previous valid save and reports recovery choices. See [Godot's save-game guide](https://docs.godotengine.org/en/latest/tutorials/io/saving_games.html); CYDLE adds atomic versioned snapshots and validation beyond that basic example.

There is no automatic compatibility promise between the old browser IndexedDB/Dexie save and the new native save. The old implementation remains available for rule comparison. Any save converter must be a separately tested, explicit migration tool and must preserve the original export.

### Data and content

Balance/content definitions are versioned typed data, validated at startup and in headless CI. IDs stay stable across UI, save, and replay data. Keep localized Russian presentation text separate from technical IDs. Port catalog values from the TypeScript reference; do not silently adjust numerical values while translating data.

### Godot presentation

- Use `Control` scenes for garage, road, inventory, Build Lab, Simulation Lab, reports, and settings.
- Use `Node2D` scenes for the side-view arena, actor rigs, layered biome backgrounds, timeline, and VFX.
- Scene scripts translate domain events into animation/audio. They cannot decide hits, loot, costs, AI choices, phase changes, or rewards.
- Animation tracks and particle/shader lifetimes use presentation time. The combat event timestamp remains authoritative.
- Use keyboard/mouse as the baseline and full controller navigation for Steam Deck. Actions must not depend on hover. Window resizing must retain access to the core loop.

## Determinism, save, and threading invariants

1. Equal state + command + content version + seed produces equal state hash and ordered domain events.
2. Render frame rate, animation state, pause/fast-forward presentation, window focus, and audio do not alter domain outcomes.
3. Active, offline, autopilot, Build Lab, and Simulation Lab call the same math/build/combat/world functions.
4. Random streams are named and serialized; content generation does not depend on render order or dictionary iteration order.
5. File writes are validate-before-promote; repeated rewards and commands cannot duplicate grants.
6. Threads are an optimization boundary only. Start offline and batch simulation synchronously for correctness; move immutable input batches to Godot's worker-thread facilities only after profiling. Never access the active SceneTree or mutate live save state from a worker.

## Tests and build gates

Use a small in-repository GDScript headless runner first; avoid making a test plugin a runtime dependency. Tests are regular typed scripts under `game/tests/` and exit nonzero on a failed assertion. CI and local gates:

```powershell
godot --headless --path game --editor --quit
godot --headless --path game --script res://tests/run_tests.gd
godot --headless --path game --export-release "Windows Desktop" build/CYDLE.exe
```

The first command imports and parses the project; the second runs unit/golden/integration tests; the third exports the standalone build. Exact CLI flags and export preset names must be verified against the pinned engine when the project scaffold is committed. Tests must compare against known TypeScript outputs, include seed replays and save round-trips, and never replace failing expectations with new outputs without review.

## Legacy handoff and migration order

The web code is a reference oracle and test corpus, not a second supported release. Keep the prior commits intact. Port vertical slices into `game/` with golden tests, then route every consumer through the same GDScript core. The order is: project/test/save foundation; math and RNG; item/build; combat; first visual slice; road/economy/content; campaign/endgame; autopilot/offline; Build Lab/Simulation Lab; art/audio and release acceptance. Do not begin a broad content port before the golden test harness catches drift.

## Decision record

| Decision | Reason |
|---|---|
| Godot 4.7.2 stable, pinned and reviewed before updates | Current stable release at this checkpoint; avoids beta engine risk. |
| Strictly typed GDScript | Native Godot workflow while catching schema drift early. |
| One GDScript domain engine | Active play, offline, advisor, and lab must share game rules. |
| Keep web project frozen in the same repository | Preserves Qwen/Luna results as reference and golden oracle without making two products. |
| Windows first; Steam/Steam Deck ready by architecture | Matches standalone PC decision and avoids mobile-web constraints. |
| No Rust/GDExtension until measured | Avoids premature native integration and split debugging. |
