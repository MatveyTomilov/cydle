# CYDLE — Alpha Vector Placeholders (visual-only source kit)

Status: **SOURCE READY, NOT INTEGRATED**. These are original, lightweight SVG drawings for the alpha presentation phase, not final art.

## Timing

Use this kit when `game/scenes/combat/arena.tscn`, garage and shared visual adapters are created. The native deterministic combat core is still being ported on `development/codex`; do not couple its tests, save format, combat outcomes or rules to image imports. Integrate a tiny visible combat slice first, then expand.

## Source mappings

| Stable ID or scene concept | SVG source in this kit | Target |
| --- | --- | --- |
| `actor_operator_base` | `actor_operator_base.svg` | operator visual |
| `drone_gun_base` | `drone_gun_base.svg` | gun drone visual |
| `drone_support_base` | `drone_support_base.svg` | support drone visual |
| `drone_shield_base` | `drone_shield_base.svg` | shield drone visual |
| `enemy_scrap_hound` | `enemy_scrap_hound.svg` | starter melee enemy visual |
| `enemy_raider_gunner` | `enemy_raider_gunner.svg` | starter ranged enemy visual |
| `enemy_sentry` | `enemy_sentry.svg` | sentry machine visual |
| `boss_core12` | `boss_core12.svg` | boss visual |
| `biome_b01_layers` | `biome_b01_placeholder.svg` | temporary B01 arena plate |
| `garage_main` | `garage_main_placeholder.svg` | temporary garage plate |

## Godot integration rules

1. Source assets live in `game/assets/source/placeholders/`; do not overwrite final paths in `docs/godot/ASSET_MANIFEST.csv`.
2. When needed, import these SVGs as temporary textures **or** reproduce their simple geometry with `Node2D._draw()`. For production actor art, follow `ASSET_PIPELINE.md`: original painted source and PNG cutout layers/atlas. SVG is an alpha-only exception for these temporary mockups.
3. A presentation-layer resolver maps stable IDs to visuals with explicit fallback; do not bake SVG filenames into combat core, loot, AI, saves, or domain events.
4. Preserve logical pivot: humanoids and scrap hound = bottom/feet; drones = center; boss = bottom-center; arena and garage = top-left. Align final assets to the same anchor when replacing.
5. Hitboxes, positioning, facing, simulation time and attack effects come from authored scene data and deterministic events, **never** pixels or animation completion.
6. Render actor nameplates, HP, shield, DoT stacks, event log, telegraph labels and direction in Godot UI, not baked into sprites. Danger is not color-only.
7. Mark the final runtime asset ID `INTEGRATED` in the manifest only after it exists in its designated runtime path, has actual provenance/license fields, and is validated at gameplay scale. This kit itself does not move any existing `PLANNED` rows.
8. No animations are required for the alpha: teleport/position updates, state tint, timers and basic lines for attacks are sufficient. Keep the same event pipeline when real animation is added.

## Provenance and license

All ten SVG source files were drawn as original vector geometry for CYDLE in this ChatGPT conversation on 2026-11-12, using no third-party game sprites, characters or reference assets. Creator's own project art source; retain this record when preparing runtime imports.

## Scope

This contribution deliberately adds **only art sources and instructions**. It does not claim a playable scene, rendered integration, passing Godot imports or changed tests.

## Approved alpha delivery contract (2026-11-12)

The first playable alpha uses original distinguishable placeholders without mandatory animation or final painted assets. The gameplay loop is the acceptance target; this art kit is a temporary presentation dependency only. See the companion `game/data/presentation/alpha_visual_fallbacks.json`, which is the machine-readable visual ID → SVG source mapping.

The future presentation resolver must prefer: **final art (when present and validated) → these SVG placeholders → generated silhouette**. A single missing texture must never change a deterministic state, run hash, combat event order, loot, replay result or save format. Do not load the placeholder map from deterministic core. Critical game-state UI remains separate from imagery. Preserve stable anchors and independently defined hitboxes.

**Acceptance checks to implement during the playable Godot slice:** show all required actors and clear HP/shield/status indicators at game scale; test missing-final and missing-placeholder fallbacks; change a source path deliberately and verify in-engine error handling; verify the same seeded combat produces identical state hashes for all visual modes. The current art PR does not claim any of these run-time checks have passed.
