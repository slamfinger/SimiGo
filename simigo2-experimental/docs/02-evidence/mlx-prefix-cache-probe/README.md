# MLX prefix-cache probe — 2026-10-14

## Verdict

`PASS` — real-model cross-session hit observed.

## Command

```bash
.build/debug/simigo2ctl mlx-prefix-cache-probe \
  "/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d" \
  --prefix-tokens 16 \
  --tokens 1 \
  --root <temporary-prefix-store>
```

## Evidence

- Probe commit: `8a50e6582865c346442f9197b0c203142489e11c`
- Model: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`
- Snapshot: `6e302ea604ad9ab206367e2c501d1571023e7b6d`
- Host: Apple M5 (`Mac17,4`), 32 GiB unified memory
- Report: `qwen3-coder-30b-a3b-20261014.json`
- Full CLI log: `/tmp/mlx-prefix-probe-real.log`

## Assertions

- `pass = true`
- `crossSessionHitObserved = true`
- `hookCalls = 1`
- `hookHits = 1`
- `matchedTokenCount = 16`
- `outputsMatch = true`

## Boundary

This is real-runtime evidence for `PrefixSnapshotStore` → `MLXPrefixSnapshotLoader` →
`ChatSession.crossSessionPrefixLookup`. It does not close G-10 or certify power-loss /
media durability.
