# SwiftUI Mount — Manual Click-Through Environment Record

> **Record ID:** `ENV-CLICKTHROUGH-SWIFTUI-20261015`
> **Date:** 2026-10-15 (Asia/Shanghai)
> **Purpose:** Environment facts collected from the actual macOS host in
> preparation for the five-item manual click-through supplementary
> verification. This record does NOT execute any item and does NOT change
> any item's status. All five items remain OPEN.

## 1. Collected host environment (verified on this machine, 2026-10-15)

| Field | Value | Source |
|---|---|---|
| App bundle path | `/Applications/SimiGo.app` | running process + `Contents/MacOS/` |
| App version | 2.1.9 (`CFBundleShortVersionString`), build 19 | `Info.plist` |
| Binary timestamp | 2026-10-15 15:17 | `Contents/MacOS/SimiGo` mtime |
| macOS | 27.0.1, build 26A434 | `sw_vers` |
| Xcode | 27.0, build 27A266a (`/Applications/Xcode.app`) | `xcodebuild -version` |
| GPU / Metal | Apple M5, 10 cores, Metal 4 | `system_profiler SPDisplaysDataType` |
| Local model | `/Users/mr.simi/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX` (snapshot `31a0106483c94e9fbb0a6d3360ff122d47377058`) | user-provided + directory confirmed |
| App process | running since 17:43 (PID 25379) | `ps aux` |

## 2. Five-item click-through status (ALL OPEN — none PASS)

Execution requires a human at the app with this environment record in hand;
each item must record actual operation result, error text, and cache-hit
evidence before it may be marked PASS. Items without such records stay OPEN.

1. **OPEN — Send before any successful Load** (incl. after a failed
   oversized Load with an error model directory).
   Expected: blocked with the "press Load first" prompt.
2. **OPEN — Bidirectional path switching** oversized → small-scale →
   oversized. Expected: old path released, hook-release check passes, new
   path works.
3. **OPEN — Same-path model directory change without Load** (both paths).
   Expected: Send and New Session both blocked.
4. **OPEN — Switch to a deliberately unloadable model.** Expected: rollback
   keeps A active while the request points at B; Send blocked.
5. **OPEN — Post-switch old-session error visibility + durable cache
   retention.** Expected: old session errors visibly; after New Session the
   durable cache is retained and the next session re-hits it.

## 3. Unchanged boundaries

- README E4/E5 conflict remains a registered documentation-maintenance item.
- exec-006 remains bounded; no auto-extension.
- PR #5–#9 conclusions unchanged; V1–V4 remain un-authorized.
- The three 2026-10-15 audit/review docs remain untracked git files; no code,
  frozen-contract, or authorization change this round.
