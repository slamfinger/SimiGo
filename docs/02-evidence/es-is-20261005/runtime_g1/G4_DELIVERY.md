# G-4 Delivery — Per-Carrier Mapping + Audit

Date: 2026-10-05
Gate state: Implementation Gate OPEN — G-1 / G-2 ACCEPTED/CLOSED; **G-3 ACCEPTED/CLOSED at `397fbca` by Human review**; G-4 delivered, awaiting Human review.
Carrier: `ConformanceSubstrate` (`i1_instantiate.py`) — a readback-capable, document-form conformance carrier. No PALACE, backend, or production substrate is selected.
Basis: source audit of `397fbca`, the machine-readable `G3_ERUN_RECORD.json`, and local re-execution on 2026-10-05: G-1 19/19, G-2 17/17, G-3 10/10.

## 1. Carrier requirements

| Requirement | Carrier mapping |
|---|---|
| MC-1 execution / bound weights | `ConformanceSubstrate.bind()` binds the declared weights identity; the E-run T2 adapter consumes the bound S2. |
| MC-2 byte surface materialization | `feed_surface()` + `materialize()` make `R2.surface` addressable; `readback_surface()` supplies the VV-2 VERIFIED path. |
| MC-3 trace granularity | E1/E2 traces record predecessor segments, consumed content identities, and new segment identifiers for document-form C-CAP(c). |
| MC-4 IS-side records | `ContentStore` stores CR blobs/nodes by content identity; IR is the in-memory attempt/result record judged in the E-run. |
| MC-5 envelope capture | `bind()` captures the declared envelope; `envelope_readback()` supplies the VV-4 VERIFIED path. |
| MC-6 tokenizer identity | `tokenizer_id` is carried in the manifest and `tokenize_position()` derives the deterministic unit position. |

## 2. Frozen I-1d §1.2 mapping table

| Frozen clause | Carrier object / field / operation | Mechanical verification | E-run result |
|---|---|---|---|
| IC-1 information completeness | `R2.surface` → `feed_surface()` / `materialize()`; used identities are reachable only by dereferencing `ir.cr_ref` → R2 (see IF-G4-04) | VV-1 clean/digest gate; VV-2 byte readback; resolved used-item checks upstream | VERIFIED / PASS |
| IC-2 binding | `decide_binding()` → `BindingRecord` | mechanical equality of predecessor and declared weights identity; three-state output | BOUND; VV-3 VERIFIED |
| IC-3 envelope | declared envelope in `tau_star`; captured by `bind()`; read by `envelope_readback()` | VV-4 declared/effective equality | VERIFIED |
| IC-4 lineage | inherited `R2.lineage.segments` → `ir.attached_segment_provenance`; IR references CR(R1) | VV-6 attachment completeness; CR lineage and E2 parent link | VERIFIED / linked |
| IC-5 position | `tokenize_position(R2.surface)` → `PositionRecord` under `tokenizer_id` | VV-5 derived position and manifest identity | VERIFIED |
| IC-6 no-oracle | VV-1..7 consist only of digest/byte/equality/structure checks; no semantic reviewer enters VV | mapping audit + tier vocabulary conformance | structurally COVERED |
| IC-7 efficiency (optional) | `carrier_state` absent on the document-form run | restore path not taken; absence recorded as annotation | NOT-TAKEN / recorded |
| SC-1 surface integrity | `readback_surface()` versus `R2.surface` | VV-2 byte equality | VERIFIED |
| SC-2 substrate bound | `BindingRecord` from `decide_binding()` | three-state mechanical decision | BOUND / VERIFIED |
| SC-3 envelope active | VV-4 readback versus declared envelope | declared/effective equality | VERIFIED |
| SC-4 lineage attached | `ir.attached_segment_provenance` | VV-6 completeness | VERIFIED |
| SC-5 task declared | `ir.task_record` from supplied `tau_star` | task record presence and task digest check | **PRESENT, but see IF-G4-02** |
| SC-6 position derivable | `PositionRecord` | VV-5 derivation under bound tokenizer | VERIFIED |

Coverage count: 13/13 frozen rows mapped; no row is omitted and no row claims a stronger tier than its recorded evidence.

## 3. I-1d §5 audit

```text
(a) IR per attempt                  PASS for pipeline/evidence structure,
                                    with IF-G4-01 OPEN on exact §1.1 fields
(b) VV surface applicability        PARTIAL — success path enters after precondition,
                                    but precondition-block records VV-1 =
                                    NOT-APPLICABLE (or, for a missing task_ref,
                                    no VV result) instead of one explicit
                                    VV-1..7 = NOT ENTERED fact; IF-G4-03 OPEN
(c) mapping coverage                13/13 rows mapped above
(d) failure taxonomy                PASS — G-2 exercises BLOCK subtypes,
                                    PROCEED-WITH-ANNOTATION, DECLARED-ALTERNATIVE,
                                    and POST-CREATION-ANOMALY without reclassification
(e) freeze lineage                  PASS — I-1d v0.3, frozen at 1832676
```

C-CAP remains accepted as **SUPPORTED (document-form, limited mechanical support on (c)) — 10/10**. The regression suites were re-run during this G-4 audit with no failure.

## 4. Findings and evidence hygiene

- **Non-blocking typo, FIXED here:** `G3_ERUN_RECORD.json` identified the accepted v3 delivery as `"G-3 E-run v1"`. The source and persisted record now say `"G-3 E-run v3"`. This changes evidence metadata only.
- **IF-G4-01 OPEN:** I-1d §1.1 includes `timestamp` and `actor` in a completed IR, but the realized IR has neither field and `ir_validate_completed()` does not check them. This is an exact-field compliance gap, not a silent semantic downgrade; it requires Human resolution.
- **IF-G4-02 OPEN:** SC-5 requires the TaskRecord digest to match the supplied `tau_star`. The implementation defaults to SHA-256 over `task_ref`, and the E-run does not pass an explicit task digest or verify equality against canonical supplied `tau_star` bytes. Thus TaskRecord presence is proven, but the stronger digest-match claim is not yet mechanically realized.
- **IF-G4-03 OPEN:** the frozen applicability boundary says a precondition block records `VV-1..VV-7 = NOT ENTERED` as one applicability fact, not a verdict tier. The realized block path writes `{"check":"VV-1","verdict":"NOT-APPLICABLE"}` for a degraded resolve, and no VV result for a missing `task_ref`. This makes the applicability fact non-uniform and resembles an out-of-vocabulary verdict.
- **IF-G4-04 OPEN:** the frozen IC-1 row puts used-item identities in the IR. The realized IR stores only `cr_ref`; used identities are reached indirectly by resolving that reference to R2. This is an auditable indirection, but not a literal realization of the frozen row's stated IR field.

No silent degradation was found: all open items are explicit registered deviations, not hidden contract rewrites. Frozen contracts remain unchanged.

## 5. Gate state after G-4 delivery

```text
G-1  ACCEPTED / CLOSED
G-2  ACCEPTED / CLOSED
G-3  ACCEPTED / CLOSED
G-4  DELIVERED — 4 OPEN IMPLEMENTATION FINDINGS

Implementation Gate close is BLOCKED until Human resolves IF-G4-01..04.
PALACE / backend / extra experiments / frozen-contract changes remain BLOCKED.
```
