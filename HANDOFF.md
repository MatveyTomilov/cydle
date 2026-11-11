# CYDLE — handoff checkpoint

Last updated: 2026-11-11

## Current status

This is a recovery branch containing the preserved Qwen snapshot and two completed recovery stages, plus an explicitly unfinished combat-kernel test/design scaffold. Development is paused at the user's request. No combat engine implementation exists yet. The current branch is expected to fail typecheck and tests because the WIP test imports that not-yet-created engine.

## Repository and checkpoint

- Working directory: `E:\cydle\project`
- Remote: `https://github.com/MatveyTomilov/cydle.git`
- Branch: `recovery/qwen-snapshot`
- Current handoff commit: use `git rev-parse HEAD` on this branch. Previous clean, verified checkpoint: `a06dbbab98581a95ae9b7af72f8a7be29fc659a2` (`feat: resolve validated CYDLE builds`).
- Previous clean, verified checkpoint: `a06dbbab98581a95ae9b7af72f8a7be29fc659a2` (`feat: resolve validated CYDLE builds`). At that commit typecheck passed and all 30 unit tests passed; the Vite build remained blocked by missing `src/main.tsx`.
- Preserved original archive: `E:\cydle\workspace.tar.gz` (SHA-256 `5E82E5BDA30D38A0FB551F242E1B14E44E8B75B1D51A874B208AD45E96D24630`). Extracted read-only comparison snapshot: `E:\cydle\recovered-snapshot\cydle`.
- The Qwen snapshot and follow-up fixes are committed locally; see the recovery commits in `git log`. The master spec matches GitHub `main` at the recovery point.

## What came from Qwen

Qwen's working files were recovered from the workspace archive; GitHub `main` contained the master spec but not the application source. The recovered source includes:

- Typed catalog data: `src/data/types.ts`, items, skills, specialization tree, enemies/bosses, biomes, affixes, unique effects, progression, events, and quests.
- Core foundations: serializable deterministic RNG, CalcTrace/stat registry and modifier resolution, scalar formulas, defense/damage partitioning, item-instance creation, combat actor/event/config/result types, and status definitions.
- Project metadata/configuration: package files, strict TypeScript and Vite configuration, master spec, and archived v1.3 spec.

The presence of catalogs and interfaces does not mean those systems are playable. The original snapshot had no app entrypoint, no full combat simulator, no save/progression loop, no Simulation Lab, and no working UI.

## Work completed in recovery branch

1. Preserved the recovered snapshot in commit `4a59add7afa50670165c0b2266c80bca545cb15b` (`recovery: preserve Qwen CYDLE snapshot`).
2. Repaired the mathematical foundation in `12ce16b37e61f90fc1a39efe3fe4bd79f3c3fc7f` (`fix: restore deterministic CYDLE math core`): shield-only incoming multiplier behavior, stable item IDs, type/configuration fixes, and regression tests.
3. Added the build resolver in `a06dbbab98581a95ae9b7af72f8a7be29fc659a2` (`feat: resolve validated CYDLE builds`). `resolveBuild()` validates equipment and allocation and gathers catalog effects through one existing stat resolver, including attribute formulas, item scaling, CalcTrace, and neural capacity checks.
4. Began—but did not implement—the combat kernel. Current WIP files are `docs/superpowers/specs/2026-11-11-combat-kernel-design.md`, `docs/superpowers/plans/2026-11-11-combat-kernel.md`, and `tests/core/combat.test.ts`. The design calls for a single fixed 100 ms transition and a headless runner using existing damage and RNG modules. There is no `src/core/combat/engine.ts` yet.

## Systems that currently work

- Catalog modules load and the catalog consistency test passes.
- Deterministic RNG, scalar formulas, stat aggregation/conditions/CalcTrace, damage mitigation, shield/HP partitioning, and stable item-instance creation are implemented and covered by unit tests.
- Validated build resolution is implemented and covered: canonical starter stats, attribute formulas, item scaling and durability thresholds, equipment/skill/passive/tree/mutation limits and validation, conditions, and neural capacity.
- These are foundations and developer-facing core logic, not a complete game loop.

## Partial or absent against `CYDLE_MASTER_SPEC.md` v2.0

- **Partial:** typed data/effects catalogs; some item instance creation; build/stat preview boundary; damage and status primitives; combat state/result interfaces.
- **Absent:** executable combat transition/simulator, tactical rule evaluation, active skill execution, trigger chains, status lifecycle/DoT, drones, enemy/boss AI and phases, encounter orchestration, campaign map/run/autopilot, economy/rewards/loot/crafting loop, persistence/migrations/atomic save transactions, meta progression/unlocks, garage, player-facing Build Lab, Simulation Lab and balance batches, React app entrypoint and UI/rendering/animation/assets, integrated and end-to-end test setup.
- `index.html` references `/src/main.tsx`, which is missing. `npm run dev` and production build cannot provide a playable app until the actual application is implemented.
- Package scripts `validate`, `sim`, and `balance` refer to missing scripts. `e2e` refers to Playwright, which is not installed in this project.

## Checks at the paused WIP commit

- `npm run typecheck`: **fails** because `tests/core/combat.test.ts` imports missing `src/core/combat/engine.ts`; the unresolved import also makes the test callback parameter implicitly `any`.
- `npm test`: **30 existing tests pass; combat suite fails to load** for the same missing module.
- `npm run build`: **fails during TypeScript check** for the same WIP errors. At the previous clean checkpoint it passed TypeScript and then Vite failed because `/src/main.tsx` is absent.
- `npm run e2e`: **fails** because the `playwright` executable/dependency is absent.
- No integration tests exist. No verification is claimed for the absent combat kernel or app.
- `npm ci` succeeded during recovery. An earlier `npm audit` reported 7 advisories (3 moderate, 2 high, 2 critical); dependencies were not upgraded during recovery.

## Exact stop point and first task

Stop point: combat-kernel TDD scaffolding only. The expected first red test cannot collect because the engine module has not been written. The worktree is saved in the recovery branch; the previous known-good core checkpoint is `a06dbba`.

First task for the next agent: read `CYDLE_MASTER_SPEC.md` sections 2, 4, 6–8, and 23.2, then `docs/superpowers/specs/2026-11-11-combat-kernel-design.md` and its plan. Implement `src/core/combat/engine.ts` to satisfy the existing tests using `ResolvedBuild`, `src/core/math/damage.ts`, and the existing deterministic RNG. Keep the master spec as the balance authority. Expand combat in later small stages; do not duplicate math or rewrite the working resolver.

## Important implementation decisions

- Percentage-only stats with zero numeric base store effective increased-percent values: additions within one compatible group sum, while independent groups multiply. See `src/core/math/stats.ts`, tests, and `docs/superpowers/plans/2026-11-11-decisions.md`.
- Tree selections are validated as an owned set (unlock order is not the saved array order); the resolver preserves the caller's selection order in its result.
- `repairCostLess` permits negative values so a cost penalty can be represented as a negative discount.
- Item instance IDs are deterministic from stable grant/template identity, not wall-clock time or process order.
- Damage to shields uses the shield-specific incoming multiplier only during shield absorption; overflow becomes ordinary incoming damage before HP loss.

## Commands for the next agent

```powershell
Set-Location E:\cydle\project
git switch recovery/qwen-snapshot
npm ci
npm run typecheck
npm test
npm run build
```

To run the unit suite, use `npm test`. After the combat WIP import is implemented, the app build will still stop later at the missing `/src/main.tsx`; implement a real app entrypoint when the UI stage is authorized. Do not add a placeholder solely to silence Vite.

## Short continuation prompt

Open `https://github.com/MatveyTomilov/cydle/tree/recovery/qwen-snapshot` and the local working directory `E:\cydle\project`. Read `CYDLE_MASTER_SPEC.md` and `HANDOFF.md`, inspect `git status` and the latest commits, then inspect the combat-kernel spec, plan, and red tests. Continue from `src/core/combat/engine.ts` without redoing the math core or build resolver. Keep changes on the recovery branch, test each stage, and commit at verified checkpoints.
