# CYDLE Art Bible

**Status:** production direction for the Godot game.
**Reference mood:** Darkest Dungeon's dramatic 2D staging meets a decaying cyberpunk frontier. This is a broad mood reference only; CYDLE must use original characters, shapes, compositions, marks, text, and assets.

## Visual promise

CYDLE is a dangerous industrial world that keeps functioning after its institutions and infrastructure have failed. The player should read a scene in this order: silhouette and threat, immediate combat state, then surface detail. Paint and texture carry the decay; restrained neon identifies active technology. The result should feel hand-made, tense, and legible at game scale rather than glossy, sterile, anime, or pixel-art.

## Palette and light

| Role | Color | Use |
|---|---|---|
| Void | `#090B10` | Deep background and occlusion |
| Coal | `#15191F` | Main shadow mass |
| Cold graphite | `#252C35` | Metal planes and UI surfaces |
| Industrial blue | `#202C3B` | Night, distant steel, interface depth |
| Rust | `#704637` | Oxidized metal, exposed structure |
| Dried wine | `#552B35` | Faction danger, stains, damaged fabric |
| Dead olive | `#42452F` | Toxic industry, old machinery |
| Signal cyan | `#56D5D0` | Scanners, clean machine signal, selected UI |
| Arc blue | `#6488F2` | Shields, energy weapons, electric effects |
| Toxic violet | `#AA70D1` | Network intrusion, virus, unstable tech |
| Warning amber | `#E5A34B` | Telegraphs, heat, hazardous machinery |
| Alarm red | `#D75A55` | Lethal threat, damage, critical state |

Most pixels belong to dark, low-saturation masses. Neon occupies small, meaningful regions and should illuminate nearby forms. Preserve value contrast before hue contrast; do not communicate HP, shields, rarity, status, or danger by color alone.

## Shape language and materials

- Human silhouettes are asymmetrical and practical: layered coats, sealed masks, scavenged plates, cable runs, and deliberately visible implants. Keep head, weapon, and torso readable when rendered small.
- Machines combine blunt industrial volumes with exposed repairs, mismatched panels, cable bundles, ceramic insulators, worn labels, and sparse signal lights.
- Drones have distinct outline and motion: a gun platform is forward-heavy, a shield unit is broad and stable, and a support unit is light with a visible emitter. Their role must be readable without color.
- Enemies use different posture, head/limb ratios, armor mass, and movement cadence. A corrupted network entity may distort edges and leave signal artifacts but still has a stable silhouette.
- Bosses use a unique large-scale outline, layered silhouette, visible weak/core region, and phase-specific changes in light or geometry.
- Surfaces use brush grain, chipped edges, oily scuffs, dust, rain streaks, soot, and selective edge highlights. Avoid uniform noise overlays that reduce text or combat-state readability.

## Scene composition

- Combat arena is side-on: operator and up to two drones occupy the left third; enemies occupy the right half; projectiles and telegraphs remain visually traceable between them.
- Maintain a protected HUD band. Do not put important silhouettes beneath health bars, event timeline, or reward panels.
- Use at least three parallax depths in a finished biome: distant skyline/structure, midground machinery, foreground debris/weather. Lighting and silhouettes support gameplay lanes.
- The garage is a lived-in repair bay with a focal operator silhouette, transport silhouette, practical equipment lights, and navigable work areas. It is a scene with useful hotspots, not an admin dashboard over wallpaper.
- The road map uses a compact readable node graph with material markers and visible route lines; choices remain distinguishable by icon, text, and risk treatment.
- UI frames may borrow from bolted plates, instrument glass, warning tape, and etched labels, but text surfaces stay calm and high-contrast.

## Motion and effects

Every combat action has three readable beats where applicable: anticipation/telegraph, impact/resolve, and recovery/aftermath. The animation event carries its simulation timestamp; fast-forward compresses the presentation while preserving order and final outcome.

- Kinetic: short directional streak, impact spark, debris or casing appropriate to the weapon.
- Energy: hard-edged arc, briefly lit silhouette, residual glow that decays quickly.
- Digital: broken scan bands, targeting geometry, data fragments, controlled distortion.
- Shield: readable surface ripple and separate break cue; do not obscure HP feedback.
- Heat: localized orange bloom, vent plume, and machine stress; avoid full-screen flashing.
- Virus/status: persistent restrained glyph or surface stain with a legible stack/duration marker.
- Boss telegraphs: high-contrast shape or lane cue, warning tone optional, never color-only.
- Death and loot: distinct collapse/disable silhouettes and a clear reward arrival; no prolonged screen shake.

Reduced-motion settings must replace long camera movement, strong shake, and repeated flashes with short fades or static state changes.

## Asset quality and originality

Each final asset must have a documented source, license or generation record, palette check, transparency/pivot data where relevant, in-engine scale review, and replacement path. Generated concepts are references until they pass the same cleanup, animation, import, and scene checks as hand-painted assets. Do not copy Darkest Dungeon, FTL, or other games' silhouettes, UI arrangements, icons, logos, or textures.

## Review checklist

- Can the unit, role, threat, and facing be read in grayscale at target display scale?
- Is the dominant silhouette distinct from every actor already in the encounter?
- Does the accent color correspond to a consistent gameplay signal?
- Does the animation match a deterministic combat event and stay readable at ×4?
- Does the asset remain legible under the HUD and both desktop and Steam Deck layouts?
- Are source, license/provenance, pivot, export settings, and manifest ID recorded?
