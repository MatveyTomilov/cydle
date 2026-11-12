# Changelog

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
