# Combat kernel implementation plan

**Goal:** Establish one deterministic 100 ms combat transition using the resolved build and existing math/RNG.

**Spec:** `CYDLE_MASTER_SPEC.md` v2.0, sections 2, 4, 6–8, 23.2.

1. [ ] Add seeded transition tests for fixed-step timing, auto-attacks, damage partition, victory/defeat/timeout, repeatability, and invalid builds.
2. [ ] Implement actor initialization and fixed-tick `stepCombat` using existing damage functions.
3. [ ] Add a headless runner that invokes the same transition until a terminal outcome, producing metrics, logs, and serialized RNG.
4. [ ] Run typecheck, focused and full tests; review stable ordering, input immutability, finite values, and state hashing.
5. [ ] Commit the kernel. Add abilities, tactical choices, statuses, and enemy ability scheduling in subsequent stages.
