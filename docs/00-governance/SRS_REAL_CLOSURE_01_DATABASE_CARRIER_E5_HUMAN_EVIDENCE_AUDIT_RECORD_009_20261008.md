# SRS-REAL-CLOSURE-01 — Database-Carrier E5 Human Evidence Audit Record 009

> **Status:** CLOSED — HUMAN-DIRECTED READ-ONLY EVIDENCE AUDIT; E5 CONFIRMED
> INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-005-2a3b358
> **Audit base:** `55d81d1b08b9478c1801c5a4f1624ad4c44c6ca7`
> **Governing Request v1.7:** `1b518c822b586dc3a6a900327267f5e3512a7e49`
> **R4 instrumentation commit:** `44514117f7657eda98b15155a916966d4e7c9b19`
> **R4 completion record:** `9c6574622fb3cd6ec06434f3fe3b9f944d613568`
> **E5 authorization/execution commit:** `2a3b3584344bcfd4f7df4dc8f2a0f1df8394a2c2`
> **E5 invalid completion record:** `2f21a137d8c6fe0f97f53cfb3424d91ca6e4856b`

## 1. Audit ruling

E5 is confirmed **INVALID / NON-ADJUDICATIVE**. The campaign lawfully stopped at
the ES2 adapter-output persistence boundary. The failure is a new, independent
harness evidence-chain binding defect, not a CarrierSQLite semantic, database
schema, ES2/ESN semantic, decision-boundary, fixture, runner, or EQ/REJ
criteria defect.

```text
outcome = INVALID / NON-ADJUDICATIVE;
stop_code = CAMPAIGN_ES2_OUTPUT_JSON_PARSE_BINDING_DEFECT;
root_cause_class =
  HARNESS_ADAPTER_OUTPUT_PERSISTENCE_RETURN_TYPE_BINDING_DEFECT;
defect_generation = THIRD INDEPENDENT HARNESS EVIDENCE-CHAIN BOUNDARY.
```

The three boundary classes are distinct:

```text
E3 = canonical observer C3 key binding;
E4 = PosixPath JSON serialization at post-sequence preflight provenance;
E5 = persistence-binding return value mis-consumed as adapter JSON.
```

## 2. Check 1 — R4 effectiveness and limits

The R4 instrumentation state was present and unchanged through the audit base:

```text
diff(R4 instrumentation commit → audit base) on campaign instrumentation = EMPTY;
accepted implementation tree through audit base = UNCHANGED;
authoritative path map version/destinations = 3 / 31;
fresh destination preflight = 31/31 PASS.
```

R4 was effective in the executed prefix:

```text
O0/O1/O2 observations = persisted through the canonical writer;
working-copy binding = persisted;
adapter build command/source hashes = persisted;
ES2 adapter output = persisted through exact-byte persistence.
```

Important limit: E5 stopped before `EVIDENCE_SERIALIZATION_SELF_CHECK`; that
artifact is ABSENT. Therefore this audit proves R4 preflight and pre-write
persistence in the executed prefix, but does **not** claim that E5 completed
R4's aggregate serialization self-check. The separate R4 completion self-check
remains valid at its own stop; it cannot be retroactively attached to E5.

## 3. Check 2 — ES2 output persistence

The ES2 adapter ran exactly once. Its output was valid JSON and was persisted
byte-exactly before the campaign failed:

```text
ES2 input SHA256  = 0c3c547af76ef386dfce65bc2d31cf2348eea2873b300cd23041eeae1c4df5e1;
ES2 output SHA256 = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
raw ES2 decision  = REUSE / REUSE_PATH;
persistence reread = PASS;
parsed-object equality inside persistence helper = PASS.
```

The raw ES2 `REUSE` observation is non-authoritative. It is not equivalence
evidence and does not become authoritative because persistence succeeded.

## 4. Check 3 — return-type contract

The code-level contract was explicit and violated by the caller:

```python
def persist_exact_json(path: Path, payload: bytes) -> dict:
```

The sole successful return is the local `binding` object. That binding contains
artifact path, byte length, byte-persistence equality, parsed-object equality,
pre-write serialization check, canonicalization identity and SHA256. The caller
instead executed:

```python
json.loads(persist_exact_json(output_path, proc.stdout))
```

`json.loads` accepts `str`, `bytes`, or `bytearray`, not a persistence binding
`dict`. Thus this is a caller-side return-type contract violation, not an
ambiguous interface contract gap. The absence of a dedicated prose docstring
does not make the signature and return implementation ambiguous. A future
authorized correction may add documentation/test coverage, but this audit does
not authorize that work.

## 5. Check 4 — correction boundary

The observed defect is confined to adapter-output persistence-binding
consumption. This audit identifies no evidence requiring changes to:

```text
CarrierSQLite semantics;
database schema or transaction semantics;
ES2 or ESN semantics;
decision boundary;
tau;
fixture;
runner semantic sequence;
EQ-1..EQ-8;
REJ-1..REJ-14.
```

Accordingly, if the Human later authorizes more work, the minimal lawful
candidate locus is adapter-output persistence return-type binding and its
fail-closed consumption check. This audit neither drafts nor authorizes that
Request or an E6 campaign.

## 6. Check 5 — reusable campaign evidence

E5 produced no complete reusable campaign evidence package.

```text
raw O0/O1/O2 observations = ACCEPTED AS FACTS ONLY;
raw ES2 REUSE             = NON-AUTHORITATIVE;
ESN                       = NOT OBSERVED;
O3/O4/O5                  = ABSENT;
observer verdict          = ABSENT;
EQ/REJ matrix             = ABSENT;
campaign outcome          = ABSENT;
runtime provenance        = ABSENT;
serialization self-check  = ABSENT;
SHA256SUMS                = ABSENT.
```

Post-stop process/stderr captures are non-authoritative failure evidence only.
They cannot be combined with O0–O2 to reconstruct or complete E5.

## 7. Adjudication disposition

```text
E5                              = INVALID / NON-ADJUDICATIVE;
EQ-1..EQ-8                      = NOT ESTABLISHED;
REJ-1..REJ-14                   = NOT ESTABLISHED;
CarrierSQLite equivalence       = NOT ESTABLISHED;
broader SimiGo/ES claim         = NOT ESTABLISHED;
raw O0–O2 facts                 = ACCEPTED;
raw ES2 REUSE                   = NON-AUTHORITATIVE;
raw ESN BLOCK                   = NOT OBSERVED.
```

## 8. Key bindings

```text
O0 database SHA256          = 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
campaign database SHA256    = f3cf49600c3f07c87b98e0cfd356dd025582b8c61ac5f682a9ccaf1da6275123;
O0 observation SHA256       = 4a032a960559d584a64465c9a8b9bd4cf7175013a46d7c4e3e5e933b1585a779;
O1 observation SHA256       = defbe8d2eaed00260ea45018ca107cd7edb7584ad1f0de2ce1ee88624ee4d8f9;
O2 observation SHA256       = 22f619674e93c8aab9dba24787b976eb0f000398996045fab989e0543dfa79d3;
transaction log SHA256      = ed549b9fa29bcda88311a8707ef71e9b9dc7dc0feb02bac5a96040457da66a0b;
evidence path execution SHA256 = 8e8001755bda74f0df13c4caacfda6b3592b436d3d30b19b6c736c40ef17513b;
authoritative path map SHA256  = 67b742397f2e245dd002a9b8344c03cdcb6dbc83be45e6369d2d5d50ee9b7d0b;
post-stop process capture SHA256 = 1c977b8f9fa31c4ff364ca7d0be86aa02c05148ede3afeea03107d9625eea60a;
post-stop stderr capture SHA256  = 0016b9d7441df0a93d711fec953250e50f158f298a85b9395abbe92926259bc3.
```

## 9. Next lawful object

The next lawful object is an explicit Human decision:

```text
DENY further work; or
authorize a new independently budgeted Request scoped only to adapter-output
persistence return-type binding correction, followed by fresh preflight and a
potential sixth frozen campaign.
```

This audit authorizes neither repair, rerun, old-evidence reuse, E6 drafting,
E6 execution, equivalence establishment, nor budget renewal.

## 10. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this audit
closure.
```
