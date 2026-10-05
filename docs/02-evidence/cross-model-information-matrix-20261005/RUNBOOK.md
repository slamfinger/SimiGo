# Runbook

## 0. Freeze check

```bash
python3 run_matrix.py --check-only
python3 run_matrix.py --render-only
```

## 1. Execute one loaded model

Start the selected model in NativeMLX, then run its four cells. Do not run this while the
existing R-D Round 1 process is active.

```bash
python3 run_matrix.py --run-root runs/<run-id> \
  --models A-qwen3-moe
python3 run_matrix.py --run-root runs/<run-id> \
  --models B-qwen3-next
python3 run_matrix.py --run-root runs/<run-id> \
  --models C-gemma4-unified
python3 run_matrix.py --run-root runs/<run-id> \
  --models D-muse-glimmer
```

Do not restart an interrupted command automatically. Inspect the last cell, the server state,
and logs first; resume only the missing `(sample, model)` cells after human confirmation.

## 2. Gate

Only after 16 successful cells: build `normalized/`, then `stability/`, then the 846 remap.
No semantic normalization, stability label, or 846 mapping may be written from raw outputs
before the matrix is complete.

If a command fails after model switch, record the error, leave the process stopped, inspect the
failed cell, and only use `--resume` after human confirmation. Resume reruns only cells without
an HTTP 200 `RUN_RECORD.json`.
