## Unreleased — Autobattle V2 migration branch (13 November 2026)

- Adopted CYDLE_MASTER_SPEC.md v2.1 §8 as the normative item-authored combat model, superseding player-programmable tactics.
- Added isolated AutobattleV2Contract deterministic action selector, action timeline, reaction budget, bounded proc ledger, target doctrines and Why-Not rejection codes, with a headless contract test registered in the native runner.
- Added isolated AutobattleV2Duel: ARC-9 basic action with canonical DamageMath, Energy/Heat, HOT damage, authored Vent and Heat-to-Shield, enemy autoattack, causal event records and replay/snapshot tests. Fixed channel occupancy semantics so cooldown does not block further weapon actions. This is **headless prototype-only**, not connected to GameSession, Build Lab, consumables or campaign. V1 saves and live combat remain unchanged; new SHA's CI and rendered/headless parity remain to be verified before merge.

# Changelog

## Unreleased — every equipment category is available to the active expedition build

- Added between-fight installation of compatible unsecured cargo into all unlocked weapon, armor, implant, drone, engine, chassis, scanner, service, cargo, and support slots. The field Build Lab, combat initialization/resume, event energy refills, and sector continuation use the same `run.equipment` through the existing `BuildResolver` and combat simulator.
- The field item remains unsecured. Extraction secures cargo and promotes the active field kit to permanent equipment; defeat, tow, and abandon reconcile references against surviving owned gear and preserve existing cargo/durability consequences.
- Wired cargo rows to real equip/restore actions and made Build Lab show the field build during an expedition.
- Regression covers all six transport/service slot types, actual combat actor stats, ownership, save/load, sector continuation, extraction, dismantle protection, and active-combat snapshot resume with the field build. Local checks: Godot 4.7.2 import exit 0, **26 tests / 88,970 assertions / 0 failures**; TypeScript typecheck, 207 tests, catalog validation, and production build passed on the preceding checkpoint. CI for the expanded checkpoint is running.

## Unreleased — Master Spec §25 animated battle screen, and two player-facing save/UI fixes

- Replaced the static text battle report with the §25 animated side-view autobattle. `game/scripts/app/battle_arena.gd` renders the shared simulator's event log only (tracers, impacts, damage numbers, miss/dodge arcs, shield/heal rings, status pops, death fades, cast telegraphs, heat lockout, rain and idle bob disabled under reduced motion) using the repo's existing original placeholder SVGs via `data/presentation/alpha_visual_fallbacks.json`. It never writes combat state, so rendering cannot change an outcome.
- `game/scripts/app/battle_view.gd` adds the operator HUD (HP/shield/energy/heat, statuses, drone roles and cooldowns), per-enemy HP and dangerous-cast telegraphs, a last-events timeline, and always-visible ПАУЗА / ×1 / ×2 / ×4 / ПРОПУСК controls. It drives `advance_combat_playback(budget, 1000 × speed)`; on outcome the controls row is replaced by an always-visible settlement action so the player never has to scroll to finish a fight.
- Layout was verified with real windowed Godot runs (viewport PNG captures, not desktop screenshots): at 1280×720 the arena, HUD, controls and settlement all fit without scrolling; an earlier draft pushed the controls below the fold and collapsed the enemy heading to one letter per line (autowrap labels report zero minimum width inside an HBox), both fixed.
- New regression `game/tests/golden/battle_view_test.gd` (24 assertions): constructing the screen does not advance the battle; pause freezes simulation; ×4 real-time playback reaches the same outcome, duration and JSON-normalised state hash as `skip_combat_to_outcome()`; the settlement button emits and settles back to ROUTE.
- QA D3 (save loss): `НОВАЯ ИГРА` no longer overwrites a live profile silently. It opens a confirmation showing save id/revision/sector/phase and explaining that `.bak1/.bak2` survive; cancel leaves the save untouched. Settings gained a "Резервные копии сейва" panel listing main + both backups with a restore action. `SaveRepository.list_snapshots()/restore_snapshot()` restore a backup as a new highest revision (so `load()` selects it) and rotate the pre-restore state into `.bak1`, keeping the operation reversible. Regression in `save_repository_test.gd` and `test_app_boot.gd`.
- QA D2 (unreachable cargo actions): checkpoint shipping rows showed raw `templateId · itemId` with no wrap, forcing the scroll body to 1011 px against a 936 px viewport and pushing right-aligned actions off-screen. Rows now show readable catalog names with the full id in a tooltip, clip/trim instead of forcing width, and the shell scroll container allows horizontal scrolling as a safety net. Measured with two real rolled cargo items: body min-width 640 px, zero off-screen children.
- Verified locally with Godot 4.7.2 and isolated `APPDATA`: import exit 0, full native suite **25 tests / 88,898 assertions / 0 failures** exit 0, asset manifest validation exit 0 (16 entries), windowed capture runs exit 0 with no script errors.

## Unreleased — real-time combat playback no longer saves on every tick

- `advance_combat_step()` wrote the full transactional save on every 100 ms tick. Measured on a 47-tick battle: **223 ms per tick**, 10.5 s total, so `ПРОСЧИТАТЬ ДО ИСХОДА` froze the UI for the whole fight and Master Spec §25 real-time autobattle was impossible.
- Added three playback entry points to `GameSession`, leaving `advance_combat_step()` and the save protocol byte-identical: `advance_combat_playback(delta_ms, persist_interval_ms = 1000)` steps in memory and persists on a bounded cadence, `skip_combat_to_outcome(max_ticks = 1800)` simulates the rest of the battle and persists once, and `flush_combat_snapshot()` forces any in-memory progress to disk before leaving the battle or closing the app.
- The cadence is derived from the already-persisted `combatSnapshot.simTimeMs`, so it is self-correcting and adds no new persisted field or save-format version. The interval scales with the playback speed, keeping the crash-loss window at roughly one second of wall-clock time at ×1/×2/×4.
- `ПРОСЧИТАТЬ ДО ИСХОДА` now calls `skip_combat_to_outcome()`. Measured on the same 47-tick battle: skip **250 ms (42× faster)**, real-time playback **23 ms per tick (9.7× faster)**.
- New regression `game/tests/golden/combat_playback_test.gd` (168 assertions): playback is bit-identical to the per-tick reference; sub-tick and negative budgets are inert; snapshots land only on cadence boundaries; a scaled interval changes persistence but not the simulation; an interrupted run resumes from the last durable boundary and replaying the lost window converges; flush + reload reproduces the battle; skip and streamed playback reach the same outcome, state and settlement; a settled battle cannot simulate further or pay twice, including after reload.
- The CI test gate now requires at least 24 tests (was 23).
- Verified locally with Godot 4.7.2 and an isolated `APPDATA`: import exit 0, full native suite **24 tests / 88,857 assertions / 0 failures** exit 0, asset manifest validation exit 0.
- Two pre-existing properties were measured while writing the regression, neither introduced nor changed here: item identifiers embed the profile `saveId` (which contains `Time.get_ticks_usec()`), so two freshly rolled profiles can never hash identically — the test clones one template profile instead; and Godot's JSON writer keeps ~15 significant digits, so a reloaded battle differs from the in-memory one in the last digits (`9.999999999999979` → `9.99999999999998`). This affects `advance_combat_step()` reloads identically and is now documented in HANDOFF.md.

## Unreleased — CI actually runs Godot and publishes a Windows build

- Root cause of every red GitHub Actions run: `chickensoft-games/setup-godot` exposes only the GUI-subsystem editor executable. PowerShell neither waits for it nor captures its output, so import, tests, asset validation and export each returned exit 0 in under a second without executing anything. The export therefore produced no file and `upload-artifact` failed with `No files were found with the provided path: game/build/CYDLE.exe`. The green Godot steps were false positives, not passing checks.
- Replaced the action with `scripts/ci/install-godot.ps1`, which downloads the official 4.7.2-stable editor archive (including `Godot_v4.7.2-stable_win64_console.exe`) and the Windows export templates, installs them into `%APPDATA%\Godot\export_templates\4.7.2.stable`, and verifies the reported engine version. Editor and templates are cached between runs.
- Every Godot step now runs through the console wrapper, echoes its log, and asserts its exit code. The test step additionally requires the real runner summary and rejects a run with fewer than 23 tests or 80,000 assertions, so a silent no-op can never pass again.
- The export step asserts the executable exists and is at least 50 MB. A new smoke step launches the exported build with an isolated `APPDATA`, requires the `CYDLE shell ready` boot marker, rejects runtime errors, and requires the user data directory to be created. Added `print("CYDLE shell ready: %s" % _screen)` at the end of `app_root._ready()` as that boot marker.
- Added superseding-run cancellation and a verification-log artifact.
- Verified on SHA `4f7d19c78af8a4ea505d001eaaca200342143a87`, run `43409888278`: all 17 steps success. CI log shows `23 tests passed, 0 tests failed; 88689 assertions, 0 assertion failures`, asset manifest valid (16 entries), and `savepack [ DONE ]`.
- The published artifact `cydle-windows-4f7d19c7…` was downloaded independently: `CYDLE.exe` is 116,396,408 bytes, and running it headless with an isolated `APPDATA` printed `CYDLE shell ready: menu`, exited 0, produced no stderr, and created `Godot/app_userdata/CYDLE`.
- Local CI-equivalent verification before the push: import exit 0, 23 tests / 88,689 assertions / 0 failures, asset validation exit 0, export exit 0, exported EXE smoke exit 0.

## Unreleased — EV16 real encounter skip verification

- Added a generated-route integration scenario: EV16's paid choice then consumes the next ordinary COMBAT node, clears its skip flag, and grants no XP, cargo, or item grants.
- Local and independent Godot 4.7.2 full native suite: 23 tests / 88,689 assertions / 0 failures on exact SHA `a5b0bc4`. EV16 skip integration verified with no XP/loot/grants and flag consumption; detached tree and diff check clean. The first local attempt surfaced a test-only wrong field name (`experience` instead of `xp`), corrected before the passing run.

## Unreleased — EV07 percentage hull damage

- EV07's scrap option now removes 10% of maximum hull instead of a flat 10 hull, matching Master Spec §20.1. The data-driven event transaction regression checks the actual before/after hull values.
- Godot 4.7.2 import exit 0; full native suite: 23 tests / 88,683 assertions / 0 failures. Independent regression on exact SHA `40a6623` reproduced import and suite with clean detached worktree/diff check.

## Unreleased — EV13 rare price rounding

- Grey Dealer now charges `ceil(60% × rounded rare shop price)` as specified. The d12 boundary was 266 before and is correctly 267 credits after the change.
- Regression is part of the 23-script Godot suite. Godot 4.7.2 import exit 0; full suite: 23 tests / 88,682 assertions / 0 failures. TypeScript oracle is unchanged by this Godot-only fix.

## Unreleased — parallel balance research and persisted offline diagnostics

- Added project agent `balance_qa` on GPT-6 Luna High. Bounded BOSS_B research (up to 24 fights, no more than 3 per archetype) runs in a detached read-only worktree alongside required regression checks.
- First six-fight result on SHA `928afbac8fba74c4cf51e55668fbfed59ca05163`: at d8/B04 with a shared seed, Kinetic and Tech/Energy each repeated defeat; Drone/Hybrid repeated victory at 20.3s with 16.998 operator HP. Treat as a balance risk signal, not campaign acceptance. All combat configurations were accepted by the existing simulator. The raw drone metrics match (`interrupts=1` both repeats); a temporary display counter searched the wrong event name (`INTERRUPT` instead of `CAST_INTERRUPT`), so no simulator nondeterminism is verified.
- Follow-up at SHA `40a662322610b12b1c38a35c5b72ad4c4d3ca107`: same three legal builds on two additional seeds; 5/6 losses overall. Kinetic and Tech/Energy lost both; Drone/Hybrid split, with one narrow win. This is risk evidence for sampled builds only; the simulator accepted every legal combat. Balance QA recommends alternative Kinetic/Tech builds in a capped next matrix before any tuning.
- Alternate-build follow-up: a legal Kinetic build with DR_GUN + DR_ARC won both same-seed-variant runs; the tested Tech/Energy alternative lost both. The Kinetic result is loadout-sensitive; Tech still warrants a different build/defense check. No boss tuning was performed.
- Final capped Tech check used `SK_ARC`/`PP_HEAT` with legal secured PLASMA equipment on the same two seeds; both lost, with 3,251/2,819 boss HP remaining. It is a signal for those Tech builds only. No simulator errors or balance change. BOSS_B probes are paused until a material combat/build checkpoint.
- Concurrency is set to 3; the config checkpoint was accepted by Codex strict-config and all four project agent definitions were exercised/visible. Removed the stale quest-only agent from active delegation.
- Added a reload check for the 12-hour cap and negative-clock diagnostics in saved autopilot report history. Local and independent Godot 4.7.2 checks passed: 23 tests / 88,680 assertions. Detached worktree and diff check were clean.
- Legacy TypeScript oracle on current code-equivalent `62c76fcbf5c2bb08af88cfcabd2839c49c12c393`: 22 files / 207 tests and `npm run typecheck` both pass.

## Unreleased — retain exact offline diagnostics

- Preserved an exact -1 ms wall-clock rollback via an explicit elapsed-delta-presence flag and exposed cap/rollback values in autopilot report history.
- Added assertions for report and history values. Godot 4.7.2 import exit 0; 23 tests / 88,679 assertions passed. Independent regression and review pending.

## Unreleased — disclose unapplied offline time

- Auto-pilot now reports wall-clock time beyond the 12-hour processing cap and backward system-clock movement; negative time applies no game progress.
- The autopilot summary displays either condition. Boundary regressions use short requests and do not run a long simulation.
- Godot 4.7.2 import exit 0; 23 tests / 88,677 assertions passed. Independent regression and review pending.

## Unreleased — active/offline battle parity smoke

- Compared identical seeded battles in manual and offline/autopilot sessions, including outcome, metrics, run economy, grants, operator progression and post-settlement reload.
- Godot 4.7.2 editor import exit 0; 23 tests / 88,675 assertions passed. This is not full 12-hour offline validation; independent regression check pending.

## Unreleased — completed HUNT reward loss on death

- Extended the natural HUNT contract flow: after exact contract reward and save reload, death before extraction loses the unsecured guaranteed item, preserves COMPLETE/reward-claimed status, and does not make the grant available again.
- Godot 4.7.2 editor import exit 0; 23 tests / 88,665 assertions passed. Independent regression check pending.

## Unreleased — contract failure integration coverage

- Added a public GameSession flow that runs an actual simulator defeat and settles through `resolve_active_combat()`, proving active contract failure, unsecured cargo/currency loss and reload persistence.
- Added ESCORT checkpoint failure coverage at wanted 41 in the generated route, confirming no reward or faction reputation is paid.
- Godot 4.7.2 editor import exit 0; 23 tests / 88,661 assertions passed. Independent regression run is pending.

## Unreleased — fail active contracts on death

- A sortie defeat now closes any still-active contract as `FAILED` while applying the existing death rule that loses unsecured cargo and run currency.
- Added a persistence regression covering the failed status and temporary cargo loss. Godot 4.7.2 import exit 0; 23 tests / 88,655 assertions passed.

## Unreleased — natural SIGNAL unique reward

- Replaced the direct reward-helper fixture with a real route flow to the SIGNAL target ELITE, shared-simulator battle, guaranteed U09 UNIQUE reward and save reload.
- Godot 4.7.2 import exit 0; 23 tests / 88,647 assertions passed. No Windows export or GUI smoke.

## Unreleased — natural ESCORT checkpoint settlement

- Added a deterministic runtime flow that follows reachable route nodes, clears two real shared-simulator battles, reaches the generated checkpoint and verifies the ESCORT credit/faction rewards and completion grant after save reload.
- Godot 4.7.2 headless import exit 0; 23 tests / 88,648 assertions passed. No Windows export, GUI smoke or CI query.

## Unreleased — natural TECH contract settlement

- Added a deterministic GameSession flow that travels through the prerequisite ordinary COMBAT via the shared simulator, reaches the accepted TECH cache target and takes the real `OPEN_CACHE` action.
- Verifies the MODIFIED item has the contract's target tag, the authored DATA payout is received, the first-success blueprint unlocks, and the result survives save reload.
- Godot 4.7.2 headless import exit 0; 23 tests / 88,642 assertions passed. No Windows export or GUI smoke.

## Unreleased — natural HUNT contract settlement

- Added a deterministic GameSession integration flow from accepting HUNT through travel, actual shared-simulator ELITE victory, the authored contract credit/item reward, and save reload.
- Seed `hunt-runtime-fixed-seed` verifies `COMPLETE`/reward claimed, one guaranteed RARE contract item in unsecured cargo and persistent settlement. No combat balance or runtime transaction logic changed.
- Godot 4.7.2 headless import exit 0; 23 tests / 88,634 assertions passed. No Windows export or GUI smoke.

## Unreleased — contract target visibility

- Accepted contract targets are now revealed and marked on the route map. The active contract panel shows objective details, live ESCORT requirements, and whether a completion reward is still unsecured or the objective failed.
- Regression verifies an accepted HUNT target is exposed as an ELITE node in route intel. Godot 4.7.2 editor import exit 0; 23 tests / 88,625 assertions / 0 failures. No Windows export or GUI smoke was run.

## Unreleased — exercise all authored quest choices

- Added real GameSession transaction scenarios for all 36 authored choices across Q01–Q06, including stage gates/targets, quest progress, event completion and save-schema roundtrip.
- Godot 4.7.2: editor import exit 0; 22 tests / 88,578 assertions / 0 failures; diff check exit 0.

## Unreleased — verify every event choice transaction

- Added a data-driven smoke for all 48 choices across the 24 event definitions using actual `GameSession` route/event operations.
- Fixed event item rewards failing when `resolve_event()` was the first operation to need the item catalog; the transaction now loads it before generation.
- Godot 4.7.2: editor import exit 0; 22 tests / 88,467 assertions / 0 failures; diff check exit 0.

## Unreleased — disable unaffordable event and quest options

- Shared `GameSession` cost quotes now drive both actual event/quest transactions and road UI availability. Paid options are disabled with currency and required amount when the unsecured sortie wallet cannot cover them.
- Scaled costs for EV13/data exchange and the Q03 engine choice use the same price calculation for UI and settlement. Regression confirms an unaffordable EV02 option leaves state untouched.
- EV02 and Q03 integrations verify unavailable paid choices cannot mutate event/quest history; the free or paid-for legal alternative remains resolvable.
- Godot 4.7.2: editor import exit 0; 22 tests / 88,319 assertions / 0 failures; diff check exit 0.

## Unreleased — execute R3D's same-target attack trigger

- Tree `ON_ATTACK_COUNTER` effects are accepted by the shared combat guard and now track successful operator attacks per target, resetting when the target changes. R3D grants and refreshes its authored accuracy buff on the fourth hit to a target.
- Added catalog trigger acceptance coverage plus targeted checks for threshold, target switch, refresh, and combat snapshot roundtrip.
- Added `docs/FEATURE_AUDIT.md`, an implementation-vs-player-access matrix with known gaps and the current checkpoint.
- Godot 4.7.2: editor import exit 0; 22 tests / 88,314 assertions / 0 failures; diff check exit 0.

## Unreleased — enable the authored E10 summon

- Added scheduled enemy `summon` ability resolution, using the existing summon cap and no-loot handling. E10 now executes its catalogued E20 spawn after its telegraph instead of silently skipping the unsupported action kind.
- Added a deterministic test for cast scheduling, telegraph event, summon ownership/template, and combat snapshot roundtrip.
- Godot 4.7.2: editor import exit 0; 22 scripts / 88,243 assertions / 0 failures.

## Unreleased — validate quest-augmented sector routes

- Fixed active multi-stage quest routing: quest events reuse existing layer-three map nodes and preserve their edges instead of expanding every source's outgoing degree.
- Added a final graph validator after quest, contract, and faction modifications; malformed route generation now fails before it is committed as a sortie.
- Added a regression with simultaneous Q02/S2 and Q03/S1 in B03, including graph invariant checks, a real GameSession sortie save, and reload.
- Godot 4.7.2: editor import exit 0; 22 scripts / 88,179 assertions / 0 failures. Campaign boss balancing was not attempted.

## Unreleased — Windows PLAYABLE ALPHA checkpoint

- Prepared `dist/CYDLE-Playable-Alpha.zip` locally with the Godot 4.7.2 Windows x64 export and a short launch guide; binaries remain out of Git.
- UI smoke followed new game/profile reload, garage and Build Lab, inventory filter/edit flow, real expedition combat/reward, autopilot pause, checkpoint cargo evacuation, and return to Garage. Simulation Lab completed three paired runs against E01 Raider using the shared combat simulator.
- Wrapped the multi-control inventory filter row and compacted Simulation Lab candidate labels so the warehouse no longer requires horizontal scrolling for the filter controls.
- Verification: editor import exit 0; 22 Godot test scripts / 88,091 assertions / zero failures; Windows Desktop export exit 0; extracted packaged EXE headless smoke exit 0.
- d8 BOSS_B remains an unresolved campaign blocker (latest level-11 attempt lost at tick 148 with 981/4,951 boss HP). This alpha is not a 1.0 release and does not claim full campaign acceptance.

## Unreleased — campaign E2E d8 blocker and resume safety

- The isolated campaign E2E now preserves the highest-ranked drone per role during test inventory cleanup and restores the boss interrupt tactic when resuming a saved profile. Runtime gameplay and balance are unchanged.
- d5–d7 routes/checkpoints and d8 ordinary combat were exercised through persisted transitions. BOSS_B at d8 remains a blocker for this pilot: level 11 lost at tick 159 with BOSS_B at 1,364/4,951 HP. The isolated profile is preserved mid d6 retry.
- Harness launched and ran under Godot 4.7.2; the full suite and export have not been rerun after this harness delta.

## Unreleased — campaign E2E authored-combat skip handling

- The campaign driver now treats an ordinary combat node cleared by a catalogued one-time skip effect as resolved when no `CombatState` is created. It reports the skip and awards no combat XP or loot, matching runtime behavior. A resumed campaign run observed the EV16 skip and proceeded to later route nodes.
- The campaign E2E run is still retrying d4 BOSS_A; this harness fix does not establish a boss win or full campaign pass.

## Unreleased — quest journal requirements and decision history

- Active/paused quest cards now show the authored stage gate, remaining Q02 sector deadline, both choice consequences, and past player decisions. The UI reads the persisted quest state and does not duplicate progression logic.
- Godot editor import exit 0; 22 scripts / 88,091 assertions / 0 failures; Windows Desktop export and EXE headless smoke exit 0; `git diff --check` passed.

## Unreleased — Q03 guaranteed drone reward

- Q03 stage 2 now rolls only its authored DR_GUN / DR_ARC / DR_MED reward set at RARE and exact sector TechLevel. A game-session integration regression clears the actual E09 quest target, resolves the choice, and checks the unsecured reward. The generic quest catalog validates that authored candidate pools are nonempty and unique.
- Godot editor import exit 0; 22 headless scripts / 88,091 assertions / 0 failures; Windows Desktop export and EXE headless smoke exit 0; `git diff --check` passed.

## Unreleased — transaction-derived autopilot and offline return report

- The existing autopilot records route/node/combat/checkpoint/terminal actions and derives its return report from actual state changes: battle/run outcomes, route, item gains/losses, strongest drop, gross/net currencies, faction changes, game-time, and real elapsed offline time. The road screen presents the added data; save validation checks optional new report fields and remains compatible with prior reports.
- Godot import exit 0; 22 headless scripts / 88,089 assertions / 0 failures; Windows Desktop export and EXE headless smoke exit 0; `git diff --check` passed. The 12-hour elapsed-time clamp is covered; a full 12-hour offline idempotency/parity acceptance run remains outstanding.

## Unreleased — save checksum JSON-roundtrip stability

- New snapshots calculate integrity hashes from the repeated JSON-normalized representation used after disk reads, preventing ordinary float serialization from invalidating a just-written temp save. Validation continues to accept older in-memory 1e-5, 1e-8 and legacy checksums; gameplay values are unchanged.
- Godot 4.7.2 editor import exit 0; 22 headless scripts / 88,085 assertions / 0 failures; `git diff --check` passed. An isolated resumed campaign E2E is in progress; Windows export/EXE smoke was not run.

## Unreleased — catalog-driven periodic and attack-counter triggers

- Periodic trigger support now dispatches authored item/tree actions for flags, shield recovery, interruption, TechLevel-scaled support damage and repeated D skills. ON_ATTACK_COUNTER actions now apply statuses, secondary damage or buffs through the shared deterministic combat pipeline instead of a list of effect IDs.
- Trigger cadence, source ownership, conditions, proc chance, ICD/once guards and proc counters are retained; the existing simulator remains the only combat engine. Godot import and 22 headless scripts / 88,085 assertions passed; diff check passed. Windows export/EXE smoke was not run.

## Unreleased — authored event trigger coverage

- The shared deterministic combat simulator now dispatches authored cast, dodge, incoming-damage/HP-threshold, status-expiry, interrupt, enemy-telegraph, drone-death, combat-start, heat-full and heat-release trigger actions. It reuses existing actor state, status definitions, combat RNG, damage pipeline and StatMath path.
- Triggered status application now honors catalogued DoT snapshots, duration bonuses, independent stacks and caps. Reaction-extra windows bypass one reaction cooldown; consume-on-hit buffs are removed after the operator's next direct attack or cast. Negative heat and SK_VENT now run the common lockout transition and release event.
- Godot 4.7.2 headless suite passed: 22 scripts, 88,085 assertions, 0 failures. `git diff --check` passed. Latest editor import and Windows export/EXE smoke were not run for this delta.

## Unreleased — packet and shield-response triggers

- The shared combat engine now runs catalogued ON_BEFORE_HIT packet modifiers and flag spending, shield absorption responses, and ON_EFFECT_SHIELD_SPENT temporary shields. This connects K4C/H4D, U04 charge/release, S3A/S4D, and X1 through the same 100 ms combat path.
- Regression exercises shield charging, energy recovery, consumed-shield damage, pre-hit penetration/damage changes, charge release, and X1 temporary shielding. Godot editor import passed; 22 scripts / 88,085 assertions passed; export/smoke not run for this delta.

## Unreleased — ON_KILL combat triggers

- The shared simulator now preserves last-hit provenance in typed, serialized combat actor state and dispatches catalogued kill triggers for energy recovery, heat change, VIRUS transfer, and secondary damage. Direct, secondary, and status-tick origins are distinguished for filters; unsupported event/action pairs still fail closed.
- Regressions cover K3D, H3C, U02, and N4C interacting on actual enemy death resolution. Godot editor import passed; 22 headless scripts passed (88,077 assertions); `git diff --check` passed. Windows export/smoke not run for this delta.

## Unreleased — executable direct-hit build triggers

- Direct player-hit triggers now execute catalogued `restoreShield`, `restoreEnergy`, `extendStatus`, and `secondaryDamage` actions alongside `applyStatus`. Filters, proc chance, owner ICDs, and once-per-combat/drone guards are honored; unsupported event/action pairs remain rejected instead of being silently accepted.
- Active temporary stat buffs are included in the existing StatMath resolution path while unexpired.
- Regression covers K4B shield recovery, U12 energy recovery against VIRUS, X2 duration extension, X4 secondary damage, and rejection of an unimplemented heat trigger. Godot editor import and all 22 headless scripts passed (88,071 assertions); export not run for this delta.

## Unreleased — EV12 energy refill

- EV12 now refills from the current `BuildResolver` max-energy result without looking up a nonexistent energy-cap field in route resources. The event still applies its authored −5 hull consequence.
- Godot editor import passed; 22 headless scripts passed (88,064 assertions), including an EV12 route transaction regression. Windows Desktop export and exported EXE headless smoke both passed.

## Unreleased — campaign combat rosters and save checksum compatibility

- Ordinary combat nodes now assemble multiple biome-themed enemies within the authored depth threat budget and unlock rules, with a six-actor cap and bounded E20 swarm packs.
- New saves use a wider float checksum bucket; validation continues to accept the prior 1e-8 bucket and pre-bucket legacy checksums. Gameplay save values are not quantized or changed.
- Godot editor import passed; 22 headless scripts passed (88,058 assertions). The explicit previous-bucket compatibility regression was added after this run and still needs verification. An isolated full campaign E2E reached d4 BOSS_A and recorded a defeat on its first attempt; later completion is unverified.

## Unreleased — resume paused quest chains

- The quest journal now offers “resume” for PAUSED chains while still showing the current stage. Previously the stage details branch swallowed the resume-button branch, leaving valid paused quests permanently inaccessible through the UI.
- Regression verifies a paused Q02 remains eligible and can resume from its saved stage. Godot editor import passed; 22 headless scripts / 87,649 assertions passed; Windows Desktop export and EXE smoke passed; `git diff --check` passed.

## Unreleased — physical quest route nodes

- Active quest stages now generate dedicated, connected `QUEST` nodes in the authored biome while keeping regular `EVENT` nodes intact. The node presents its real stage text and choices, enforces the quest target/requirements, consumes transactional rewards, persists progress, and returns the run to the route after a decision.
- Route intel marks quest nodes. Autopilot can resolve a configured eligible choice or safely leave an ineligible quest node. Legacy saved graphs with event-tagged quest stages remain compatible.
- Godot editor import passed; 22 headless scripts / 87,646 assertions passed, including dedicated-node links, Q06 target gating, and quest resolution/route return. Windows export/smoke not yet rerun for this change.

## Unreleased — Q06 objective gate regression

- Extended the Q06 route test: the sector's default anomaly alone does not unlock stage 2, while clearing the additional Q06-tagged anomaly does. This guards the objective condition rather than only checking node generation.
- Godot editor import and 22 headless scripts / 87,644 assertions passed. Windows export/EXE smoke passed for the preceding production-code checkpoint; this delta is test/doc-only.

## Unreleased — Q05 anomaly survival objective

- The Q05 fallback “survive three B05 combat nodes” now counts a cleared ANOMALY node. Regression verifies an anomaly among three B05 clears unlocks the Q05_S2 decision.
- Godot import passed; 22 headless scripts / 87,641 assertions passed; Windows Desktop export and exported EXE smoke passed; `git diff --check` passed. TypeScript not run (native Godot-only change).

## Unreleased — checkpoint quest and faction integration

- Campaign checkpoint transitions now inject active quest elite targets, quest-stage event IDs and faction world effects into the next sector, matching the normal expedition-start path. Previously `continue_campaign()` bypassed those integrations.
- Regression continues d5→d6 with Q03 active and verifies its E09 target plus Q03_S2 event tag. Godot import, 22 scripts / 87,639 assertions, Windows export, EXE smoke, and `git diff --check` passed. TypeScript not run (native Godot-only change).

## Unreleased — Q06 extra anomaly objective

- An active Q06 stage 2 now adds a second elite ANOMALY encounter to the B06 route, keeps the sector's default anomaly, and marks the added fight as the quest objective. The stage requires the tagged quest encounter to be cleared on new routes; old route saves retain the generic anomaly fallback.
- Godot editor import passed; 22 headless scripts / 87,634 assertions passed. Windows export and EXE smoke are pending for this checkpoint.

## Unreleased — quest-stage event identity

- Assigned unique event IDs to all 18 stages in the six authored quest chains. Generated event nodes record the matching IDs for active, biome-eligible stages; stage actions are gated to those IDs on new routes while older persisted graphs remain load-compatible.
- The quest catalog rejects duplicate or missing stage IDs. Regression pairs the Q03_S2 event tag with its required E09 elite target. Godot import and 22 headless scripts / 87,630 assertions passed. Windows export/smoke has not yet run for this checkpoint.

## Unreleased — quest milestone progression

- Completed quest stages now grant permanent `ceil(60 × R(depth))` XP. The XP milestone is marked in the existing quest flags and paid once; alternate completion counts, while a paused Q06 evacuation does not.
- `game_session_test.gd` checks the stage reward value and duplicate-claim prevention. Godot editor import, 22 headless scripts / 87,630 assertions, Windows Desktop export, exported EXE smoke, and `git diff --check` passed. TypeScript not run (native Godot-only changes).

## Unreleased — event consequence integration

- EV18 now contributes an E08 50%-strength allied turret to the next deterministic combat; the shared combat state saves the ally and it performs real attacks. EV05's extra RARE reward is now elite-only.
- EV08 B now asks the player which unsecured cargo item to surrender to VANTA, protects active-run equipped items, and removes the chosen item in the same saved transaction as the authored credits and reputation.
- Verification: Godot 4.7.2 editor import exit 0; 22 headless scripts / 87,624 assertions / 0 failures; Windows Desktop export exit 0; exported EXE `--headless --quit-after 3` exit 0; `git diff --check` exit 0. TypeScript not run (native Godot-only change).

## Unreleased — campaign chronicle

- Added the garage campaign chronicle with the authored Act I archive, Act II drone-line milestone, Act III finale, current ending choice, endgame access and faction standings. Entries render from persisted milestone flags and remain locked until their actual boss gates are cleared.
- Added a navigation regression for opening the chronicle. Checks: Godot 4.7.2 editor import exit 0; 22 scripts / 87,593 assertions / 0 failures; Windows Desktop export exit 0; exported EXE `--headless --quit-after 3` exit 0; `git diff --check` exit 0.

## Unreleased — functional enemy intel events

- EV15's archive option now selects a deterministic, previously unknown catalog enemy eligible for the current depth/biome and stores its ID in permanent META. Added a browsable enemy archive from the garage/quest journal with the discovered enemy's real catalog stats and description; the list is validated and save-compatible.
- EV10's boss scan now resolves the current route's actual boss, reveals the lower of its energy/digital resistance tags, and stores depth/boss-specific intel. The revealed weakness appears on that boss node in the road map.
- Regression covers EV15 grant and reload plus EV10's BOSS_A DIGITAL weakness. Checks: Godot 4.7.2 editor import exit 0; 22 scripts / 87,592 assertions / 0 failures; Windows Desktop export exit 0; exported EXE `--headless --quit-after 3` exit 0; `git diff --check` exit 0. TypeScript not run (native Godot only).

## Unreleased — bounded autopilot restart

- Added the policy editor controls for explicitly opting into a follow-up outing and setting `maxRuns` (1–100). After extraction only, the shared autopilot may repair the transport at the existing checkpoint service within `maxSpendRepair`, then starts a new sortie from the open outpost. It pauses the restart if repair cannot be paid for or exceeds the policy budget. Defeat never auto-restarts.
- Legacy RUN saves without `autopilotRunCount` begin the current chain at 1 before a restart; the first follow-up is counted as run 2 instead of resetting the maximum-run limit.
- Persisted the outing count across save/load, preserved the active offline autopilot for restarted runs, and accounted for game-time across sortie boundaries. Reports expose `runsStarted` and give a specific stop reason for time, max runs, restart rejection, or repair limits.
- Checks: Godot 4.7.2 editor import exit 0; 22 scripts / 87,587 assertions / 0 failures; Windows Desktop export exit 0; exported EXE `--headless --quit-after 3` smoke exit 0; `git diff --check` exit 0. Tests verify the persisted outing count and that the simulator stops before starting run 3 after `maxRuns=2`.

## Unreleased — persistent autopilot reports

- Added backward-compatible META storage for the 20 latest autopilot reports, strict structural validation, and a road-screen view of the latest five stop summaries. Empty history is omitted from saves, preserving the prior payload shape.
- Appended every completed online/offline simulation through the regular validated save transaction. Session coverage checks online/offline ordering and persistence after reload.
- Checks for this preceding checkpoint: Godot 4.7.2 editor import exit 0; 22 scripts / 87,580 assertions / 0 failures; `git diff --check` exit 0. Windows export was completed at the bounded-restart checkpoint above; TypeScript checks were not run for either Godot-only change.

## Unreleased — configurable autopilot policies

- Added a saved policy editor for the three starter profiles: min HP/shield, max Wanted, fuel reserve, allowed route node types, elite/anomaly permission, repair budget, route objective weights, checkpoint action, quest choice, explicit `Qxx:stage → choiceId` mappings, preferred mutations, cargo priority, and opt-in tow/abandon. Policies are immutable during an active outing, validated when saved, and backward compatible with profiles that have no settings object.
- Connected policy values to route scoring and route restrictions without exposing unrevealed node data; recorded autopilot repair spending in RUN so the configured cap persists across offline reloads; routed MATCH choices through real quest transactions; preferred mutation IDs through event choices; and explicit tow/abandon permissions through the emergency-exit transaction. Balanced cargo shipping honors the configured cargo priority.
- Tests cover UI save/reload, a named Q02 choice, preferred EV22 mutation, and a zero-credit repair budget. Auto-restart/max-runs remain unimplemented.
- Checks: Godot 4.7.2 editor import exit 0; 22 scripts / 87,578 assertions / 0 failures; Windows Desktop export and exported EXE headless smoke exit 0. The current executable is `%TEMP%\CYDLE-export-autopilot-config-final\CYDLE.exe`. TypeScript checks were not rerun because this WIP changes only native Godot code.

## Unreleased — protected checkpoint cargo shipping

- Added Master Spec §16.6 checkpoint SHIP as a persisted transaction: pay `ceil(10×R(d))` from unsecured credits, secure selected cargo up to five cargo units, and transfer up to 50% of each unsecured currency balance into the protected bank. A checkpoint can ship only once; its transaction ID and shipped cargo are saved, and already secured items are not duplicated.
- Connected the balanced autopilot checkpoint action to ship the highest-rarity cargo that fits the five-unit limit and up to half the run currencies before continuing. The road screen lets the player choose cargo and currency transfer percentage.
- Added session regressions for fee, cargo capacity, currency split, permanent securing, duplicate prevention, and balanced-autopilot shipping; added a checkpoint UI presence check.
- Currency transfer is measured against the original unsecured wallet balance; the service fee is charged separately, and the quote refuses a credit transfer if fee plus transfer exceeds available run credits.
- Checks: Godot 4.7.2 import exit 0; 22 scripts / 87,561 assertions / 0 failures; Windows Desktop release export and exported EXE headless smoke exit 0; `git diff --check` passed. The current export was built at `%TEMP%\CYDLE-export-checkpoint-shipping-final\CYDLE.exe`.

## Unreleased — selectable specification-based autopilot presets

- Added persistent CAUTIOUS, BALANCED and AGGRESSIVE starter presets with the §16.5 risk, health/shield, Wanted, route restriction, fuel reserve and checkpoint defaults. The player selects a preset between sorties; the active choice is immutable during an outing and appears on the road screen.
- Replaced the legacy hand-weighted node scores with the specification's normalized loot/XP/quest/service/risk/fuel/Wanted scoring equation. Only revealed type/threat/loot hints, visible quest targets, graph fuel cost and current state are considered; hidden node content is not scored.
- Old single-BALANCED saves remain compatible and add the other preset records when a different profile is selected. TypeScript's starter save oracle and schema now include the optional selected preset. Custom weights, expense/filter/quest/tow controls, auto-restart and report history remain unimplemented.
- Checks: Godot editor import; 22 scripts / 87,541 assertions / 0 failures, including route UI selection and hidden-info policy; TypeScript typecheck, 207 tests, data validation and production build passed after the save-schema refinement. Windows export not rerun.

## Unreleased — emergency recovery for no-fuel routes

- Implemented Master Spec §16.4 evacuation tow and ABANDON_RUN through persisted `GameSession` transactions and a route-screen confirmation flow. Tow pays `ceil(30×R(d))` credits, drops one deterministic random unsecured item, loses 30% of remaining unsecured currencies and secures the rest; abandon loses all unsecured cargo/currency and damages permanently equipped gear by 10 durability.
- Added tow/abandon regressions and taught the campaign E2E driver to invoke these real session actions when it has no affordable outgoing edge. The saved d12 no-fuel route was recovered by tow; BOSS_CORE was defeated after 192 ticks, the FREE_CORRIDOR ending was selected, and the player continued through d13 combat to its checkpoint. The d13 first sortie also used the real tow, and the next sortie cleared three combats and reached the checkpoint.
- Corrected the E2E stop condition so `CAMPAIGN_COMPLETED` still permits a pending d12 ending choice; then extended acceptance through the d13 route/checkpoint. Full campaign E2E and, afterward, Godot editor import plus 22 scripts / 87,529 assertions / 0 failures passed. TypeScript and Windows export were not rerun for this Godot-only WIP.

## Unreleased — high-rarity generated gear remains equipable

- TypeScript and Godot BuildResolver no longer reject distinct generated affixes solely because they share a broad pool group; duplicate affix IDs still fail validation. The item catalog permits up to five affixes while some slots, including MAIN, expose fewer groups, so strict group validation made valid T12 drops unusable. Item generation and numeric rolls are unchanged.
- Added a deterministic T12 legendary MAIN build regression and regenerated the native resolver fixture for parity. The E2E final-boss retry is active; the first BOSS_CORE defeat retained 8,832/9,268 HP after 2,141 operator damage.
- Checks: TypeScript 207 tests, typecheck and Vite build passed; Godot editor import and 22 scripts / 87,512 assertions passed; `git diff --check` passed. Windows export not rerun.
- Master Spec §12.2 group uniqueness conflicts with its affix counts and slot pools. This current compatibility rule is documented for deliberate content/spec resolution.

## Unreleased — checkpoint sector progression

- Continuing past any depth checkpoint now persists that depth as cleared, independently of the d4/d8/d12 boss-gate unlock. This makes depth based quest availability and the Master Spec's HANGAR L2 after d6 progression reachable at the correct point.
- Added a session regression that advances past d6 and verifies both the META milestone and HANGAR L2 gate. The campaign diagnostic equips the second drone when the upgrade is available and affordable.
- Corrected the diagnostic garage picker to exclude items already mounted in another slot. The previous pass moved DR_BULWARK from DRONE_1 to DRONE_2 rather than equipping a second distinct drone; the preserved profile is stopped before further progression so the corrected pass can verify both slots.
- Godot headless suite: 22 scripts, 87,512 assertions, 0 failures; Godot editor import exit 0. Full d8 boss and campaign validation remains active/incomplete.

## Unreleased — stable save checksum round-trips

- Fixed a save-integrity failure where Godot's JSON float serialization alternated between adjacent numeric representations after repeated load/write cycles. New checksums canonicalize numeric precision without changing stored gameplay values; old checksum documents remain loadable. Added repeated file/JSON round-trip regression coverage.
- Campaign E2E reproduced the issue at the d8 boss reward save. After the fix, the resumed d8 BOSS_B defeat (167 ticks) persisted and reloaded correctly, then the driver resumed its next attempt; a successful d8 gate clear is still unverified.
- Godot headless suite: 22 scripts, 87,506 assertions, 0 failures. Full campaign acceptance remains in progress.

## Unreleased — targeted boss reactions and d4 campaign win

- Tactic condition `enemyCasting` now scopes to the selected target when one exists; untargeted rules retain group-wide behavior. This fixes boss tactics that previously spent EMP on a healer cast before the boss telegraph. Added a regression covering simultaneous boss/healer targets.
- The campaign E2E profile now uses the existing K3A→ARMOR_BREAK / K2B damage synergy, heavy armor, a healing reaction, boss-targeted EMP and healer-selecting Burst. The real shared-engine d4 run defeated BOSS_A in 27.2 s, killed E09 and interrupted both rail casts; d4 rewards persisted and an initial d5–d7 pass secured the pre-boss d8 farm. The driver is replaying d5–d7 before continuing to d8. Full campaign completion remains unverified.
- The isolated diagnostic harness can fund repairs by dismantling secured unequipped duplicates and preserves its heavy armor build. No game balance values changed.
- Godot 4.7.2 editor import passed; 22 Godot scripts / 87,504 assertions / 0 failures; TypeScript Vitest 206/206; typecheck, production build and `git diff --check` passed. Windows export has not been rerun.

## Unreleased — tactic thresholds and K3A proc-weight parity

- Corrected the new-game starter shield trigger from invalid whole-percent `45` to the native 0–1 fraction `0.45` in Godot and the TypeScript save oracle. The tactic editor now constrains fractional HP/shield thresholds to 0–1 and displays older whole-percent thresholds as normalized fractions; the combat simulator interprets historical values such as `45` as 45%.
- Direct `ON_HIT` status procs now multiply their configured chance by the skill's `procWeight` as well as the owning build's proc multiplier, matching the TypeScript dispatcher. The deterministic K3A regression and legacy threshold regression pass.
- Campaign diagnostics: at level 11, the defensive tree plus shield/EMP reached BOSS_A, killed E09 and interrupted once, but died after 17.7 s with 1,034 boss HP left. A 10-point mixed K/defense tree with `PP_AMMO` is now saved for the next real route attempt; its boss result is pending. No balance values changed.
- Checks: Godot editor import 0; Godot 22 scripts / 87,501 assertions / 0 failures; TypeScript/Vitest 206 tests, typecheck and Vite build pass; `git diff --check` passes.

## Unreleased — direct kinetic status procs and resource-safe settlement

- The Godot combat simulator now executes direct `ON_HIT` status triggers from non-skill build sources, including K3A's kinetic ARMOR_BREAK proc. Proc chances use the deterministic battle RNG; cooldowns belong to the trigger owner; damage type/directness and supported status conditions are respected. Secondary splash/detonation packets do not count as direct hits.
- Combat settlement clamps returned HP and shield to the persisted sortie maxima, preventing fractional max-stat drift from rejecting an otherwise valid save after victory.
- Added a Godot combat regression that forces K3A's proc and checks both ARMOR_BREAK and the proc metric.
- Latest Godot editor import and headless tests pass (22 scripts, 87,499 assertions); `npm run typecheck` and `git diff --check` also pass. The resumed diagnostic completed its three d3 extraction farms and has started the next d1–d4 attempt. BOSS_A and later sectors are not yet confirmed in this continuation.

## Unreleased — terminal loadout persistence and campaign diagnostics

- Save validation no longer compares a terminal run's historical field equipment against the player's post-run skills/tree. This lets garage build changes after defeat/extraction persist while keeping full BuildResolver validation for active runs.
- Added regression coverage proving an incompatible historical energy loadout is rejected during a live run but accepted as terminal history, and still reloads successfully.
- Added an isolated solo E09 campaign-combat integration check; the deterministic encounter reaches victory within the test's 900-tick bound.
- Expanded the opt-in campaign driver to preserve its resumed test profile, collect three legal d3 extraction farms before each boss gate, prefer compatible T3 kinetic rifle loadouts, restore the canonical starter skills, and use a mixed defensive/kinetic tree. The d4 boss remains undefeated in the current acceptance profile; no balance values were changed.
- Latest checks: Godot editor import passed; 22 Godot tests passed, 87,481 assertions, zero failures; TypeScript typecheck passed. Full campaign completion, Windows export, and d8/d12 boss acceptance are not verified by this checkpoint.

## Unreleased — campaign acceptance continuation

- Added the Master Spec `healer` tactic selector in the shared combat simulator, save command validation and tactic editor; unavailable targets fall back deterministically to the first live enemy.
- Prevented reaction-channel skills from starting on the main combat channel; regression coverage confirms SK_EMP remains a reaction and can still interrupt.
- Fixed d4/d8 milestone reward settlement that crashed after a boss victory when constructing milestone arrays through a typed GDScript array.
- Expanded the opt-in shared-engine campaign driver to exercise the authored starter loadout, healer-focused SK_BURST, secured prototype/equipment progression and resumption from a persisted victory.
- Acceptance has defeated BOSS_A and resumed through its saved victory into d5–d7. Full d12 ending/d13 acceptance remains in progress and unverified.

## Unreleased — B06 anomaly route integration

- B06 sectors now generate a guaranteed ANOMALY branch using an existing elite modifier and a biome-eligible enemy; other biomes do not receive this node.
- Anomalies enter the shared 100 ms combat simulator, award elite-band loot, remain at the node after victory for an explicit exit, reject repeat fights, and can complete the targeted TECH contract with its unique item/DATA/blueprint reward.
- B06 scouting operates one INTEL level lower. Q06's early sensor and future-preview unlock can reveal one upcoming anomaly protocol; consuming the scan is persisted.
- Q06 stage two now becomes reachable after surviving an anomaly and arriving at a B06 event. Contract loot advances from the post-combat RNG state, avoiding replaying the same loot stream.
- Added route generation, INTEL/preview, anomaly settlement, Q06 progress, and TECH-contract regressions.
- EV06 now stores its three nearest forward node disclosures in the RUN save; the road map exposes those node types to both the player and autopilot, including after reload.
- Connected quest `signalContract:U09/U04/U14/U07/U18` unlocks to biome-gated SIGNAL offers and generated elite objectives; successful target fights grant the exact unique template through the shared item factory with save validation and duplicate-reward protection.
- Added all eight endgame escalation contracts with a three-contract maximum, saved per-sector selection, picker UI after campaign ending, and actual route, combat, INTEL, loot, wanted, data, scrap, and travel effects.
- Connected Q03's SERVICE choice to paid hull repair at checkpoints (+15% repair amount) and gated Q01/Q02 visit-biome and Q04 elimination follow-ups until their next matching sector.
- Persisted and validated each accepted world-seeded contract offer's event ID, with old RUN saves remaining compatible.
- ESCORT offers now reveal their deterministic faction reputation reward; campaign faction-control endings theme endgame ESCORTs to the controlling faction, and the accepted reward survives save/load validation.
- Reputation thresholds now affect the world loop: +30/+60 discounts faction shop stock by 10%/15%, +60 exposes one faction HUNT contract, ≤−30 adds 3 wanted after a matching faction victory, and ≤−60 adds a marked elite bounty to the route. The encounter faction, discount, contract, and bounty are visible in the interface.
- Added session regressions for threshold contract acceptance, discounted persisted shop stock, hostile route bounty, and wanted gained from a hostile faction fight.
- Active Q03/Q04/Q05 kill-elite stages now reserve a deterministic reachable ELITE target in the next matching biome (excluding the active contract target); the target enemy and quest marker are persisted in the route and disclosed on arrival.
- Added route-generation regressions proving Q03's E09, Q04's E12 and Q05's E19 objectives exist in B03/B02/B05 at the correct progression points.
- Corrected campaign boss assignment to the authored BOSS_A/BOSS_B/BOSS_CORE sequence at d4/d8/d12. Endgame bosses are now seeded from the current biome-compatible catalog, avoid the immediately previous boss when alternatives exist, and persist the last defeated boss across sectors and reloads.
- Added boss-selection fixtures for all three campaign milestones plus deterministic, compatible, non-repeating endgame selection.
- A faction-control ending now generates a distinct endgame-exclusive HUNT offer for its controlling faction, with compatible targeted loot and faction reputation; neutral endings and all ordinary contracts remain available. The offer is accepted through the same deterministic contract target/reward pipeline.
- Added the VANTA Wanted rules from Master Spec §16.3: reputation below −60 starts an expedition at +10 Wanted; VANTA ordinary/elite route victories add +4/+7 Wanted, with the separate hostile-reputation +3 applied on top. The node view previews the consequence.
- Faction bounties now avoid quest-reserved elite nodes, so hostile standing cannot replace an active Q03/Q04/Q05 target; added a combined hostile-faction and quest-target regression.
- Wanted ≥80 now deterministically assigns one catalogued elite modifier to each enemy without an existing modifier, using seed+node so combat restores remain deterministic; the node UI warns about the effect.

## Unreleased

- Added garage affix replacement and free-slot crafting with deterministic rolls, TechLevel-based cost previews, compatibility/rank/TR validation, and atomic save updates.
- Added secured unequipped item sale and dismantling, shop-price sale formula, digital-tag DATA recovery, capped material rewards, explicit confirmation, and single-transaction item removal.
- Added regression coverage for affix replacement/addition, sale, dismantling, retained item identity, resource costs, rarity slots, and duplicate payout prevention.
- Added backward-compatible save fields for the 100-entry disassembly history and latest undo record. Undo restores the original owned item and revokes the exact materials; entering a route node expires it. Inventory exposes recent reason/seed/reward details and the available undo action.
- Added base-item fabrication for exact quest/contract blueprints, COMMON output, open TechLevel selection, spec-scaled SCRAP/DATA quotes, deterministic item IDs and atomic protected-resource spending. TECH contract completion unlocks the schematic matching its generated tech reward.
- Imported the six three-stage quest chains and three contract templates from frozen TypeScript data into Godot. Added the persisted quest journal and initial biome-gated HUNT, TECH, and ESCORT contract gameplay, including generated objectives, rewards, checkpoint requirements, and repeat-grant protection. Offer breadth and some quest semantics remain incomplete; B06 anomaly gameplay is recorded in the newer entry above.
- Earlier item-generation/save changes left an unresolved conflict between the affix-group uniqueness rule and broad catalog groups; see the active HANDOFF note before changing item-roll validation.
- Added a conservative road autopilot that scores only revealed route information, acts through existing game transactions, resolves battles with the shared 100 ms simulator, extracts at checkpoints, pauses on material decisions/resources, and reports its stop reason. Configurable policy breadth remains incomplete.
- Added explicit persisted offline-autopilot opt-in. Loading an active opted-in run simulates elapsed wall-clock time up to 12 hours through the same route, node, combat, and reward transactions; decision stops such as the tutorial prototype choice require the player's input.
- Added d4/d8 campaign milestone flags and a final d12 ending choice. Free Corridor and faction-control endings record persistent branch flags, unlock endgame/sector 12, and gate final extraction or continuation until the choice is made. Depth-13+ biome rolls use saved history to prevent three identical biomes consecutively.
- Completed Q02 timeout compensation and Q05's documented alternate three-combat requirement in B05, preserving the elite E19 path.
- Updated implementation guidance and roadmap to FULL GAME FIRST: integrate the full campaign and all major systems before Simulation Lab extras or polish.
- Implemented the first native main-channel skill cast (`SK_BURST`) with energy/heat costs, cooldown, immutable windup and recovery timing, three shared damage-pipeline hits, tactical-priority selection, and AUTO fallback. Added a 14-frame TypeScript-oracle replay; other skills and conditional tactical rules remain explicitly unsupported.
- Added native `SK_PIERCE` cast replay with its +20 armor penetration applied only to the skill hit. Corrected BuildResolver so skill-local stat effects do not leak into permanent build modifiers; verified a 16-frame TypeScript-oracle replay including intervening AUTO attacks.
- Added native `SK_EXEC` low-HP execute multiplier and lowest-HP target selection, covered by a 16-frame TypeScript-oracle replay against a wounded enemy.
- Added native `SK_PLASMA` using the shared TECH_E basis, energy damage, and skill-energy scaling; verified with a 16-frame oracle replay.
- Added five TypeScript-oracle auto-combat replays for RIFLE_K2, PLASMA_E1, SPIKE_D2, DUAL_H1 mixed packets, and SHOTGUN_K5 pellets. Combat stat conditions now resolve through shared `StatMath` at point of use, and weapon heat-per-attack is applied before the attack event.
- Ported catalogued ordinary-combat status effects for ARMOR_BREAK, SHOCK, DRONE_JAM, SHIELD_LEAK, MARK, SCAN_MARK, DRONE_MARK, CONTROLLED, GUARD, OVERCLOCK, ACC_BUFF, EVASION_BUFF, SHIELD_REGEN_BUFF, and two-stack BERSERK. Added 14 TypeScript-oracle replay checkpoints, including a working drone jam case; STUN/JAM and cast/tactical behavior remain unsupported.
- Exported and validated the 25-entry native status catalog. Added native BLEED/BURN/VIRUS status application, independent DoT stacks, snapshot ticks, expiration-boundary ticks, and status expiration to the single combat transition; added a 40-frame BLEED replay fixture checked against the TypeScript oracle. Other status behaviors remain unsupported.
- Added a checked 15-frame TypeScript combat oracle and an immutable native `step_combat()` slice for eligible basic auto-attack encounters, covering baseline resource updates, hit/crit RNG, shared damage mitigation, shields/HP, metrics, death, and combat termination.
- Added typed native combat actor/state initialization for operators, drones, and enemies, plus deterministic RNG, rules hash, metrics, and COMBAT_START event; verified against one TypeScript `createCombatState` oracle fixture with an EL_FAST enemy.
- Exported and validated the native enemy catalog: 24 regular enemies, 6 bosses with phase/rotation data, and 6 elite modifiers. This is a data port only; combat behavior remains pending.
- Exported the native skill/passive/tree/mutation catalogs and extended `BuildResolver` to validate and apply these selections through the shared stat pipeline; expanded the two TypeScript build oracle fixtures.
- Added `GameSaveFactory` and a checked TypeScript starter-save oracle. The generated native starter profile contains 12 deterministic item instances and is now the basis of typed save-state roundtrip tests.
- Strengthened native save validation: full item records resolve against the item catalog; META and RUN equipment must be uniquely owned, slot-compatible builds resolved by `BuildResolver`; added invalid-template, invalid-skill, and RUN ownership regressions.
- Added an initial typed native game-save model and structural validator around `SaveRepository`, including typed repository roundtrip coverage. This is groundwork only: active-run field parity and full legacy schema validation remain incomplete, and gameplay does not yet consume the typed state.
- Extended the native run-save model for events, service/checkpoint counters, deferred travel/combat effects, and command/result fields, with active-run roundtrip and range checks. Nested item, graph, and combat-result validation still needs parity with the reference schema.
- Added the first native canonical build resolver over the shared `StatMath` pipeline. It applies attributes, armor, implants, affixes, weapons, and drones, validates supported equipment constraints, and matches two TypeScript build fixtures. Skill/passive/tree/mutation systems and run-build ownership checks remain unported and are rejected explicitly.
- Exported all 73 ordinary and unique item templates from the frozen TypeScript catalog into native JSON, with a Godot loader that checks top-level structure and returns immutable-by-copy definitions.
- Exported all 30 affix definitions and item roll tables; added typed item instances plus deterministic rarity, affix, and biome loot generation. Nine golden cases match the TypeScript oracle for common/rare/unique creation, rarity shifts, biome selection, unique drops, and unique fallback.
- Added a native asset-manifest validator and a Windows GitHub Actions workflow for Godot import/tests/export plus the frozen reference checks.
- Added root agent instructions for the Godot-only product boundary, protected branches, deterministic core, asset provenance, and local verification commands.
- Fixed TypeScript 5.9 readonly-array typing in the math fixture generator without changing fixture values.
- Corrected the final planned audio row in the asset manifest so its CSV fields align with the manifest header.
- Enabled EV05's elite contract. Its RARE reward remains pending through ordinary combat and is granted exactly once at the first later ELITE.
- Added tests for EV05 event eligibility, persistence through an ordinary combat, guaranteed RARE elite reward, and contract consumption.
- Enabled EV18's allied turret choice: one E08 joins the next combat with 50% HP and damage through the existing ally simulator path. The log records ally count and the saved effect is consumed once.
- Added tests for EV18 event state, generated map eligibility, ally delivery, and consumption after combat.
- Enabled EV14 and EV21 forced bounty events. EV14 applies +25% credits; EV21 targets E21 and guarantees one RARE reward roll. Both convert the next selected ordinary COMBAT to BOUNTY and use the existing BOUNTY reward/XP rules.
- Added tests for event eligibility, pending target/effect persistence, map node promotion, credit scaling, and guaranteed rare reward identity.
- Enabled EV16's two encounter choices. Paying skips the next ordinary COMBAT without XP or loot; fighting transforms the next selected ordinary COMBAT into an ELITE and grants one extra item roll. The pending effect persists across service/checkpoint nodes and clears after the next combat encounter.
- Added regression tests for EV16 currency cost, zero-reward skip, forced elite node/reward behavior, and deterministic generated event availability.
- Enabled EV17 and EV24 after wiring their `extraHeat` and `shieldBonus` values to the shared combat simulator. Pending values are saved in run state, logged in `COMBAT_START`, consumed after one combat attempt, and default to zero on legacy active saves. Generated events continue to exclude unsupported deferred effects.
- Added regression coverage for EV17/EV24 choices, map eligibility, combat delivery and consumption, plus legacy route/event/combat commands that omit newer state fields.
- Enabled EV19 in generated road maps and applied its signed travel-time effects to exactly the next successfully chosen edge. Effects persist within an active run, clamp total travel time at zero, reset after use, and default to zero when older active saves lack the field.
- Added tests for EV19 availability, route timing, effect consumption, invalid route preservation, zero-time clamping, and legacy save parsing.
- Enforced run cargo capacity using the canonical build's cargo stat and item cargo-unit values. The road screen shows used/capacity; SHOP blocks purchases that do not fit; EVENT item grants are rejected atomically when full; CACHE and combat loot keep fitting items in stable order and report discarded overflow; CARGO-module swaps cannot strand the current load above capacity.
- Added regression coverage for cargo unit totals, base and CARGO_2 capacity, shop/event overflow, combat/cache overflow, and loadout capacity reduction.
- Added a playable deterministic SHOP road node to regular sectors. Each store shows five seed-stable biome-pool items and exact §19 prices; one-time purchases spend unsecured run credits and add at-risk cargo. Closing the node advances game time by 8 seconds.
- Added tests for shop stock, purchase payment and ownership, idempotency, sold/invalid items, insufficient funds, shop completion, and regular-sector placement.
- Enabled optional ELITE encounters in regular routes and a wanted-gated BOUNTY encounter (at most one per sector at wanted 50+). Both use the existing deterministic combat simulator and their §19 currency/item/core rewards.
- Applied B02 credit and corporate wanted bonuses and the B04 data bonus to combat rewards. BOUNTY awards no XP because the master spec defines none for that encounter.
- Added graph and combat integration coverage for elite/bounty generation and reward behavior.
- Added persistent one-step EVENT nodes from the supported subset of the event catalog. Choices apply run resource/currency/item effects and permanent bounded faction reputation; choices resolve once and event IDs do not repeat during one run.
- Added save defaults for faction reputation and campaign flags so existing version-1 saves remain readable. Advanced event hooks for reveals, next-combat modifiers, mutations, and quest progression remain unimplemented and are excluded from generated event choices.
- Added fuel emergency tow and abandon actions when all outgoing roads exceed available fuel. Tow applies its specified fee, 30% currency loss and one deterministic cargo loss before securing the remainder; abandon loses all unsecured rewards and wears secured equipped items by 10 durability.
- Added regression coverage for tow/abandon settlement, explicit protected-bank permission, retained cargo, durability loss, and blocking emergency actions when travel is affordable.
- Added run-specific equipment ownership and loadouts. Secured inventory and unsecured cargo feed the same canonical build resolver; equip/unequip is validated at safe points, combat uses the selected field loadout, extraction secures it, and defeat loses unsecured gear while restoring protected gear with durability loss.
- Connected the run loadout editor to the road screen with compatible-slot filtering, implant/drone unlock states, and warehouse/risk labels.
- Kept active run saves created before loadouts readable: they inherit the previous garage equipment on load, and their original snapshot/export checksums remain verifiable.
- Added tests for cargo equipment, invalid slot/loadout operations, extraction and defeat ownership settlement, plus legacy active-run checksum compatibility.
- Added protected garage equip/unequip commands and a loadout editor in the Build screen. Commands use the canonical build resolver, preserve equipped items in the secured inventory, and lock permanent equipment changes during an active run.
- Added garage equipment tests for valid swaps, incompatible slots, required main weapon, and active-run restrictions.
- Added the secured inventory screen with a separate at-risk run-cargo list. Players can dismantle one owned, unequipped, non-material item for the existing catalog salvage value; the confirmation shows exact scrap/data yield and the action is blocked during an active run.
- Added regression tests for one-time dismantling, equipped-item protection, unsecured ownership, and active-run restrictions.
- Added protected item repair from the Inventory screen. The cost follows the master-spec durability formula, is capped by a comparable common item's price, consumes protected scrap only, restores durability to 100%, and leaves TR unchanged.
- Added repair tests for exact cost, insufficient scrap, already repaired items, unsecured ownership, and active-run restrictions.
- Added deterministic affix reroll and one-tier upgrade operations to the Inventory screen. They consume the declared TR/scrap/data costs, obey the TechLevel tier cap, preserve unselected rolls, reject fixed AF_SCAN rerolls, and preview costs before use.
- Added craft tests for targeted reroll, tier upgrade, exact resource/TR consumption, insufficient resources, tier caps, and fixed affixes.
- Completed affix replacement/addition and secured-item TechLevel calibration. Replacement/addition enforce category compatibility, no duplicate affixes, and rarity slot limits; TechLevel upgrades preserve item identity, affixes, and TR while consuming a matching calibration core plus exact scrap/data.
- Added calibration tests for replacement, addition, core group, unlocked TechLevel limits, active-run protection, and full rarity slots.
- Added a deterministic, persisted first-sector run loop with validated route, combat, cache, service, and checkpoint commands; battle resolution reuses the existing simulator. Checkpoint shipment/evacuation, death settlement, item/currency rewards, XP, and six-layer graph state are tested.
- Connected the road screen to transactional save commits with route selection, combat report/log, cache choice, repair/fuel services, and checkpoint decisions.
- Kept old schema-v1 saves compatible and verified active-run save/reload without graph reroll.
- Added the real Vite/React entrypoint and responsive Garage/Build screens.
- Added the CYDLE v1 strict save schema with starter profile, canonical equipment, tactics, transport, and protected/unsecured resources.
- Added IndexedDB persistence through Dexie with transactional, checksummed snapshots, two-valid-snapshot retention, recovery to a prior valid snapshot, and checked JSON import/export.
- Added catalog cross-reference validation at app startup and through `npm run validate`.
- Added four save-boundary tests, including IndexedDB integration through `fake-indexeddb`.
- Multi-sector campaign, general inventory transfer, item generation recipes, other road-node systems, later save migrations, CI, browser E2E, and final art/animation remain incomplete.
# Unreleased — resumed combat budget and quest choice gating

- Fixed offline/autopilot accounting when continuing a partially simulated combat snapshot: previous ticks remain in cumulative run time but no longer consume the new simulation budget twice. Added save/reload and exactly-once settlement regression.
- Q03/Q04 stage-2 paid alternatives can be used without winning the elite fight, while elite reward options remain locked until their objective is satisfied. UI quotes and transaction checks share readiness logic.
- Q02 stage-3 delivery choice now binds to B03 rather than inheriting the initial B01 biome.
- Hardened the Godot test runner to skip scripts that fail parsing instead of attempting to instantiate them.
- Verification: Godot 4.7.2 headless import exit 0; native suite 23 tests / 88,624 assertions passed; npm tests 207 passed; npm build exit 0. Windows export and campaign E2E were not run.
