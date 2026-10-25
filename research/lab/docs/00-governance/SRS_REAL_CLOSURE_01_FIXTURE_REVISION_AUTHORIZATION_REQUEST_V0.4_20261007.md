# SRS-REAL-CLOSURE-01 — FIXTURE_PREPARATION REVISION Authorization Request v0.4

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** FIXTURE_PREPARATION REVISION Authorization Request v0.3
> @ `bb25fae` (superseded lineage)
> **Review basis:** Human independent audit of v0.3 ruled **B = REVISE** with
> one substantive gap and one doc-consistency item (Fix 1 register cleanup
> and the choice of IMMUTABLE_SNAPSHOT_PRESEALED both ruled PASS):
> **Gap** — F-4.3 skipped how a read instance obtains an IMMUTABLE revision
> snapshot from the **mutable** current-resolution mapping. Append-only
> entries are immutable, but "current revision" is determined by the whole
> mapping's latest state; without a sealing step, a mapping append between
> read begin and verification would silently change the read instance's
> semantics (a TOCTOU §9 forbids, and which "before/after equality alone"
> cannot cure).
> **Fix applied** — F-4.3b: at read-instance start the mapping file is read
> ONCE as bytes, the snapshot is hashed/sealed, the LAST entry is parsed
> FROM THE SNAPSHOT (never re-read from the file), the immutable revision
> and revision→content-digest binding are resolved from the sealed
> snapshot, and only then is the object read and verified. Two concepts
> are now mechanically separated: the SAME read instance cannot drift with
> later mapping appends; a NEW read instance resolves the then-current
> revision. This is exactly the N1 semantics.
> **SV-4 extended** accordingly (drift test + new-instance test).
> **Doc consistency** — §7 now says "deliver F-5 manifest/completion
> outputs" (numbering alignment; no authorization change).
> Everything else carried unchanged from v0.3.
> **Requested stage set:** `{ FIXTURE_PREPARATION (revision cycle) }`
> **Execution / IS mutation / experiment:** NOT AUTHORIZED
> **Design change:** NONE
> **SimiGo code change / Package.swift / Frozen Contracts:** NOT AUTHORIZED

## 1. Exact bindings

```text
defect_register =
  SRS_REAL_CLOSURE_01_EXECUTION_READINESS_DEFECT_REGISTER_20261007
  (D-SEC-1 binding semantics standing alone; unchanged in this cycle);

frozen_predicate_design =
  SRS_VAL_01_DESIGN_V0_8 @ 1170208,
  git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
  sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;

frozen_governance_package =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6 @ 6089f0b,
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
  sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37
  (§9 read-instance immutability — including the rule that before/after
  equality alone is invalid and a revision number is never compared as if
  it were a digest);

experiment_design =
  SRS_REAL_CLOSURE_01_DESIGN_…_V0_2 @ 050b918,
  git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
  sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe;

fixture_manifest (to be superseded by manifest v2 of this revision) =
  FIXTURE_MANIFEST @ d6507ff,
  git:blob:b700942737fdf89ccc102b1f1629139c378e80c7,
  sha256 8d240a70d3397b7f60923463e28af9071deddfe3063229f5a5b48f078843169e;

t_impl_01_components (canonical, unchanged, @ 07176ec):
  SRSVALInvocation.swift  git:blob:0fd65bdf40b7c9885de2ada491d66348ebfa28fa
                          sha256 6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75
  SRSVALDecision.swift    git:blob:cbd24721a97f3c06e012fb02649feb19c2b9cb8b
                          sha256 e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de
  SRSVALCore.swift        git:blob:9f11ef1af45be6bc9450e0fbdc0117211f99a74a
                          sha256 9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e
```

## 2. Revision scope (exact; no other change permitted)

```text
F-1  es_runner.py mapping_read(): LAST-entry-per-dependency_id resolution
     semantics, exactly as IS_LAYOUT.md (frozen) declares. Repairs D-6.

F-2  es_runner.py run_step(): pass env=env to subprocess.run so that
     SRSVAL_ADAPTER_BIN, PYTHONPATH, and PYTHONDONTWRITEBYTECODE=1 reach
     the ES subprocesses. Repairs D-7.

F-3  es_runner.py mode_driver(): after es1 completes, read the ES₁ event
     log's SRS_SETTLED_AND_PERSISTED event, extract the actual
     srs_identity, and write runtime τ copies (tau2-runtime.json,
     tauN1-runtime.json) into runs/<run_id>/ with the placeholder
     substituted; es2/esn are invoked with the runtime copies; the
     substitution is recorded as a driver event; fixture τ originals are
     never modified. Repairs D-8.

F-4  es_runner.py READ-INSTANCE INSTRUMENT implementing Auth Package §9
     with the registered proof mechanism IMMUTABLE_SNAPSHOT_PRESEALED:

     F-4.1  proof form and establishment conditions for OBJECT reads
            (unchanged from v0.3):
              a) IS objects are addressed by sha256(content);
              b) writes go through tmp+fsync+rename, and an existing
                 address REFUSES divergent content (write-once seal);
              c) the seal precedes the read instance;
              d) every read verifies read_time_content_digest against
                 the sealed address before consumption;
            divergence → READ_INSTANCE_NOT_IMMUTABLE or
            READ_TIME_CONTENT_MISMATCH → abort → campaign INVALID.

     F-4.2  per-read record: ALL ELEVEN §9 fields
            (read_instance_identity; declared_input_identity;
            declared_input_binding_kind; declared or resolved declared
            content digest; read_time_content_digest;
            read_instance_snapshot_or_atomicity_proof =
            IMMUTABLE_SNAPSHOT_PRESEALED; observer_authorization_identity;
            channel_universe_identity; read_begin_boundary;
            read_end_boundary; consumed_content_matches_declaration),
            plus SUPPLEMENTARY instrumentation fields (additive evidence,
            never substituting for the eleven).

     F-4.3  binding kinds per input class:
            τ runtime copies and fixture-seeded inputs → CONTENT_ADDRESS;
            IS objects (SRS record, D, D') → CONTENT_ADDRESS;

     F-4.3b NEW — MAPPING READ-INSTANCE SEALING (the v0.3 gap):
            the current-resolution mapping is mutable append-only state;
            an immutable revision input is therefore obtained by sealing
            the mapping state AT READ-INSTANCE START:
              1. read the mapping file ONCE as bytes (the snapshot);
              2. seal: mapping_snapshot_digest = sha256(snapshot bytes),
                 recorded in the read-instance record's supplementary
                 fields;
              3. parse LAST entry per dependency_id FROM THE SNAPSHOT
                 BYTES ONLY — the mapping file is never re-read inside
                 this read instance;
              4. resolve declared_immutable_revision and the
                 revision→content-digest binding from the sealed
                 snapshot's entry;
              5. read the object at the resolved content address and
                 verify read_time_content_digest ==
                 resolved_declared_content_digest.
            Consequences (mechanically guaranteed by steps 1-3):
              - the SAME read instance cannot drift when the mapping
                file later gains new entries (the instance resolves from
                its sealed snapshot, not from the file);
              - a NEW read instance (fresh snapshot) resolves the
                then-current revision;
              - a mapping append between snapshot seal and object
                verification cannot alter this instance's declared
                revision or declared digest.
            Failure vocabulary unchanged: READ_INSTANCE_NOT_IMMUTABLE /
            READ_TIME_CONTENT_MISMATCH /
            REVISION_TO_DIGEST_BINDING_INVALID → typed abort → campaign
            INVALID.

     F-4.4  binding-kind rule (unchanged): a revision number is never
            compared as if it were a digest — the IMMUTABLE_REVISION
            binding resolves revision→digest via the sealed snapshot's
            entry, and the digest is what is compared.

F-5  FIXTURE_MANIFEST v2 + FIXTURE_PREPARATION_COMPLETION_RECORD v2
     (inside the fixture subtree per R3 precedent): changed artifacts
     re-bound by git blob + SHA256; unchanged artifacts carried with
     original bindings; revision changelog mapping each change to its
     defect ID; violation counts and scope verdict fields as before.
```

## 3. Instrument self-validation (SV-1..SV-6; no campaign sequence)

Temporary directory outside the repository; synthetic inputs; outputs
discarded. SV-1, SV-2, SV-3, SV-5, SV-6 carried unchanged from v0.2/v0.3:

```text
SV-1  mapping semantics (LAST entry; single-revision fallback);
SV-2  environment propagation (trivial probe child; three variables);
SV-3  tau substitution (synthetic ES₁ log; exact identity; originals
      byte-unchanged);
SV-5  adapter integration (synthetic positive + N1-shaped graphs);
SV-6  channel hygiene (no __pycache__ or other generated cache anywhere
      under the fixture subtree after SV-1..SV-5).
```

SV-4 REPLACED — validates the §9 mechanism INCLUDING the new mapping seal:

```text
SV-4a  seal-then-read happy path (object): create object via the
       write-once path (seal), read via the instrumented path; assert the
       record carries ALL ELEVEN §9 fields, proof form
       IMMUTABLE_SNAPSHOT_PRESEALED, read_time digest == sealed address,
       consumed = true;

SV-4b  tamper case: attempt divergent content under an existing address
       → write-once refusal; attempt a read whose content does not hash
       to the sealed address → READ_TIME_CONTENT_MISMATCH recorded and
       consumed = false;

SV-4c  IMMUTABLE_REVISION + drift test (the v0.3 gap, now closed):
       pre-seal mapping = rev1→addrA;
       establish the read instance's immutable mapping snapshot;
       THEN append rev2→addrB to the original mapping file;
       the SAME read instance must continue resolving the sealed
       snapshot's declared revision/content digest — it must NOT silently
       switch to rev2:
         assert declared_immutable_revision = 1;
         assert resolved_declared_content_digest = addrA;
         assert read_time_content_digest = addrA;
         assert the revision number "1" is never compared as a digest;
       then, in a NEW read instance (fresh snapshot taken after the
       append), assert resolution yields rev2→addrB;
       the two assertions together prove the separated concepts:
         same instance → no drift under later appends;
         new instance  → resolves the new current revision
       (exactly the semantics N1 exercises).

SV-4d  failure-vocabulary assertions: the three §9 failure codes are
       produced by constructed fault injections.
```

**Boundary statement (binding, carried):** none of SV-1..SV-6 runs the full
or partial campaign sequence; no observer campaign run; no IS
materialization; no evidence artifact is produced; sandbox outputs are
discarded. Fixture revision proves fixture mechanics — the campaign remains
exclusively behind EXECUTION Request v0.3 and its three authorization
records.

## 4. Out of scope (explicitly)

```text
- any change to Design v0.2, frozen contracts, T-IMPL-01 canonical
  artifact, Package.swift, or repository sources;
- any change to adapter/BUILD.md, schema/validate_srs.py, is_layout,
  inputs, tau originals, or observer.py (expected: none change);
- any full or partial campaign sequence under any name;
- any governance-track expansion;
- the §6.2 classification and channel-universe reclassification decisions
  (EXECUTION Request v0.3 scope, per the binding D-SEC-1/D-SEC-2
  semantics).
```

## 5. Authorized writable path set

```text
docs/02-evidence/srs-real-closure-01/fixture/
  (runner/es_runner.py; FIXTURE_MANIFEST.md;
   FIXTURE_PREPARATION_COMPLETION_RECORD.md);
plus the temporary self-validation directory outside the repository
(discarded after SV-1..SV-6).
```

## 6. Budgets and validity

```text
fixture_revision_work_cycle_budget = 1;
execution_run_budget = 0;
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden;
validity_boundary = from Human approval until completion record v2,
  withdrawal, or expiry.
```

## 7. Required Human decision

```text
APPROVE FIXTURE_PREPARATION REVISION ONLY
      create the revision SAR; apply F-1..F-4; run SV-1..SV-6; deliver
      the F-5 manifest v2 and completion record v2 outputs; push +
      ls-remote verify; STOP. EXECUTION Request v0.3 then exact-binds the
      revised manifest.

REVISE REQUEST     return with registered defects.
DENY REQUEST       no fixture revision (execution remains blocked).
```

No stage is authorized by opening this Request.
