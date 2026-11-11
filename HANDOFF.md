# CYDLE — handoff checkpoint

Last updated: 2026-11-11

## Current status

This is a recovery branch containing the preserved Qwen snapshot, two completed recovery stages, an implemented **combat kernel**, and two combat-expansion sub-stages (**2a: effective stats + status lifecycle + DoT**, **2b: active main-channel skills + tactical rules + targeting**). `src/core/combat/engine.ts` satisfies the WIP combat tests and now also resolves statuses/DoT and active skills through the same pure 100 ms `stepCombat`. Typecheck passes and all 56 unit tests pass. The kernel resolves deterministic auto-attacks, continuous resources, status effects, and main-channel skill casts (Windup → Resolve → Recovery → Ready) selected by tactical rules; the reaction channel, drone/enemy abilities, boss AI, and bounded trigger chains are **not yet implemented** (stage 2c–2e). The Vite production build still stops at the missing real app entrypoint `src/main.tsx`, a UI-stage task — no placeholder was added to silence it.

## Repository and checkpoint

- Working directory: `E:\cydle\project`
- Remote: `https://github.com/MatveyTomilov/cydle.git`
- Branch: `recovery/qwen-snapshot`
- Current handoff commit: use `git rev-parse HEAD` on this branch. Previous clean, verified checkpoint: `a06dbbab98581a95ae9b7af72f8a7be29fc659a2` (`feat: resolve validated CYDLE builds`); at that commit typecheck and all 30 unit tests passed, while Vite remained blocked by missing `src/main.tsx`.
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
4. Combat-kernel TDD scaffolding: `docs/superpowers/specs/2026-11-11-combat-kernel-design.md`, `docs/superpowers/plans/2026-11-11-combat-kernel.md`, and `tests/core/combat.test.ts`. The design calls for a single fixed 100 ms transition and a headless runner using existing damage and RNG modules.
5. Implemented the combat kernel in `src/core/combat/engine.ts` (this checkpoint). Exports `createCombatState`, `stepCombat` (exactly one 100 ms tick, pure — returns a new state, never mutates its input), `simulateCombat` (headless runner), `resultFromState`, `allActors`, plus `COMBAT_RULES_VERSION` and `MAX_LOG_EVENTS`. It builds operator/drone/enemy/ally actors from a validated `ResolvedBuild`, rolls hit/crit via the deterministic `Rng`, routes every packet through `math/damage.ts` (`mitigatePacket` → incoming multiplier → `partitionDamage`) exactly once, applies continuous resources once per tick (energy regen, heat cooling/ambient/lockout at 100→release ≤80, shield regen after 4 s), resolves deaths and terminal outcome (VICTORY/DEFEAT/TIMEOUT), accumulates `CombatMetrics`, and emits an immutable event log capped at 5000. No `Math.random`, wall-clock, or process-global counters touch combat state; `nextTraceId`/CalcTrace nodes are deliberately kept out of events so `stateHash` stays reproducible. The three WIP combat tests pass unmodified.
6. Combat expansion **2a — effective stats + statuses + DoT** (same `stepCombat`). Added a unified `effectiveSheet` that recomputes an actor's stats through the existing `resolveStats` pipeline from `baseMods + runtimeMods + buffMods + statusMods` with a live combat `StatContext`, cached by a condition/stack fingerprint (operator `baseMods` = `build.modifiers`; enemies/drones use OVERRIDE mods reproducing their baseline). Implemented `applyStatus` (DoT snapshot at application from rawDamage or TechPower × source status multipliers, independent stacks vs refresh, stack caps incl. `bleedStackCap`/`virusStackCap`, duration scaling, STUN boss half-duration + 3 s ICD), periodic `tickStatuses` (BLEED/BURN/VIRUS tick through target resists each tick, no crit/on-hit, final tick lands on the expiry boundary), and `expireStatuses` (statuses/buffs/temp shields). Point-of-use effects wired: ARMOR_BREAK/GUARD/OVERCLOCK/ACC_BUFF/EVASION_BUFF/SHIELD_REGEN_BUFF via the sheet; SHOCK/DRONE_JAM action speed, SHIELD_LEAK regen, MARK (consume +30% next hit), SCAN_MARK (+12% direct), DRONE_MARK (+15 drone accuracy), BERSERK/CONTROLLED outgoing. `cloneState` shares static `baseMods` by reference to avoid per-tick deep clones. Exports `applyStatus`, `statusStacks`, `hasStatus`, `effectiveSheet`. Covered by 7 new tests in `tests/core/combat-status.test.ts`.
7. Combat expansion **2b — active main-channel skills + tactical rules + targeting** (same `stepCombat`). Extracted the shared damage pipeline into `applyHit` (roll hit → roll crit → raw → per-packet defense → incoming multipliers → shields → HP) so auto-attacks and skills use identical math; `resolveAttack` now calls it. Added a cast state machine (`CastState.resolved`): `startSkillCast` charges energy + heat at cast start, sets cooldown from cast start (`cooldownMs(base, cooldownRecovery)`), blocks the main channel until `endAt = start + windup + recovery`; `advanceCasts` resolves at `resolveAt` and frees the channel at `endAt`, with STUN pausing windup/recovery. Tactical engine: `selectMainRule` picks the first valid enabled main-channel rule by priority desc + stable ruleId, recording aggregated `ruleFailures` (cooldown/energy/no_target/requirement/conditions/not_equipped/heat_lockout) and falling back to AUTO; `evalTacticCondition` covers all `TacticCondition` kinds; `selectTarget` implements nearest/lowestHPPercent/marked/healer/imminentCast/boss/infected/self/secondary with stable-actorId fallback. `resolveSkillCast` handles basis (MAIN_K/MAIN_ANY/TECH_E/TECH_D/OFFHAND/NONE), multi-hit, multi-target (`maxTargets`/allEnemies), splash, and specials EXECUTE/OVERCLOCK/SCAN/DETONATE/LEECH/CHAIN_HEAT/SIDE_FIRE plus guaranteed ON_HIT status triggers (SK_BLADE BLEED on last hit, SK_NEURO/SK_SEED VIRUS, SK_BREAK ARMOR_BREAK). SK_PIERCE applies +20 flat pen per-cast only. **Corrected `build.ts`: skill `extraEffects` are per-cast effects (kept in `effects` for display), no longer permanent build modifiers** — fixes SK_PIERCE permanent pen and SK_OVR permanent attack speed. Covered by 16 new tests in `tests/core/combat-skills.test.ts`.

## Systems that currently work

- Catalog modules load and the catalog consistency test passes.
- Deterministic RNG, scalar formulas, stat aggregation/conditions/CalcTrace, damage mitigation, shield/HP partitioning, and stable item-instance creation are implemented and covered by unit tests.
- Validated build resolution is implemented and covered: canonical starter stats, attribute formulas, item scaling and durability thresholds, equipment/skill/passive/tree/mutation limits and validation, conditions, and neural capacity.
- The combat kernel runs deterministically: a validated build fights a depth-scaled encounter to VICTORY/DEFEAT/TIMEOUT through one pure 100 ms transition, with reproducible `stateHash` across identical seeds, hit/crit rolls, per-packet mitigation and shield/HP partitioning, continuous energy/heat/shield resources, heat lockout, metrics, and a capped event log. Covered by the three combat tests (tick purity + energy regen, deterministic victory, invalid-build rejection).
- These are foundations and developer-facing core logic, not a complete game loop. Combat models **auto-attacks, status effects/DoT, and main-channel active skills driven by tactical rules** (cast lifecycle, costs, cooldowns, targeting, rule-failure diagnostics). Reactions, drone/enemy abilities and boss AI are still pending.

## Partial or absent against `CYDLE_MASTER_SPEC.md` v2.0

- **Partial:** typed data/effects catalogs; some item instance creation; build/stat preview boundary; damage and status primitives; combat state/result interfaces; **executable combat transition + headless simulator for auto-attacks, continuous resources, deaths and terminal outcome**; **effective-stat recomputation, status lifecycle/stacking and DoT (BLEED/BURN/VIRUS), expiry, and status-derived combat modifiers** (stage 2a); **main-channel active skill casts (windup/resolve/recovery/cooldown/energy/heat), tactical rule evaluation, targeting selectors, AUTO fallback and rule-failure diagnostics** (stage 2b) — all in `src/core/combat/engine.ts`.
- **Absent (combat expansion, stages 2c–2e):** the reaction channel (shield/EMP/guard/vent/heal/drone-mark) and interrupt/telegraph resolution, drone active abilities, bounded trigger chains with budget (random procs/unique effects), the enemy ability scheduler and boss phases/rotating casts, elite mods, encounter orchestration hooks (wanted/reveal deltas, escape, death burst).
- **Absent (other systems):** campaign map/run/autopilot, economy/rewards/loot/crafting loop, persistence/migrations/atomic save transactions, meta progression/unlocks, garage, player-facing Build Lab, Simulation Lab and balance batches, React app entrypoint and UI/rendering/animation/assets, integrated and end-to-end test setup.
- `index.html` references `/src/main.tsx`, which is missing. `npm run dev` and production build cannot provide a playable app until the actual application is implemented.
- Package scripts `validate`, `sim`, and `balance` refer to missing scripts. `e2e` refers to Playwright, which is not installed in this project.

## Checks at this checkpoint (combat kernel + stages 2a–2b)

- `npm run typecheck`: **passes** (no errors).
- `npm test`: **56 tests pass** across 7 files — math (11), build (14), combat (3), combat-status (7), combat-skills (16), rng (4), catalog (1). The WIP combat tests were not modified or deleted.
- `npm run build`: **passes the TypeScript check, then Vite fails to resolve `/src/main.tsx`** from `index.html`. This is the same pre-existing UI-stage blocker documented at `a06dbba`, not a regression. It clears only when a real app entrypoint is implemented; no placeholder was added.
- `npm run e2e`: **fails** because the `playwright` executable/dependency is absent.
- No integration tests exist yet. No verification is claimed for the absent combat-expansion features (2c–2e) or the app/UI.
- `npm ci` succeeded during recovery. An earlier `npm audit` reported 7 advisories (3 moderate, 2 high, 2 critical); dependencies were not upgraded during recovery.

## Exact stop point and next task

Stop point: combat kernel + stages 2a (statuses/DoT) and 2b (main-channel skills + tactical rules) implemented and verified (typecheck + 56 tests green). The engine resolves auto-attacks, continuous resources, status effects and tactical skill casts deterministically. The worktree is on `recovery/qwen-snapshot`; the previous known-good core checkpoint is `a06dbba`.

Next task (stage 2 — combat expansion, sub-stages 2c–2e): extend the **same** `stepCombat` transition with the reaction channel (shield/EMP/guard/vent/heal/drone-mark) and interrupt/telegraph resolution, drone active abilities, bounded trigger chains (random procs + unique effects with maxChainDepth=8 / maxChildEventsPerOrigin=32 / dedup), the enemy ability scheduler and boss phases/rotating casts, and elite mods. Reuse `ResolvedBuild`, `math/damage.ts`, `math/stats.ts`, the status definitions, the new `applyHit`/cast machinery, and the deterministic `Rng`; do not duplicate math or rewrite the working resolver. Add tests for each sub-stage and keep `stateHash` reproducible (never embed CalcTrace/`nextTraceId` in combat events).

Then bring forward the real React app entrypoint (`src/main.tsx`) and UI so `npm run build` and `npm run dev` produce a playable app, followed by road/economy/progression, autopilot/offline sim, Build Lab/Simulation Lab, and the 12-sector campaign acceptance. Keep the master spec as the balance authority.

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

To run the unit suite, use `npm test` (56 tests). The combat kernel + stages 2a–2b are implemented; the app build still stops at the missing `/src/main.tsx`. Implement a real app entrypoint at the UI stage — do not add a placeholder solely to silence Vite.

## Short continuation prompt

Open `https://github.com/MatveyTomilov/cydle/tree/recovery/qwen-snapshot` and the local working directory `E:\cydle\project`. Read `CYDLE_MASTER_SPEC.md` and `HANDOFF.md`, inspect `git status` and the latest commits. The combat kernel (`src/core/combat/engine.ts`) plus stages 2a (statuses/DoT) and 2b (main-channel skills + tactical rules) are implemented and verified (typecheck + 56 tests). Continue with stage-2 combat expansion (2c–2e: reactions, drones, trigger chains, enemy/boss AI) through the same `stepCombat`, then the real app entrypoint/UI, without redoing the math core or build resolver. Keep changes on the recovery branch, test each stage, and commit at verified checkpoints.
