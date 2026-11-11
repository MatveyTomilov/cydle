# CYDLE 1.0 delivery roadmap

The normative design source is `CYDLE_MASTER_SPEC.md` v2.0. This roadmap records implementation order and actual completion; catalog entries and interfaces alone are not counted as working gameplay.

## Recovered baseline (`2e5a597`)

- Recovered source and data catalogs, deterministic math/CalcTrace, item instances, and validated build resolver.
- Combat transition with 100 ms deterministic steps, auto-attacks, statuses/DoT, tactical main-channel skills, and reaction-channel defensive skills/interruption.
- Typecheck and 68 unit tests pass. Vite build fails because `src/main.tsx` is missing; E2E cannot run because Playwright is absent.
- Enemy ability/phase/elite/drone combat behavior, game state/persistence, run loop, progression/economy, UI, Simulation Lab, and campaign are incomplete or absent.

## Delivery sequence

1. **Finish combat rules:** execute the existing enemy abilities, boss thresholds/rotations, elite modifiers, drone behavior, and bounded event/proc chains inside the existing `stepCombat` transition. Complete shield bypass and combat acceptance tests.
2. **Bootable application and save boundary:** in progress. A React entrypoint, Garage/Build navigation, strict Zod schema v1, legal starter-build validation, checksummed Dexie snapshots with recovery, import/export, and catalog validator now exist. Save `run` remains null; no legacy migration, CI, or E2E harness exists yet. Keep the simulation core independent of rendering/storage.
3. **One complete playable sector:** command-validated run state, procedural six-layer DAG, combat encounter composition, inventory and unsecured loot, reward grant IDs, checkpoint/evacuation/death, and save/reload.
4. **Build and garage gameplay:** connect existing equipment/catalog/tree/skills/uniques/crafting, currencies, repair, TechLevel calibration, unlocks, contracts, quests, and factions through validated commands and actual screens.
5. **Campaign and endgame:** all six biomes, encounter budgets and elites, six bosses, sector milestones and story outcomes, campaign sectors 1–12, finale, and depth-13+ escalation.
6. **Automation and offline:** route autopilot policies and thresholds, exact deterministic offline game-time through the same world/combat engines, 12-hour cap, safe handling and one-time reward guarantees.
7. **Build Lab and Simulation Lab:** exact source/CalcTrace view and comparisons; worker-based reproducible scenarios, directed search, statistical reports, replay, and player build advisor without direct save mutation.
8. **Visual finish and release verification:** original SVG/Canvas/Pixi art and motion, responsive desktop/mobile screens, accessibility/settings, minimum E2E flows, seeded campaign acceptance, balance smoke/full batches, and manual visual checks.

## Active work

Combat expansion 2d and stage 2e tasks 1–2 remain implemented and verified on `development/luna` at `d9a88e7`: timed enemy abilities, boss thresholds/CORE rotation, all six elite modifiers, enemy event behaviors, all six drone roles, both droneA skills, source-aware catalog triggers, and bounded proc chains. The boot/save boundary is now partially implemented: typecheck, 124 unit tests, `npm run validate`, production build, and dev-server HTTP response pass. The next task is one persisted playable sector/run loop. Visual browser interactions remain unverified, and E2E is unavailable without Playwright. See `HANDOFF.md`. Do not mark a roadmap item complete until its code, tests, and interactions work.
