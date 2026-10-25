# SRS-REAL-CLOSURE-01 — FIXTURE_PREPARATION REVISION Authorization Request v0.7

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Revision lineage:** Request v0.6 was approved and consumed by FIXTURE_
> PREPARATION REVISION SAR 001 (`fdf45ea`). Human acceptance audit of the
> resulting canonical work state `e729e32` has ruled **B = REVISE**.
> This Request is the next lawful authorization object. It supersedes only
> the claim that `e729e32` closes the fixture revision cycle; it does not
> reopen, re-adjudicate, or diminish the accepted portions of SAR 001.
> **Review basis:** Human acceptance audit confirmed the authorization chain,
> path scope, event order, F-1/F-2/F-3, snapshot boundary mechanism, writer
> invariant, and the claimed SV-1..SV-6 30/30 result. It rejected final
> completion because the realized §9 record payload remains narrower than the
> v0.6 contract.
> **Requested stage set:** `{ FIXTURE_PREPARATION (one new revision cycle) }`
> **Execution / IS mutation / experiment / Observer campaign:** NOT AUTHORIZED
> **Design change:** NONE
> **Frozen-contract, T-IMPL-01, SimiGo source, and Package.swift change:**
> NOT AUTHORIZED

## 1. Findings registered by this Request

```text
RF-4.5  IMMUTABLE_REVISION §9 payload incomplete.
        Records with declared_input_binding_kind = IMMUTABLE_REVISION
        currently carry only generic declared/read-time digest fields.
        They omit:
          declared_immutable_revision;
          revision_to_content_digest_binding;
          resolved_declared_content_digest.
        Therefore the code has branch semantics, but not the complete
        binding-kind-specific §9 record contract.

RF-4.6  Mapping snapshot boundary field absent.
        The mapping seal and MAPPING_SNAPSHOT_SEALED event carry identity,
        file identity, start size, and digest, but omit the required
        mapping_snapshot_seal_boundary field. The sealed byte interval is
        therefore implicit rather than explicitly represented.

RF-4.6m FD-level post-check exactness is PARTIAL.
        The current metadata post-check occurs after FD close and uses
        os.stat(path). The closed-world invariant may preserve the proof,
        but it does not mechanically realize the v0.6 requirement to check
        the original FD before close. This is corrected together with
        RF-4.6, not opened as a separate research defect.

Coverage rule: SV-4 truly proved the tested mechanism; it did not prove the
two missing contract fields. Passing self-validation is never sufficient
evidence that an authorization contract is complete unless the validation
asserts the contract payload itself.
```

## 2. Exact bindings

```text
repository_position_at_request_introduction = f902fad
  full SHA = f902fadb0aa082f332feac4d2cc61d14a0eb7282

approved_request_v0_6 =
  commit c01f0bfbb578db3e371151d343906619270a67e6,
  git:blob:d6eee39f6bf37f1536d152e56509f02f77d8afd3,
  sha256 06c969c2dfe9dea527833690e519303b7aecb876673165ac12011db0f2c2722e;

consumed_revision_sar_001 =
  commit fdf45ea262dd6516af834c0aa38eb9bf840798fa,
  git:blob:55448b50e2f56ba5b75e5320adc1596ba8581ff7,
  sha256 1d093069b8b4c5edc1696dc3105fb0ec9fa236fdbabb94e34494ac8d66a53481;

canonical_but_not_accepted_completion_state =
  commit e729e32fd384a3d7173e536f823417445861f406;

baseline_fixture_files_at_e729e32 = {
  runner/es_runner.py:
    git:blob:689b0401e305c16a2bed9905bb71c57e8798875b,
    sha256 ea8e64ebe2e71d92815051cd6e42685b4e9e2706a50bc448c00780d39a76fb5a;
  FIXTURE_MANIFEST.md:
    git:blob:eeb3f3a0a157c40db3c53db8a628075d81ee56eb,
    sha256 d031df216178e27eb0ca69a6000121e02f14b96677199c3e6e1691f8a317c587;
  FIXTURE_PREPARATION_COMPLETION_RECORD.md:
    git:blob:a39f5f81834334381139626212f9d98995b1010c,
    sha256 1f08be1f27b854e45857d79ba42f5600ff4778abf321d725a8cc7e06a318c5ea;
};

inherited bindings (unchanged):
  defect_register =
    SRS_REAL_CLOSURE_01_EXECUTION_READINESS_DEFECT_REGISTER_20261007 @ main,
    git:blob:c83c8b7597f0e1dc40d3e34d56fd8e5c3c521f2f,
    sha256 4851d4f7c650f2c1b23aa5948aed721217976b4efdb80a9956923029056a18c1;
  SRS_VAL_01_DESIGN_V0_8 @ 1170208,
    git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
    sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6 @ 6089f0b,
    git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
    sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;
  SRS-REAL-CLOSURE-01 Design v0.2 @ 050b918,
    git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
    sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe.
```

## 3. Revision scope (exact)

```text
CARRIED AND NOT REOPENED:
  FIXTURE_PREPARATION REVISION SAR 001 authorization chain and scope;
  F-1 LAST-entry-per-dependency_id mapping semantics;
  F-2 subprocess environment propagation;
  F-3 runtime tau substitution;
  exact [0, start_size) prefix acquisition from the open FD;
  sealed-prefix-only LAST-entry parsing;
  mapping content never re-read after snapshot acquisition;
  append-only writer invariant / SV-4c-1b closed-world audit;
  §9 failure vocabulary;
  no campaign sequence, observer run, or repository IS materialization.

F-4.5  COMPLETE_IMMUTABLE_REVISION_RECORD:
  For every READ_INSTANCE record whose
  declared_input_binding_kind = IMMUTABLE_REVISION, the runner must emit:
    declared_immutable_revision =
      the revision value in the sealed LAST mapping entry;
    revision_to_content_digest_binding = {
      revision: the same sealed revision value;
      content_digest: the content address in the same sealed entry;
      binding_source: "MAPPING_SNAPSHOT_LAST_ENTRY";
    };
    resolved_declared_content_digest =
      the content address in the same sealed entry;
  and the generic declared_content_digest must equal
  resolved_declared_content_digest. The digest algorithm remains sha256.
  The revision value is never compared as if it were a digest. Resolution
  comes only from the sealed prefix. Missing, ambiguous, malformed, or
  digest-invalid revision→digest resolution produces
  REVISION_TO_DIGEST_BINDING_INVALID.

F-4.6  EXPLICIT_MAPPING_SNAPSHOT_SEAL_BOUNDARY:
  Every mapping snapshot seal and every MAPPING_SNAPSHOT_SEALED event must
  contain:
    mapping_snapshot_seal_boundary = {
      boundary_type: "BYTE_PREFIX_CLOSED",
      start_offset: 0,
      end_offset_exclusive: mapping_snapshot_start_size,
      acquisition_order: [
        "OPEN_FD",
        "FSTAT_IDENTITY_AND_START_SIZE",
        "EXACT_PREFIX_CAPTURE",
        "SHA256_SEAL"
      ],
      content_re_read_after_boundary: false
    }.

F-4.6m FD-LEVEL METADATA CLOSURE:
  Before closing the mapping FD, capture and record the FD-level
  post-snapshot metadata result with os.fstat(fd):
    same st_dev/st_ino as captured; current_size >= start_size.
  After close, perform the separate path identity check with os.stat(path)
  and require the same st_dev/st_ino. Mapping content remains forbidden
  after snapshot acquisition.

F-5  UPDATE ONLY THE TWO FIXTURE OUTPUT BINDINGS:
  re-bind es_runner.py, advance FIXTURE_MANIFEST.md to v3, and replace
  FIXTURE_PREPARATION_COMPLETION_RECORD.md with completion record v3.
  The ten unchanged artifacts must remain byte-identical and carry their
  existing bindings. The changelog must map changes to RF-4.5 and RF-4.6
  only, including RF-4.6m as part of RF-4.6.
```

## 4. Instrument self-validation additions

SV-1, SV-2, SV-3, SV-5, and SV-6 are carried unchanged. SV-4 remains a full
re-run in a discarded temporary sandbox and is extended with field-level
contract assertions:

```text
SV-4.5  For every IMMUTABLE_REVISION record, assert the three RF-4.5 fields
        exist, bind exactly to the sealed LAST entry, and satisfy
        declared_content_digest == resolved_declared_content_digest. Assert
        the revision value is not used as a digest and that a malformed
        revision→digest resolution produces
        REVISION_TO_DIGEST_BINDING_INVALID.

SV-4.6  For every mapping seal and MAPPING_SNAPSHOT_SEALED event, assert
        mapping_snapshot_seal_boundary exists and exactly equals the sealed
        closed byte interval [0, start_size), with the required acquisition
        order and content_re_read_after_boundary = false.

SV-4.6m Assert FD-level fstat identity and size checks are evaluated before
        FD close, and that the path identity check is separate. Assert no
        mapping content is read after the boundary.

SV-4c-0 / SV-4c-1a / SV-4c-1b / SV-4d carry their v0.6 event-order, drift,
replacement, writer-audit, and failure-vocabulary requirements, now
augmented by SV-4.5, SV-4.6, and SV-4.6m.
```

The boundary statement is unchanged: SV-1..SV-6 never run the full or partial
campaign, never run an observer campaign, materialize no repository IS, and
produce no evidence artifact. Temporary outputs are discarded.

## 5. Out of scope

```text
- F-1, F-2, F-3, snapshot mechanics, append-only proof, and already accepted
  authorization-scope decisions are not re-litigated;
- EXECUTION Authorization Request v0.3 remains CLOSED as a lawful next object
  until this Request is approved and its work cycle is accepted;
- no Design v0.2, Frozen Contract, T-IMPL-01, adapter, schema, layout, input,
  tau-original, observer, SimiGo source, Package.swift, or repository source
  change;
- no locking/versioning channel;
- no governance expansion;
- no §6.2 or Channel Universe reclassification decision.
```

## 6. Authorized writable path set and budgets

```text
authorized_writable_path_set = {
  docs/02-evidence/srs-real-closure-01/fixture/runner/es_runner.py;
  docs/02-evidence/srs-real-closure-01/fixture/FIXTURE_MANIFEST.md;
  docs/02-evidence/srs-real-closure-01/fixture/
    FIXTURE_PREPARATION_COMPLETION_RECORD.md;
};
plus one temporary self-validation directory outside the repository,
discarded after SV-1..SV-6.

docs/00-governance/ is forbidden to the work cycle; its SAR, if approved,
is a separate governance commit that precedes and authorizes that cycle.

fixture_revision_work_cycle_budget = 1;
execution_run_budget = 0;
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden.

This budget is not an automatic renewal of the consumed SAR 001 budget. It
can begin only after a new Human ruling and a new exact-binding SAR.
```

## 7. Required Human decision

```text
APPROVE FIXTURE_PREPARATION REVISION ONLY
      create the exact-binding REVISION SAR 002; apply RF-4.5/RF-4.6 only;
      re-run SV-1..SV-6 with the field-level assertions; deliver manifest v3
      and completion record v3; push + ls-remote verify; STOP for fresh
      Human acceptance review.

REVISE REQUEST     return with registered defects.
DENY REQUEST       fixture revision remains incomplete; execution remains
                   blocked.
```

No stage is authorized by opening this Request.

## 8. Record integrity binding

```text
record_integrity_binding = registered by the governing commit introducing
this Request on main; any later modification of this file creates a new
content address and voids this Request.
```
