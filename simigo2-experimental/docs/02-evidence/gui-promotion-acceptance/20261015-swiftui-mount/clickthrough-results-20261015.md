# SwiftUI Mount — Manual Click-Through Results (Executed)

> **Record ID:** `RESULTS-CLICKTHROUGH-SWIFTUI-20261015`
> **Date executed:** 2026-10-15, 20:40–21:40 (Asia/Shanghai)
> **Executor:** AI agent via macOS UI automation (accessibility-tree clicks + typed input), NOT the human reviewer. Every observation below is an actual executed GUI operation with its real on-screen result.

## 0. Tested app identity — MANDATORY correction

The five click-through items CANNOT run on `/Applications/SimiGo.app` (v2.1.9):
that binary is the menu-bar **local API server manager** (MLX / LLaMA.cpp /
api.z.ai service toggles, "选择模型…", "复制 API 地址"). Its source
(`SimiGo-v2.1/SimiGo/App/MenuApp.swift`) contains NO chat Load/Send/New-Session
UI, and its binary does not contain the string `press Load first`.

The tested app is therefore the SwiftUI mount under acceptance, built from
this repository at the audited HEAD:

| Field | Value |
|---|---|
| App | `simigo2-experimental/build/SimiGo2Experimental.app` (packaged via `scripts/build-app.sh debug`; bare executable alone exits silently without a bundle) |
| Bundle ID | `local.simigo.experimental2`, CFBundleName "SimiGo 2 Experimental" |
| Binary contains | `press Load first` (verified via `strings`) |
| Built from | repo HEAD `1f80d50e` working tree, simigo2-experimental Package.swift |
| Environment | macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Apple M5 (10 cores, Metal 4); see `clickthrough-environment-20261015.md` for full host facts |
| Models | oversized: `models--mlx-community--Qwen3-Coder-Next-4bit` snapshot `7b9321ea…`; small-scale A: `models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX` snapshot `31a01064…`; small-scale B: `models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit` snapshot `6e302ea6…` |

The user-supplied statement "simigo为v2.1.9构建" does NOT match the app the
five items were written against; the discrepancy is recorded here rather than
silently reconciled.

## 1. Item 01 — Send before any successful Load: **PASS**

Sequence (fresh app launch, "model not loaded / engine not loaded"):
1. Typed `hello test 01`, clicked Send.
   UI: status line → `execution path or model changed — press Load first`;
   no transcript entry, no generation (`idle`). Screenshot captured.
2. Oversized path (default), model directory set to
   `/tmp/definitely-not-a-model-dir-xyz`, clicked Load.
   UI: `load error: The file "config.json" couldn't be opened because there
   is no such file.` + `engine not loaded`. Error text recorded verbatim.
3. Clicked Send again: status line → `execution path or model changed —
   press Load first`; no transcript entry, no generation.

Unexpected generation: none. Both sends blocked.

## 2. Item 02 — oversized → small-scale → oversized: **PASS**

| Leg | Request path + model | Observed |
|---|---|---|
| 1 | oversized + Qwen3-Coder-Next-4bit | `loaded: core 1.26 GiB \| resident floor 0/48 layers \| 6 streaming units × 8 layers \| load 1.4s budget 20480 MiB \| peak 1.55 GiB`; sent "Say OK only" → generated `OK…` (24-token cap; 11251 ms/token) |
| 2 | small-scale + Nail snapshot 31a01064 | `small-scale host active: 31a0106483c9…` + `content-identity namespace \| canonical prefill profile`; oversized stats lines REPLACED by small-scale lines (old engine torn down first per code); sent "Reply with exactly: READY" → generated `READY` |
| 3 | oversized + Qwen3-Coder-Next-4bit | `loaded: core 1.61 GiB \| … \| load 8.6s budget 20480 MiB \| peak 1.97 GiB` — this bind PASSES the code's loud-fail hook check (a retained cross-session hook would have produced `load error: cross-session hook still installed after deactivate`; it did not) |

Honesty note (per protocol): for leg 1→2 the UI does NOT display a
hook-release state, so "old path released" for that direction is code-behavior
inference (engine nilled before host activation), NOT direct UI evidence.
Direct hook-release evidence exists only for leg 2→3 (loud-fail check passed).
No dual-path binding errors occurred in any leg.

## 3. Item 03 — same-path model-directory change without Load: **PASS (both paths)**

**Part A (small-scale).** Loaded A (Nail) → `small-scale host active:
31a01064…`. Changed directory field to B (Qwen3-Coder-30B snapshot) WITHOUT
Load:
- Send clicked → BLOCKED: status `execution path or model changed — press
  Load first`; no transcript entry.
- New Session clicked → BLOCKED: transcript fully retained.
- Restored field to A, Send → generated WITHOUT any reload; reply
  self-identifies `I am Nail-35b-a3b, a variant of Qwen3.6-35B-A3B` — proves
  the surviving binding was A and B was never loaded.

**Part B (oversized).** Oversized A (Qwen3-Coder-Next) bound (`loaded: core
2.37 GiB | load 1.6s` — engine already resident). Changed field to B (Nail
path) WITHOUT Load:
- Send → BLOCKED: `press Load first` set by the guard; no transcript entry.
- New Session → BLOCKED: transcript retained.
- Restored field to A, Send → generated WITHOUT reload (24-token turn
  completed, 9000 ms/token); binding was A throughout.

Execution note: one earlier Send attempt raced a field-commit and did not
register (click repeated); recorded for completeness, does not affect the
blocked/allowed outcomes above, each of which was confirmed with a settled UI.

## 4. Item 04 — switch to a deliberately unloadable model: **PASS**

small-scale, A (Nail) active. Request directory set to
`/tmp/definitely-not-a-model-dir-xyz`, Load clicked:
- Error recorded verbatim: `small-scale load error: The operation couldn't
  be completed. (SimiGo2Experimental.MLXSmallScaleChatHost.HostError error 0.)`
- Request state: field points at the unloadable B path (AX readback).
- Send attempt while request ≠ binding: BLOCKED (`press Load first`; no
  transcript entry) — request-to-B did NOT silently use A and did NOT load B.
- Actual surviving binding proven: restored field to A → Send generated
  WITHOUT reload; reply self-identifies `I am Nail-35b-a3b…`.

Request-vs-binding were recorded as separate states throughout, per protocol.

## 5. Item 05 — old-session failure + durable cache reuse: **NOT TESTABLE (GUI) / NOT CONFIRMED**

**5a. Old-session explicit rejection via GUI: NOT TESTABLE.**
Sequence actually executed: Nail (A) turns completed → switched to
Qwen3-Coder-30B (B) via Load → `small-scale host active: 6e302ea6…` →
sent "old session trigger attempt: which model are you?".
Observed: NO error. The GUI silently drops the held ChatSession on model
switch (code: `chatSession = nil` inside `loadSmallScale()` BEFORE switching),
so the send created a NEW session against B and generated normally
(reply: "I am Claude, …" — B's answer, transcript history retained as
presentation only).
Per the protocol rule: the host-layer stale-session rejection evidence
must NOT be presented as GUI click evidence, and it is not. No GUI path
exists in this build to trigger the visible stale-session error.

**5b. Durable cache retention + re-hit after New Session: NOT CONFIRMED.**
Executed: baseline probe `cache probe ZEBRA-7734…` on A (reply `OK`) →
switch to B and back to A → New Session (transcript visibly CLEARED —
that part is proven) → identical probe resent (reply regenerated,
self-identifies Nail) → long-prefix passage turn → New Session → identical
long-prefix resent (reply `ACK`).
Observable evidence status:
- Cache hit counters: written by the app to `execStateLine`
  (`cross-session cache | hook calls N | hits N | last match M`) — that
  field has NO view in `ChatRootView` (only `loadLine`, `statsLine`,
  `liveGauge` render). Hit counts are NOT observable in the GUI.
- Disk durable cache:
  `~/Library/Application Support/SimiGo2SmallScaleCache/` contains the two
  content-identity namespace directories (31a01064… created 21:00, 6e302ea6…
  created 21:25) but ZERO snapshot files after short probes, the long
  passage, New Sessions, and model switches. Nothing was ever written.
- `last turn: 0 ms/token` is identical across all turns (small-scale mean is
  hardcoded 0), so it cannot distinguish cache-hit from cold prefill.

Verdict: the expected "New Session re-hits the durable prefix" is neither
confirmed nor refuted by observable evidence in this run; with zero disk
snapshots written, a re-hit is in fact not currently demonstrable by any
available observation. Item stays OPEN; NOT marked PASS.

## 6. Matrix status after this run

| Item | Status |
|---|---|
| 01 Send before Load | **PASS** |
| 02 Bidirectional path switch | **PASS** |
| 03 Same-path directory change without Load | **PASS** |
| 04 Unloadable-model rollback | **PASS** |
| 05 Old-session rejection / durable cache re-hit | **NOT TESTABLE (GUI) / NOT CONFIRMED — remains OPEN** |

GUI click-through overall status remains **OPEN** until item 05 is either
made observable (UI exposes hit counts; or durable snapshots actually land on
disk) or explicitly waived by the human reviewer.

Unchanged boundaries: README E4/E5 conflict still a registered maintenance
item; exec-006 bounded; PR #5–#9 conclusions unchanged; V1–V4 un-authorized;
the three 2026-10-15 audit docs remain untracked.
