# CYDLE — handoff checkpoint

Last updated: 2026-11-11

## Resumed development — current checkpoint

The user explicitly resumed autonomous implementation after the earlier audit handoff. Work is now on `development/luna`, created from user-specified base `2e5a59798695aaf7666a8fa13cb709fcdaad9fc7`. The recovery branch remains the untouched source of the handoff.

- Current work: combat expansion 2d and stage 2e drone roles/skills are verified. Timed enemy abilities, boss thresholds/CORE rotation, all six elite modifiers, cataloged enemy event triggers, and all six drone roles execute inside `stepCombat`.
- Tests: all 102 unit tests and TypeScript typecheck pass. Production build reaches Vite and fails on the absent `src/main.tsx`; E2E remains unavailable because Playwright is absent.
- Next combat task: catalog-driven trigger chains with authored depth/child-event bounds. The full game still lacks run/persistence systems, UI, campaign, crafting, and Simulation Lab.
- The user requests continued implementation through a playable CYDLE 1.0; the old emergency stop is superseded.

## Current status

This is `development/luna`, based on the preserved Qwen snapshot and implemented combat expansions **2a: effective stats + status lifecycle + DoT**, **2b: active main-channel skills + tactical rules + targeting**, **2c: independent reaction channel + interrupt/telegraph**, **2d: timed enemy abilities, boss phases/rotation, elite modifiers, and cataloged enemy events**, and **2e task 1: all drone roles and droneA skills**. Typecheck and all 102 unit tests pass. General bounded trigger chains remain. The Vite production build still stops at the missing real app entrypoint `src/main.tsx` — no placeholder was added.

## Repository and checkpoint

- Working directory: `E:\cydle\project`
- Remote: `https://github.com/MatveyTomilov/cydle.git`
- Branch: `development/luna`
- Base: `2e5a59798695aaf7666a8fa13cb709fcdaad9fc7` from `recovery/qwen-snapshot`. Current commit: check `git rev-parse HEAD`.
- Last fully-verified feature checkpoint before Luna work: `f14bdbc8fda39bc75e277219002194dab61d9061` (stage 2c). Earlier clean core checkpoint: `a06dbbab98581a95ae9b7af72f8a7be29fc659a2` (`feat: resolve validated CYDLE builds`).
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
8. Combat expansion **2c — independent reaction channel + interrupt/telegraph** (same `stepCombat`). Added a separate `CombatActor.reactionCast` slot so the operator's reaction channel runs independently of the main channel (both casts can be active at once). `selectReactionRule` picks the first valid enabled reaction-channel rule by priority desc + stable ruleId, reusing the same cost/cooldown/target/condition diagnostics plus an EMP-specific `no_interruptible` reason; `chooseReaction` runs each tick the reaction channel is free. `startSkillCast` now writes reaction casts to `reactionCast`, uses `reactionCooldownMs` (base × (1 − `reactionCooldownLess`/100) then the general recovery formula), and emits a `TELEGRAPH` event for telegraphed casts (infrastructure for enemy casts in 2d). `advanceReactionCasts` resolves reactive/interrupt actions **before** normal casts (spec event order step 2 before step 3), with STUN pausing windup. `resolveReaction` implements the six defensive reactions: SK_SHIELD (+60 temp shield, per-source cap 90, 5 s, no double accumulation), SK_EMP (interrupt an interruptible cast via `interruptCast` + 0.60 TechPower DIGITAL), SK_GUARD (GUARD status → 20% LESS incoming kinetic, 2 s), SK_VENT (−35 heat at cast start, releases lockout ≤80), SK_HEAL (30 + 10% maxHP, bonus capped 12% maxHP, total ≤22% maxHP, × healing), SK_DRONE_MARK (DRONE_MARK on the boss, 5 s + `droneMarkBonusMs`, +15 drone accuracy via the existing `applyHit` path). Reaction activations emit a distinct `REACTION` event; added `CombatMetrics.interrupts`. Covered by 12 new tests in `tests/core/combat-reactions.test.ts` (interrupt tested against a manually-created enemy cast, as enemy AI lands in 2d).
9. Combat expansion **2d task 1 — scheduled enemy abilities + bypass** (Luna). Added scheduler for timed heavy hits, status application, heat, mark, healing, and shield restoration. Casts have stable IDs, authored start/interval timing, interruptibility, telegraph events, target fallback/fizzle diagnostics, and resolution through the existing `applyHit`/status pipeline. `bypassShieldRatio` now reaches `partitionDamage`; BOSS_B's 25% bypass and SHIELD_LEAK are covered. E07 interrupt, E02 exact windup, ability interval, timed JAM/heat/MARK, heal, and shield restoration are covered by `tests/core/combat-ai.test.ts`.
10. Combat expansion **2d task 2 — boss phases and rotation** (Luna). Added one-shot threshold handling with stable multi-threshold ordering, bounded phase summons, attack/cast speed changes, attack/ability interval reduction, harmful-status cleanse, digital bypass upgrade, and boss ambient heat. BOSS_CORE timed rotation is tested at 12/24/36 seconds. Boss behaviors continue through the single deterministic transition and existing status/damage paths.
11. Combat expansion **2d task 3 — elite modifiers and event hooks** (Luna). Applies the elite ×1.75 HP/×1.25 damage baseline and all six declared modifiers, including EL_PEN's shared armor-penetration path and actual 200 ms basic-attack windup, EL_SPLIT's bounded half-HP no-loot summons, and EL_ANTI_DRONE's telegraphed scheduler entry. Wired E14/E18/E19/E23/E24 event behaviors: third-hit VIRUS, first-hit SHIELD_LEAK, delayed death burst, ally-death BERSERK, and repeated-program JAM. Every effect remains in the single deterministic combat engine.
12. Combat expansion **2e task 1 — drone combat roles and droneA skills** (Luna). Combat actors retain drone role/pellet definitions; DR_GUN prioritizes DRONE_MARK, DR_ARC applies SHOCK on its fifth landed attack, DR_MED restores up to 18 operator shield every 10 s, DR_EMP runs its 14 s interrupt cycle, DR_BULWARK diverts 10% of incoming raw damage up to 20 per operator hit through the shared defense/shield pipeline, and DR_SWARM fires three 8-damage packets with procWeight 0.25 each. `SK_DRONE_REPAIR` and `SK_DRONE_EMP` resolve on the droneA channel independently of its basic-attack cast slot.

## Systems that currently work

- Catalog modules load and the catalog consistency test passes.
- Deterministic RNG, scalar formulas, stat aggregation/conditions/CalcTrace, damage mitigation, shield/HP partitioning, and stable item-instance creation are implemented and covered by unit tests.
- Validated build resolution is implemented and covered: canonical starter stats, attribute formulas, item scaling and durability thresholds, equipment/skill/passive/tree/mutation limits and validation, conditions, and neural capacity.
- The combat kernel runs deterministically: a validated build fights a depth-scaled encounter to VICTORY/DEFEAT/TIMEOUT through one pure 100 ms transition, with reproducible `stateHash` across identical seeds, hit/crit rolls, per-packet mitigation and shield/HP partitioning, continuous energy/heat/shield resources, heat lockout, metrics, and a capped event log. Covered by the three combat tests (tick purity + energy regen, deterministic victory, invalid-build rejection).
- These are foundations and developer-facing core logic, not a complete game loop. Combat models **auto-attacks, status effects/DoT, main-channel active skills driven by tactical rules** (cast lifecycle, costs, cooldowns, targeting, rule-failure diagnostics), an **independent reaction channel** (shield/EMP/guard/vent/heal/drone-mark), scheduled enemy abilities, boss phases/CORE rotation, all six elite modifiers, and cataloged E14/E18/E19/E23/E24 event triggers inside the single combat transition. General bounded trigger/proc-chain execution remains pending.

## Partial or absent against `CYDLE_MASTER_SPEC.md` v2.0

- **Partial:** typed data/effects catalogs; some item instance creation; build/stat preview boundary; damage and status primitives; combat state/result interfaces; **executable combat transition + headless simulator for auto-attacks, continuous resources, deaths and terminal outcome**; **effective-stat recomputation, status lifecycle/stacking and DoT (BLEED/BURN/VIRUS), expiry, and status-derived combat modifiers** (stage 2a); **main-channel active skill casts (windup/resolve/recovery/cooldown/energy/heat), tactical rule evaluation, targeting selectors, AUTO fallback and rule-failure diagnostics** (stage 2b); **independent reaction channel (shield/EMP/guard/vent/heal/drone-mark), cast interrupts and telegraph event infrastructure** (stage 2c) — all in `src/core/combat/engine.ts`.
- **Partial (combat expansion 2d–2e):** combat AI, all six elite effects, all six drone roles, and the two drone active skills are implemented and unit tested; general catalog-driven bounded trigger/proc chains are absent. Encounter orchestration hooks (wanted/reveal deltas, escape, other death effects) remain absent.
- **Absent (other systems):** campaign map/run/autopilot, economy/rewards/loot/crafting loop, persistence/migrations/atomic save transactions, meta progression/unlocks, garage, player-facing Build Lab, Simulation Lab and balance batches, React app entrypoint and UI/rendering/animation/assets, integrated and end-to-end test setup.
- `index.html` references `/src/main.tsx`, which is missing. `npm run dev` and production build cannot provide a playable app until the actual application is implemented.
- Package scripts `validate`, `sim`, and `balance` refer to missing scripts. `e2e` refers to Playwright, which is not installed in this project.

## Checks at this checkpoint (combat kernel + stages 2a–2c + 2d + 2e task 1)

- `npm run typecheck`: **passes** (no errors).
- `npm test`: **102 tests pass** across 9 files — math (11), build (14), combat (3), combat-AI (34), combat-status (7), combat-skills (16), combat-reactions (12), rng (4), catalog (1).
- `npm run build`: **passes the TypeScript check, then Vite fails to resolve `/src/main.tsx`** from `index.html`. This is the same pre-existing UI-stage blocker documented at `a06dbba`, not a regression. It clears only when a real app entrypoint is implemented; no placeholder was added.
- `npm run e2e`: **fails** because the `playwright` executable/dependency is absent.
- No integration tests exist yet. Unit tests cover exact-tick interrupt order, boss target reacquisition, phase summon-cap saturation, E19 death→telegraph→damage ordering, deterministic transitions without input mutation, and drone role/skill behavior. General trigger-chain limits and app/UI remain unverified.
- `npm ci` succeeded during recovery. An earlier `npm audit` reported 7 advisories (3 moderate, 2 high, 2 critical); dependencies were not upgraded during recovery.

## Exact stop point and next task

Current saved point: branch `development/luna`, combat expansion 2e task 1. Timed enemy abilities, boss thresholds/rotation, elite modifiers, enemy event triggers, all six drone roles and droneA skills, and shield bypass execute in `src/core/combat/engine.ts`. Typecheck and the full unit suite (102/102) pass; production build still stops at missing `src/main.tsx`. The current commit is obtained with `git rev-parse HEAD`.

Next task: implement catalog-driven trigger execution with `maxChainDepth=8`, `maxChildEventsPerOrigin=32`, duplicate `(sourceId, trigger, causeId)` suppression, and `CHAIN_LIMIT` diagnostics as defined in `CYDLE_MASTER_SPEC.md` §7. Reuse the current combat event/damage/status pipeline and proc metrics; do not create another simulator. Then continue to missing encounter/world/save/UI systems.

## Important implementation decisions

- Percentage-only stats with zero numeric base store effective increased-percent values: additions within one compatible group sum, while independent groups multiply. See `src/core/math/stats.ts`, tests, and `docs/superpowers/plans/2026-11-11-decisions.md`.
- Tree selections are validated as an owned set (unlock order is not the saved array order); the resolver preserves the caller's selection order in its result.
- `repairCostLess` permits negative values so a cost penalty can be represented as a negative discount.
- Item instance IDs are deterministic from stable grant/template identity, not wall-clock time or process order.
- Damage to shields uses the shield-specific incoming multiplier only during shield absorption; overflow becomes ordinary incoming damage before HP loss.

## Commands for the next agent

```powershell
Set-Location E:\cydle\project
git switch development/luna
npm ci
npm run typecheck
npm test
npm run build
```

The unit suite currently has 102 tests. Implement a real app entrypoint at the UI stage; do not add a placeholder solely to silence Vite.

## Short continuation prompt

Open `https://github.com/MatveyTomilov/cydle/tree/development/luna` and `E:\cydle\project`. Read `CYDLE_MASTER_SPEC.md`, `HANDOFF.md`, and `docs/ROADMAP.md`; inspect `git status` and recent commits. Combat 2a–2c, 2d, and 2e drone roles/skills are implemented and verified. Implement bounded catalog-driven trigger chains inside the existing engine, then continue the roadmap. Do not redo the math core or build resolver; test and commit each stage.
