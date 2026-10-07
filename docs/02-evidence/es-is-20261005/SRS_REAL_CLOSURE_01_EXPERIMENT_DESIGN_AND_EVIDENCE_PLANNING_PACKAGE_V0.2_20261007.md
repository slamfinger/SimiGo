# SRS-REAL-CLOSURE-01 — Experiment Design and Evidence Planning Package v0.2

> **Status:** DESIGN / EVIDENCE PLANNING ONLY — PENDING HUMAN REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** Design v0.1 @ `38bda97` (retained as superseded lineage)
> **Review basis:** Human independent audit of v0.1 (canonical `38bda97`) ruled
> **B = REVISE** with exactly two required corrections, applied in this version:
> **R1** — N1 dependency-mutation semantics must preserve the write-once IS
> (§8: D is never replaced; D′ is a new immutable object and only the fixture's
> current-resolution mapping changes);
> **R2** — E1's "absence of any other SRS channel" is downgraded from a
> runtime-proof claim to a closed-world fixture/code-audit boundary (§11).
> All other v0.1 sections were ruled PASS and are carried unchanged except
> where R1/R2 require consequential wording (§3 mutable-state declaration, §9
> IS_MUTATION scope enumeration).
> **Commission:** `SIMIGO_SRS_REAL_CLOSURE_COMMISSION_20261007.md` (Human research-direction ruling, 2026-10-07)
> **Critical path:** `SIMIGO_SRS_REAL_CLOSURE_CRITICAL_PATH_V0.1_20261007.md`
> **Frozen predicate basis:** SRS-VAL-01 Design v0.8 @ `1170208` (blob `dbbeb5cb…`, sha256 `1f661bda…`)
> **Frozen governance basis:** Authorization Package v0.6 @ `6089f0b` (blob `fb05a60d…`, sha256 `e16ca843…`)
> **Implementation artifact (canonical):** T-IMPL-01 SettledRelationValidationCore @ `07176ec`
> (exact component bindings registered in `AUTH_REQ_01_IMPLEMENTATION_COMPLETION_RECORD_20261007.md`)
> **Fixture preparation:** NOT AUTHORIZED
> **Execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED (including experiment IS writes — see §9)
> **SimiGo code change:** NOT AUTHORIZED

## 0. Audited claim boundary (anti-smuggling constraint)

Binding constraint on this entire package, registered at Human direction:

```text
T-IMPL-01 = ESTABLISHED (canonical implementation artifact exists)
  ≠ "REUSE capability exists"
  ≠ "cross-ES actual reuse is established"
```

The claim this experiment exists to test remains:

```text
ES₁ → IS(SRS) → independent ES₂ lawful reuse = NOT ESTABLISHED
```

and it can move to an experiment-supported conclusion only if E1–E6 and the
SRS-N1 negative control (§Evidence chain) are simultaneously established
under a valid instrument. No prior artifact (T-IMPL-01 implementation,
Qin-Shen 0308, R01, U-A/CCVS, relation persistence, PIR design, document-form
G-3 continuation evidence) may be upgraded to substitute for that proof.

Primary evidence is NOT continuation output equality. Output equality is
demoted to auxiliary evidence for all purposes of this experiment.

## 1. ES₁ construction boundary

**ES₁ = one fresh operating-system process** (PID recorded in its event log),
executing the externally declared task τ1. Consistent with the frozen ES
definition (minimal relation closure preserving computational continuity),
ES₁ is relation-defined, not substrate-defined; the round-1 substrate is
deterministic (D-SUBSTRATE-1, §Non-claims).

**τ1 (external declaration, frozen before ES₁ starts):**

```text
given dependency document D (content-addressed) and
      derivation procedure P (identity + exact version pinned):
compute result R = U(D, P)
settle the relation "R derives from D under P" as an SRS
persist the SRS into IS
exit
```

**Only-in-ES₁ computation:** the invocation of the expensive computation unit
`U`. U is an instrumented pure function — an iterated hash chain
`sha256^N(digest(D) ‖ identity(P))` with N fixed at fixture time (N = 50,000;
measurable sub-second cost, deterministic). U appends one ledger entry per
invocation — `(run_id, input_digest, output_digest, entry_ordinal)` — to its
process event log, flushed **before** the result is returned.

**Settled relation:** R is settled if and only if

```text
a) U returned successfully exactly once for (D, P) in this ES₁ lifetime;
b) R is content-addressed (result identity = content address);
c) the settlement record binds: result identity, source relation
   ("R derives from D under P"), exact dependency binding (D's content
   address and revision), formation provenance (ES₁ run id + U invocation
   record reference), settlement status = DECLARED_SETTLED, freshness
   condition (dependency-content-current), and request class;
d) the settlement record is schema-valid (§2 rejection rule).
```

**What does not qualify as an SRS:** a bare output digest, an unbound result
value, or any record lacking dependency bindings, provenance, freshness
conditions, or settlement status. The schema validator rejects these at
persist time (ES₁) and again at resolve time (ES₂ / ES-N).

**Temporal boundary:** after settlement and persistence, ES₁ plays no further
role. ES₁ exits (exit code recorded) before any later process is created.

## 2. SRS schema and identity binding

**Minimal schema (round 1):**

```text
SRS = {
  schema_version;
  settlement_status        = DECLARED_SETTLED;
  result: {
    identity               = content address of R;
    derivation_procedure   = { identity, exact version };
  };
  source_relation: {
    relation_id;
    semantics_binding      = exact binding;
  };
  dependencies: [ {
    dependency_id;
    content_address;         // pinned at settlement time
    revision;
  } ];
  provenance: {
    formation_es_id;         // ES₁ run identity
    formation_run_id;
    u_invocation_record_ref; // links to the ES₁ ledger entry
  };
  freshness: [ {
    requirement_id;
    condition;               // round 1: dependency-content-current
    initial_evidence_ref;
  } ];
  request_class;             // I-15-compatible
  identity_rule: { identity, exact version };  // pins the rule that generates srs_identity
}

srs_identity = HASH( canonical_serialization(SRS) )
```

**Design decision D-SRS-ID-1:** the identity hash covers **all** fields,
including provenance. Formation is constitutive for reuse (the standing
doctrine "same content, different formation = different identity"); two
settlements of the same result from different runs therefore carry different
SRS identities. Canonical serialization order is fixed field order with sorted
keys — deterministic and replayable.

**Rejection rule (anti-masquerade):** any record lacking dependency bindings,
provenance, freshness conditions, or `settlement_status = DECLARED_SETTLED`
is not an SRS and cannot enter the IS index as one. The schema validator is
part of the fixture instrument and is itself fixture content (subject to the
fixture-preparation authorization).

## 3. IS persistence boundary

**IS (round 1, document form)** is a write-once content-addressed document
store in a dedicated fixture directory:

```text
is/objects/<sha256>             // immutable content-addressed objects (write-once)
is/index.jsonl                  // append-only: srs_identity → object references
is/current/dependencies.jsonl   // the ONLY mutable fixture state (see below)
```

**Current-dependency resolution mapping (registered with R1):**
`is/current/dependencies.jsonl` is the fixture's **explicitly declared mutable
index state** — a mapping `dependency_id → current content address / revision`.
It is the single state through which "the current content of dependency X" is
resolved at read time. Write-once objects and the append-only SRS index are
**never** mutated or rewritten; only this mapping changes when the fixture's
current dependency state legitimately advances. This separation is what makes
the N1 negative control expressible without violating the write-once IS (§8).

**Write path:** ES₁ only, at settlement time (objects + SRS index entry).
Objects are immutable after write. Writes are **IS mutation effects** and are
authorized only as an explicitly scoped IS_MUTATION effect of the later
execution stage (§9) — they are not smuggled as ordinary file writes. The
N1 phase additionally writes one new object (D′) and updates the
current-dependency resolution mapping — both scoped IS mutation effects (§8, §9).

**Resolve path:** identity-reference lookup only. ES₂ receives
`srs_identity` through τ2 and the IS index, fetches the referenced object,
and verifies `content_hash(bytes) == object address` (byte-evidence
recorded). ES₂ never receives SRS bytes through any other channel.

**Read boundary:** ES₂ (and ES-N) read only from the IS directory. No ES₁
process memory, pipe, handle, or event log is readable by later processes;
no IPC channel is declared or opened (spawn records are evidence).

**Persisted-not-residual proof:** the object consumed by ES₂ is proven to be
the persisted object by (a) temporal separation (ES₁ exit recorded before
ES₂ spawn), (b) absence of declared IPC, and (c) byte-equality of
ES₂-resolved bytes against the content-addressed object written by ES₁.

## 4. Independent ES₂ creation boundary

**ES₂ = a fresh operating-system process**, created only after ES₁ exit is
confirmed (recorded exit code + PID lifecycle).

**ES₂ inputs — exactly two:**

```text
τ2   task declaration: which srs_identity to resolve, and which
     continuation (Δ computation) to perform;
IS   the IS location.
```

Explicitly not inputs: ES₁ memory, ES₁ handles, ES₁ event log, observer
output, or any cached/piped artifact from the ES₁ lifetime. This is the
round-1 form of the I-1c doctrine: the basis comes from IS; the task is
declared forward (τ2); resolve does not infer the future task.

**ES₂ sequence:**

```text
1. create observation boundary B-2 (I-16), populating it from its own reads;
2. resolve srs_identity from IS; verify content hash; schema-validate;
3. read current dependency content through the current-dependency
   resolution mapping; mechanically compare with the SRS-pinned dependency
   binding (both raw values recorded);
4. build the closed SRS-VAL invocation value graph from these observations;
5. invoke T-IMPL-01 with that graph;
6. on REUSE: consume the settled result into the Δ computation —
   the continuation output is a direct data function of the SRS result
   content (its digest is an input to Δ), so a silent recomputation or
   substitution cannot pass invisibly;
7. write its own event log (ledger + events) and a continuation record
   referencing the consumed srs_identity (IS write, scoped per §9).
```

**Independence evidence:** disjoint PID sets; recorded spawn order (ES₁ exit
< ES₂ start, monotonic harness clocks); no declared IPC; hash-verified loaded
SRS bytes. ES₂ does not import ES₁ execution state in any form.

## 5. SRS-VAL invocation and expected decisions

**Invocation graph construction** is mechanical, from ES₂'s own observations
(§4 steps 2–4): boundary B-2 with its consistency declaration; SRS evidence
from the resolved record; dependency evidence carrying the pinned binding and
the resolution outcome of the current content; result evidence including
`resolvedWithoutRecomputation = true` as declared by ES₂'s own zero-invocation
ledger; resolution/policy/provenance/lifecycle/freshness evidence from the
resolved record; I-15 as the exact request binding (request class,
requested settlement identity, content-addressed binding fields); I-14 =
`notUsedNoRecomputePath`; predicate rule = `notUsed`.

**T-IMPL-01 artifact binding:** the adapter invoking the Decision Core is a
thin fixture-side adapter compiled against the exact canonical implementation
artifact (the three component blob/SHA256 bindings registered in the
implementation completion record). The adapter source is fixture content; no
repository change occurs.

**Pre-registered expected decision (positive path) — frozen in this design:**

```text
primary_decision    = REUSE
decision_path       = REUSE_PATH
i14_marker_validity = VALID_NO_FAILURE_REMAINS
derivation trace    = DP-0 PASS, DP-1 PASS (G-V1..G-V7 all PASS), DP-2 PASS,
                      DP-4 REUSE
typed_failures      = []
```

Any other outcome on the positive path is a FAIL or INVALID stop (§10), not a
tuning opportunity.

**Evidence location:** the serialized invocation graph (canonical JSON) and
the complete decision output (including the derivation trace) are written to
the ES₂ event log and as standalone evidence objects. The expected-vs-actual
comparison is recorded field by field.

## 6. Observer separation

**Round-1 instrument (bounded):**

```text
ES₁ / ES₂ / ES-N  each append events to their own process-local,
                  write-before-return event logs (ledger entries included);
Observer          a separate process that runs only AFTER both ES processes
                  have exited, and independently:
                    - re-hashes every IS object;
                    - re-derives expensive-unit invocation counts from the
                      raw ledger entries (not from ES self-reports);
                    - verifies temporal order and process separation records;
                    - verifies persisted-vs-resolved byte equality;
                    - emits observer_verdict.json.
```

**Separation properties:** ES processes cannot read observer output (it does
not exist until after their exit, and the contract forbids it); the observer
cannot inject state into any ES process (it has no write channel to them and
no role in continuation); the observer's verdicts are re-derived from raw
artifacts, not from participant self-reports.

**Registered delta:** the full prebound tamper-resistant Observation
Integrity Boundary (Authorization Package v0.6 §6) remains an EXECUTION-stage
obligation. The round-1 instrument provides evidence separation only, and
every claim from this experiment carries that bounded status.

## 7. Non-recomputation observability (E6 — the core)

The distinction the experiment must make mechanically:

```text
persisted SRS reuse              vs.   ES₁ computation silently repeated
```

**Instrument:**

```text
a) U is declared by the experiment contract as the ONLY lawful path to the
   result class;
b) U writes exactly one ledger entry per invocation to its own process log,
   flushed before the result is returned;
c) the observer re-derives the invocation counts from raw ledger entries.
```

**E6 evidence = all of:**

```text
E6.1  ES₁ ledger contains exactly one U invocation entry;
E6.2  ES₂ ledger contains zero U invocation entries;
E6.3  ES₂'s continuation output is a direct data function of the SRS result
      content (the result digest is an input to Δ) — so the reused value
      actually flowed into the continuation;
E6.4  ES₂'s trace references the consumed srs_identity.
```

If ES₂ recomputed via U, E6.2 would fail. If ES₂ substituted an unearned
value, E6.3/E6.4 would fail. If ES₂ recomputed via a *different, unregistered*
path, this instrument cannot detect it — that is the standing no-oracle
detection boundary, registered here as such (the experiment contract makes
any non-U derivation path a contract violation detectable by code-level
audit, not by runtime instrumentation).

## 8. SRS-N1 negative control (primary counterexample test)

N1 is a primary test of the reuse semantics boundary, not an appendix: if a
mutated dependency does **not** block, the lawful-reuse semantics fail and
the experiment takes the FAIL path (§10).

**What N1 tests (R1-corrected semantics):**

```text
SRS pinned dependency binding = D        (immutable, unchanged)
current dependency            = D′       (new immutable object)
D ≠ D′
  → pinned binding no longer resolves against current state
  → dependencyBlockingInvalidation
```

N1 does **not** replace D. The original SRS continues to pin D; D and every
existing object remain immutable; the write-once IS property is **exercised**
by N1, not violated. The only mutation is the current-dependency resolution
mapping (§3), which is the fixture's explicitly declared mutable state.

**Sequence (after the positive campaign, same fixture):**

```text
1. add D′ to IS as a NEW immutable object (new content address, new
   revision) — an additive write, consistent with write-once;
2. update ONLY `is/current/dependencies.jsonl` so the same dependency_id
   now resolves to D′; the SRS index, all objects, and the original SRS's
   pinned binding (D) are untouched;
3. ES-N = fresh independent process, meeting every ES₂ independence
   requirement (§4), except τ2 requests the SAME srs_identity;
4. ES-N resolves the SRS, reads the current dependency content through the
   resolution mapping (now D′), and mechanically compares: pinned address
   (D, from SRS) vs current address (D′) — both raw values are recorded as
   evidence;
5. ES-N builds the invocation graph with the dependency evidence:
   revisionBinding = SRS-pinned D binding; resolved = false (current D′
   does not resolve to pinned D); blockingInvalidation = true;
6. invoke T-IMPL-01.
```

**Pre-registered expected decision — frozen in this design:**

```text
primary_decision    = BLOCK
decision_path       = BLOCKED_NON_RECOMPUTE_PATH (via DP-1)
typed_failure       = hardBlock(dependencyBlockingInvalidation)
i14_marker_validity = VALID_HIGHER_PRECEDENCE_RESOLVED
```

**RECOMPUTE is not expected and not automatic:** with the predicate rule
not bound and no I-14, no lawful recompute path exists. A RECOMPUTE-capable
negative case requires a registered predicate rule artifact plus an exact
I-14 under separate authorization — registered as later work, never as
in-experiment remediation.

## 9. Authorization stage mapping

```text
This package        = DESIGN / EVIDENCE PLANNING ONLY. It authorizes nothing.

Later lawful chain (each stage a separate Human ruling; no cross-stage
implication):
  1. FIXTURE_PREPARATION authorization request — exact-binding: this design
     (v0.x content address), the canonical T-IMPL-01 artifact bindings, and
     the fixture manifest (computation parameters, IS layout including the
     current-dependency resolution mapping, schema validator, adapter
     source, τ1/τ2 declarations);
  2. EXECUTION authorization request — exact-binding: fixture artifacts,
     runner identity, observer script, run budget, and an explicitly
     declared IS_MUTATION effect scope = { the fixture IS directory }
     (covering ES₁ settlement writes, ES₂ continuation-record writes, the
     N1 D′ object addition, and the N1 current-resolution-mapping update);
  3. execution → machine-readable evidence package → Human audit.

The experiment's IS writes are IS_MUTATION effects and must be authorized
as such. This package does not pre-authorize, imply, or estimate any of
those later records.
```

## 10. Stop conditions and failure doctrine

```text
PASS (closure evidence sufficient)
  valid instrument + E1–E6 all established + N1 expected BLOCK observed
  → pre-registered bounded claim wording:
    "ES₁ → IS(SRS) → independent ES₂ lawful reuse = ESTABLISHED
     (round-1 instrumented form; deterministic substrate; document-form IS;
     registered detection boundary)"
  — this wording, and no stronger form, is the only lawful advance.

INVALID (experiment invalid)
  instrument defect: broken process isolation, unflushed ledger,
  non-determinism, observer contamination, schema-validator defect,
  adapter/artifact binding mismatch
  → campaign INVALID; results not interpretable; instrument repair =
    implementation revision requiring review and a NEW execution
    authorization.

FAIL (semantic hypothesis falsified)
  E1–E6 cannot be simultaneously established under a valid instrument,
  or N1 does not produce the expected BLOCK
  → register: Finding → violated assumption (named) → bounded reversal /
    doctrine revision → new experiment.
  NO governance-text repair: adding rules, manifest fields, predicate
  revisions, or authorization packages to reinterpret a failed result as
  PASS is forbidden (Commission §9).

NEEDS-REVISION
  design defects discovered before execution → revise this design →
  re-review. No execution may begin from a defective design.
```

No post-hoc reinterpretation of the frozen expected decisions is permitted.

## 11. Evidence chain (pre-registered)

**Positive path — E1–E6, all machine-readable, all re-derivable by the
observer from raw artifacts:**

```text
E1  ES₂ consumed the persisted SRS through the declared IS resolution path
      evidence (closed set, each item instrument-provable):
        - τ2 requested srs_identity;
        - the IS index resolved that identity;
        - resolved bytes hash to the referenced immutable object;
        - ES₂ trace references that identity;
        - ES₂ input boundary contains only τ2 + the IS location;
        - fixture/code audit shows no alternate SRS injection path.
      registered boundary (R2): "absence of any other SRS channel" is NOT
      a runtime-proof claim — it is a closed-world fixture/code-audit
      assumption, registered as such (the same discipline as §7's
      unregistered-path recomputation boundary).
E2  SRS identity matched
      evidence: requested identity (τ2) == resolved identity == index
      identity; canonical re-hash equality
E3  dependency bindings matched
      evidence: SRS-pinned content address == current IS content address
      (both raw values recorded per dependency)
E4  SRS-VAL classified REUSE
      evidence: decision output object (trace included) from the canonical
      T-IMPL-01 artifact; invocation graph attached
E5  REUSE branch actually executed
      evidence: ES₂ continuation record referencing consumed srs_identity;
      Δ-input includes the result content digest; ledger zero-entries
E6  ES₁ expensive computation did not recur
      evidence: ES₁ ledger = 1 U-entry; ES₂ ledger = 0 U-entries (§7)
```

**Negative control:**

```text
N1  dependency state advanced (D′) → pinned binding mismatch → NOT REUSE
    (expected BLOCK)
      evidence: D′ object-addition record, resolution-mapping update
      record, ES-N comparison record (pinned D vs current D′), decision
      output with the pre-registered typed failure
```

Only E1–E6 **and** N1 simultaneously established under a valid instrument
advance the core gap.

## 12. Minimality exclusions (Commission §6)

The first experiment excludes: X-08-scale mutation campaigns; multi-backend
comparison; multi-carrier comparison; large models and large corpora; LLM
inference (D-SUBSTRATE-1: round-1 ES is a deterministic instrumented
trajectory — relation-defined, not substrate-defined); MCP/MemPalace
integration; production SimiGo integration.

## 13. Non-claims

```text
1. T-IMPL-01 = ESTABLISHED does not establish REUSE capability or cross-ES
   actual reuse (§0 constraint).
2. Output equality between ES₁ and ES₂ continuations proves nothing here
   (auxiliary evidence at most).
3. No claim about carrier-form IS, model-inference ES, concurrency, or
   semantic-equivalence detection (standing no-oracle boundary).
4. No claim that the round-1 observer equals the Authorization Package §6
   Observation Integrity Boundary (§6 delta).
5. No stage is authorized by this package.
6. No open-world channel-exclusion claim is made for E1; its
   closed-world fixture/code-audit assumption is registered in §11.
```

## 14. Decision requested

```text
A = ACCEPT design v0.2
      → next lawful object: FIXTURE_PREPARATION authorization request
        (exact-binding this design + T-IMPL-01 canonical artifact)
B = REVISE
      → return with registered defects (NEEDS-REVISION path)
C = DENY
      → no experiment
```
