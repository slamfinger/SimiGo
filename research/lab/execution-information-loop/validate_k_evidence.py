#!/usr/bin/env python3
"""Strict verifier for SimiGo K evidence; re-derives acceptance from on-disk
artifacts, not from the driver's narration.

The K round promotes the native Swift result-contract engine to the
pre-settlement authority on the real production continuation. What this
verifier insists on, independently re-reading the raw evidence files:

  * the recorded binary SHA is the binary actually on disk (proves the run used
    the compiled native gate, not an earlier build);
  * cross-language parity really closed at issue_count == 0, over the exact
    expanded fixture whose SHA the run recorded;
  * every prior-round gate (H / I / J / admission) and the full native Swift
    result-contract suite are green on this code state;
  * K0: each of the three real-model stages was gated by the native engine from
    Information Space-verified bindings, typed a value that reproduces the
    declared derivation, and only then settled and signed;
  * N2: the native engine refused an unwritten constraint kind fail-closed
    (nothing settled, nothing signed) after a real generation but before
    settlement, where the Python gate implements that same kind.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HEX64 = re.compile(r"^[0-9a-f]{64}$")
RUNTIME_ITEM = re.compile(r"^J-[0-9a-f]{8}-U[123]$")
BINARY = ROOT / "simigo2-experimental/.build/debug/SimiGoTaskRun"
PARITY_FIXTURE = (ROOT / "execution-information-loop/tests/fixtures/"
                  "native_python_contract_parity_expanded.json")
NATIVE_GATE = "native.SimiGoResultContracts"
PRE_SETTLEMENT = "native_pre_settlement"
STAGE_MARKER = "PRODUCER_RESULT_CONTRACT"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(msg, issues):
    issues.append(msg)


def safe_child(root: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute():
        raise ValueError("artifact paths must be relative to the run root")
    resolved_root = root.resolve()
    resolved = (root / candidate).resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ValueError("artifact path escapes the run root")
    return resolved


def reload_rejection(failure: str):
    """Independently re-parse the wrapped refusal reason the settlement layer
    produced, mirroring the native gate's own structured evidence. If the driver
    had fabricated a rejection block that does not follow from the failure
    string, this reconstruction will disagree."""
    if not isinstance(failure, str):
        return None
    marker = STAGE_MARKER + "."
    idx = failure.find(marker)
    if idx < 0:
        return None
    tail = failure[idx + len(marker):]
    code = ""
    for ch in tail:
        if ch in (":", " "):
            break
        code += ch
    field = ""
    fidx = tail.find("field=")
    if fidx >= 0:
        for ch in tail[fidx + len("field="):]:
            if ch == " ":
                break
            field += ch
    return {"code": code, "stage": STAGE_MARKER, "field": field}


def validate(root: Path):
    issues = []
    summary_path = root / "summary.json"
    if not summary_path.is_file():
        return [f"missing {summary_path}"]
    try:
        s = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception as e:
        return [f"invalid summary JSON: {e}"]

    if s.get("schema_version") != "simigo-k-evidence-v1":
        fail("schema_version mismatch", issues)
    if s.get("round") != "K":
        fail("round must be K", issues)
    if s.get("carrier_loop_semantics_changed") is not False:
        fail("carrier_loop_semantics_changed must be false", issues)
    if s.get("historical_artifacts_modified") is not False:
        fail("historical_artifacts_modified must be false", issues)

    guards = s.get("guards", {})
    if guards.get("parity") != "PASS":
        fail("guard parity not PASS", issues)
    if guards.get("regression") != "PASS":
        fail("guard regression not PASS", issues)

    impl = s.get("implementation", {})
    if impl.get("gate_authority", "") == "":
        fail("implementation.gate_authority absent", issues)
    if impl.get("native_gate") != NATIVE_GATE:
        fail("native gate identity is not the compiled SimiGoResultContracts", issues)
    # The recorded binary must be the binary on disk: this ties every native
    # stage observation below to a specific compiled build.
    bsha = str(impl.get("binary_sha256", ""))
    if not HEX64.match(bsha):
        fail("binary_sha256 missing/invalid", issues)
    elif BINARY.is_file() and sha(BINARY) != bsha:
        fail("recorded binary_sha256 does not match the on-disk binary", issues)
    elif not BINARY.is_file():
        fail("on-disk native binary not found to verify binary_sha256", issues)

    # Cross-language parity had to actually close at zero over the recorded
    # fixture, not merely claim a PASS verdict.
    pgate = impl.get("parity_gate", {})
    if pgate.get("verdict") != "PASS":
        fail("parity_gate verdict not PASS", issues)
    if pgate.get("issue_count") != 0:
        fail(f"parity_gate issue_count is {pgate.get('issue_count')}, expected 0", issues)
    if pgate.get("harness_exit") != 0:
        fail("parity harness did not exit 0", issues)
    if not pgate.get("case_count"):
        fail("parity_gate recorded no cases", issues)
    pverify = root / "parity/parity_verify.json"
    if pverify.is_file():
        pv = json.loads(pverify.read_text(encoding="utf-8"))
        if pv.get("issue_count") != 0:
            fail("re-read parity_verify.json issue_count is not 0", issues)
    else:
        fail("parity/parity_verify.json artifact missing", issues)
    csha = str(pgate.get("cases_sha256", ""))
    if not HEX64.match(csha):
        fail("parity cases_sha256 missing/invalid", issues)
    elif PARITY_FIXTURE.is_file() and sha(PARITY_FIXTURE) != csha:
        fail("recorded parity cases_sha256 does not match the on-disk fixture", issues)

    # Prior rounds' gates plus the native unit tests are part of K acceptance.
    reg = impl.get("regression", {})
    if reg.get("verdict") != "PASS":
        fail("regression verdict not PASS", issues)
    suite = reg.get("python_suite", {})
    for m in ("j_contract_selftest", "h_selective_invalidation_selftest",
              "i_semantic_sufficiency_selftest", "admission_selftest", "<unit>"):
        e = suite.get(m)
        if not e:
            fail(f"regression member {m} has no recorded result", issues)
            continue
        if e.get("exit_code") != 0:
            fail(f"regression member {m} exited {e.get('exit_code')}", issues)
        if e.get("verdict") != "PASS":
            fail(f"regression member {m} verdict is {e.get('verdict')}", issues)
        if e.get("failed_checks"):
            fail(f"regression member {m} has failed checks: {e.get('failed_checks')}", issues)
    swift = reg.get("swift_native_tests", {})
    # Independently re-derive the delivered native test count from the on-disk
    # test file (do not trust the summary's number), then require the run to have
    # executed exactly that many with zero failures. Guards against a recorded
    # green check that skipped or truncated the suite.
    native_tests_file = (ROOT / "simigo2-experimental/Tests/"
                         "SimiGo2ExperimentalTests/"
                         "NativeDeclarativeResultContractTests.swift")
    expected_native = len(re.findall(r"\bfunc test",
                                     native_tests_file.read_text(encoding="utf-8")))
    if expected_native <= 0:
        fail("could not count native result-contract tests on disk", issues)
    if (swift.get("exit") != 0
            or swift.get("failures") != 0
            or swift.get("executed") != expected_native):
        fail(f"native Swift result-contract tests did not report "
             f"{expected_native}/{expected_native} with exit 0 "
             f"(recorded exit={swift.get('exit')} "
             f"executed={swift.get('executed')} failures={swift.get('failures')})",
             issues)

    cond = s.get("conditions", {})
    expected = {"K0-NATIVE-AUTHORITY-3-PROCESS",
                "N2-NATIVE-REFUSES-WHERE-PYTHON-ACCEPTS"}
    if expected - set(cond):
        fail(f"missing conditions: {sorted(expected - set(cond))}", issues)
    states = {cid: cond.get(cid, {}).get("terminal_state") for cid in expected & set(cond)}
    if s.get("terminal_state") == "OBSERVED" and any(v != "OBSERVED" for v in states.values()):
        fail(f"top-level OBSERVED requires all conditions OBSERVED: {states}", issues)

    # ---- K0: native engine as pre-settlement authority on the real model ----
    k0 = cond.get("K0-NATIVE-AUTHORITY-3-PROCESS", {})
    if k0.get("terminal_state") == "OBSERVED":
        stage_files = sorted((root / "runs/K0/evidence").glob("j0-p*.json"))
        if len(stage_files) != 3:
            fail(f"K0: expected 3 real-model stage evidence files, found {len(stage_files)}", issues)
        for sf in stage_files:
            ev = json.loads(sf.read_text(encoding="utf-8"))
            tag = sf.name
            if ev.get("terminal_state") != "TASK_SETTLED":
                fail(f"K0 {tag}: stage did not settle (terminal {ev.get('terminal_state')})", issues)
            item = ev.get("task_item_id", "")
            if not RUNTIME_ITEM.match(item):
                fail(f"K0 {tag}: task ID {item!r} is not a run-time generated ID", issues)
            if ev.get("contract_dispatch_basis") != "declared_contract":
                fail(f"K0 {tag}: not dispatched by the item's own declaration", issues)
            nv = ev.get("native_result_contract_validation") or {}
            if nv.get("gate") != NATIVE_GATE:
                fail(f"K0 {tag}: native gate did not author the validation", issues)
            if nv.get("authority") != PRE_SETTLEMENT:
                fail(f"K0 {tag}: native gate was not the pre-settlement authority", issues)
            if nv.get("native_validation_status") != "VALID":
                fail(f"K0 {tag}: native status not VALID on a settled result", issues)
            bindings = nv.get("verified_bindings") or []
            if not bindings:
                fail(f"K0 {tag}: native gate ran without IS-verified bindings", issues)
            for b in bindings:
                if not b.get("settlement_object_id") or not b.get("value_sha256"):
                    fail(f"K0 {tag}: a native binding lacks its IS settlement/value digest", issues)
            vals = nv.get("native_values") or {}
            if not vals:
                fail(f"K0 {tag}: native gate typed no result values", issues)
            origin = vals.get("origin_code")
            dest = vals.get("destination_code")
            route = vals.get("route_key")
            if origin and dest and route != f"{origin}>{dest}":
                fail(f"K0 {tag}: native route_key {route!r} does not derive from origin/destination", issues)
        # The condition must internally claim every stage ok and settled+signed.
        for sc in k0.get("observations", {}).get("native_authority_stages", []):
            if sc.get("ok") is not True:
                fail(f"K0 stage {sc.get('stage')}: recorded ok is not True", issues)
            if sc.get("settlement_created") is not True or sc.get("signature_created") is not True:
                fail(f"K0 stage {sc.get('stage')}: a VALID native result must have settled and signed", issues)
            if sc.get("native_vs_python_values_agree") is not True:
                fail(f"K0 stage {sc.get('stage')}: native and Python disagreed on real-model values", issues)

    # ---- N2: native refuses where only Python implements the construct ----
    n2 = cond.get("N2-NATIVE-REFUSES-WHERE-PYTHON-ACCEPTS", {})
    if n2.get("terminal_state") == "OBSERVED":
        n2files = list((root / "runs/N2/evidence").glob("n2-p*.json"))
        if len(n2files) != 1:
            fail(f"N2: expected exactly 1 evidence file, found {len(n2files)}", issues)
        for nf in n2files:
            ev = json.loads(nf.read_text(encoding="utf-8"))
            tag = nf.name
            recorded = ev.get("native_result_contract_rejection") or {}
            rebuilt = reload_rejection(ev.get("failure", ""))
            if not recorded:
                fail(f"N2 {tag}: no structured native rejection captured", issues)
            if rebuilt is None:
                fail(f"N2 {tag}: failure string carries no native refusal marker", issues)
            else:
                if recorded.get("code") != rebuilt["code"]:
                    fail(f"N2 {tag}: recorded rejection code {recorded.get('code')!r} "
                         f"does not follow from the failure string {rebuilt['code']!r}", issues)
                if recorded.get("stage") != STAGE_MARKER:
                    fail(f"N2 {tag}: rejection stage is not {STAGE_MARKER}", issues)
            if not RUNTIME_ITEM.match(ev.get("task_item_id", "")):
                fail(f"N2 {tag}: item under test is not a run-time generated ID", issues)
            gen = int((ev.get("counters") or {}).get("model_continuation_calls") or 0)
            if gen < 1:
                fail(f"N2 {tag}: no real model continuation ran before the refusal", issues)
        o = n2.get("observations", {})
        if o.get("native_refused") is not True:
            fail("N2: native engine did not refuse the Python-only constraint kind", issues)
        if o.get("valid_settlement_created") is not False:
            fail("N2: a refused result must not create a settlement", issues)
        if o.get("signature_created") is not False:
            fail("N2: a refused result must not create a signature", issues)
        if o.get("python_implements_kind") is not True:
            fail("N2: Python gate does not implement the counterfactual kind", issues)
        if o.get("python_gate_outcome_for_same_kind") == "CONTRACT_UNKNOWN_CONSTRAINT":
            fail("N2: Python also treated the kind as unknown; no divergence shown", issues)
        if o.get("generation_before_refusal") is not True:
            fail("N2: native refusal must follow a real generation, not precede it", issues)

    return issues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_root", type=Path)
    args = ap.parse_args()
    issues = validate(args.run_root)
    result = {"result": "PASS" if not issues else "FAIL",
              "issue_count": len(issues), "issues": issues}
    print(json.dumps(result, indent=2))
    return 0 if not issues else 1


if __name__ == "__main__":
    sys.exit(main())
