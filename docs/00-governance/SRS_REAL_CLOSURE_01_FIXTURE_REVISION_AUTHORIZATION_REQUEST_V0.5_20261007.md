# SRS-REAL-CLOSURE-01 — FIXTURE_PREPARATION REVISION Authorization Request v0.5

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** FIXTURE_PREPARATION REVISION Authorization Request v0.4
> @ `0ba333c` (superseded lineage)
> **Review basis:** Human independent audit of v0.4 ruled **B = REVISE** on a
> single remaining §9 gap (everything else PASS: D-SEC-1, proof-form
> selection, eleven-field closure, CONTENT_ADDRESS/IMMUTABLE_REVISION
> distinction, revision≠digest, same/new-instance semantics, SV-4 as
> mechanism test):
> **Gap** — "read the mapping file once as bytes" does not prove that those
> bytes are the mapping state AT READ-INSTANCE START. TOCTOU: an append at
> T0+ε can be swept into a read that completes at T0+2ε, and the definition
> did not say whether rev1 or rev2 is the sealed state. The mapping's
> frozen semantics are append-only with existing entries never rewritten —
> so fixing the START LENGTH excludes later appends from this instance.
> **Fix applied** — F-4.3b is upgraded with the exact **mapping snapshot
> boundary**: open FD → capture file identity + start_size → capture
> exactly bytes [0, start_size) → seal that prefix → parse LAST entry from
> the sealed prefix only. Snapshot boundary fields registered; failure
> rules (identity replaced / prefix not exactly obtainable / append-only
> invariant violated → READ_INSTANCE_NOT_IMMUTABLE) registered.
> **SV-4c extended** with SV-4c-0 (append before/during acquisition) and
> the truncate/replace/non-append mutation case. Proof form unchanged:
> IMMUTABLE_SNAPSHOT_PRESEALED. Everything else carried unchanged.
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
  (§9 read-instance immutability; before/after equality alone invalid;
  revision number never compared as a digest);

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
            (unchanged): content-addressed objects; tmp+fsync+rename with
            overwrite refusal as the seal; seal precedes the read
            instance; read-time digest verification; divergence →
            READ_INSTANCE_NOT_IMMUTABLE / READ_TIME_CONTENT_MISMATCH →
            abort → campaign INVALID.

     F-4.2  per-read record: ALL ELEVEN §9 fields, plus SUPPLEMENTARY
            instrumentation fields (additive, never substituting).

     F-4.3  binding kinds: τ runtime copies and fixture seeds →
            CONTENT_ADDRESS; IS objects → CONTENT_ADDRESS; dependency
            current state via the resolution mapping → IMMUTABLE_REVISION
            (a revision number is never compared as if it were a digest).

     F-4.3b MAPPING READ-INSTANCE SEALING — v0.5 UPGRADE with the exact
            snapshot boundary:

            procedure (in order):
              1. at read-instance start, open the mapping file and obtain
                 an FD;
              2. capture the file identity (st_dev/st_ino of the FD) and
                 start_size = fstat(FD).st_size;
              3. capture EXACTLY the byte range [0, start_size) from that
                 same FD — a short read (fewer than start_size bytes) is
                 a failure, not a smaller snapshot;
              4. seal: mapping_snapshot_digest = sha256(prefix bytes);
              5. parse the LAST entry per dependency_id FROM THE SEALED
                 PREFIX ONLY — the mapping path is never re-read inside
                 this read instance;
              6. resolve declared_immutable_revision and the
                 revision→content-digest binding from the sealed entry;
              7. read the object at the resolved content address and
                 verify read_time_content_digest ==
                 resolved_declared_content_digest.

            snapshot boundary record (supplementary fields on the
            read-instance record):
              mapping_snapshot_identity;
              mapping_snapshot_file_identity (st_dev/st_ino);
              mapping_snapshot_start_size;
              mapping_snapshot_digest;
              mapping_snapshot_seal_boundary (event-log ordinal).

            mechanical rules:
              start_size      = size of the mapping file at read-instance
                                start;
              snapshot_bytes  = exactly bytes [0, start_size);
              after snapshot acquisition the mapping file is NEVER
                re-read by this read instance;
              failure rules → READ_INSTANCE_NOT_IMMUTABLE:
                - the file identity is replaced (path now resolves to a
                  different st_dev/st_ino than the opened FD captured);
                - the captured prefix cannot be obtained exactly (short
                  read: file shrank below start_size — non-append
                  mutation);
                - the append-only invariant is violated (later file size
                  < start_size, or the captured prefix cannot be matched
                  against the file state at read-instance end).

            consequences (mechanically guaranteed):
              - appends after the snapshot seal are outside this read
                instance by construction (they extend beyond start_size);
              - the SAME read instance cannot drift when the mapping
                gains new entries;
              - a NEW read instance (fresh FD, fresh start_size) resolves
                the then-current revision;
            this is exactly the N1 semantics.

     F-4.4  failure vocabulary wired: READ_INSTANCE_NOT_IMMUTABLE /
            READ_TIME_CONTENT_MISMATCH / REVISION_TO_DIGEST_BINDING_
            INVALID → typed abort → campaign INVALID.

F-5  FIXTURE_MANIFEST v2 + FIXTURE_PREPARATION_COMPLETION_RECORD v2
     (inside the fixture subtree per R3 precedent): changed artifacts
     re-bound by git blob + SHA256; unchanged artifacts carried with
     original bindings; revision changelog mapping each change to its
     defect ID; violation counts and scope verdict fields as before.
```

## 3. Instrument self-validation (SV-1..SV-6; no campaign sequence)

Temporary directory outside the repository; synthetic inputs; outputs
discarded. SV-1, SV-2, SV-3, SV-5, SV-6 carried unchanged:

```text
SV-1  mapping semantics (LAST entry; single-revision fallback);
SV-2  environment propagation (trivial probe child; three variables);
SV-3  tau substitution (synthetic ES₁ log; exact identity; originals
      byte-unchanged);
SV-5  adapter integration (synthetic positive + N1-shaped graphs);
SV-6  channel hygiene (no __pycache__ or other generated cache anywhere
      under the fixture subtree after SV-1..SV-5).
```

SV-4 — validates the §9 mechanism INCLUDING the snapshot boundary:

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

SV-4c  IMMUTABLE_REVISION + drift test:
       pre-seal mapping = rev1→addrA; establish the read instance's
       immutable mapping snapshot; THEN append rev2→addrB; the SAME read
       instance must continue resolving the sealed snapshot's declared
       revision/content digest (declared_immutable_revision = 1;
       resolved_declared_content_digest = addrA; read_time_content_digest
       = addrA; the revision number "1" is never compared as a digest);
       then, in a NEW read instance (fresh FD, fresh start_size), assert
       resolution yields rev2→addrB;

SV-4c-0  SNAPSHOT BOUNDARY test (new):
       start_size = mapping size containing rev1 only;
       append rev2 BEFORE or DURING the acquisition attempt;
       assert:
         the sealed snapshot contains exactly bytes [0, start_size) —
           rev2's bytes are NOT part of the sealed snapshot;
         declared revision = 1;
         resolved digest = addrA;

SV-4c-1  NON-APPEND MUTATION test (new):
         truncate / replace / rewrite the mapping file (violating the
         append-only invariant) → assert READ_INSTANCE_NOT_IMMUTABLE is
         produced by the corresponding failure rule (identity replaced,
         prefix not exactly obtainable, or size/invariant violation);

SV-4d  failure-vocabulary assertions: the three §9 failure codes are
       produced by the constructed fault injections.
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
