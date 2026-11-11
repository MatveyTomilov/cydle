# Changelog

## Unreleased

- Added a playable deterministic SHOP road node to regular sectors. Each store shows five seed-stable biome-pool items and exact §19 prices; one-time purchases spend unsecured run credits and add at-risk cargo. Closing the node advances game time by 8 seconds.
- Added tests for shop stock, purchase payment and ownership, idempotency, sold/invalid items, insufficient funds, shop completion, and regular-sector placement.
- Added run-specific equipment ownership and loadouts. Secured inventory and unsecured cargo feed the same canonical build resolver; equip/unequip is validated at safe points, combat uses the selected field loadout, extraction secures it, and defeat loses unsecured gear while restoring protected gear with durability loss.
- Connected the run loadout editor to the road screen with compatible-slot filtering, implant/drone unlock states, and warehouse/risk labels.
- Kept active run saves created before loadouts readable: they inherit the previous garage equipment on load, and their original snapshot/export checksums remain verifiable.
- Added tests for cargo equipment, invalid slot/loadout operations, extraction and defeat ownership settlement, plus legacy active-run checksum compatibility.
- Added protected garage equip/unequip commands and a loadout editor in the Build screen. Commands use the canonical build resolver, preserve equipped items in the secured inventory, and lock permanent equipment changes during an active run.
- Added garage equipment tests for valid swaps, incompatible slots, required main weapon, and active-run restrictions.
- Added the secured inventory screen with a separate at-risk run-cargo list. Players can dismantle one owned, unequipped, non-material item for the existing catalog salvage value; the confirmation shows exact scrap/data yield and the action is blocked during an active run.
- Added regression tests for one-time dismantling, equipped-item protection, unsecured ownership, and active-run restrictions.
- Added protected item repair from the Inventory screen. The cost follows the master-spec durability formula, is capped by a comparable common item's price, consumes protected scrap only, restores durability to 100%, and leaves TR unchanged.
- Added repair tests for exact cost, insufficient scrap, already repaired items, unsecured ownership, and active-run restrictions.
- Added deterministic affix reroll and one-tier upgrade operations to the Inventory screen. They consume the declared TR/scrap/data costs, obey the TechLevel tier cap, preserve unselected rolls, reject fixed AF_SCAN rerolls, and preview costs before use.
- Added craft tests for targeted reroll, tier upgrade, exact resource/TR consumption, insufficient resources, tier caps, and fixed affixes.
- Completed affix replacement/addition and secured-item TechLevel calibration. Replacement/addition enforce category compatibility, no duplicate affixes, and rarity slot limits; TechLevel upgrades preserve item identity, affixes, and TR while consuming a matching calibration core plus exact scrap/data.
- Added calibration tests for replacement, addition, core group, unlocked TechLevel limits, active-run protection, and full rarity slots.
- Added a deterministic, persisted first-sector run loop with validated route, combat, cache, service, and checkpoint commands; battle resolution reuses the existing simulator. Checkpoint shipment/evacuation, death settlement, item/currency rewards, XP, and six-layer graph state are tested.
- Connected the road screen to transactional save commits with route selection, combat report/log, cache choice, repair/fuel services, and checkpoint decisions.
- Kept old schema-v1 saves compatible and verified active-run save/reload without graph reroll.
- Added the real Vite/React entrypoint and responsive Garage/Build screens.
- Added the CYDLE v1 strict save schema with starter profile, canonical equipment, tactics, transport, and protected/unsecured resources.
- Added IndexedDB persistence through Dexie with transactional, checksummed snapshots, two-valid-snapshot retention, recovery to a prior valid snapshot, and checked JSON import/export.
- Added catalog cross-reference validation at app startup and through `npm run validate`.
- Added four save-boundary tests, including IndexedDB integration through `fake-indexeddb`.
- Multi-sector campaign, general inventory transfer, item generation recipes, other road-node systems, later save migrations, CI, browser E2E, and final art/animation remain incomplete.
