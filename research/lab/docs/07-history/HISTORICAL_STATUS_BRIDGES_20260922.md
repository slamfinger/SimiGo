# Historical Status Bridges (2026-09-22)

## Purpose

This file prevents future Agents from mistaking a historical opening/design snapshot for the later authoritative endpoint.

It does **not** rewrite historical documents. It provides explicit navigation from superseded snapshots to the documents that established the later state.

## 1. H-P1 Opening → H-P1 Results / Closure

| Historical snapshot | Later authoritative state | Interpretation |
|---|---|---|
| `trackE-residency/RESIDENCY_H-P1_OPENING_20260922.md` v0.2 | `trackE-residency/RESIDENCY_H-P1_RESULTS_20260922.md` | Opening snapshot recorded the state **before** design-question lock and experiment execution. Its PASS / Design Question Lock Pending wording is historical provenance, not current state. |
| H-P1 opening | H-P1 results | H-P1 later reached **CLOSED / SEALED** after design lock, regression gate, L1, Hot Null v2 calibration, and L3. |
| H-P1 results | `trackE-residency/TRACK_E_CLOSED_RECORD_20260922.md` | Track-level closure supersedes informal continuation assumptions; the Track E closure record is the authoritative Track E endpoint record. |

### Agent rule

When the opening document is encountered:

1. treat it as a historical snapshot;
2. follow this bridge to the later results/closure;
3. do not infer that H-P1 is still waiting for design lock;
4. do not alter the opening document merely to make its historical wording look current.

## 2. Provenance principle

Historical snapshots retain their original status because changing them would destroy the record of what was known at that point in time.

Therefore:

```
historical wording ≠ current state
```

The current state must be recovered from `docs/RESEARCH_STATE.md`, current endpoint/closure records, and the repository's provenance chain.

## 3. Scope

This bridge is a navigation aid only.

It does not:

- reopen H-P1;
- modify any sealed result;
- create a new RQ;
- authorize implementation or measurement;
- replace the endpoint/closure documents.
