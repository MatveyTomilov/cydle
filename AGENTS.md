# CYDLE agent instructions

## Product and authority

- `CYDLE_MASTER_SPEC.md` is the normative source for game rules, balance, and release acceptance. Do not change its design decisions without explicit approval.
- The native product lives in `game/` and targets Godot 4.7.2 Stable with strictly typed GDScript. Root `src/` and `tests/` are frozen legacy/reference code and the oracle for ports; do not add game features there.
- `docs/godot/TECHNICAL_ARCHITECTURE.md`, `ART_BIBLE.md`, `ASSET_PIPELINE.md`, and `ASSET_MANIFEST.csv` govern implementation and art. Do not claim a planned manifest entry is an integrated asset.
- Keep one deterministic domain engine for active play, offline progress, Build Lab, and Simulation Lab. Scenes render domain events and do not calculate gameplay outcomes.

## Git and preservation

- Work on `development/codex`. Keep `main`, `development/luna`, `development/qwen`, and `recovery/qwen-snapshot` unchanged.
- Preserve existing Qwen/Luna code and commits. Avoid destructive Git commands and broad rewrites. Keep changes focused, tested, committed, and pushed to `origin/development/codex` at completed checkpoints.
- Do not commit generated build output, `.godot` cache, local save data, credentials, or unlicensed/undocumented assets.

## Implementation rules

- Follow FULL GAME FIRST: implement and connect all major Master Spec systems so the player can start, progress through all 12 sectors, complete the campaign, and continue into endgame. When one system works enough to support campaign progression, move to the next missing major system; do not turn work into a series of isolated feature releases. Do not stop after a narrow feature or treat a checkpoint commit as task completion. Defer saved Simulation Lab presets, report exports, cosmetic polish, secondary settings, and redundant tests until functional campaign coverage exists. A file, interface, catalog row, or screen is not evidence that a system works.
- Do not create duplicate math/combat rules or silently alter formulas, economy, progression, or probabilities. Add oracle/golden tests for ports and use the existing deterministic RNG/state hashing.
- Keep saved data versioned and backward-compatible. Validate imports and transactions before changing live or persisted state; never silently reset a damaged save.
- Use original or verified licensed assets only. Record source and license in the manifest. No paid assets without owner approval; do not generate graphics unless asked.
- Do not add a test framework or runtime dependency without a demonstrated need. Preserve the in-repository Godot runner and golden fixtures. Add or extend tests for new system boundaries, critical rules, persistence, or concrete regressions; avoid retesting already-proven functions without a reason.
- Update `CHANGELOG.md`, `docs/ROADMAP.md`, and the current section of `HANDOFF.md` when a meaningful implementation checkpoint changes.

## Verification commands

Run from the repository root in PowerShell:

```powershell
$godot = Join-Path $env:LOCALAPPDATA 'Programs\Godot\4.7.2\godot_console.exe'
& $godot --headless --path game --editor --quit
& $godot --headless --path game --script res://tests/run_tests.gd
npm run typecheck
npm test -- --run
npm run validate
npm run build
```

At export gates, also run:

```powershell
& $godot --headless --path game --export-release 'Windows Desktop' build/CYDLE.exe
```

Report only checks actually run, including failures and exit codes. The npm app validates the frozen reference; Godot validates the native product.

## Codex subagents

- Use `regression_tester` on committed checkpoints for required fast checks and `balance_qa` on significant gameplay/combat/balance checkpoints; launch them together when scopes are independent. `balance_qa` is read-only and uses bounded deterministic batches.
- `game_qa` is for significant playable checkpoints, not routine commits. Avoid running it alongside a balance sweep on the same checkpoint. Use `reviewer` only for substantial architecture, save, combat, or cross-system changes.
- Pass every agent the full checkpoint SHA. Test agents use a detached temporary worktree and a unique `%APPDATA%` per Godot run; source is read-only. Continue independent implementation while agents run. The main agent owns fixes and integrates findings.
- Current project roles are exactly `regression_tester`, `balance_qa`, `game_qa`, and `reviewer`; no quest-only subagent is configured.
