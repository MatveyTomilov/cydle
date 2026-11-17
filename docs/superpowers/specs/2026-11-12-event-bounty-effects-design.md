# Event BOUNTY effects design

## Intent

Implement EV14's paid-off bounty hunt and EV21's E21 target as real deferred encounter effects. Both choices convert the next selected ordinary COMBAT into a BOUNTY; EV14 adds 25% credits, while EV21 guarantees one RARE item roll.

## Approaches

1. Place a new BOUNTY node in a later graph layer at event resolution. The route is not selected yet and the generated layer may not contain a compatible slot.
2. Store run-scoped pending bounty fields, transform the next selected ordinary COMBAT in `chooseRunNode`, and apply reward details in the existing reward function. **Selected.**
3. Inject event logic into the combat simulator. Rewards and encounter selection belong to the run layer, so this would couple unrelated systems.

## Behavior

- EV14 B stores `forceBounty` with `bountyCreditsBonus = 0.25`.
- EV21 B stores `forceBounty`, targets `E21`, and guarantees one RARE item roll.
- The transformed node is persisted as BOUNTY, uses its ELITE reward table and no XP, and consumes its pending event effect after that combat attempt.
- The EV21 `bountyE21` flag is interpreted as run-scoped target metadata; it is not written as a permanent campaign flag.
- Existing unsupported encounter flags and effects remain excluded from generated event choices.

## Out of scope

No elite-only event contract, allied turret, forced skip, bounty UI redesign, or new combat mechanics.
