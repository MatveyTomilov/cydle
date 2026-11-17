# CYDLE Luna implementation decisions

## 2026-11-11: recovery branch baseline

Ruling: `development/luna` starts at the user-named commit `2e5a59798695aaf7666a8fa13cb709fcdaad9fc7` on `recovery/qwen-snapshot` — this is the published emergency handoff and contains stages 2a–2c; earlier locally remembered hashes were superseded on the remote. Cost if wrong: work would branch from an incomplete code lineage.

## 2026-11-11: preserve one combat transition

Ruling: enemy abilities, phases, and elites extend existing `stepCombat` and `applyHit` — the master spec requires headless and displayed combat to have identical state/time and one math engine. Cost if wrong: engine responsibilities may become large, but splitting behavior before a stable event boundary risks divergent simulation.

## 2026-11-11: timed versus event-driven catalog abilities

Ruling: schedule `applyStatus` abilities only when `firstAtMs > 0` or `everyMs > 0`; `firstAtMs=0`/`everyMs=0` entries are reserved for explicit event hooks such as E14's every-third-hit VIRUS, E18's on-hit SHIELD_LEAK, and E23's ally-death BERSERK. Cost if wrong: one of those entries might have been intended as an immediate cast; the distinction follows their descriptions and prevents an untelegraphed status at combat time zero.
