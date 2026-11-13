# Autobattle V2 — Gate A evidence

Working branch: `feature/autobattle-v2`; draft PR #3. Gate A is **OPEN**.

| Stage | Actual state | Missing acceptance evidence |
|---|---|---|
| A1 core | Contract, serialized channel, real-weapon compiler/factory and opt-in shared-simulator dispatch; legacy snapshot guard | Authored ability/proc/drone compiler, session V2 dispatch, integrated save/replay and reaction bus |
| A2 Thermocircuit | Prototype ARC/HOT/Vent/heat-shield only | Real catalog equipment, armor, passive, KITE-3, branches |
| A3 playable slice | Existing V1 screens and progression preserved | V2 garage/loot/Build Lab/battle integration |
| A4 campaign | No V2 natural campaign attempted | Natural component acquisition, 12 sectors, ending, early endgame |
| A5 offline/commands | No V2 integration | Manual consumables, command idempotency, same-engine offline parity |
| A6 reference | Small deterministic core regressions only | 12 scenario categories, paired seeds, resource budgets, GUI screenshots and Windows playthrough |

## Migration map

1. Retain V1 math/status/replay fixtures and safely finish existing V1 snapshots through their version. Unknown versions reject without modifying META/RUN.
2. Compile immutable authored actions from real resolved equipment; use existing CombatFactory actors and common damage/status/proc operations, not duel constants as live content.
3. Introduce V2 dispatch in shared runtime and persist its channel/commands with version-specific validation. Remove player tactics from the V2 flow only when real loadouts can play.
4. Bind BattleView, session rewards, offline and Lab to that same versioned runtime. Retire isolated duel logic once the integrated tests replace its role.

## Initial evidence

- Source `5d9e059`, CI run 43460440500: all checks successful, Windows artifact 14055363627 (40,881,686 B), exported EXE smoke successful. PR tests use merge commit `a8021caf645a13c95537246992cb211aa184a4c4`. This executable still boots V1 gameplay.

- `5d9e059b3a81a874b0690b8c057c8c886c50b496`: independent detached regression, 30 native scripts / 89,232 assertions / 0 failures; import/diff check exit 0. Real weapon/channel runs through the shared simulator and resumes a typed snapshot. GameSession activation, JSON float persistence parity and full V2 build integration remain open.

- `23194c2e2f8f0ce475247303b8409ce766d6322a`: independent detached regression, 29 native scripts / 89,072 assertions / 0 failures, import and diff check exit 0. First shared-runtime adapter is a subsequent checkpoint; it is not a playable migration yet.

- Base `d6dc327`: CI run 43452520024 passed 28 scripts / 89,045 assertions and exported/smoked Windows EXE. This proves prototype and V1 only.
- New targeted tests (fresh process): combat_step 483, V2 contract 54, channel 19, duel 26 assertions, zero failures, exit 0. Added JSON post-commit channel restore, interruption, support starvation, invalid state/version and overheat boundary regressions. Full committed-checkpoint regression/CI results are recorded in HANDOFF when available.
- Independent reviewer identified unreachable thermal lock, shallow channel validation and equal-time procedural ordering; corrected in this checkpoint. Fairness diagnostic concern was checked: the first all-candidate selection already preserves rejected offensive candidates; a targeted test now proves ENERGY remains visible.
- No V2 campaign, progression availability, rendered/offline parity, GUI quality or balance claim is made. Do not merge the draft PR until all Gate A acceptance criteria have actual evidence.
