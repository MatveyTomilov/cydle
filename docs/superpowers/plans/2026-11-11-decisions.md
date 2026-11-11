# CYDLE recovery implementation decisions

## 2026-11-11: percentage modifiers on zero-base stats

`resolveStats()` previously multiplied `INCREASED` percentages by a stat's base value. Percentage-only stats such as kinetic damage and attack speed have a zero base, so their attribute, item, skill, and passive bonuses all vanished. Additive increases are now summed within a stack group and separate groups multiply as factors, producing an effective percentage value; the existing stat sheet carries that value for the combat engine to apply to its corresponding damage or timing formula. This follows the master spec's same-group additive and separate-group multiplicative rule. Direct regression tests cover both behaviors.

## 2026-11-11: tree input order

Tree selections are validated as an owned set, not as an acquisition history. The resolver repeatedly accepts nodes whose published branch/point requirements are satisfied, so a saved selection array may be in any order. The returned `treeNodeIds` preserves the input order. This is based on the master spec defining unlocks through allocated points and branch tiers without prescribing array order.

## 2026-11-11: negative repairCostLess

The stat registry previously clamped `repairCostLess` at zero, suppressing the chassis entry whose specification increases repair cost by 10%. Its minimum is now -100, allowing the named “less” stat to represent a penalty as a negative percentage. A resolver test pins the chassis value to -10.

## 2026-11-11: keystone validation reason

The tree catalog's lock helper reports the two-keystone cap as a generic lock reason. The build boundary now maps that case to the dedicated `KEYSTONE_LIMIT` issue code, with a regression test selecting three otherwise legal keystones. Selection remains invalid and no selected node is silently removed.
