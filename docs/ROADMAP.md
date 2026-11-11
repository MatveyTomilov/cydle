# CYDLE 1.0 delivery roadmap — Godot

`CYDLE_MASTER_SPEC.md` is the normative source for game design and release requirements. `docs/godot/` records the current engine, architecture, visual direction, and asset production rules. This roadmap records what actually exists; a plan or catalog entry is not working gameplay.

## Current migration checkpoint

- Product direction changed to standalone Godot 4.x Windows game on 2026-11-12. Current engine pin: Godot 4.7.2 stable.
- Root TypeScript/React/Vite project is frozen legacy/reference source for rules, catalog values, and golden fixtures. Do not continue it as the product and do not delete it.
- Documentation checkpoint is in progress on `development/luna`, whose code history descends from the preserved Qwen SHA `2e5a59798695aaf7666a8fa13cb709fcdaad9fc7`.
- Godot implementation has not started; no `game/project.godot`, native scenes, native tests, or Windows export exist yet. Godot CLI was not installed/discoverable during the audit.
- Legacy baseline freshly verified before this documentation update: typecheck pass; 206/206 tests pass; content validation pass; Vite build pass (611.46 kB JS, 192.24 kB gzip). These checks do not verify the future Godot game.

## Delivery sequence

1. **Engine and production documentation:** update the master spec to remove browser stack constraints while preserving game rules; document Godot architecture, Art Bible, Asset Pipeline, and initial Asset Manifest. Commit these documents before runtime code.
2. **Godot foundation:** pin stable engine, create `game/project.godot`, typed app shell, keyboard/controller focus, headless test runner, Windows export profile, and local versioned save repository. Validate import, headless launch, tests, and export.
3. **Golden port harness:** port the existing deterministic RNG exactly; pin seed streams, serialized state, hashes, and event fixtures against the legacy TypeScript reference.
4. **Math and build core:** port stats, modifiers, formulas, CalcTrace, mitigation, damage partition, item instances, and build resolution without balance changes. Compare golden outputs at each boundary.
5. **Combat core:** port the existing single 100 ms simulation including statuses/DoT, skills/reactions, AI, boss phases, elite modifiers, drones, interrupts, and bounded procs. Same seeded input must match legacy expected results.
6. **First illustrated vertical slice:** garage, one road, one arena, operator, one drone, three enemy types, one boss, several items, rewards, extraction/death, save recovery, readable timeline and real original assets. Run in Godot, not in a browser.
7. **Full game systems:** port catalog, equipment/crafting/tree, events/contracts/quests/factions, all biomes/enemies/bosses, sectors 1–12 and endings, then depth-13+ progression.
8. **Autopilot and offline:** legal-data route policy and real 12-hour-capped simulation through the shared core; exactly-once rewards, safe checkpoints, cancel/recovery.
9. **Build Lab and Simulation Lab:** complete mathematical provenance, comparison, directed search, reproducible archetype/seed batches and reports on the same core.
10. **Art, accessibility, and release:** produce/validate original art, animation, audio, controller support, Steam Deck review, save migration/recovery, seeded full-campaign acceptance, balance suites, Windows export, and manual playtest report.

## Legacy project status at freeze

The preserved web implementation on `development/luna` through `739ff3654317d19d609bcd61c2ba17ab2112a4f3` contains recovered math/build foundations, a deterministic combat engine, a first-sector loop, equipment/inventory operations, shop/elite/bounty and partial events. It is incomplete relative to 1.0: later campaign/endgame, quests/contracts, autopilot/offline, full Build Lab/Simulation Lab, and final art are missing. `HANDOFF.md` holds the detailed per-system inventory and known limitations.

## Commit gates

- Make one focused commit per complete feature slice; keep documentation and implementation commits separate when requested.
- Every ported calculation has a checked reference fixture before downstream consumers are connected.
- Run the relevant tests after each slice; run full import, headless tests, and Windows build at each release gate.
- Preserve the reference code and baseline; do not mark a subsystem complete based on file presence.
- Do not claim 1.0 until the master-spec release checklist is verified on a real native build.
