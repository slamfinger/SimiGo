# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.0

> **Status:** DELIVERED FOR HUMAN REVIEW — DESIGN ONLY
> **Date:** 2026-10-09
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.0`
> **Canonical base:** `cf96f08f5eee60b69c1027df9a9492b0990a9608`
> **Instrumentation implementation:** NOT AUTHORIZED
> **Adapter redesign implementation:** NOT AUTHORIZED
> **D-002 rerun / campaign:** NOT AUTHORIZED
> **D-001 Decision Core / observer execution:** NOT AUTHORIZED
> **canonical / PALACE mutation:** NOT AUTHORIZED

## 1. Research question

The next lawful study must make the D-002 failure precisely explainable without
changing the observed system's semantic boundary:

```text
Which adapter stage caused real PALACE-derived fixtures to materialize as
unresolved D-001 inputs, and what structured evidence proves that stage?
```

The prior audit established only:

```text
fault boundary     = D-002 replay adapter / evidence infrastructure;
secondary label    = D002_REPLAY_ADAPTER_UNRESOLVED_INPUT_DEFECT;
exact exception    = NOT ESTABLISHED;
D-001 core         = NOT IMPLICATED;
PALACE data        = NOT IMPLICATED;
Carrier/Observer   = NOT IMPLICATED.
```

## 2. Frozen audit baseline

This Package binds the completed read-only postmortem:

```text
POSTMORTEM_AUDIT_RECORD.md SHA256 =
  c1d525fec465dff765ee0cda266ab655f8d58c3283934b417423346f684afb5d;
AUDIT_EVIDENCE_SHA256SUMS SHA256 =
  d156b4095825ad8026137361e32aa5cad8e0cc32d8b509576e5d7cd13b058a1f.
```

It also preserves the prior classification:

```text
primary fault     = EVIDENCE_INFRASTRUCTURE_DEFECT;
secondary label   = D002_REPLAY_ADAPTER_UNRESOLVED_INPUT_DEFECT;
70 field rows     = 69 VALIDATION_REJECTION + 1 INTENTIONAL_UNRESOLVED_ENCODING;
exact exception   = NOT ESTABLISHED.
```

## 3. Required instrumentation design

If separately accepted for implementation, the implementation package must first
define and freeze the following design contracts.

### 3.1 Adapter stage universe

Every adapter path must emit a record for each stage:

```text
S0 baseline verification;
S1 real-source selection;
S2 snapshot binding;
S3 primitive inventory;
S4 fixture representation;
S5 typed mapping;
S6 D-001 wrapper translation;
S7 D-001 exact-field/schema preflight;
S8 closure digest materialization;
S9 invocation materialization;
S10 resolved input assembly;
S11 pre-decision validation;
S12 D-001 handoff boundary;
S13 unresolved fallback capture.
```

### 3.2 AdapterStageRecord contract

Each stage record must bind:

```text
trace_id;
case_id;
source_internal_id;
stage_id;
stage_sequence;
input_schema_id;
input_object_digests;
output_schema_id;
output_object_digests;
D001_core_sha256_set;
status = PASS | FAIL | SKIPPED;
failure_class;
exception_type_digest;
exception_message_digest;
stack_frame_digests[];
evidence_reference;
previous_stage_record_digest.
```

Raw exception text may remain local evidence, but the canonical record must bind
digests rather than treating exception text as semantic authority.

### 3.3 Required failure fields

Every FAIL must retain:

```text
first_failed_stage_id;
input availability result;
translated representation digest;
expected D-001 schema;
actual translated schema;
exact-field missing keys;
exact-field extra keys;
validation rejection reason;
fallback attempted flag;
semantic decision attempted flag.
```

The failure taxonomy must preserve:

```text
REPRESENTATION_LOSS;
BINDING_LOSS;
TRANSLATION_LOSS;
VALIDATION_REJECTION;
INTENTIONAL_UNRESOLVED_ENCODING;
EVIDENCE_CAPTURE_DEFECT;
NOT_ESTABLISHED.
```

### 3.4 D-001 boundary

Instrumentation must wrap the D-002 adapter, not alter D-001.

```text
D-001 Decision Core implementation = read-only and byte-identical;
D-001 decide()                     = not invoked by instrumentation design;
D-002 adapter                      = sole observed object;
observer                           = separate future authorization;
exception text                     = diagnostic evidence only;
semantic decisions                 = never derived from exception text.
```

The design must prove that D-001 core hashes remain unchanged during any future
authorized implementation or validation.

### 3.5 Evidence and write-once policy

The future implementation package must bind exact evidence destinations and use
write-once closure:

```text
TRACE_MANIFEST.json;
ADAPTER_STAGE_RECORDS.jsonl;
FAILURE_CLASSIFICATION.json;
D001_COMPATIBILITY_PREFLIGHT.json;
ADAPTER_REDESIGN_PROPOSAL.json;
EVIDENCE_SHA256SUMS.
```

No existing D-002 evidence may be rewritten.

## 4. Required redesign questions

The design package must answer statically:

```text
1 which adapter stages lack deterministic stage records;
2 which D-001 exact-field validations can be preflighted before D-001;
3 where representation, binding, translation, and validation losses should be separated;
4 how to capture exact exception evidence without changing semantic authority;
5 how to prove the D-001 core remains byte-identical;
6 how to prevent instrumentation from becoming decision authority;
7 how to avoid relying on a rerun of the sealed D-002 campaign.
```

## 5. Stage separation

This Package authorizes only its own Human review. ACCEPT would freeze this
design only.

```text
DESIGN REVIEW
  ↓ ACCEPT / REVISE / REJECT
DESIGN FREEZE
  ↓ separate Human authorization
INSTRUMENTATION / REDESIGN IMPLEMENTATION
  ↓ separate Human authorization
STATIC VALIDATION OR DRY MATERIALIZATION
  ↓ separate Human authorization
ANY NEW CAMPAIGN
```

No stage may be skipped or combined without a new ruling.

## 6. Explicit prohibitions

This Package does not authorize:

```text
implementation mutation;
adapter redesign execution;
instrumentation execution;
D-002 rerun;
new D-002 campaign;
D-001 Decision Core execution;
observer execution;
canonical IS mutation;
PALACE source/snapshot mutation;
D-001 Decision Core mutation;
semantic search;
embedding/vector traversal;
cloud/model causal participation;
E9;
EXP-004;
PIR reopening;
evidence overwrite;
PALACE equivalence claim;
integrated SimiGo proof;
general Execution State theorem;
production SimiGo validity;
LLM autonomy.
```

## 7. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze this instrumentation / redesign design for later,
         separately authorized implementation;
REVISE   require a new reviewed design revision;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, execution, campaign, mutation, or any
equivalence claim.
