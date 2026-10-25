# TC-A Runner Runbook

This runbook describes preparation only. It does **not** authorize Execution A,
Observer store, Execution B, or evaluation.

All commands use:

```bash
HARNESS=docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/runner/harness.py
RUN_ROOT=docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/runs/<run-id>
T4CTL=<path-to-existing-t4ctl-binary>
```

## 0. Package verification

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" verify-package
```

## 1. Prepare isolated working artifacts

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" prepare
```

This copies source files, copies Information₀, and renders no Agent request.

## 2. Execution A — NOT AUTHORIZED

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" run-a
```

## 3. Observer — NOT AUTHORIZED

After separate authorization and A review:

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" observer \
  --expected-identity <identity-printed-by-run-a>
```

## 4. Runtime isolation — NOT AUTHORIZED

After separate authorization, isolate NativeMLX externally, then record it:

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" mark-isolated \
  --isolation-method reload \
  --isolation-evidence "path/to/isolation-evidence.md"
```

## 5. Execution B — NOT AUTHORIZED

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" run-b
```

## 6. Evaluate — NOT AUTHORIZED

```bash
python3 "$HARNESS" --run-root "$RUN_ROOT" --t4ctl "$T4CTL" evaluate
```
