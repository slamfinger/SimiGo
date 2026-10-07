# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.4 — CORRECTED ENVIRONMENT BINDING (paired exact IS_MUTATION + supplemental Observer Authorization)

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Human opening authorization, exact form:** “授权 corrected EXECUTION
> Request” — this authorizes opening this corrected Request only. It does not
> approve A+B+C, authorize a campaign, create SAR/OAR records, or revive any
> old budget.
> **Supersedes:** EXECUTION Authorization Request v0.3
> @ `1088a0c27f64fcbd59c207460d9b7576e6797e9e`
> (blob `a3760c8d…`; SHA256 `b63c71aa…`), which is CONSUMED and INVALIDATED
> FOR RERUN by campaign `exec-001-edf7d4a`.
> **Review basis:** Post-campaign audit `fa597bc…` identified the sole root
> cause as a pre-authorization environment-binding inconsistency: Request
> v0.3 expected `swift-driver version…` while its own ENV-PROBE-V1 faithfully
> stored `/usr/bin/swiftc --version` output. Fixture, T-IMPL-01, adapter
> runtime, D-SEC-1, D-SEC-2, §9, and expected semantic decisions are NOT
> reopened.
> **Single-contract correction:** preserve ENV-PROBE-V1 byte-for-byte; align
> expected `swiftc_version` with that probe's actual `/usr/bin/swiftc
> --version` output semantics. No other environment field, semantic expected
> decision, scope, or frozen contract changes.
> **Requested authorization set:** EXECUTION SAR 002 + IS_MUTATION SAR 002 +
> OBSERVER AUTHORIZATION RECORD 002, as three new separate cross-bound
> records.
> **No run authority exists from opening this Request.**

## 1. Authorization-chain history

```text
050b918  Experiment Design v0.2 ACCEPT;
7d590d7  FIXTURE_PREPARATION Request v0.2 ACCEPT basis;
4c3def8  FIXTURE_PREPARATION SAR 001;
d6507ff  fixture v1;
fdf45ea  FIXTURE_PREPARATION REVISION SAR 001;
e729e32  canonical-but-not-accepted fixture v2 work state;
5cfcc16  FIXTURE_PREPARATION REVISION Request v0.7;
5296d9f  FIXTURE_PREPARATION REVISION SAR 002;
5eb1ec0  REVISION SAR 002 one-cycle work state;
51caa4c  pre-acceptance navigation state;
d56ff1b  FIXTURE_PREPARATION Acceptance Record 002 (ACCEPT);
1088a0c  EXECUTION Request v0.3;
c454687  consumed EXECUTION/IS_MUTATION/OAR records 001;
6b511da  exec-001-edf7d4a INVALID evidence;
4d15e97  post-campaign INVALID navigation;
fa597bc  post-campaign audit: authorization contract defect;
9966d31  post-audit navigation state and corrected-request base;
this governing commit introduces Request v0.4.
The execution repository commit remains 9966d31; later governance commits
introducing this Request or future records are not execution state.
```

Commit identities do not replace content bindings. Any change to a bound
commit, blob, SHA256, scope, budget, expected decision, or runtime binding
voids this Request.

## 2. Exact governance and fixture bindings

```text
frozen_predicate_design =
  SRS_VAL_01_DESIGN_V0_8 @ 1170208,
  git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
  sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;

frozen_governance_package =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6 @ 6089f0b,
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
  sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;

experiment_design =
  SRS_REAL_CLOSURE_01_DESIGN_V0_2 @ 050b918,
  git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
  sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe;

fixture_acceptance_record =
  SRS_REAL_CLOSURE_01_FIXTURE_PREPARATION_ACCEPTANCE_RECORD_002
  @ d56ff1bb6bf2a3fe945ee31ac13a6ff560780c8f,
  git:blob:934a1dab3709b46d5516b64fde4b7da3f87c3241,
  sha256 4a34bd9befe056b778bc918afe478fa9e5f803fc4df0dd7f707bcc5696ceb2b6;

fixture_manifest =
  FIXTURE_MANIFEST v3,
  git:blob:a715b850659963ae381cde29ba0915bd68ab3a5f,
  sha256 19fe1a702202f7f6441aac18af1c7cb5dac25acf92e906148217fe531a3905df;

fixture_completion_record =
  FIXTURE_PREPARATION_COMPLETION_RECORD v3,
  git:blob:93c2d341abad0aa377de90be3eb3bd8c639802dd,
  sha256 87b6587bc81b6c76d6bdd3ed1d96844cc8780e02cefbb0f7df93046866456c55;
```

### 2.1 Eleven fixture artifacts (full independent bindings)

Execution step 0 re-verifies each entry against Manifest v3 and this Request.

```text
runner/es_runner.py
  git:blob:875cb1d9577940e65fa507bf8228d477b2e171ff
  sha256 bc393362a5693527196b71149d59df53ad27aef58fd30255718ded831d669833;
adapter/srsval_adapter.swift
  git:blob:1573ae9eb7c7b334589a6ac901ea1889a20703a0
  sha256 61b8ad39c467ed7ff90e4d8670ea903bf7be12e20166c7cff21df4bdbf0231ac;
adapter/BUILD.md
  git:blob:8573c1a60ce304323e582db6f5073e9435303740
  sha256 af2384b0bf20ae73d8fdcee1a929a273d6e052666cc36ac2b3314ae38779d2ba;
schema/validate_srs.py
  git:blob:8c8fd9e8f87175debf77c485d7169e4e46c5e50b
  sha256 c1d75a7592652ba8eeb3831d734701b4494e6be0b14b0a6a295261fbe8822422;
is_layout/IS_LAYOUT.md
  git:blob:4ea38dd5b81bb5a99f8e82ee5379939a30008d6b
  sha256 68f0590f273f644f75c8120f5721220b027d345b9bde1f9ef079bc71a9bdf113;
inputs/D.md
  git:blob:f39361db5ac4c583287b1ae15d75e928f3bedfab
  sha256 806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c;
inputs/D_prime.md
  git:blob:daaeae4eb3dab4ad52bba2214ea29eddeee0a2b8
  sha256 8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955;
tau/tau1.json
  git:blob:678bdec2fd2911e9df317a2a0cac16b8de1ce5d1
  sha256 bc31ce63e764aa79068fccf232767648d3b79eb1c15a57faf25dd0da465f63b0;
tau/tau2.json
  git:blob:4b4aae5986abca0505306fd28cab51eec99b95c5
  sha256 bb8122d34d3bec16494cdeeee840f45140645eb54ae232dfb47721e02531e464;
tau/tauN1.json
  git:blob:eda97c2ae1ff6e1c74e464ee6c30d36413180ea4
  sha256 fe211518e4082636b4ce3c34aabf96406308b68719ce4be47d6e3f66564fdd3f;
observer/observer.py
  git:blob:248d3003c08609bbe3823ae7c05fb5c8747e2b52
  sha256 787b70d9cc291cfab081d9313877c58e375249875857f36dd93da45a44a80aaa.
```

### 2.2 T-IMPL-01 canonical sources

```text
SRSVALInvocation.swift
  git:blob:0fd65bdf40b7c9885de2ada491d66348ebfa28fa
  sha256 6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75;
SRSVALDecision.swift
  git:blob:cbd24721a97f3c06e012fb02649feb19c2b9cb8b
  sha256 e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de;
SRSVALCore.swift
  git:blob:9f11ef1af45be6bc9450e0fbdc0117211f99a74a
  sha256 9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e.
```

## 3. Part A — EXECUTION stage request

### 3.1 Requested stage and scope

```text
requested_stage_set = { EXECUTION };
authorized_repository_revision =
  9966d311e7e52ab3f5ca828e593ea569cddb008e (immutable full SHA; later
  governance commits are not execution repository state);
authorized_writable_path_set = {
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/
};
fixture subtree = READ-ONLY;
temporary build/probe directory outside the repository = allowed, discarded
  after evidence-package completion;
network_scope = NONE;
execution_campaign_budget = 1;
automatic_renewal = forbidden.
```

### 3.2 Exact runtime artifact binding

The old `TO_BE_REGISTERED_BEFORE_FIRST_USE` policy is void. This Request
binds the exact deterministic runtime artifact before authorization.

```text
exact_executable_or_runtime_artifact_identity =
  SRS-REAL-CLOSURE-01-ADAPTER-RUNTIME-ARTIFACT-V1;
runtime_artifact_integrity_binding =
  sha256 e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7;

exact_repository_commit = recorded in runtime_binding.json at step 0;
implementation_artifact_content_addresses = §2.2;
adapter_source_content_address = §2.1 adapter/srsval_adapter.swift.

exact_build_inputs = §2.2 T-IMPL-01 sources + §2.1 adapter source;
exact_build_command =
  swiftc -O SRSVALInvocation.swift SRSVALDecision.swift SRSVALCore.swift
         main.swift -o srsval_adapter
  where main.swift is byte-identical to the bound adapter source;
build_toolchain =
  swift-driver 1.168.6; Apple Swift 6.4
  (swiftlang-6.4.0.34.1 clang-2100.3.34.1);
  Target: arm64-apple-macosx26.0.

binding_build_evidence =
  two independent temporary-directory builds from exact inputs produced the
  same SHA256 above; this is a binding measurement, not a campaign run.

step_0_runtime_rule =
  rebuild only from exact inputs in a temporary directory; compute SHA256;
  record repository commit, all source hashes, build command, toolchain,
  and binary SHA256 in runtime_binding.json BEFORE adapter first use;
  any absent field, source mismatch, toolchain mismatch, or binary mismatch
  → STOP / campaign INVALID with
    RUNTIME_ARTIFACT_UNREGISTERED_OR_DRIFTED.
```

### 3.3 Frozen campaign

```text
sequence =
  materialize -> es1 -> es2 -> mutate-n1 -> esn -> post-exit observer ->
  evidence package;
campaign_budget = 1;
any defect, mismatch, schema rejection, adapter failure, observer failure,
  channel drift, dependency-closure drift, or crash → INVALID;
a rerun requires a new Request and Human authorization.
```

Frozen expected decisions, unchanged and never tunable:

```text
ES2 positive = REUSE / REUSE_PATH / VALID_NO_FAILURE_REMAINS;
ESN N1 = BLOCK / BLOCKED_NON_RECOMPUTE_PATH via DP-1 /
  HARD_BLOCK.dependencyBlockingInvalidation(D-1) /
  VALID_HIGHER_PRECEDENCE_RESOLVED;
E6 = exactly one U_INVOCATION_LEDGER in ES1 and zero in ES2/ESN.
```

### 3.4 Execution effect set and prohibitions

```text
execution_effect_set = {
  BUILD_BOUND_ADAPTER_IN_TEMPORARY_DIRECTORY_BEFORE_FIRST_USE;
  RUN_BOUND_INSTRUMENT_PROCESSES_PER_FROZEN_SEQUENCE;
  WRITE_RUNTIME_BINDING_ENV_MEASUREMENT_EVENT_LOGS_INVOCATION_GRAPHS_
    DECISION_OUTPUTS_AND_EVIDENCE_PACKAGE_UNDER_RUNS_RUN_ID;
}

forbidden_effect_set = {
  network access; external service access; multi-backend or model runs;
  MCP/MemPalace/production integration;
  modification of fixture subtree, frozen contracts, sources, manifests,
    governance records, Package.swift, or repository sources;
  post-hoc reinterpretation of expected decisions;
  governance-text repair of failed results;
  any INFORMATION_SPACE_MUTATION under Part A.
}
```

## 4. Part B — IS_MUTATION stage request

### 4.1 Exact scope

```text
requested_stage_set = { IS_MUTATION };
is_mutation_scope = {
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/is/
};
is_mutation_budget = one campaign's worth, exactly the following:
  1. materialize writes D object + initial mapping revision 1;
  2. es1 writes SRS record object + index entry;
  3. es2, only on REUSE, writes continuation record object + index entry;
  4. mutate-n1 adds D' object + one revision-2 mapping entry.
```

No overwrite, deletion, truncate, remap, or out-of-scope write is authorized.
The executor is exactly bound `es_runner.py` §2.1, modes `materialize`,
`es1`, `es2`, and `mutate-n1` only. All writes must obey IS_LAYOUT invariants
I-1..I-5.

## 5. Part C — supplemental Observer Authorization

### 5.1 D-SEC-1 binding semantics

```text
observer_authorization_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_002;
observer_identity = SRS-REAL-CLOSURE-01-ROUND1-BOUNDED-OBSERVER;
observer_artifact = §2.1 observer/observer.py;
observer_runtime_artifact_identity = exact Python runtime in §5.3;
observer_execution_boundary =
  POST-EXIT RE-DERIVATION WINDOW only;
authorized_observation_scope =
  supplemental evidence re-derivation (post-exit), read-only;

D-SEC-1 = Option B:
  this is SUPPLEMENTAL bounded evidence, permanently for this campaign.
  It is NOT a §6-authoritative Observation Integrity Boundary. The campaign
  makes no authoritative-observation claim. observation_integrity_record
  must say BOUNDED_EVIDENCE_SEPARATION. Stronger-form claims remain
  unavailable and require a future prebound tamper-resistant OIB.
```

### 5.2 D-SEC-2 channel universe

```text
channel_universe_identity = SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V2;
coverage_contract_identity = SRS-REAL-CLOSURE-01-COVERAGE-CONTRACT-V2;
unclassified_channel_set = {} (forbidden non-empty);

COVERED:
  driver↔child stdout/stderr anonymous capture pipes and their directly
    associated child FDs — D-SEC-2 mechanical plumbing, no experiment
    semantics, stderr tails recorded by driver;
  filesystem files/directories in the run scope and declared IS reads;
  declared IS/SRS writes and mutations in Part B;
  process/fork/exec boundaries in the declared driver spawn graph;
  runtime loading via Python stdlib and fixture validate_srs; statically
    linked Swift adapter invocation;
  declared environment variables SRSVAL_ADAPTER_BIN, PYTHONPATH,
    PYTHONDONTWRITEBYTECODE=1, ENV_MEASUREMENT_PATH;
  monotonic ordinals as the evidence-relevant clock/entropy boundary;
  state hashes and mutation-effect re-derivation.

IMPOSSIBLE, except the declared capture pipes above:
  network/socket traffic; localhost/external services; other IPC; shared
  memory; named pipes; memory-mapped files; other inherited FDs; signals;
  device/GPU/shared-accelerator state; credentials/helper services; launch
  agents/services; filesystem watchers; persistent caches.

Any discovered channel outside this universe → STOP / INVALID with
CHANNEL_UNIVERSE_INCOMPLETE_OR_DRIFTED.
```

### 5.3 Pre-run environment closure

The sole contract correction from v0.3 is here: `ENV-PROBE-V1` remains
byte-for-byte unchanged, and the expected `swiftc_version` is aligned to the
exact value produced by `/usr/bin/swiftc --version` under the bound
toolchain. No other expected environment field changes.

```text
environment_measurement_artifact_identity =
  SRS-REAL-CLOSURE-01-ENV-PROBE-V1;
environment_measurement_artifact_sha256 =
  79744078f5fca89f4f8b36701e4c05c7859bbf166451dcd0915b20b5fe6661af;
measurement_time = after runtime build, before materialize;
measurement_output = runs/<run_id>/environment_measurement.json;

expected_environment_identity =
  sha256 ad2abb6809ead5a4d198f35d6f1b8a06624a803c6fc7e161dbb06f1f0838f15a
  over exactly this UTF-8 canonical JSON object:

```json
{"adapter_runtime_artifact_sha256":"e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7","mac_version":"26.6.2","platform_machine":"arm64","platform_platform":"macOS-26.6.2-arm64-arm-64bit","python_executable":"/Applications/Xcode.app/Contents/Developer/usr/bin/python3","python_executable_sha256":"dff595035109e19c43c4b3e73ee08b5f4651e719f25f8b4713f819d28964dc19","python_version":"3.9.6 (default, Aug 25 2026, 21:26:21) \n[Clang 21.0.0 (clang-2100.3.34.2)]","swiftc_path":"/usr/bin/swiftc","swiftc_sha256":"b8763cf250e607a778bb4603cecb5b90338814d0a3dfcba0d57b1de242f610e9","swiftc_version":"Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)\nTarget: arm64-apple-macosx26.0"}
```

step_0_environment_rule =
  reconstruct ENV-PROBE-V1 from Appendix A; verify its SHA256; run it;
  canonicalize the measured record without `probe_identity`; compare SHA256
  to expected_environment_identity;
  mismatch → STOP / campaign INVALID with ENVIRONMENT_CLOSED_UNIVERSE_MISMATCH.
```

## 6. §9 v3 read-instance contract carried into execution

Execution evidence must preserve and audit the runner's v3 records exactly:

```text
CONTENT_ADDRESS records:
  declared_input_binding_kind, declared_content_digest,
  declared_digest_algorithm, read_time_content_digest, proof form,
  observer/channel identities, begin/end boundaries, consumed match.

IMMUTABLE_REVISION records additionally require:
  declared_immutable_revision;
  revision_to_content_digest_binding = {
    revision, content_digest,
    binding_source = MAPPING_SNAPSHOT_LAST_ENTRY
  };
  resolved_declared_content_digest;
  generic declared_content_digest == resolved value;
  revision never compared as a digest.

mapping snapshot records/events require:
  mapping_snapshot_identity, file identity, start_size, digest,
  mapping_snapshot_seal_boundary = BYTE_PREFIX_CLOSED over
    [0, start_size), acquisition order, and
    content_re_read_after_boundary = false;
  FD-level fstat identity/size before close plus separate metadata-only
    path identity after close.
```

Registered coverage boundary ACCP-1 is carried, not erased:

```text
the evidence package must record
  read_instance_contract_coverage.bounded_status =
    FIELD_LEVEL_CONTRACT_COVERAGE_WITH_REGISTERED_PRE_CALL_GAP;
it must not claim coverage of every malformed-entry call path. A Python
KeyError from a malformed sealed entry is an untyped stop and renders the
campaign INVALID; it is not reinterpreted as typed §9 coverage.
```

## 7. Evidence package obligations

`EXECUTION_EVIDENCE_PACKAGE.md` under `runs/<run_id>/` must register:

```text
run_id; exact_repository_commit; runtime_binding.json; environment_measurement.json;
step-0 verification of §2, §3.2, and §5.3; per-process event logs;
invocation graphs; decision outputs; expected-vs-actual records; E1-E6;
N1 evidence; observer_verdict.json; observation integrity record with
BOUNDED_EVIDENCE_SEPARATION; channel universe integrity statement;
§9 coverage statement including ACCP-1; changed_path_set;
forbidden_path_violation_count = 0; scope_compliance_verdict.
```

## 8. Budgets and validity

```text
execution_campaign_budget = 1;
is_mutation_budget = 1 campaign's four declared write classes;
observer_use_budget = 1;
fixture_preparation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden;
validity_boundary = approval of THIS Request until evidence-package
  completion, withdrawal, or expiry. The v0.3 campaign budget and c454687
  records remain consumed/non-reusable; this Request carries a new,
  independent campaign budget that exists only after approval of THIS
  Request.
```

## 9. Required Human decision

```text
APPROVE A+B+C
  create EXECUTION SAR 002, IS_MUTATION SAR 002, and OBSERVER AUTHORIZATION
  RECORD 002 as new, separate cross-bound records; then execute the single
  frozen campaign and STOP for evidence audit. Do not reuse Request v0.3,
  c454687 records, or the consumed v0.3 budget.

REVISE REQUEST   return with registered defects.
DENY REQUEST     do not execute.
```

No stage is authorized by opening this Request. The core claim
`ES1 -> IS(SRS) -> independent ES2 lawful reuse` remains **NOT ESTABLISHED**
until Human audits valid campaign evidence under the pre-registered bounded
wording.

## Appendix A — Environment probe v1 exact source

The exact UTF-8 source below has SHA256
`79744078f5fca89f4f8b36701e4c05c7859bbf166451dcd0915b20b5fe6661af`.

```python
#!/usr/bin/env python3
"""SRS-REAL-CLOSURE-01 pre-authorized environment probe v1."""
import hashlib, json, os, platform, subprocess, sys

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

adapter = os.environ["SRSVAL_ADAPTER_BIN"]
swiftc = subprocess.check_output(["/usr/bin/swiftc", "--version"], text=True).strip()
record = {
    "probe_identity": "SRS-REAL-CLOSURE-01-ENV-PROBE-V1",
    "python_executable": sys.executable,
    "python_version": sys.version,
    "platform_platform": platform.platform(),
    "platform_machine": platform.machine(),
    "mac_version": platform.mac_ver()[0],
    "python_executable_sha256": sha256_file(sys.executable),
    "swiftc_path": "/usr/bin/swiftc",
    "swiftc_sha256": sha256_file("/usr/bin/swiftc"),
    "swiftc_version": swiftc,
    "adapter_runtime_artifact_sha256": sha256_file(adapter),
}
with open(os.environ["ENV_MEASUREMENT_PATH"], "w", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True, indent=2)
    fh.write("\n")
```
