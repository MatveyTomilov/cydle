# CYDLE 1.0 delivery roadmap

The normative design source is `CYDLE_MASTER_SPEC.md` v2.0. This roadmap records implementation order and actual completion; catalog entries and interfaces alone are not counted as working gameplay.

## Recovered baseline (`2e5a597`)

- Recovered source and data catalogs, deterministic math/CalcTrace, item instances, and validated build resolver.
- Combat transition with 100 ms deterministic steps, auto-attacks, statuses/DoT, tactical main-channel skills, and reaction-channel defensive skills/interruption.
- Typecheck and 68 unit tests pass. Vite build fails because `src/main.tsx` is missing; E2E cannot run because Playwright is absent.
- Enemy ability/phase/elite/drone combat behavior, game state/persistence, run loop, progression/economy, UI, Simulation Lab, and campaign are incomplete or absent.

## Delivery sequence

1. **Finish combat rules:** execute the existing enemy abilities, boss thresholds/rotations, elite modifiers, drone behavior, and bounded event/proc chains inside the existing `stepCombat` transition. Complete shield bypass and combat acceptance tests.
2. **Bootable application and save boundary:** implemented for the unreleased v1 save format. A React entrypoint, Garage/Build navigation, strict Zod validation, legal starter-build validation, checksummed Dexie snapshots with recovery, import/export, and catalog validation are in place. Active run state is persisted while prior `run:null` v1 saves remain valid. No CI or E2E harness exists yet. Keep the simulation core independent of rendering/storage.
3. **First persisted sector loop:** implemented at `38a5787`; deterministic six-layer graph, tutorial, validated route/cache/service/combat/checkpoint commands, rewards and death settlement, run-safe save validation, and a connected road screen. The implemented node set is intentionally limited to COMBAT/CACHE/REPAIR/FUEL/CHECKPOINT/BOSS. Full sector behavior has core tests; browser smoke reached and resolved only the opening combat.
4. **Build, garage, and road economy:** run-specific equipment at `9598e11`; protected garage equipment at `5fa32c3`; dismantling at `7c50820`; repair at `be1a549`; affix operations/calibration at `6130774`; deterministic playable SHOP at `2001402`. These stages cover secured/unsecured ownership, validated loadouts, extraction/death settlement, inventory salvage/repair, bounded item calibration, and item purchasing. Next: ELITE/BOUNTY encounter rewards and the remaining event/quest/anomaly nodes, then TechLevel progression/unlocks, tree/skills, Build Lab, contracts, quests, and factions.
5. **Campaign and endgame:** all six biomes, encounter budgets and elites, six bosses, sector milestones and story outcomes, campaign sectors 1–12, finale, and depth-13+ escalation.
6. **Automation and offline:** route autopilot policies and thresholds, exact deterministic offline game-time through the same world/combat engines, 12-hour cap, safe handling and one-time reward guarantees.
7. **Build Lab and Simulation Lab:** exact source/CalcTrace view and comparisons; worker-based reproducible scenarios, directed search, statistical reports, replay, and player build advisor without direct save mutation.
8. **Visual finish and release verification:** original SVG/Canvas/Pixi art and motion, responsive desktop/mobile screens, accessibility/settings, minimum E2E flows, seeded campaign acceptance, balance smoke/full batches, and manual visual checks.

## Active work

Combat expansion 2d–2e, the persisted sector loop, run/garage equipment, inventory salvage/repair, affix/TechLevel calibration, and deterministic SHOP node are committed on `development/luna` through `2001402`. Latest checks: typecheck, all 173 unit tests, `npm run validate`, and production build pass. Browser smoke verified the first combat from a newly-created profile; no full-sector/E2E/mobile pass has been recorded. Next task: ELITE/BOUNTY encounters and reward rules, then ANOMALY/EVENT/QUEST. See `HANDOFF.md`. Do not mark a roadmap item complete until its code, tests, and interactions work.
