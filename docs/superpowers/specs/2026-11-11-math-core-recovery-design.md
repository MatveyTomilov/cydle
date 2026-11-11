# CYDLE mathematical core recovery

## Intent

Restore Qwen's existing CYDLE source as the basis for a single deterministic engine. The first code stage should make its current mathematical modules verifiable and remove the compile errors that block later engine work.

## Goals

- Preserve the recovered source and its repository history on `recovery/qwen-snapshot`.
- Pin the master spec's stat, damage, shield, and reproducibility rules with tests.
- Correct the shield-only incoming-damage multiplier so it affects only the amount absorbed by shields.
- Make TypeScript typecheck runnable without inventing combat behavior; record the production-build blocker until the real application entry point is implemented.
- Keep the combat configuration's build boundary typed for the later build resolver.

## Non-goals

- Implement combat, route, save, UI, offline, or Simulation Lab systems in this stage.
- Treat data tables or type declarations as implemented game mechanics.
- Change master-spec balance values or replace the existing math pipeline.

## Approaches

1. Replace the project with a new scaffold: rejected because it would discard Qwen's recovered work.
2. Add broad combat behavior to satisfy the current type errors: rejected because the combat engine and build resolver are not present, so this would risk adding placeholder mechanics.
3. Keep the current layout, test the math modules, repair their narrow typing/build blockers, and add the shield-multiplier behavior in place: selected because it preserves existing architecture and creates a reliable gate for the next engine stage.

## Constraints

Use the existing TypeScript/Vitest/Vite stack and `CYDLE_MASTER_SPEC.md` v2.0 as the only normative rules source. Keep math deterministic, unrounded internally, and shared by later simulation and Build Lab code. Do not change saves or master-spec balance decisions.

## Open implementation choices

The next builder decides exact file organization for the future build resolver and combat engine after this recovery gate passes; this stage only establishes a typed contract and verifies current math.
