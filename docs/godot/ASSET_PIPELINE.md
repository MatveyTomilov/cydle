# CYDLE Asset Pipeline

This pipeline turns an approved visual requirement into a replaceable, reviewed Godot asset. A concept image is not a finished game asset.

## Repository layout

```text
game/assets/
  source/                 # layered source art and editable audio sessions
  concepts/               # approved reference boards; not runtime assets
  characters/{operator,drones,enemies,bosses}/
  environments/{garage,biomes}/
  vfx/{combat,world,ui}/
  ui/{icons,frames,type}/
  audio/{sfx,music}/
```

Keep licensed/generated source and metadata in `source/` where size permits. Runtime exports live in the categorized folders, and Godot `.import` settings are checked into Git. Large originals can later move to Git LFS only after the repository policy is set; do not silently drop source provenance.

## Naming and manifest IDs

- Stable IDs are lowercase `category_subject_variant`, for example `actor_operator_base`, `enemy_scrap_hound_idle`, `boss_core12_phase2`, `biome_b01_far_sky`, `vfx_digital_hit`, `ui_status_burn`, `sfx_weapon_kinetic_fire`.
- Runtime filenames use the same ID plus an explicit animation/frame suffix. Avoid names based on temporary artist names or generation dates.
- `docs/godot/ASSET_MANIFEST.csv` is the single source-of-truth manifest. Every runtime asset has exactly one row with path, status, format, dimensions/frame layout, pivot/anchor, animation list, loop flag, source/provenance, license, and in-engine owner scene.
- Replacements retain the stable ID and gameplay-facing resource reference. A breaking change to animation events gets a versioned manifest note.

## Production stages

1. **Need:** identify the exact gameplay/readability need, scene, size, role, required states, and fallback. Add a `PLANNED` manifest row.
2. **Concept:** create a silhouette/value/color board using the Art Bible. Concepts are clearly marked `CONCEPT`; they are not imported into a release scene.
3. **Approval:** select one coherent direction and record the choice/provenance in the manifest or source metadata. Reject palette/style outliers before animation work.
4. **Production:** paint or rig the final asset. Use cutout layers for reusable characters; frame-by-frame for effects/transforms where rigging is unsuitable. Keep source layers and original resolution.
5. **Prep:** remove stray pixels, verify alpha, set a stable pivot, define frame dimensions and animation names, and prepare density variants only where pixel density requires them.
6. **Import:** use Godot-supported PNG/WebP for raster art, SVG only for resolution-independent UI symbols, WAV/OGG for audio, and native Godot materials/shaders for procedural effects. Record import filtering, mipmap, compression, and loop settings.
7. **Integrate:** load through an asset registry/resource lookup keyed by stable ID. Combat logic refers to entity/action IDs and animation event names; it never hard-codes a file path.
8. **Review in scene:** inspect at 100% and target gameplay size, normal and reduced motion, dark/light effects, ×1 and ×4, desktop and Steam Deck layout. Verify that actor state is never inferred from animation completion.
9. **Accept:** update status to `INTEGRATED` only after scene review and asset validation. Record known limits or the remaining animation set explicitly.

## Formats and technical targets

- Character cutouts: layered source (ORA/KRA/PSD with license noted), exported transparent PNG layers or atlas. Use a consistent logical canvas and named pivot points. Avoid atlas rotation until import/runtime checks prove it safe.
- Frame animation: fixed frame cells, documented order, origin and FPS; use separate strips per action when it improves replacement and review.
- Environment: transparent foreground/midground layers plus opaque distant plates, with parallax speed recorded in the manifest.
- UI symbols: clean vector source plus exported SVG/PNG as appropriate; include a text/icon label alternative for critical state.
- VFX: source art plus Godot particles/shaders where useful. Keep fill-rate bounded and expose reduced-motion fallback.
- Audio: original/procedural or explicitly licensed; record source URL/license, sample rate, loop points, and loudness target. No unlicensed music or extracted game audio.

Do not invent a universal pixel resolution before the first in-engine scene is measured. Establish a reference viewport and pixels-per-unit during the vertical slice, then record the measured production values here and in the manifest.

## Validation

The eventual `game/tools/validate_assets.gd` must fail on duplicate IDs, missing files, invalid status transitions, unrecorded provenance/license, invalid dimensions/pivots, missing required animation states, and references from scenes to unknown IDs. A headless import plus manifest validation runs in CI. Runtime logs a single actionable error for a missing optional asset and never changes combat math to compensate for presentation failure.

## Initial acceptance gate

Before scaling production, integrate an operator base, one drone, three visually distinct enemies, one boss, one biome background set, and a small attack/impact/telegraph effect set into a playable test arena. Confirm silhouette readability, frame/event mapping, asset replacement by ID, and performance on Windows desktop and Steam Deck. Only then bulk-produce the remaining roster.
