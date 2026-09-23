# SimiGo 2.0 App Real-Device Proof

**Date**: 2026-09-24  
**Status**: APP_BUILD_PASS / REAL_DEVICE_GATE5_PASS  
**Device**: Apple M5, arm64, macOS 26.6.2 (25G83), 34,359,738,368 bytes physical memory  
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`  
**States**: `STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL`

## 1. Build artifact

The package now contains a minimal SwiftUI app target and bundle script:

```bash
cd simigo2-experimental
./scripts/build-app.sh debug
```

Artifact:

```text
simigo2-experimental/build/SimiGo2Experimental.app
```

The app opens a local Gate 5 runner when launched normally. It also has a
command-line self-test mode used for reproducible evidence.

## 2. Real-device run

```bash
./build/SimiGo2Experimental.app/Contents/MacOS/SimiGo2App \
  --self-test \
  --model /Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d \
  --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL
```

Exit code: `0`  
Self-test verdict: `PASS`

## 3. Result

```text
outputIdentityPass                  = true
idleReductionObserved               = true
maximum idle reduction              = 10,871,635,200 bytes
reload reduction vs naive           = 10,871,635,968 bytes
all-resident generation total       = 4,510.48 ms
naive-on-demand generation total    = 5,252.10 ms
execution-state generation total    = 5,608.81 ms
naive reload bytes                  = 65,229,815,808
execution-state reload bytes        = 54,358,179,840
```

All 15 generations returned `pong`.

## 4. Boundary

This is a local Apple Silicon real-device feasibility proof, not a release-app or
performance-optimization claim. The execution-state policy controls idle group
retention between complete generations; it does not skip layers during inference.

Raw evidence: docs/02-evidence/SIMIGO2_APP_REAL_DEVICE_PROOF_20260924.json
