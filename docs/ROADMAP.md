# CYDLE 1.0 delivery roadmap — Godot

`CYDLE_MASTER_SPEC.md` is the normative source for game design and release requirements. `docs/godot/` records the current engine, architecture, visual direction, and asset production rules. This roadmap records what actually exists; a plan or catalog entry is not working gameplay.

## Current migration checkpoint

- Product direction changed to standalone Godot 4.x Windows game on 2026-11-12. Current engine pin: Godot 4.7.2 stable.
- Root TypeScript/React/Vite project is frozen legacy/reference source for rules, catalog values, and golden fixtures. Do not continue it as the product and do not delete it.
- Active work is on `development/codex`, branched from the verified Qwen checkpoint `3f28c7926a8c6ea4a99b1291a8c9e0ac8025cc67`. The protected branches `main`, `recovery/qwen-snapshot`, `development/luna`, and `development/qwen` are unchanged.
- The native shell has `game/project.godot`, a startup scene, typed app root, headless runner, Windows export preset, RNG/state hashing, math/CalcTrace, generic save repository, and the oracle differential harness. A first typed game-save model preserves current top-level RUN fields and has structural validation, but nested graph/combat-result validation and cross-reference/build checks are incomplete; saves are not connected to gameplay. The 73 item templates and 30 affix definitions load in Godot; typed item instances and deterministic rarity/affix/biome-loot generation match nine oracle fixtures. Build logic is not implemented. There is still no playable gameplay loop, combat scene, or integrated art/audio.
- Local environment verified on 2026-11-12: Godot 4.7.2 stable, Node 24.20.0, npm/npx 11.19.0, Git 2.55.0, matching Windows export templates. Godot MCP 0.1.2 is installed project-locally with a compact tool set, confirmation enabled, and arbitrary game-code evaluation disabled. Context7 is available in Codex.
- Fresh native checks: headless import exit 0; **9 headless test scripts / 85667 assertions / 0 failures**; the 1628-case differential suite covers conditions, all 85 stats and computational CalcTrace trees, conversions, formulas, and damage. Asset manifest validation passes for 16 entries (all planned, none integrated). A Windows release export completed (exit 0), and the executable survived a 2-second launch smoke after the MCP project plugin was enabled.
- Legacy reference checks after fixing a readonly-array cast in the fixture generator: typecheck passes; 206/206 tests pass; catalog validation passes; Vite production build passes. Regenerating the 1628 fixtures produced no tracked fixture changes. These checks validate the oracle/reference, not the Godot game.
- GitHub Actions has been added but has not yet run on GitHub. Check the branch's remote SHA before continuing after the first checkpoint push.

## Delivery sequence

1. **Engine and production documentation:** update the master spec to remove browser stack constraints while preserving game rules; document Godot architecture, Art Bible, Asset Pipeline, and initial Asset Manifest. Commit these documents before runtime code.
2. **Godot foundation:** project config, app shell, headless runner, Windows export, local save repository, tests, CI, and basic asset-manifest validation are in place. The application is still a shell.
3. **Golden port harness:** deterministic RNG, serialized streams, hashes, and save repository golden tests are done. The 1628-case math differential harness replays the oracle.
4. **Math and build core:** stats, formulas, damage, conversions, and computational CalcTrace are differentially verified. A first typed save model/repository adapter now has active-run roundtrip tests, but nested data and cross-reference validation need completion before use. The 73 item templates, 30 affixes, typed instances, rarity rolls, and biome loot selection are differentially verified; the canonical build validator/resolver and cosmetic trace explanation parity remain.
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
