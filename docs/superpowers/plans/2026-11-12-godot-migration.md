# CYDLE Godot Migration Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task-by-task. Keep the web implementation frozen as a reference. Each implementation task ends with a check and a focused commit.

**Goal:** Deliver CYDLE 1.0 as a native Godot 2D Windows game while preserving all game rules and using one deterministic GDScript simulation core.

**Architecture:** The root TypeScript project remains historical reference and golden oracle. A separate `game/` project owns the native product. Typed GDScript domain modules return deterministic state/events; Godot scenes display them, and all active/offline/lab consumers call that same core.

**Tech Stack:** Godot 4.7.2 stable, statically typed GDScript, Godot 2D scenes/resources, local versioned saves, in-repository headless test runner, Windows Desktop export.

**Spec:** `CYDLE_MASTER_SPEC.md`; `docs/godot/TECHNICAL_ARCHITECTURE.md`; `docs/godot/ART_BIBLE.md`; `docs/godot/ASSET_PIPELINE.md`.

## Global Constraints

- Use Godot 4.x stable; current pin is 4.7.2 stable.
- Preserve the single operator, up to two drones, deterministic automatic combat, 100 ms logical step, 12-sector campaign, and uncapped endgame.
- Do not change balance during the port; version any later measured balance change.
- Do not create a second math/combat implementation for UI, offline simulation, Build Lab, or Simulation Lab.
- Do not continue React/Vite/PixiJS product development; preserve the legacy project and its tests.
- Use only original or appropriately licensed art/audio and record every asset's provenance.
- Target Windows desktop first and support full controller navigation for Steam Deck.
- Do not add Rust/GDExtension without a measured performance case.

## Review Focus

- 32-bit PRNG overflow and serialized streams must match the TypeScript oracle; golden RNG and replay tests belong to Task 2.
- GDScript `Variant` inference or untyped collection values can weaken strict typing; import/static validation belongs to Task 1 and Task 2.
- Save failure during temp-write/promote must preserve the prior valid file; round-trip and fault-injection checks belong to Task 1.
- Animation timing must not affect combat outcomes or reward order; event replay checks belong to Tasks 4 and 5.
- Threaded offline work must not mutate live state or reorder deterministic results; immutable-batch comparison belongs to Task 9.

---

## Stage 1 — Decision and production documents (documentation checkpoint)

**Files:**
- Modify: `CYDLE_MASTER_SPEC.md`
- Modify: `HANDOFF.md`
- Modify: `docs/ROADMAP.md`
- Create: `docs/godot/TECHNICAL_ARCHITECTURE.md`
- Create: `docs/godot/ART_BIBLE.md`
- Create: `docs/godot/ASSET_PIPELINE.md`
- Create: `docs/godot/ASSET_MANIFEST.csv`

- [x] Remove obsolete browser/React/Vite/Pixi/IndexedDB/Worker requirements from the normative spec while preserving gameplay rules.
- [x] Define the current stable engine pin, code boundaries, save strategy, legacy reference role, test gates, and release target.
- [x] Establish the art direction, production stages, provenance rules, and first asset inventory.
- [x] Verify remaining web/mobile wording and review the complete documentation diff; this docs-only stage is committed before implementation.

## Stage 2 — Godot foundation

### Task 1: project shell, input, and headless checks

**Files:**
- Create: `game/project.godot`
- Create: `game/scenes/app/main.tscn`
- Create: `game/scripts/app/app_root.gd`
- Create: `game/scripts/core/` module folders
- Create: `game/tests/run_tests.gd`
- Create: `game/export_presets.cfg` when the Windows template is available

- [x] Create a bootable minimal scene with typed navigation and keyboard/controller focus.
- [x] Add a headless script runner that reports assertion count/failures with a nonzero exit.
- [x] Run import/parse, test runner, and editor launch on the pinned stable Godot binary; verify Windows release export and app launch.

### Task 2: deterministic RNG, state hashing, and golden harness

**Files:**
- Create: `game/scripts/core/math/deterministic_rng.gd`
- Create: `game/scripts/core/math/state_hash.gd`
- Create: `game/tests/golden/rng_golden_test.gd`
- Reference: `src/core/rng.ts`, `tests/core/rng.test.ts`

- [x] Port the existing PRNG and stream serialization exactly with explicit 32-bit masks.
- [x] Pin known next-value sequences, serialized states, and replay hash outputs from TypeScript.
- [x] Compare all fixtures headlessly before porting formulas.

### Task 3: local save repository

**Files:**
- Create: `game/scripts/core/persistence/save_repository.gd`
- Create: `game/scripts/core/persistence/save_validator.gd`
- Create: save schema resources and round-trip/fault tests.

- [ ] Implement versioned JSON, checksum, temp/validate/promote, two valid backups, export/import validation, and recovery reporting.
- [ ] Verify repeat writes, interrupted writes, malformed imports, future schema refusal, and unchanged previous snapshot.

## Stage 3 — deterministic rules port

### Task 4: stats and damage

Port typed stats, aggregation, conditions, CalcTrace, scalar formulas, mitigation, and shield/HP partition from `src/core/math/`. Add a golden fixture for each formula class and property tests for clamps, finite values, and order invariants. No balance retuning.

### Task 5: item data, item instances, and build resolver

Port versioned catalogs and exact item-generation inputs from `src/data/` and `src/core/items/`. Port the canonical build resolver once. Compare starter build, equipment limits, neural capacity, durability, and item rolls against checked-in legacy fixtures.

### Task 6: combat transition

Port the existing single deterministic combat transition in small slices: actors/resources/auto attacks; status lifecycle/DoT; main tactical channel; reaction channel/interrupts; enemy abilities/boss phases/elites/drones/proc chains. Each slice gets golden/replay tests against the legacy implementation before the next. Presentation remains separate.

## Stage 4 — first playable vertical slice

### Task 7: illustrated arena and combat timeline

Build a layered B01 arena, operator, one drone, three distinct enemies, one boss, readable HUD, telegraphs, combat timeline, pause/speed/skip controls. Every visual follows domain events; assert identical result hashes at normal, accelerated, skipped, and headless playback.

### Task 8: garage, road, rewards, and one persistent sector

Implement the first complete loop: create/load profile, garage/equipment, generated road, encounter choices, combat rewards, cache/service, extraction/death, and durable recovery. Add controller operation and seeded end-to-end acceptance.

## Stage 5 — complete game systems

### Task 9: content, progression, campaign, and economy

Port all required catalog content, six biomes, events, contracts, quests, factions, tree/mutations, crafting, garage progression, sectors 1–12, finale, and depth-13+ escalation. Add cross-reference validation and milestone acceptance tests. Keep catalog values equal to the reference.
### Task 10: autopilot and offline simulation

Implement the actual route policy, legal-information limits, stop conditions, and 12-hour real-battle simulation over the shared core. Check equal state hashes for equal active/offline command streams, cancellation at a committed checkpoint, and exactly-once grants. Thread only immutable batches after measurement.

### Task 11: Build Lab and Simulation Lab

Implement exact CalcTrace/source display, scenario comparison, directed build search, reproducible balance batches, reports, and player advisor. All evaluation uses the same build/combat/world engine and does not mutate the save.

## Stage 6 — art production and release

### Task 12: full asset production

Use the asset manifest and pipeline to produce original, coherent character/enemy/boss/biome/UI/VFX/audio sets. Do not mark a concept as integrated. Validate each asset in a real scene and record provenance.

### Task 13: release acceptance

Run clean headless import, full GDScript tests, golden tests, seeded campaign and endgame scenarios, save recovery, 12-hour offline acceptance, all 12 archetype balance batches, Windows export, Steam Deck/controller and visual review, and critical defect triage. Publish no 1.0 claim while any release criterion is missing.
