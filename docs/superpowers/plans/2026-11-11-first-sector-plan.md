# First persisted sector — implementation plan

1. **Run schema and command result contract** — complete for current scope; active and legacy v1 save validation are tested.
2. **Deterministic graph generator** — complete for current scope with 12-node tutorial base, six-layer reachability and bounded branches.
3. **Validated world transitions** — route, cache, repair and fuel commands implemented and tested.
4. **Single-engine combat integration and rewards** — implemented through existing `simulateCombat()` and tested for deterministic victory/reward behavior.
5. **Checkpoint settlement** — EXIT, SHIP and CONTINUE are implemented; cargo and wallet protection, one shipment per checkpoint, and death rules have unit coverage.
6. **Player interface** — run start, route, combat report/log, prototype choice, service, and checkpoint UI are connected to IndexedDB commits. Browser smoke reached only the first combat; full-sector interaction remains unverified.
7. **Verify and checkpoint** — typecheck, 144 unit tests, catalog validator, and production build pass. No Playwright/E2E harness is installed. Feature commit: `38a5787`.

## Follow-up outside this stage

- Persistent inventory/equipment operations for secured and unsecured items, cargo ownership, full garage UX, additional node types and their mechanics, campaign/endgame, autopilot/offline, Simulation Lab, and final art/animation remain open.

## Review focus

- Whether the tutorial exception remains a six-layer path and does not create inaccessible graph nodes.
- Exactly-once command/reward handling across refresh and Dexie transaction failure.
- Whether only one `simulateCombat`/`stepCombat` engine resolves every run encounter.
- Whether defeated runs preserve prior protected bank, shipped cargo, and max unlocked progress.
- Whether timeout and player/operator defeat are reflected in the same run phase without losing the combat replay data.
