# CYDLE build resolver

## Intent

Connect the recovered item, attribute, skill, passive, mutation, and specialization data to the existing stat engine. A build shown as legal by the resolver must be the same build later consumed by combat and Build Lab.

## Goals

- Resolve one immutable `BuildLoadout` into exact `StatResults`, stat sheet, equipment, and active effects.
- Validate slot/type compatibility, unlocked slot counts, duplicate ownership, neural capacity, skill/passive limits, tree point limits and prerequisites, and mutation limits.
- Apply the v2.0 attribute formulas and item TechLevel scaling, including durability penalties and SYN scaling only for tagged implant effects.
- Keep one stat pipeline (`resolveStats`) and expose its CalcTrace for every calculated stat.

## Non-goals

- Simulate attacks, statuses, enemy AI, road state, persistence, or UI in this stage.
- Infer triggers from item names/descriptions; executable behavior comes only from typed effect definitions.
- Auto-repair or auto-correct an invalid loadout.

## Approaches

1. Let UI/components calculate stats independently: rejected because it would create a second math path.
2. Put item/attribute logic inside combat: rejected because Build Lab and validation need the same calculation without running a fight.
3. Add a pure `resolveBuild()` module over current data and the existing stat resolver: selected because it centralizes legality and exact stats for combat, Build Lab, and simulation.

## Constraints

`CYDLE_MASTER_SPEC.md` v2.0 sections 5, 6, 9, 10, 11, 12, 14, 15, 22.1, 23, and 26 are normative. Preserve integer milliseconds and unrounded math. Never mutate input items or definitions. A result with any validation issue is invalid and must not start combat.

## Implementation decisions

- Base attributes are 5; only points explicitly granted by level can be assigned above 5.
- Implant slots 5–6 and drone slot 2 require explicit unlock counts; defaults match a new save (four implant slots, one drone slot).
- `UNIVERSAL` implant items fit any implant socket; any implant can fit a `UNIVERSAL` socket, consistent with it being an adapter socket.
- Build resolution produces the current math context. Runtime target/HP/status conditions remain conditional trace nodes and can be recomputed with a combat `StatContext`.
- The resolver reports missing MAIN weapon as invalid for combat while still returning a diagnostic stat preview.

## Risks

The recovered tables currently encode some scaling in note strings. The resolver will only interpret the exact existing `×D(T)` and `×H(T)` markers; other scaling must be represented by typed fields in a later data migration. If wrong, the cost is incorrect scaling shown both in CalcTrace and combat, so tests pin the published examples at T1 and above.
