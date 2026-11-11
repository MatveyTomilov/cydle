# Changelog

## Unreleased

- Added run-specific equipment ownership and loadouts. Secured inventory and unsecured cargo feed the same canonical build resolver; equip/unequip is validated at safe points, combat uses the selected field loadout, extraction secures it, and defeat loses unsecured gear while restoring protected gear with durability loss.
- Connected the run loadout editor to the road screen with compatible-slot filtering, implant/drone unlock states, and warehouse/risk labels.
- Kept active run saves created before loadouts readable: they inherit the previous garage equipment on load, and their original snapshot/export checksums remain verifiable.
- Added tests for cargo equipment, invalid slot/loadout operations, extraction and defeat ownership settlement, plus legacy active-run checksum compatibility.
- Added protected garage equip/unequip commands and a loadout editor in the Build screen. Commands use the canonical build resolver, preserve equipped items in the secured inventory, and lock permanent equipment changes during an active run.
- Added garage equipment tests for valid swaps, incompatible slots, required main weapon, and active-run restrictions.
- Added a deterministic, persisted first-sector run loop with validated route, combat, cache, service, and checkpoint commands; battle resolution reuses the existing simulator. Checkpoint shipment/evacuation, death settlement, item/currency rewards, XP, and six-layer graph state are tested.
- Connected the road screen to transactional save commits with route selection, combat report/log, cache choice, repair/fuel services, and checkpoint decisions.
- Kept old schema-v1 saves compatible and verified active-run save/reload without graph reroll.
- Added the real Vite/React entrypoint and responsive Garage/Build screens.
- Added the CYDLE v1 strict save schema with starter profile, canonical equipment, tactics, transport, and protected/unsecured resources.
- Added IndexedDB persistence through Dexie with transactional, checksummed snapshots, two-valid-snapshot retention, recovery to a prior valid snapshot, and checked JSON import/export.
- Added catalog cross-reference validation at app startup and through `npm run validate`.
- Added four save-boundary tests, including IndexedDB integration through `fake-indexeddb`.
- Multi-sector campaign, general inventory transfer/salvage/crafting, other road-node systems, later save migrations, CI, browser E2E, and final art/animation remain incomplete.
