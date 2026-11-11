# First persisted sector — implementation plan

1. **Run schema and command result contract** — define Zod run/save types, world resources, node statuses, encounter specs, cargo, combat snapshot/result, and stable run command failures. Add tests for null/active save compatibility, invalid refs, and failed-command immutability.
2. **Deterministic graph generator** — derive six-layer nodes/edges from the world RNG; author the sector-one tutorial kernel; add bounded side-node policy and repair/shop alternatives. Test pinned output, seed variation, reachability, acyclicity, branching, path requirements, and reload stability.
3. **Validated world transitions** — start run; choose only reachable nodes and debit fuel/time once; resolve cache and services; reject invalid/duplicate commands. Test resource floors, edge costs, idempotency, and state hashes.
4. **Single-engine combat integration and rewards** — resolve encounters with `resolveBuild()` + `simulateCombat()`; persist deterministic combat result, damaged durability, reward grant IDs, run wallet, and unsecured items. Test victory, defeat, replay, and one-time grants.
5. **Checkpoint settlement** — implement EXIT, SHIP, and CONTINUE gate behavior for the current sector; persist protected cargo/currency atomically; defeat loses unsecured cargo/wallet and damages permanent equipment. Test each outcome and save-reload behavior.
6. **Player interface** — add run start, map choice, encounter/result, cache, service, and checkpoint interactions to the existing React app. Buttons dispatch commands and show exact rejection reasons; screen changes occur after IndexedDB commit.
7. **Verify and checkpoint** — run typecheck, all unit/integration tests, catalog validator, production build, E2E if available, inspect diff; update HANDOFF/ROADMAP/CHANGELOG and commit this stage.

## Review focus

- Whether the tutorial exception remains a six-layer path and does not create inaccessible graph nodes.
- Exactly-once command/reward handling across refresh and Dexie transaction failure.
- Whether only one `simulateCombat`/`stepCombat` engine resolves every run encounter.
- Whether defeated runs preserve prior protected bank, shipped cargo, and max unlocked progress.
- Whether timeout and player/operator defeat are reflected in the same run phase without losing the combat replay data.
