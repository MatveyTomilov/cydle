# CYDLE native project

This is the Godot product project. The TypeScript project at the repository root is frozen reference material.

## Requirements

- Godot 4.7.2 stable, standard Windows x86_64 build.
- Godot 4.7.2 stable Windows export templates for a standalone release build.

## Run and verify

From the repository root in PowerShell:

```powershell
godot --headless --path game --editor --quit
godot --headless --path game --script res://tests/run_tests.gd
godot --headless --path game --export-release "Windows Desktop" build/CYDLE.exe
godot --path game
```

The project runs from source in the last command. The Windows release export is written to `game/build/CYDLE.exe` and that directory is ignored by Git. The current build is an early playable prototype: it has profile/garage, route travel, a basic shared-simulator combat loop, rewards, simple service/cache/shop nodes, checkpoints, inventory and a CalcTrace Build Lab view. It is not feature-complete against `CYDLE_MASTER_SPEC.md`; in particular, combat compatibility currently falls back to an explicitly disclosed AUTO-only tactic for unsupported saved rules, and the campaign, offline/autopilot, quest/faction, Simulation Lab, and several battle behaviors remain incomplete. See the top of root `HANDOFF.md` for the exact checkpoint and tested state.

## Approved Autobattle V2 migration (13 November 2026)

The normative combat contract is CYDLE_MASTER_SPEC.md §8 (v2.1). The current playable combat engine is still V1 and still interprets legacy tactic rules; this is a known migration gap. The isolated AutobattleV2Contract and its headless test start V2 implementation without switching player saves or runtime combat. Full integration requires versioned CombatState, real action commits, equipment-authored abilities, Heat synergy, live Build Lab, 12 scenarios, and rendered/headless parity.
