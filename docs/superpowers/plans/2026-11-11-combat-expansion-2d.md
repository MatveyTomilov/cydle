# Combat Expansion 2d Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute authored enemy abilities, boss phases/rotations, shield bypass, and elite modifiers through CYDLE's single deterministic combat transition.

**Architecture:** Extend existing `CombatActor` cast/ability state and `stepCombat`; use `EnemyAbility`/`BossTemplate` data and existing damage, status, summon, cast, and logging functions. No second simulator or description-based behavior.

**Tech Stack:** TypeScript strict, Vitest, existing deterministic RNG and combat kernel.

**Spec:** `docs/superpowers/specs/2026-11-11-combat-expansion-2d-design.md`; master sections 4, 6–8, 17–18, 27.

## Global Constraints

- Integer game time advances at 100 ms per logical transition; stable event order uses timestamp, priority, actor ID, and sequence.
- Combat math uses one shared pipeline. Bypass is partitioned directly to HP; only non-bypassed damage can consume shields.
- No `Math.random`, unbounded summons, duplicate threshold triggers, hidden armor/resistance depth scaling, or untelegraphed dangerous casts.
- Same config and seed produce the same result and event log; no source catalog or input mutation.

## Review Focus

- Interrupt exactly on the resolve tick: an earlier reaction interrupt wins; after resolve, it does not undo damage.
- A target dying or disappearing during windup yields a stable retarget/fizzle outcome.
- One hit crossing multiple boss thresholds emits each phase once in deterministic order.
- Summons stop at the documented cap even if multiple controllers resolve simultaneously.
- Bypass 0 and 1, and shield-only multiplier with bypass, preserve HP/shield partition semantics.

---

### Task 1: Enemy ability scheduling and shield bypass

**Files:**
- Modify: `src/core/combat/engine.ts`
- Test: `tests/core/combat-ai.test.ts`

**Interfaces:** consume `EnemyAbility`, `CastState`, `applyHit`, `interruptCast`; keep scheduler internal to `stepCombat`.

- [x] Test E07 telegraph/windup, interrupt cancellation, and deterministic resolve on schedule.
- [x] Test BOSS_B bypass attack: 25% of post-defense damage hits HP directly, remaining 75% encounters shield; SHIELD_LEAK applies only on successful hit.
- [x] Schedule ready abilities by `firstAtMs`/`everyMs`, emit cast/telegraph, and resolve generic heavy attack, status, heat, mark, heal, and shield restore behaviors.
- [x] Wire `HitOptions.bypassShieldRatio` into `partitionDamage` and preserve event bypass details.
- [x] Run focused and full tests; commit `feat: execute scheduled enemy abilities`.

### Task 2: Boss thresholds and rotating abilities

**Files:**
- Modify: `src/core/combat/engine.ts`, `src/data/types.ts`, `src/data/enemies.ts`
- Test: `tests/core/combat-ai.test.ts`

**Interfaces:** consume each `BossTemplate.phases` and optional `rotating` list; retain state-local phase/rotation counters.

- [x] Test one-shot phase activation, multi-threshold crossings, phase summon/cleanse/attack interval/cast speed/bypass upgrades.
- [x] Test BOSS_CORE rotating cast order and its phase-upgraded digital bypass.
- [x] Implement phase transitions, rotating schedule, boss ambient rules, and deterministic event output.
- [x] Run focused/full tests and typecheck; commit `feat: execute boss phases and rotations`.

### Task 3: Elite modifier behaviors

**Files:**
- Modify: `src/core/combat/engine.ts`
- Test: `tests/core/combat-ai.test.ts`

**Interfaces:** consume `EncounterEnemySpec.elite`; use typed elite IDs and existing status/hit/summon paths.

- [ ] Test all six elite definitions: shield threshold restore, fast/HP tradeoff, every-third-hit VIRUS, telegraphed DRONE_JAM, extra penetration/windup, and bounded split on death.
- [ ] Implement exact stat/event hooks without duplicating the defense or status pipeline.
- [ ] Run full suite/typecheck and encounter smoke cases; commit `feat: implement elite combat modifiers`.

### Task 4: Verify and hand off this combat stage

- [ ] Run typecheck and full unit tests; inspect determinism, input mutation, death ordering, cap behavior, and event order.
- [ ] Run production build and record the expected missing real app entrypoint.
- [ ] Update `HANDOFF.md` and `docs/ROADMAP.md`; commit the verified stage.
