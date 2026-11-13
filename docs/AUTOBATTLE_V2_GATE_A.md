# Autobattle V2 — Gate A evidence

Working branch: `feature/autobattle-v2`; draft PR #3. Gate A is **OPEN**.

| Stage | Actual state | Missing acceptance evidence |
|---|---|---|
| A1 core | Contract, serializable channel, fixed headless duel using canonical damage math; legacy snapshot guard | Real build/compiler, factory and session V2 dispatch, integrated save/replay and reaction bus |
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

- Base `d6dc327`: CI run 43452520024 passed 28 scripts / 89,045 assertions and exported/smoked Windows EXE. This proves prototype and V1 only.
- New targeted tests (fresh process): combat_step 483, V2 contract 54, channel 19, duel 26 assertions, zero failures, exit 0. Added JSON post-commit channel restore, interruption, support starvation, invalid state/version and overheat boundary regressions. Full committed-checkpoint regression/CI results are recorded in HANDOFF when available.
- Independent reviewer identified unreachable thermal lock, shallow channel validation and equal-time procedural ordering; corrected in this checkpoint. Fairness diagnostic concern was checked: the first all-candidate selection already preserves rejected offensive candidates; a targeted test now proves ENERGY remains visible.
- No V2 campaign, progression availability, rendered/offline parity, GUI quality or balance claim is made. Do not merge the draft PR until all Gate A acceptance criteria have actual evidence.
