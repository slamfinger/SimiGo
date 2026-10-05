# G-4 Delivery — Per-Carrier Mapping + Audit

Date: 2026-10-05 (v2 post-fix audit; Human acceptance same day)
Gate state: **Implementation Gate CLOSED by Human ruling** — G-1 / G-2 / G-3 / G-4 all ACCEPTED/CLOSED; IF-G4-01..04 all CLOSED.
Carrier: `ConformanceSubstrate` (`i1_instantiate.py`) — a readback-capable, document-form conformance carrier. No PALACE, backend, or production substrate is selected.
Basis: source audit plus local post-fix re-execution on 2026-10-05: G-1 19/19, G-2 17/17, G-3 10/10.

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
| IC-1 information completeness | `R2.surface` → `feed_surface()` / `materialize()`; used identities are now written directly to `ir.used_item_identities` (IF-G4-04 CLOSED) | VV-1 clean/digest gate; VV-2 byte readback; G-2 equality lock against the CR used set | VERIFIED / PASS |
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
| SC-5 task declared | `ir.task_record` from supplied `tau_star` | SHA-256 over canonical supplied `tau_star`; independently recomputed in G-2 (IF-G4-02 CLOSED) | PRESENT / digest MATCH |
| SC-6 position derivable | `PositionRecord` | VV-5 derivation under bound tokenizer | VERIFIED |

Coverage count: 13/13 frozen rows mapped; no row is omitted and no row claims a stronger tier than its recorded evidence.

## 3. I-1d §5 audit

```text
(a) IR per attempt                  PASS — exact §1.1 fields, including
                                    timestamp/actor and direct used identities
                                    (IF-G4-01/04 CLOSED)
(b) VV surface applicability        PASS — every precondition block records
                                    uniform VV-1..7 = NOT ENTERED
                                    (IF-G4-03 CLOSED)
(c) mapping coverage                13/13 rows mapped; SC-5 canonical digest match
                                    (IF-G4-02 CLOSED)
(d) failure taxonomy                PASS — G-2 exercises BLOCK subtypes,
                                    PROCEED-WITH-ANNOTATION, DECLARED-ALTERNATIVE,
                                    and POST-CREATION-ANOMALY without reclassification
(e) freeze lineage                  PASS — I-1d v0.3, frozen at 1832676
```

C-CAP remains accepted as **SUPPORTED (document-form, limited mechanical support on (c)) — 10/10**. The regression suites were re-run during this G-4 audit with no failure.

## 4. IF-G4-01..04 — fixed and closed (frozen contracts unchanged)

Human ruling: treat all four as implementation/evidence defects, no contract revision; subsequent closure ruling accepted all four on the post-fix evidence.

- **IF-G4-01 CLOSED:** completed IRs now carry `timestamp` and `actor`; the completed-IR validator rejects either missing field. G-1/G-2 lock the format.
- **IF-G4-02 CLOSED:** the TaskRecord digest is now SHA-256 over the supplied `tau_star` after canonical JSON serialization (`sort_keys=True`, compact separators, UTF-8). The old `hash(task_ref)` proxy and caller-supplied digest bypass were removed. G-2 independently recomputes and compares the expected digest; the refreshed `G3_ERUN_RECORD.json` persists the resulting `ir_task_record`.
- **IF-G4-03 CLOSED:** every precondition-block path records exactly `VV-1..VV-7` with uniform `NOT ENTERED`; no `NOT-APPLICABLE` variant remains. G-2 checks exact IDs/order, absence of tier values, and absence of the old variant.
- **IF-G4-04 CLOSED:** the IR now carries `used_item_identities` directly (`name` + pinned `content_digest`) from the resolved R2; the validator requires the field, and G-2 compares it to the CR's used set.

The earlier evidence-metadata typo (`v1` → `v3`) remains fixed.

## 5. Post-fix regression and final Gate state

```text
G-1                  ACCEPTED / CLOSED — 19/19 PASS
G-2                  ACCEPTED / CLOSED — 17/17 PASS
G-3                  ACCEPTED / CLOSED — 10/10 PASS
G-4                  ACCEPTED / CLOSED — 13/13 mapping PASS
IF-G4-01..04         CLOSED
Implementation Gate  CLOSED (Human ruling 2026-10-05)
```

No silent degradation was found or introduced. Frozen contracts remain unchanged. Gate close makes PALACE, backend integration, further experiments, and report packaging eligible for explicit route evaluation; none starts automatically. Frozen Contract revision still requires an independent gate.
