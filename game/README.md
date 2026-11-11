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

The project runs from source in the last command. The Windows release export is written to `game/build/CYDLE.exe` and that directory is ignored by Git. The current boot screen is a technical shell that reports the game loop is not connected yet; it is not a playable build.
