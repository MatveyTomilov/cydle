# CYDLE 1.0 delivery roadmap — Godot

`CYDLE_MASTER_SPEC.md` is the normative source for game design and release requirements. `docs/godot/` records the current engine, architecture, visual direction, and asset production rules. This roadmap records what actually exists; a plan or catalog entry is not working gameplay.

## Current migration checkpoint

- Product direction changed to standalone Godot 4.x Windows game on 2026-11-12. Current engine pin: Godot 4.7.2 stable.
- Root TypeScript/React/Vite project is frozen legacy/reference source for rules, catalog values, and golden fixtures. Do not continue it as the product and do not delete it.
- Active development branch: `development/qwen`, created from the Luna handoff `1840872f692c2855abdd575f187e9ae1d3c8eea1` and pushed to origin. `main`, `recovery/qwen-snapshot` and `development/luna` are preserved unchanged.
- The native shell has `game/project.godot`, one startup scene, typed app root, headless runner, and a Windows export preset. The deterministic math core (RNG, scalar formulas, damage/mitigation, 85-stat resolver, CalcTrace) and the versioned save repository are ported; gameplay scenes, the combat loop and art are not yet migrated.
- Godot 4.7.2 stable and Windows x86_64 export templates are installed in the current user profile for local verification; they are not vendored into the repository.
- Current native checks on `development/qwen` at `2d185a5`: headless import/parse exit 0; **6 headless test scripts / 85611 assertions / 0 failures**, including a 1628-case differential suite that replays the frozen TypeScript math oracle (condition eval/text, all 85 stats plus computational CalcTrace trees, conversion order/sheets, scalar formulas, damage results and traces). Windows export was last verified at the earlier shell/save checkpoint and must be re-run at the next release gate.
- Legacy baseline (frozen reference, not the product): typecheck pass; 206/206 tests pass; content validation pass; Vite build pass. These verify the oracle, not the future Godot game.

## Delivery sequence

1. **Engine and production documentation:** update the master spec to remove browser stack constraints while preserving game rules; document Godot architecture, Art Bible, Asset Pipeline, and initial Asset Manifest. Commit these documents before runtime code.
2. **Godot foundation:** project config, typed app shell, controller/keyboard focus, headless runner, and Windows export preset are implemented. Next add the local versioned save repository and validation.
3. **Golden port harness:** port the existing deterministic RNG exactly; pin seed streams, serialized state, hashes, and event fixtures against the legacy TypeScript reference. *(RNG/save golden tests done; a 1628-case math differential harness now replays the oracle.)*
4. **Math and build core:** port stats, modifiers, formulas, CalcTrace, mitigation, damage partition, item instances, and build resolution without balance changes. Compare golden outputs at each boundary. *(Math core done and differentially verified — values plus computational CalcTrace trees; cosmetic trace explanation text deferred to the Lab UI. Item instances and build resolution remain.)*
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
