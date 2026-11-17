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
6. **Import:** use Godot-supported PNG/WebP for raster art, transparent PNG for game/UI art (vector-generated new assets are no longer in scope), WAV/OGG for audio, and native Godot materials/shaders for procedural effects. Record import filtering, mipmap, compression, and loop settings.
7. **Integrate:** load through an asset registry/resource lookup keyed by stable ID. Combat logic refers to entity/action IDs and animation event names; it never hard-codes a file path.
8. **Review in scene:** inspect at 100% and target gameplay size, normal and reduced motion, dark/light effects, ×1 and ×4, desktop and Steam Deck layout. Verify that actor state is never inferred from animation completion.
9. **Accept:** update status to `INTEGRATED` only after scene review and asset validation. Record known limits or the remaining animation set explicitly.

## Formats and technical targets

- Character cutouts: layered source (ORA/KRA/PSD with license noted), exported transparent PNG layers or atlas. Use a consistent logical canvas and named pivot points. Avoid atlas rotation until import/runtime checks prove it safe.
- Frame animation: fixed frame cells, documented order, origin and FPS; use separate strips per action when it improves replacement and review.
- Environment: transparent foreground/midground layers plus opaque distant plates, with parallax speed recorded in the manifest.
- UI symbols: original PNG source and transparent cropped PNG runtime, or Godot-drawn primitives; include an accessible text label alternative for critical states. No new SVG production.
- VFX: source art plus Godot particles/shaders where useful. Keep fill-rate bounded and expose reduced-motion fallback.
- Audio: original/procedural or explicitly licensed; record source URL/license, sample rate, loop points, and loudness target. No unlicensed music or extracted game audio.

Do not invent a universal pixel resolution before the first in-engine scene is measured. Establish a reference viewport and pixels-per-unit during the vertical slice, then record the measured production values here and in the manifest.

## Validation

The eventual `game/tools/validate_assets.gd` must fail on duplicate IDs, missing files, invalid status transitions, unrecorded provenance/license, invalid dimensions/pivots, missing required animation states, and references from scenes to unknown IDs. A headless import plus manifest validation runs in CI. Runtime logs a single actionable error for a missing optional asset and never changes combat math to compensate for presentation failure.

## Alpha temporary-visual policy (2026-11-12 decision)

CYDLE alpha is **gameplay-first**, not art-production-first. During alpha, **all new generated character, equipment, environment and icon art is raster PNG**, plus Godot-native shapes or procedural silhouettes when appropriate. Each paper-doll asset follows `PAPERDOLL_VISUAL_CONTRACT.md`: original source image, full-canvas aligned transparent PNG master, cropped transparent PNG runtime and per-asset JSON offsets/anchors. **Do not produce new SVG assets or vectorize generated images.** Older imported SVG placeholders remain transitional until replaced safely; the final PNG cutout/art rules apply to new raster art.

- `game/data/presentation/alpha_visual_fallbacks.json` currently maps legacy SVG fallback IDs and remains presentation-only. It must be migrated by ID as new PNG assets become available, without changing combat or saves.
- The **presentation-layer** visual resolver must use this order: **verified final runtime asset → mapped temporary asset → generated procedural silhouette**. Missing visuals do not crash combat or change deterministic outcomes. Avoid silently using an unrelated sprite.
- The existing `ASSET_MANIFEST.csv` remains the source of truth for final runtime assets. A temporary placeholder or a PNG source/master alone does **not** make a final asset `INTEGRATED`; leave those entries `PLANNED` until final path/provenance/scene acceptance is verified.
- Keep visual dimensions, anchor/pivot, hitboxes, facing, health/status presentation and attack origin independently defined. Later sprite replacement must not change domain object IDs, simulation state, damage, saves, rewards, AI or event order.
- The alpha must display operator, drones, distinct enemies/bosses, route/garage context, HP and shields, status effects, danger cues, combat outcomes, loot, and save recovery. **No character animations, final art or audio required for the alpha gate.**
- Alpha acceptance: run a playable in-engine vertical slice and verify visual fallback in three cases (final available, placeholder available, neither available), with identical replay/state hash for the same fixed seed. Confirm cropped PNG/metadata loading in Godot before marking a new art asset integrated. Existing SVGs do not qualify as new production art.

## Initial acceptance gate

Before scaling visual production, complete the **playable alpha** with a base operator, one drone, three distinguishable enemy types, one boss, one biome and visible attack/impact/telegraph cues. Temporary **PNG/procedural** drawings are sufficient for alpha when readable and bound to the same deterministic events; the already-imported legacy SVGs may continue only until replaced.

Before bulk-producing **final illustrated assets**, separately confirm a real operator cutout, drone, three enemies, boss and layered biome art in Godot, plus sprite replacement by stable ID, animation-event alignment and performance on Windows/Steam Deck. This final-art gate comes after the functional alpha; it must not block core gameplay development.

## Mandatory cropped PNG production standard (2026-11-12)

All new paper-doll visuals and generated 2D art must be produced as original source raster → aligned RGBA full-canvas PNG master → tightly cropped RGBA runtime PNG → JSON with crop rect, pixel offset and attachment anchors. No new SVG or automatic vector tracing. Crop uses alpha>8 bounds plus 8px clamped padding, never resizes. Canonical front-view paper-doll source canvas is 1024×1536; feet_center=(512,1456) until calibrated and locked on approved artwork. Weapon sources may have a dedicated local canvas and their own source-local grip/muzzle points. See `PAPERDOLL_VISUAL_CONTRACT.md` for pose groups, draw-order, QA, example metadata and exact conversion conventions.

Legacy `game/assets/source/placeholders/*.svg` remain strictly transitional because current Godot screens load them by path. Do not delete or migrate them in a documentation-only PR. Replace them one by one with verified PNGs and only then delete obsolete SVG files and update all references and fallback manifests. Game-state and math must remain unchanged.
