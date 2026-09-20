# Track B engine branch requirement — 2026-09-20

## Production boundary

- SimiGo production pin remains `mlx-swift-lm dc3ca619717192425254d4da18af0c29b978fcf7`
- mlx-swift remains `0.31.6`
- This Track B branch must never modify the production pin on `main` or the 1.7 release path.

## Local engine fork

The current SimiGo workspace already resolves mlx-swift-lm from a local source-control path:

`/Users/mr.simi/Documents/mlx-swift-lm`

Track B should use a separate experimental checkout/branch of that repository, with a fresh Xcode `derivedDataPath` after switching the vendor revision.

Suggested vendor branch name:

`exp/simigo-2.0-execution-state-f1`

The branch must start from the same production pin above, then add only the minimum F1 capability surface:

1. sequence identity
2. shared immutable prefix ownership
3. copy-on-write suffix materialization
4. restore of logical execution state

No production API change is implied by this document.

## Required A/B setup

A/B builds must make the vendor revision explicit in the experiment log:

| Build | mlx-swift-lm | mlx-swift | Purpose |
|---|---|---|---|
| A | production pin | 0.31.6 | baseline |
| B | F1 experimental branch | 0.31.6 unless required otherwise | fork prototype |

After changing the local vendor checkout:

1. verify the resolved revision;
2. use a fresh `derivedDataPath`;
3. record the exact vendor commit in the experiment result;
4. do not copy the experimental revision back into the production workspace.

## Migration rule

Passing F1 does **not** authorize migration into 1.7.

The only migration path is:

`F1 evidence → Level gate → separate version/PR → production validation`

