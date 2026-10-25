# R27-G0: Production-Signed Record Precheck — Read-Only

> **Precheck ID:** `R27-G0-20261015`
> **Date:** 2026-10-15 (Asia/Shanghai)
> **Repository HEAD:** `1f80d50e31d678c13beed35f3c9026a2d2580958` (main; origin/main identical)
> **Nature:** READ-ONLY. No source/test modification, no Build/Test, no fixture, no
> evidence-root creation, no signed-record creation, no REPAIR_ATTEMPT_6 consumption.
> **Basis:** Signing Key Custody Fact-Finding `R27-SIGNING-KEY-CUSTODY-FACTFINDING-20261012-01`
> (conclusion UNKNOWN); Implementation Repair Authorization Package v2.1 §2 (R27 hard
> Attempt-6 gate); user directive 2026-10-15 (route: R27-G0 first, then Route A/B).

---

## 1. Conclusion

```text
NO_COMPLIANT_PRODUCTION_SIGNED_RECORD_FOUND_IN_SCOPE
```

This is a scoped negative: no compliant production-anchor-signed SRS record exists
inside the searched local evidence scope. It does **not** prove that no external
system, custodian, or signing service holds or could produce such a record.
Consequence per the user's routing = **Route B**: REPAIR_ATTEMPT_6 stays STOPPED;
the blocking object is production signing capability (custodian or authorized
signing interface), and failing that, a separate governance decision on the
signing trust architecture. Per Package v2.1 §2: no new fixture, no Build, no Test.

## 2. Scope searched (and exclusions, stated)

```text
S1 tracked tree at HEAD (git grep, all paths);
S2 full git history, all refs (pickaxe -S over the anchor key string);
S3 working tree including untracked and git-ignored paths (find + grep,
   excluding .git internals and .build artifacts);
S4 evidence dir docs/02-evidence/persistent-srs-20261011/ (complete listing);
S5 logical closure: local signing capability (see E5).
Out of scope (cannot and does not prove non-existence): external systems,
custodian holdings outside this repository, network services, /tmp ephemeral
test outputs (which are test-key-signed by construction and cannot satisfy the
production-anchor precondition anyway).
```

## 3. Evidence

```text
E1 anchor key occurrences: the production anchor public key
   +fG2YJ+YnW1RtsX8bCbukUERvSlIq4fvP7cZcs6+VMI= appears at HEAD only in
   (a) frozen Manifest Contracts v1.2–v1.8,
   (b) three governance docs (custody fact-finding, E2 clarification,
       external custody attestation request),
   (c) PersistentSRSRepresentation.swift and SRSVALDecisionCore.swift
       (the pinned verifier / recordIntegrityIssuer binding).
   No record file carries it. Working tree matches HEAD exactly.

E2 physical record files: zero .psrs files exist anywhere under the
   repository (S1–S3). The persistent-srs evidence dir contains only schema
   versions V1.3–V1.6 and Manifest Contracts v1.0–v1.8 — no records.

E3 git history: pickaxe over the anchor string returns 11 commits, all
   source/schema/governance changes (6c345d73 … 397552f2). No commit ever
   added a record carrying the anchor or a production signature.

E4 authorized evidence root: none exists. Manifest v2.2 §14 leaves the
   evidence root REQUIRED_BEFORE_EXECUTION; no EXECUTION stage was authorized,
   so no lawful location for a production record has ever been created.

E5 logical closure (from the E2 Technical Clarification, 2026-10-12): the only
   local issuer construction is the test key
   SHA256("TEST-ONLY PRIVATE KEYrecordIntegrity"); its derived public key is
   byte-level NOT EQUAL to the production anchor (computed 2026-10-12). No
   production call site constructs SRSVALIssuer. Therefore no local process
   could ever have produced a production-anchor signature, independent of file
   searches.

E6 external attestation: SIMIGO_PERSISTENT_SRS_EXTERNAL_CUSTODY_ATTESTATION_
   REQUEST_20261012.md is committed but never sent; §6 responsible-party
   fields are blank. No external confirmation of custody exists.
```

## 4. Repository state verification (R27-G0 item 4)

```text
HEAD = 1f80d50e (main) = origin/main; working tree has only 5 untracked
  session-record markdown files; no modifications.
PersistentSRSRepresentation.swift blob = f5ea0130d8187b9845f324f653d4f99fcada643a;
PersistentSRSRepresentationTests.swift blob = 4ea07ca0d02e525d0e92585e472f584de0a96477
  (both match the values cited in the 2026-10-15 ruling; file lineage is exactly
  57643964 initial implementation → f1a6b876 REPAIR_ATTEMPT_5 result).
Materialization startup-window fix: c9a7ba36 (2026-10-13 23:46) IS in main
  history (af44199f is also an ancestor); the 2026-10-13 handoff's
  "not yet implemented" reading is obsolete, as the ruling stated.
docs/RESEARCH_STATE.md: 1,366,189 bytes BOTH locally and at origin/main — the
  file is NOT empty; the "empty remote file" observation is consistent with a
  GitHub web-render limit on ~1.3 MB markdown, not with actual emptiness.
TWO state-layer findings, handed to Human (this precheck does not edit them):
  (a) RESEARCH_STATE.md contains NO stratum for the repair cycle — zero hits
      for REPAIR_ATTEMPT / Repair Authorization Package / R27 / signing-key
      custody. The operative current state of the implementation line lives
      only in the docs/00-governance chain (packages v1.0/v1.1/v2.0/v2.1,
      custody documents, completion evidence).
  (b) Within its 2026-10-12 gate section, RESEARCH_STATE.md carries two
      coexisting strata: prose line ~444 "IMPLEMENTATION AUTHORIZED / NOT
      STARTED" vs code-block line ~472 "persistent SRS implementation =
      NOT AUTHORIZED". Attempt numbering for humans: Implementation Attempts
      1–8 (attempt 8 = 57643964) and REPAIR_ATTEMPT_1–5 (attempt 5 =
      f1a6b876) are independent series; REPAIR_ATTEMPT_6 is next and
      NOT AUTHORIZED / NOT CONSUMED.
```

## 5. Read-only defect comparison table (parallel deliverable)

Current code = repair-attempt-5 result (f1a6b876 = HEAD blobs above). Anchors
are `PersistentSRSRepresentation.swift` / `PersistentSRSRepresentationTests.swift`.

| Item | Requirement (v2.0 §2–§8 / v2.1 §1–§2) | Current state at HEAD | Minimal repair scope |
|---|---|---|---|
| R1 real-byte V1 negatives | mutate actually-encoded sealed bytes; fail exactly at V1 with `ATTEMPT_CANONICAL_ENCODING_MISMATCH` / `UNSUPPORTED_CANONICAL_VALUE_TYPE` | `testSealedFieldTypeMatrix` (tests:471–499) validates only that all 14 labels use allowed types — a positive matrix; the disallowed/unknown-type negative injections are absent | tests only |
| R2 unforgeable descriptor | immutable fields; production constructor self-computes SHA-256; no public writable digest/I1 field in production module | `production()` self-computes (impl:1494–1504) ✓, but `SRSClassificationDescriptor` fields are `public var` (impl:1477–1480) = publicly writable in the production module | impl only |
| R3 zero side effects + write order | v2.1 §1 five-step order: verify key → (root absent) create ONLY root → lock → classify → only NEW_RECORD creates subdirs | `write()` creates `records/` at impl:1620–1625 BEFORE lock (1627–1633) and classification (1641+); test covers invalid-key zero side effects for one root state only | impl + tests (both root states, recursive snapshots) |
| R4 fail-closed refresh | replace `try? synchronize()` with explicit error → `PERSISTENCE_VERIFICATION_INDETERMINATE`, never rename after failed flush; remove mutable fault switches; injection only via seam parameter | impl:1577 still `try? handle.synchronize()` (a real fsync failure is swallowed → rename proceeds); `SRSRefreshFailureInjector` static mutable vars at impl:1544–1547 | impl + tests |
| R5 per-class matrix + R27 E2E | 13 nested object classes × {unknown member → R17, structural type → R17, enum/length/pattern/const → R19}, exact stage asserted; R27 via complete Reader over a real anchor-signed record | three sample tests (tests:189/210/232) do not cover all 13 classes × 3 kinds; R27 positive E2E absent (blocked by this precheck's conclusion) | tests (R27 part blocked by Route B) |
| R6 evidence-derived eligibility | eligibility/invalidation derived from verified evidence flows; boolean self-declaration in typed structures not acceptable | `SRSCandidateEligibility(evidenceV1to5Pass: true, …)` boolean inputs (tests:570–582) — exactly the named anti-pattern | impl + tests |
| R14 stage ordering | Contract v1.8 §13.1 orders R14 before R15; implementation performs it after R27 (payload dependency) | confirmed in code: R14 at impl:1386–1390 runs after R27 (impl:1381–1385) | NOT a code fix — separate Human ruling; no frozen rule may change |
| R27 end-to-end | complete Reader must pass R25 then return `DECISION_CORE_BINDING_MISMATCH` at R27 on a mutated real anchor-signed record; helper unit tests do not count | Reader chain order is implemented (R25 at 1369–1376 → R27 at 1381–1385); `testR27EnvelopeBindingMutationBoundary` (tests:547–563) only calls the comparison helper — disqualified by v2.1 §2; no compliant record exists to drive the full path (§1 above) | blocked by Route B precondition |
| Repair boundary | only the two authorized paths (manifest v2.2 §7 `authorized_writable_path_set`); Contract v1.8 / I0 Schema v1.6 / Manifest v2.2 / PALACE / Information Space frozen | unchanged; frozen_nonwritable test input listed | none — boundary restated |

## 6. Human decision package (only Human can move these)

```text
D1 production signing capability: identify a responsible party and send the
   already-committed External Custody Attestation Request (fields blank), or
   otherwise establish a lawful signing interface for the frozen anchor;
D2 if D1 confirms unavailability: a new governance decision on whether/how to
   revise the signing trust architecture (test keys may not impersonate the
   anchor; the frozen anchor may not be silently replaced in implementation);
D3 independent of D1/D2: R14 ordering ruling; acceptance decision on Repair
   Package v2.1; only after those, any explicit REPAIR_ATTEMPT_6 authorization;
   and the RESEARCH_STATE.md state-layer corrections of §4 (a)/(b).
```

## 7. Compliance statement

This precheck executed no Build and no Test, created no fixture, no marker, no
evidence root, no signed record, modified no source or governance file, and did
not consume REPAIR_ATTEMPT_6. This document is a session record under
docs/08-research-memory/ and is not an execution authorization credential.
