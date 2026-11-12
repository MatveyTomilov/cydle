# CYDLE — operator paper-doll visual contract v1 (DRAFT)

**Status:** design contract drafted on 2026-11-12; numeric reference landmarks are **provisional until verified against one approved front-view base art**. No runtime rig/scene is implemented by this change.

**Purpose:** generated → cleaned SVG overlays fit a fixed operator's anatomy, reusable weapons, ARMOR outfits, OFFHAND devices and implants without hand-aligning every new item. This is a purely presentation-layer contract and does not change CYDLE combat, loot, saved item IDs, item validity or RNG.

**Source rules:** CYDLE_MASTER_SPEC.md section 5 already defines MAIN_WEAPON ×1, OFFHAND ×1, ARMOR ×1 and IMPLANT ×4–6 with HEAD/ARMS/CHEST/NEURAL/UNIVERSAL types. Section 10 lists 12 main weapons, six offhands, six armor templates and twelve implants. No new gameplay equipment slots are authorized by this art proposal. See ART_BIBLE.md, ASSET_PIPELINE.md, ALPHA_VECTOR_PLACEHOLDERS.md.

## 1. Two views, one equipment configuration

- **paperdoll_front_v1** is a 2D **straight-on** neutral A-pose used in garage, loadout, item preview and Build Lab. Level shoulders/pelvis, feet stable, elbows slightly bent and arms separated from chest; base hands are **open, empty**, never permanently holding a weapon. No three-quarter perspective, fisheye, body rotation, shadows baked into background or equipment baked into base undersuit.
- **combat_side_v1** is a *separate eventual visual rig/asset set* for the side-on arena in ART_BIBLE.md. Do not assume flipping or rotating a front-view SVG creates a side-view character. The same gameplay equipment ID resolves distinct front/side art where present, otherwise the relevant alpha silhouette fallback remains.
- The approved full-body front *undersuit* is the only source of truth for anatomy, style, proportions, scale and joint positions. The scarf/cloak is a removable visual layer (rear cape and front collar), **not** fused into the chest/base anatomy.

## 2. Authoring canvas and origin

- Canonical **source design canvas = 1024 × 1536 art units**, SVG `viewBox="0 0 1024 1536"`; X grows right, Y grows down. Transparent background. Position is fixed for all front-view body, armor and implant overlays.
- Feet midpoint reference at (512,1456). Front body occupies the stable guide bounds; leave margin for equipment, no cropping of worn modules. Full-canvas visual overlays retain the identical viewBox and origin even if only a gauntlet occupies a small area.
- This is an **authoring/attachment coordinate space**, not a global Godot viewport or final in-game texture size. Garage preview indicative size 320 × 480 UI px; smaller HUD portraits are separate/downscaled or simplified. Exact in-engine scale to be measured at first visual slice.
- Reference sockets and pose points are described in `game/data/presentation/operator_paperdoll_rig_v1.json`, which is intentionally **presentation-only**, not an input to the deterministic core.

## 3. Skeleton landmarks and joints

In anatomical convention, `r` means the **operator's own right** (screen-left), `l` is operator-left (screen-right).

| marker | canonical x,y | usage |
|---|---|---|
| feet | 512,1456 | align entire operator to stage |
| head | 512,212 | visor/helmet/HEAD implant |
| neck | 512,365 | scarf and collar |
| chest | 512,560 | ARMOR chest and CHEST implants |
| hips | 512,885 | belt, holster and leg armor |
| shoulder_r / shoulder_l | 355,435 / 667,435 | upper arm pose root |
| elbow_r / elbow_l | 299,594 / 721,594 | upper→forearm hinge |
| wrist_r / wrist_l | 276,780 / 748,780 | forearm→hand joint (cut boundary) |
| grip_r / grip_l | 253,832 / 767,832 | empty neutral pose; weapon poses override grip |
| knee_r / knee_l | 421,1160 / 603,1160 | leg overlay landmark |

**Wrist definition:** the visible glove/hand begins immediately distal to the wrist socket. The forearm art should run **24 art units beneath the gauntlet seam** (concealed overlap) to eliminate transparent cracks. Do not terminate forearm artwork at the exact line with no margin. Hand-back and finger-front can be separate to visually wrap around a weapon.

These are calibration targets, **not assertions that already approved character artwork conforms**. Once one base art is accepted, refine them only in a versioned rig revision, not independently per gear piece.

## 4. Logical equipment → visual slots

| Existing gameplay slot | Visual presentation |
|---|---|
| MAIN_WEAPON | weapon layer at pose-specific primary grip; long guns also have support grip + muzzle origin |
| OFFHAND | separate left-hand item for SIDEARM_1; other offhands are body/forearm-mounted devices, scanner or back attachments, depending on approved visual profile |
| ARMOR | one item ID resolves a *bundle* of torso, shoulders, leg plates and optional boots; visually split into overlays, never new gameplay slots |
| IMPLANT HEAD | helmet/visor/hairline hardware over head |
| IMPLANT ARMS | arm plates/bracers/gloves, with forearm↔wrist overlap |
| IMPLANT CHEST | underlay or exposed chest implant according to conflicts with ARMOR |
| IMPLANT NEURAL/UNIVERSAL | use a compatible visible overlay if relevant; otherwise show item icon but do not hallucinate external hardware |
| DRONE | separate actor, **not** a costume attached to operator |

Multiple mechanical implants can coexist; their **visual precedence and visibility** are controlled by the presentation profile. Do not alter equipment legality to resolve picture overlap. Not every mechanical effect must be visibly attached.

Only `templateId`/`item category` determines the alpha visual profile initially; item-instance ID, rarity/affix/TechLevel stay in game data, and optional cosmetics can be added later.

## 5. Weapon posing: never pre-draw a gun onto the base

A single neutral A-pose cannot plausibly hold every item. Use replaceable static **arm-pose groups**, with the torso, legs, face and equipped armor unchanged:
- `neutral`: empty, both hands low.
- `pistol_onehand`: right arm bent, one grip, left idle or offhand module.
- `longgun_twohand`: right hand on weapon's `grip_main`, left on `grip_support`; also record `muzzle` for presentation VFX.
- `blade_onehand`: right arm lowered/ready, hand encloses hilt.
- `dual_sidearm`: when compatible OFFHAND sidearm is explicitly displayed, both hand sockets can be occupied.
- `digital_focus`: visually-held focus or forearm device per template; don't depict all digital attacks as rifles.

Each weapon is **a separate SVG without hands**. Its metadata has local art dimensions, `grip_main`, optional `grip_support` and `muzzle`. Convert weapon-local grip to the selected pose's hand marker; use the second marker to validate two-hand alignment, not to independently re-scale the weapon after the fact.

Indicative weapon source envelopes: pistol/small 512 × 384, long gun 896 × 384, blade 512 × 768. Their exact cropped viewBoxes may differ; **accurate grip markers matter more than identical weapon file dimensions**. For basic alpha only pre-author a few weapon-family poses; animations are not required.

If a weapon lacks a matching pose, fall back to a distinct visual placeholder *without claiming a correct hand-held pose*. Missing visual data never rejects a valid game item.

## 6. SVG generation and vectorization rules

1. Approve **one original front-view base character** first. Never independently regenerate the entire body when adding a piece of armor or a weapon.
2. For each armor/implant, use the same base art as conditioning/reference. Produce the new piece at the exact canonical view, body proportions and joint map; output its own transparent layer, not a re-painted full character or screenshot.
3. Generate source illustration first; **then** trace to real editable SVG paths, clean paths/overlaps manually or programmatically and confirm the output contains no embedded raster data.
4. All front equipment full-canvas SVGs must use the 1024 × 1536 viewBox with no implicit `transform` to fake alignment. Weapon local sprites may have distinct viewBoxes and explicit sockets. Store original source image, SVG, color palette, generation/provenance metadata and visual ID.
5. No stray white lines / transparency seams: maintain 24-unit concealed overlaps at joints, opaque underlayers where relevant and test rendered output against dark (#15191F), middle-grey and white backgrounds.
6. Keep strong ink silhouette, cell-shaded planes and restrained cyan/red highlights of ART_BIBLE.md. Do not copy external game's exact characters, symbols, or UI.
7. SVG syntax must import in the pinned Godot engine: avoid unsupported filters, embedded fonts/text and untested SVG effects. Validate actual Godot import (ThorVG SVG support can differ from browser/Inkscape); use source SVG with imported Texture2D for alpha.
8. Each published asset includes stable ID, view, equipment slot, associated templateId, visual family, viewBox, anchors, provenance, logical draw layer and a fallback.
9. Require **a screenshot at actual game scale** plus a white/dark/gray comparison and joint/weapon-socket diagram for each new pose family before marking visually accepted.

## 7. Draw order, scene implementation and integration point

Suggested Godot presentation scene (not yet present in the current branch):

```text
OperatorPaperdoll (Control)
  VisualRoot (Node2D; stage transform from 1024x1536)
    CapeBehind (Sprite2D)
    BaseUndersuit (Sprite2D)
    ArmorLegs (Sprite2D)
    ChestImplantsUnderArmor (Sprite2D)
    ArmorBodyAndShoulders (Sprite2D)
    CollarScarfFront (Sprite2D)
    PoseArms (Node2D; upper/forearm/hand-back; Marker2D joints and grips)
    OffhandDeviceOrWeapon (Node2D)
    MainWeapon (Node2D; Sprite2D, grip markers)
    ForegroundFingers (Sprite2D)
    HeadAndVisorOverlays (Sprite2D)
  PreviewControls (Control)
```

Use a canvas-aligned `Sprite2D` with `centered=false` or equivalent explicit origin so source coordinates map directly to Godot local positions. Weapon transform maps its `grip_main` to the pose primary-hand marker; for `longgun_twohand`, support grip must coincide with support hand within tolerance. Animated combat-side view remains a separate presentation rig.

At garage/Build Lab, replace the currently static `actor_operator_base.svg` `TextureRect` in `game/scripts/app/app_root.gd` with reusable `OperatorPaperdoll` **during the visual integration slice**, not by touching native `CombatSimulator` or `BuildResolver`. After `GameSession` confirms an equipment change, read current META/RUN equipment and rebuild the visible layers from **actual equipped item template IDs**, not button labels. Preview invalid builds without committing state.

The global art resolver stays final runtime art → mapped SVG → procedural fallback. Existing manifest final `PLANNED` rows do not become `INTEGRATED` because this draft exists.

## 8. Alpha verification gate

Test with **PISTOL_K1**, **RIFLE_K2**, **BLADE_K4**, **ARM_LIGHT** and **ARM_HEAVY** first. Check both armor variations with all three weapon pose groups plus missing/offhand cases.

- Same rig transform and feet location, **no torso jump or scale drift** when switching gear.
- Grip alignment tolerance: **≤ 8 source art units**, equivalent to 2.5 UI pixels at 320/1024 source scale. Check both long-gun grips, and muzzle origins.
- Wrist overlap hides gaps; both gloves visibly clasp weapons and armor doesn't cover fingers.
- Visuals remain readable at 320 × 480 garage preview and at a much smaller battle presentation scale; for combat-side, use a separate silhouette/rig.
- Godot SVG import/headless checks succeed; validated paths, source provenance and fallbacks exist.
- Equip → un-equip → reload save → same visual composition; invalid equipment is never displayed as committed.
- Run a seeded combat replay with visuals enabled/disabled; simulation result, events and state hash are identical.

**No implementation/animation/final rendered art or test results are asserted by this proposal.** Create one accepted base operator and three grip poses, then calibrate and freeze the v1 landmarks before broad content generation.
