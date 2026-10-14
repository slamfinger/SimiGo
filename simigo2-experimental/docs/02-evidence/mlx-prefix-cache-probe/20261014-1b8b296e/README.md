# MLX prefix-cache system acceptance — 2026-10-14 / 1b8b296e

## Verdict

`PASS` on current implementation HEAD.

A fresh `simigo2ctl` process loaded the real Qwen3-Coder model, exported a prefix
artifact through `PrefixSnapshotStore`, and installed the verified lookup for a
fresh `ChatSession`. The warm session consumed the durable artifact through
`ChatSession.crossSessionPrefixLookup`.

## Assertions

- `pass = true`
- `crossSessionHitObserved = true`
- `hookCalls = 1`
- `hookHits = 1`
- `matchedTokenCount = 23`
- `outputsMatch = true`

## Scope

This is process-level real-runtime acceptance for:
`PrefixSnapshotStore` → `MLXPrefixSnapshotLoader` → `ChatSession.crossSessionPrefixLookup`.

It does not certify power-loss/media durability, the oversized engine path, G-10
closure, or production GUI wiring.

## Files

- `manifest.json` — machine-readable acceptance manifest
- `cli-output.json` — raw probe report
- `artifact-sidecar.json` — exported sidecar metadata
- snapshot SHA-256: `ddbf7955e47bfe2f9d14543b2150e1f75a5d1a0b88902551fc81219bd049ae26`
- sidecar SHA-256: `49af49d52c3914acc92e54042f0076f3147e2974f4ed783f545e3f13745e66da`
