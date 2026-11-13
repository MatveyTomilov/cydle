# CYDLE — Paper Doll & Raster Asset Production Contract v1 (DRAFT)

**Decision (2026-11-12): new CYDLE alpha art is PNG, NOT SVG.** The prior plan to trace/generated artwork into vectors is superseded. We first generate compelling original raster artwork, then cleanly isolate each usable component and export tightly cropped transparent PNGs with precise placement metadata. Do not generate SVGs, convert PNG to SVG, embed PNG in SVG, or require vectorization for the new art pipeline.

**Status:** approved production *direction*, **draft geometry**. The 1024 × 1536 reference grid and numeric sockets are provisional until one base operator and its test outfit/weapon assets are reviewed. This document defines presentation art production, not game mechanics. No gameplay code, saves, formulas or RNG are changed by this PR.

Read with `CYDLE_MASTER_SPEC.md` (equipment slots), `ART_BIBLE.md` (style) and `ASSET_PIPELINE.md` (asset states). Existing SVG demo placeholders are **legacy temporary assets only**; the goal is to replace them with PNGs without breaking existing Godot scenes or CI.

## Hard production rules (mandatory for every new character/equipment asset)

1. **Source image first.** Generate original illustration/painted concept in the approved dark, high-contrast, inked/cel-shaded cyberpunk style; source should match the approved operator reference. Do not use a previous UI screenshot as the gameplay sprite.
2. **Fixed canonical front body.** Adopt one approved `paperdoll_front_v1` base operator, straight-on, neutral A-pose, relaxed empty/open hands, clear shoulder/elbow/wrist joints, torso unobscured. No three-quarter perspective. Every new armor/implant uses that exact body as conditioning and positioning reference; never re-generate the whole body to create a single item.
3. **Two different cameras.** Front view is for garage, loadout and Build Lab. The side-on combat arena needs a **separate** `combat_side_v1` asset/pose rig. Never rotate or perspective-warp the front PNG and call it a side view.
4. **Reference canvas.** Front master canvas is **1024 × 1536 physical pixels**, origin top-left, X right, Y down, transparent RGBA. Full-body/armor/implant/arm-pose masters all share exactly this grid. Anchor feet midpoint **(512,1456)**. No baked backgrounds or cast shadows in these layers.
5. **Three obligatory deliverables per visual asset:** (a) original generated/painted source image, retained for provenance; (b) full-canvas RGBA **master PNG** showing only this item's layer on its reference canvas; (c) **tight-cropped transparent runtime PNG**, plus a **JSON metadata sidecar** describing the crop/anchors/slot/pose/source. The source image can be a flattened PNG or editable layered raster file; the cleaned master and runtime must be PNG.
6. **Deterministic cropping.** Crop to alpha>8 pixel bounds, expand by **8 px padding** on each side, clamp to master boundaries; do **not** resize, rotate, trim internal whitespace, re-center, or add background during export. Save `crop_rect: [x,y,w,h]` in reference-canvas pixels; `offset: [x,y]` MUST equal the crop's top-left position. Cropped PNG size MUST be exactly `[w,h]`. Fully transparent PNG is invalid for a published item.
7. **Coordinate reconstruction.** Pixel at cropped local `[u,v]` maps to canonical `[u + offset_x, v + offset_y]` before the common stage transform. Reconstruct **without changes** when switching items. For weapons, local source canvas may differ, but metadata must identify its source canvas, crop rect and local grip(s) so its attachment remains mathematically unambiguous.
8. **Hands and equipment are independently composable.** Body, rear cape, armor pieces, implants, arm pose/hand-back, weapon, and foreground gripping fingers live in ordered layers. The visible hand starts immediately past the wrist; forearm/gauntlet overlaps the wrist seam by **24 canvas pixels**, not a zero-overlap hard cut. Do not bake a weapon into a hand or base operator.
9. **Static weapon pose families.** `neutral`, `pistol_onehand`, `longgun_twohand`, `blade_onehand`, `dual_sidearm`, `digital_focus`. Select arm-pose art by weapon family; keep fixed torso/legs/scale. Weapon `grip_main` is compulsory; `grip_support` for two-handed guns; `muzzle` for guns using muzzle VFX. For front pose the hands must actually enclose the handle in drawing order.
10. **Game equipment slots remain unchanged.** `MAIN_WEAPON`, `OFFHAND`, `ARMOR`, existing `IMPLANT` types and `DRONE` are the sole gameplay sources. `ARMOR` may resolve to multiple raster overlay layers. Invisible implants may remain visible only in UI icons. Never add gameplay slots, recalculate combat, block a valid build or change a save for visual convenience.
11. **Clean transparency, no white fringing.** Cutout silhouettes with quality edge/matte decontamination. Preview on white, #777777 and #15191F. No opaque white boxes, halos, stray outlines, holes or semi-opaque generator remnants; no unrelated pixels and no hard seams at joint connections.
12. **Correct image QA.** Check placement at native 1024×1536, garage 320×480, and smaller battle-readability size; confirm identical original proportions, weapon grips **within 8 reference pixels** of the chosen pose points, correct left/right anatomical naming, untouched baseline body, no overlapping layer errors. Save comparison previews to asset-review path where practical.
13. **Metadata and provenance required.** Use stable gameplay-facing visual IDs; include actual `template_id`, `view`, `visual_slot`, `pose_profile`, `source_image`, `master_png`, `runtime_png`, `source_canvas`, `crop_rect`, `offset`, `anchors`, `draw_layer`, `generation_provenance`, `license`. Weapon-specific grip/muzzle points required by the type. An example is in `docs/godot/PAPERDOLL_ASSET_METADATA_EXAMPLE.json`.
14. **Godot renders PNG layers, not a flattened UI mockup.** `OperatorPaperdoll` uses `Sprite2D` / `Texture2D` and an outer shared stage transform. Cropped art positioned using metadata offsets. Every game action is still handled by Godot controls and real gameplay data; no interactive labels are baked into sprite images.
15. **Decommission SVG carefully.** Existing `game/assets/source/placeholders/*.svg` and `alpha_visual_fallbacks.json` still power current Godot screens. Do **not delete them in this documentation PR**. Once a matching tested PNG exists and references are migrated, retire that individual SVG. Do not introduce any new SVG sources. Default future fallback: approved PNG → temporary legacy SVG *only for unmigrated IDs* → Godot procedural silhouette.
16. **Acceptance, no invented implementation.** A written contract is not a working paper doll. After choosing one base art, calibrate sockets and then prove 3 poses (PISTOL_K1, RIFLE_K2, BLADE_K4) × 2 armor sets (ARM_LIGHT, ARM_HEAVY), equip/unequip and save reload in Godot. Seeded combat state/event hash must match with art enabled and disabled. Only then finalize coordinates and scale production.

## Canonical layers and socket anchors

In `operator_paperdoll_rig_v1.json`, `r` is **operator's own right, screen-left**; `l` is operator-left, screen-right. Coordinate values are provisional and must be measured from the **approved base PNG**, never inferred as finalized landmarks from an unrelated generated image.

| Anchor | Draft position (x,y) | Role |
|---|---|---|
| feet_center | 512,1456 | stage reference |
| head_center | 512,212 | visor/head implant |
| neck | 512,365 | collar/scarf |
| chest_center | 512,560 | armor and chest device |
| hips_center | 512,885 | belt/leg armor |
| shoulder_r / shoulder_l | 355,435 / 667,435 | upper-arm attachment |
| elbow_r / elbow_l | 299,594 / 721,594 | hinge |
| wrist_r / wrist_l | 276,780 / 748,780 | forearm/hand boundary |
| grip_r_neutral / grip_l_neutral | 253,832 / 767,832 | no-weapon hand guide |
| knee_r / knee_l | 421,1160 / 603,1160 | legs |

Default stack, back to front: cape behind → base undersuit → leg armor → chest implant under armor → torso/shoulder armor → collar → posed arms/hand-backs → offhand → main weapon → foreground fingers → head/visor. Compatibility and z overrides are **presentation-only**.

## Asset path & naming contract

Source (not necessarily transparent) and full master and cropped runtime are **different** files:
```text
game/assets/source/paperdoll/<visual_id>/source.png       # original image, untouched
game/assets/source/paperdoll/<visual_id>/master.png       # cleaned transparent 1024x1536 aligned
game/assets/characters/operator/paperdoll/<visual_id>.png # tight transparent cropped runtime
game/data/presentation/assets/<visual_id>.json            # cropped PNG metadata/anchors
```
For a weapon's own local canvas, `master.png` size may vary and must match `source_canvas`; front body/armor/implants/pose arms always use 1024×1536. Source may additionally include original layered paint files and alternate generation attempts, but accepted files must be uniquely identified.

**Example sidecar geometry:** `source_canvas=[1024,1536]`, `crop_rect=[390,220,260,430]`, `offset=[390,220]`, `runtime_size=[260,430]`. A Godot Sprite2D using a top-left origin draws the cropped PNG at `offset` in the shared 1024×1536 coordinate system.

**Weapon rule:** metadata for `grip_main`/`grip_support`/`muzzle` is in the **uncropped weapon source coordinate system**. When cropping, display-local grip point = original grip point − `offset`; align weapon by matching its translated `grip_main` to the selected pose's canonical grip position. The second grip validates alignment, it does not silently stretch the gun.

## Integration boundary

Current `game/scripts/app/app_root.gd` loads a static SVG texture for the garage operator. In a later *implementation* PR Codex can replace that TextureRect with `OperatorPaperdoll`, reading actual equipped `templateId`/slot values from `GameSession` **after** validation. The full item instance still drives stats; only visual profiles are chosen by template/category.

The current art/documentation PR changes **no runtime implementation**, no current CSV final-art acceptance state, no deterministic calculations and no existing placeholders. The JSON contract is a specification draft, not a guarantee that a PNG exporter, scene renderer, automated test, or accepted operator art already exists.
