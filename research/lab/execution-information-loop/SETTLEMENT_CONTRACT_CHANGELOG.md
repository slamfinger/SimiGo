# Settlement Contract Changelog

Settlements live in the append-only carrier under the schema id
`EINFO-SETTLEMENT-V1`. That schema id is *not* the contract: the envelope shape
was previously implied by whichever writer produced the record. This file
records every change to the envelope so a reader can tell a conforming
settlement from an opaque historical one without guessing.

## V2 — 2026-10-20 — `EINFO-SETTLEMENT-CONTRACT-V1`

### Why

Two writers used the same `EINFO-SETTLEMENT-V1` schema id with incompatible
shapes:

| writer | `result` | `basis` |
| --- | --- | --- |
| `carrier_loop.execute_demand` | `value`, `payload_digest`, `source_version`, `dependency_object_ids`, `evaluated_at_utc`, `valid_until_utc`, `validity_policy` | `source_payload_sha256`, `source_version`, `dependency_object_ids`, `evaluated_at_utc`, `valid_until_utc`, `validity_policy` |
| `g2/batch/run_batch.py` | `fixture_id`, `r1`, `r1_canonical`, `r1_sha256` | `fixture_id`, `source_item_object_id`, `source_kind`, `source_version`, `dependency_ids`, `dependency_object_ids`, `validity_policy_sha256`, `validity_policy_version`, `s1_sha256` |

The reuse predicate could only ever match the dialect that wrote the record, so
a G2 settlement was invisible to `execute_demand` and vice versa. In addition
`result.payload_digest` held the digest of the *source input* while sitting in
the result scope, and the business payload of `real_palace_loop` already
carries a same-named field — the name was a lie about the domain.

### Envelope

`settlement_contract` is written at the **top level** of the settlement object,
beside `schema_id`, `state`, `result`, `basis`. It describes the envelope and
never enters `value`. `value` holds the computed result and nothing else.

Both `result` and `basis` carry the same seven semantic fields; the two digest
domains are explicit and are never compared against one another:

| field | binds | write-time check |
| --- | --- | --- |
| `value` (result only) | the computed result, any canonical JSON | canonicalisable |
| `source_payload_sha256` | `digest(item.source_payload)` — the **source input** domain | 64 lowercase hex; equal in both scopes |
| `result_value_sha256` | `digest(result.value)` — the **result** domain | 64 lowercase hex; equal in both scopes and equal to `digest(result.value)` |
| `source_version` | the item's `source_version` | non-empty, equal in both scopes |
| `dependency_object_ids` | dependency item id → that dependency's settlement object id | map of 64-hex values, equal in both scopes |
| `evaluated_at_utc` | when the computation happened | `YYYY-MM-DDTHH:MM:SSZ`, equal in both scopes |
| `valid_until_utc` | end of the item's validity window | `null` or UTC, `>= evaluated_at_utc`, equal in both scopes |
| `validity_policy` | the whole sealed policy | `validity_policy_identity()` passes, equal in both scopes |

`payload_digest` is removed. A settlement that cannot answer "which input,
which result, which dependencies, which window, which policy" is not
conforming.

### Write rule

`CarrierInformationLoop.settle()` validates before touching the carrier and
raises `SettlementContractViolation(missing, mismatched)`. A rejected
settlement writes zero objects, zero index entries and zero dependency entries.
`SETTLEMENT_CONTRACT` and `CARRIER_LOOP_CONTRACT_VERSION = "2"` are the
constants that identify this version.

### Read rule

`_settlement_reuse_decision()` returns `(reusable, reason)` and never raises. A
settlement without `settlement_contract == EINFO-SETTLEMENT-CONTRACT-V1` is
`SETTLEMENT_CONTRACT_OPAQUE` and is **not** reusable. There is no inference, no
migration and no compatibility read of V1 records: they stay readable for
audit, never for reuse.

`audit_settlement_contracts(db_path)` (read-only `mode=ro`) classifies the
current settlement of every item as `CONFORMING`, `OPAQUE`,
`INVALIDATION_RECORD`, `MALFORMED`, `NOT_SETTLED` or `MISSING_OBJECT`.

### Historical records

The G2 batch carrier (run `20261020T082124Z`) is V1. Its bytes are frozen and
untouched. Auditing the three canonical carriers
(`evidence/20261020T082124Z/fixtures/fixture-{1,2,3}/B1/carrier/g2.sqlite`)
yields `{"OPAQUE": 1}` for each: every G2 settlement is opaque and non-reusable
under V2. That is a recorded fact, not a defect to repair.

`g2/batch/run_batch.py` is frozen and still calls the V1 `settle()` shape, so
re-running it against this module raises `SettlementContractViolation` listing
the missing fields. G2 is closed and is not re-run; the V2 replacements are
`g2/batch/carrier_gate_v2.py` (validity-aware gate) and
`g2/batch/replay_g2_as_core_api.py` (rebinding recorded evidence without
creating new execution facts).

### Drift discipline

- `g2/manifest/`, `g2/evidence/`, `g2/batch/run_batch.py`,
  `g2/batch/carrier_gate.py` and `g2/batch/checker.py` are byte-frozen and were
  not modified by this change:

  | file | sha256 |
  | --- | --- |
  | `g2/batch/run_batch.py` | `6cd580cda4235e50bb01464bff4c398dc76b49aa0b48eff181a052dbde3644ac` |
  | `g2/batch/carrier_gate.py` | `a791de301283f21d26ecfa92bcd17dfbe1e20e0cb963ba93f763af052aaaa99d` |
  | `g2/batch/checker.py` | `bc453515789a432d88c80af6c6fb2a8f82a7b8fd8cfdd274b21660fecefaff32` |

- `carrier_loop.py` moved from `d3fb317ad9588eed84b0f7e1…` (the hash bound by
  `ACTUAL_MLX_SMOKE_MANIFEST_V6`) to
  `464e5c557275417a6724f1d96baa0dd7323a5a691bbfb0205d1f29f3f6db5b4f`.
  V6 is closed and not re-runnable; its binding stays a **historical record**.
  HEAD is not claimed to satisfy V6.
  Intermediate hashes are not contract versions: `67ccdee2…` was the file after
  the V2 envelope landed, `464e5c55…` is the same version `2` after the W4
  invalidation tightening described below. `CARRIER_LOOP_CONTRACT_VERSION`
  stayed `"2"` across both, because neither change altered the envelope.
- Any future freeze record must bind both the `carrier_loop.py` hash and
  `CARRIER_LOOP_CONTRACT_VERSION`, so a contract change cannot hide behind an
  unchanged file list.

### Invalidation semantics (W4, same contract version)

`invalidate_settlement()` gained `strict: bool = True`. With the default, an
unknown target raises the carrier's own `MissingLogicalEntry` and writes
nothing; `strict=False` reproduces the pre-W4 computation and return shape for
historical callers. The dependency graph is now the union of an item's
`dependencies` and the keys of its settlement's `basis.dependency_object_ids`,
so a settlement written by an external writer cannot hide a real dependency.
The invalidation scope is still exactly the transitive closure: items that do
not depend on the target keep their settlements.

### Gate dialect coverage (W2 follow-up, same contract version)

`g2/batch/carrier_gate_v2.py` originally inherited the V1 gate's
`r1_digest_matches_payload` check, which reads `result.r1_canonical` — a G2
field that no conforming settlement has. The consequence was that the gate
refused *every* settlement the loop itself writes, so "gate and loop agree on
the four window states" could not hold on the dialect the loop actually
produces. The gate now branches on `result.settlement_contract`: conforming
settlements are checked against `result.value` / `source_payload_sha256` /
settlement-object dependency ids / the full sealed policy, historical ones keep
the G2 checks. An unrecognised marker is `SETTLEMENT_CONTRACT_UNKNOWN`. The
report body carries `dialect: "CONFORMING" | "HISTORICAL"`.

`g2/batch/carrier_gate.py` (the V1 gate) is byte-frozen and does **not** gain
this coverage; it remains the historical gate for the historical dialect.

### Dialect selection is checked, not inferred (same contract version)

The marker decides the reading; the field shape is then checked *against* the
marker. Three refusals make that explicit, all mapped to
`SETTLEMENT_CONTRACT_MALFORMED`:

| case | example | check |
| --- | --- | --- |
| marker contradicts shape | `settlement_contract` says conforming, `result` carries `r1_canonical` only | `settlement_contract_shape_agrees` |
| both dialects in one payload | `result` carries `value` **and** `r1_canonical` | `settlement_dialect_not_mixed` |
| conforming shape, no marker | `result.value` present, `settlement_contract` absent | `settlement_contract_shape_agrees` |

An absent marker remains the V1 dialect, because every carrier written before
the contract existed is in that state. Inferring the dialect from whichever
fields happen to be present is not allowed: a payload would then choose the
contract it is verified under. `settlement_contract_shape_complete` additionally
requires the exclusive fields of the chosen dialect to be complete, not partial.

### Scope agreement inside one envelope (W1 completion)

`result` and `basis` are two scopes of one settlement, not two independent
records. `validate_settlement_payload` therefore requires, in addition to the
per-field checks:

| equality | rejection label |
| --- | --- |
| `result.source_version == basis.source_version` | `result.source_version!=basis.source_version` |
| `result.evaluated_at_utc == basis.evaluated_at_utc` | `result.evaluated_at_utc!=basis.evaluated_at_utc` |
| both digests, both windows, both policies, dependency map | same `!=` form |

Without the first two, one envelope could describe two source versions or two
evaluation instants while every field on its own stayed well-formed, and a
reader could not say what was settled. The two cases are covered by
`carrier_selftest.py` (`settlement_contract_rejects_cross_scope_source_version`,
`settlement_contract_rejects_cross_scope_evaluated_at`).

## V1 — implicit, before 2026-10-20

No marker, no declared digest domain. Settlements written by `execute_demand`
used `result.payload_digest` (source-input digest in result scope);
settlements written by the G2 batch used a fixture-shaped `result` with no
validity window at all. Neither shape is readable as V2.
