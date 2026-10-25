#!/usr/bin/env python3
"""K round: the NATIVE result-contract engine as the pre-settlement authority.

J proved result validation dispatches on each item's own declared contract (no
task-id branch) using the PYTHON gate. K moves that gate's authority into the
native Swift producer: the ordinary `SimiGoTaskRun` continuation now validates
the model's own generated text with the NATIVE `simigo.result-contract/v1`
engine, against bindings the Information Space admission already verified,
BEFORE any value file or settlement bridge call. A native refusal therefore
creates no settlement object and no signature.

Conditions:
  PRE  cross-engine parity: the shared canonical case file run through both the
       Python production gate and the native engine reports issue_count == 0, and
       the H/I/J/admission regressions plus the native Swift unit tests are green.
  K0   three fresh processes on run-time ids with a real model: every stage is
       admitted, its OWN declaration is validated by the NATIVE gate (a native
       trace is recorded with IS-verified bindings), it settles and signs, and the
       native typed values agree with the settled value AND with the driver's
       independent Python re-extraction -- native and Python agree on real output.
  N2   native-authority counterfactual: a run-time U1 whose declaration uses a
       constraint kind the PYTHON gate implements but the NATIVE engine does not
       (equals_binding_segment). The native pre-settlement gate refuses
       fail-closed (CONTRACT_UNKNOWN_CONSTRAINT), so NO settlement and NO
       signature exist -- even though the Python gate would evaluate that kind.
       This proves the refusal is the native gate acting as authority, not a
       post-hoc complaint. (digest_equals_binding was used before K2, but the
       native engine now implements it, so it no longer demonstrates a refusal.)

The native `SimiGoTaskRun` binary owns every real model call. This runner only
prepares graphs through the production bridge, launches processes and aggregates
evidence. It never reads a settled value to build a prompt, never injects a value
through argv/env, does not change carrier recompute semantics, does not touch
prior run roots, and does not stage or commit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import run_phase_e as e  # noqa: E402
import run_phase_j as j  # noqa: E402

LAB_ROOT = Path("/Users/mr.simi/Documents/SimiGo-Lab")
RUN_ROOT_DEFAULT = (Path.home() / "SimiGo-Agent-Runs" /
                    "es-is-native-result-contract-20261023k")
RUN_LABEL = "es-is-native-result-contract-20261023k"
LOOP_DIR = LAB_ROOT / "execution-information-loop"
PARITY_FIXTURES = LOOP_DIR / "tests" / "fixtures"
PARITY_CASES = PARITY_FIXTURES / "native_python_contract_parity_expanded.json"
PARITY_COMPARE = LOOP_DIR / "tests" / "compare_native_python_parity.py"
NATIVE_HARNESS = (LAB_ROOT / "simigo2-experimental/.build/debug/"
                  "NativeContractParityHarness")
UNKNOWN_KIND = "equals_binding_segment"  # Python implements, native does not


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(cmd: list, cwd: Path = None, timeout: int = 1800) -> tuple:
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          cwd=str(cwd) if cwd else None, timeout=timeout)
    return proc.returncode, proc.stdout, proc.stderr


def parity_precondition(run_root: Path) -> dict:
    """Both engines over the shared case file; issue_count must be zero."""
    cases_sha = hashlib.sha256(PARITY_CASES.read_bytes()).hexdigest()
    code, out, err = run([str(NATIVE_HARNESS), "--cases", str(PARITY_CASES)])
    native_path = run_root / "parity" / "native_harness_out.json"
    native_path.parent.mkdir(parents=True, exist_ok=True)
    native_path.write_text(out, encoding="utf-8")
    vcode, vout, verr = run(["/usr/bin/python3", str(PARITY_COMPARE),
                             "--cases", str(PARITY_CASES),
                             "--native", str(native_path)])
    try:
        verdict = json.loads(vout)
    except json.JSONDecodeError:
        verdict = {"issue_count": -1, "issues": [verr[-400:] or "no json"]}
    result = {
        "harness_exit": code,
        "cases_sha256": cases_sha,
        "case_count": verdict.get("case_count"),
        "issue_count": verdict.get("issue_count"),
        "issues": verdict.get("issues", []),
        "verdict": "PASS" if (code == 0 and verdict.get("issue_count") == 0)
        else "FAIL",
    }
    (run_root / "parity" / "parity_precondition.json").write_text(
        json.dumps({"compare": verdict, "gate": result}, indent=2,
                   sort_keys=True), encoding="utf-8")
    # The independent verifier re-reads the RAW comparator output as its own
    # source of truth (never the driver's narration), so persist it verbatim.
    (run_root / "parity" / "parity_verify.json").write_text(
        json.dumps(verdict, indent=2, sort_keys=True), encoding="utf-8")
    return result


def regression_precondition(run_root: Path, attempt: int) -> dict:
    """H/I/J/admission model-free gates + the native Swift unit tests."""
    suite = j.run_regression_suite(run_root, LOOP_DIR, attempt)
    scode, sout, serr = run(["swift", "test", "--filter",
                             "DeclarativeNativeResultContractTests"],
                            cwd=LAB_ROOT / "simigo2-experimental", timeout=900)
    # Derive the expected native test count from the delivered test file so the
    # gate stays honest as the suite grows (16 in K1, 21 after the K2 digest
    # increment) instead of pinning a magic number that would falsely fail.
    native_tests_file = (LAB_ROOT / "simigo2-experimental/Tests/"
                         "SimiGo2ExperimentalTests/"
                         "NativeDeclarativeResultContractTests.swift")
    expected_tests = len(re.findall(r"\bfunc test", native_tests_file.read_text(
        encoding="utf-8")))
    matches = re.findall(r"Executed (\d+) tests, with (\d+) failures",
                         sout + serr)
    total_failures = sum(int(f) for _, f in matches)
    max_executed = max((int(n) for n, _ in matches), default=0)
    passed_marker = (scode == 0 and total_failures == 0 and expected_tests > 0
                     and max_executed == expected_tests)
    swift = {"exit": scode, "expected_tests": expected_tests,
             "executed": max_executed, "failures": total_failures,
             "all_passed": passed_marker, "tail": (sout + serr)[-400:]}
    verdict = "PASS" if (suite.get("verdict") == "PASS" and scode == 0
                         and passed_marker) else "FAIL"
    return {"verdict": verdict, "python_suite": suite.get("members", {}),
            "swift_native_tests": swift}


def read_native_stage(evidence_path: str) -> dict:
    ev = json.loads(Path(evidence_path).read_text(encoding="utf-8"))
    native = ev.get("native_result_contract_validation") or {}
    settled = (ev.get("settlement") or {}).get(
        "signed_settlement_object_id") or ""
    return {
        "item": ev.get("task_item_id"),
        "terminal_state": ev.get("terminal_state"),
        "contract_dispatch_basis": ev.get("contract_dispatch_basis"),
        "native_gate": native.get("gate"),
        "native_authority": native.get("authority"),
        "native_status": native.get("native_validation_status"),
        "native_values": native.get("native_values"),
        "native_verified_bindings": native.get("verified_bindings") or [],
        "native_constraint_checks": native.get("native_constraint_checks") or [],
        "native_rejection": ev.get("native_result_contract_rejection") or {},
        "failure": ev.get("failure"),
        "settlement_object_id": settled,
        "generated_text": ev.get("generated_text"),
        "evidence_path": evidence_path,
    }


def run_k0(binary, bridge, lab_root, model_dir, trust, world, run_root,
           max_tokens, ids) -> dict:
    j0 = j.run_j0(binary, bridge, lab_root, model_dir, trust, world, run_root,
                  max_tokens, ids)
    stages = [read_native_stage(p) for p in j0.get("evidence_paths", [])]
    db = world / "carrier.sqlite"

    def settled_value_of(stage):
        content = j.read_settled_content(db, stage["settlement_object_id"])
        return (content.get("result") or {}).get("value") or {}

    stage_checks = []
    for index, stage in enumerate(stages):
        rec = j0["observations"]["stage_records"][index]
        native_vals = stage["native_values"] or {}
        reextracted = (rec.get("declared_contract_audit") or {}).get(
            "reextracted_fields") or {}
        settled = settled_value_of(stage)
        # native typed values == driver python re-extraction == settled IS value
        agree_native_vs_python = all(
            str(native_vals.get(k)) == str(reextracted.get(k))
            for k in set(native_vals) | set(reextracted))
        # The settled IS value carries extra identity keys alongside the declared
        # semantic fields, so compare only over the fields the native gate typed.
        agree_native_vs_settled = bool(native_vals) and all(
            str(native_vals[k]) == str(settled.get(k)) for k in native_vals)
        bindings = stage["native_verified_bindings"]
        binding_from_is = all(
            b.get("settlement_object_id") and b.get("value_sha256")
            for b in bindings)
        constraint_passed = bool(stage["native_constraint_checks"]) and all(
            c.get("passed") for c in stage["native_constraint_checks"])
        ok = (stage["terminal_state"] == "TASK_SETTLED"
              and stage["native_gate"] == "native.SimiGoResultContracts"
              and stage["native_authority"] == "native_pre_settlement"
              and stage["native_status"] == "VALID"
              and stage["contract_dispatch_basis"] == "declared_contract"
              and bool(bindings) and binding_from_is and constraint_passed
              and agree_native_vs_python and agree_native_vs_settled
              and j.settlement_exists(db, stage["item"])
              and j.signature_exists(db, stage["item"]))
        stage_checks.append({
            "stage": rec.get("stage"), "item": stage["item"],
            "native_gate": stage["native_gate"],
            "native_authority": stage["native_authority"],
            "native_status": stage["native_status"],
            "native_verified_binding_count": len(bindings),
            "native_bindings_from_is": binding_from_is,
            "native_constraint_checks_passed": constraint_passed,
            "native_vs_python_values_agree": agree_native_vs_python,
            "native_vs_settled_values_agree": agree_native_vs_settled,
            "settlement_created": j.settlement_exists(db, stage["item"]),
            "signature_created": j.signature_exists(db, stage["item"]),
            "terminal_state": stage["terminal_state"],
            "ok": ok,
        })
    all_ok = len(stage_checks) == 3 and all(s["ok"] for s in stage_checks)
    observations = {
        "run_token": ids["run_token"],
        "item_ids": ids["model_item_ids"],
        "j0_terminal_state": j0["terminal_state"],
        "native_authority_stages": stage_checks,
        "contract_dispatch_basis": "native_pre_settlement_declared_contract",
    }
    return {
        "id": "K0-NATIVE-AUTHORITY-3-PROCESS", "kind": "real_model", "stages": 3,
        "terminal_state": "OBSERVED" if (all_ok and j0["terminal_state"]
                                         == "OBSERVED") else "FAILED",
        "observations": observations,
        "j0": j0,
        "evidence_paths": j0.get("evidence_paths", []),
        "world": str(world),
    }


def run_n2(binary, bridge, lab_root, model_dir, trust, run_root, max_tokens) -> dict:
    world = run_root / "runs" / "N2"
    for name in ("logs", "state", "evidence", "stdout", "stderr"):
        (world / name).mkdir(parents=True, exist_ok=True)
    ids = j.define_graph(
        bridge, world / "carrier.sqlite", run_root, trust, lab_root,
        world / "logs" / "define-j-graph.log", secrets.token_hex(4),
        ["--u1-constraint-kind", UNKNOWN_KIND])
    env = e.child_environment(lab_root, trust, "n2-p1",
                              "N2-P1-%s" % ids["u1"], with_key=True)
    entry = j.launch(binary, world, run_root, lab_root, model_dir, ids["u1"],
                     ids["demand_u1"], "n2-p1", "n2-p1", max_tokens, env)
    stage = read_native_stage(entry["evidence_path"])
    db = world / "carrier.sqlite"
    # A refused result carries no generated_text in its entry record, but the
    # runtime counters prove a real model continuation ran before the native
    # gate threw. Generation must be evidenced by the counter, not the absent
    # text, or the counterfactual would look like it never reached the model.
    n2_entry = json.loads(Path(entry["evidence_path"]).read_text(encoding="utf-8"))
    gen_calls = int((n2_entry.get("counters") or {})
                    .get("model_continuation_calls") or 0)
    settled = j.settlement_exists(db, ids["u1"])
    signed = j.signature_exists(db, ids["u1"])
    reject = stage["native_rejection"]
    native_refused = (reject.get("code") == "CONTRACT_UNKNOWN_CONSTRAINT"
                      and reject.get("stage") == "PRODUCER_RESULT_CONTRACT")
    # Independent proof the PYTHON gate implements this kind (would not refuse it
    # as unknown): a direct call resolves the constraint rather than erroring on
    # an unimplemented kind.
    sys.path.insert(0, str(LOOP_DIR))
    import declarative_result_contract as drc
    python_code = ""
    try:
        pcontract = {"schema_version": drc.CONTRACT_VERSION,
                     "fields": {"route_key": {"pattern": "ROUTE=([A-Z]+>[A-Z]+)",
                                               "capture_group": 1, "type": "string",
                                               "match_policy": "first"}},
                     "constraints": [{"kind": UNKNOWN_KIND, "field": "route_key",
                                      "binding": "d", "separator": "-",
                                      "segment": 0}]}
        drc.validate_result_text("ROUTE=NORTH>EAST", pcontract,
                                 {"d": "NORTH>EAST-suffix"})
        python_code = "VALID"
    except drc.ContractError as err:
        python_code = err.code
    python_implements_kind = python_code != "CONTRACT_UNKNOWN_CONSTRAINT"

    observations = {
        "run_token": ids["run_token"],
        "item_id_under_test": ids["u1"],
        "declared_constraint_kind": UNKNOWN_KIND,
        "native_rejection": reject,
        "native_refused": native_refused,
        "valid_settlement_created": settled,
        "signature_created": signed,
        "python_gate_outcome_for_same_kind": python_code,
        "python_implements_kind": python_implements_kind,
        "generation_before_refusal": gen_calls > 0,
        "model_continuation_calls": gen_calls,
        "model_loads": 1, "generation_calls": 1,
    }
    terminal = ("OBSERVED" if (native_refused and not settled and not signed
                               and python_implements_kind)
                else "FAILED")
    (run_root / "logs" / "N2-NATIVE-REFUSES.driver.log").write_text(
        json.dumps(observations, indent=2, sort_keys=True, default=str),
        encoding="utf-8")
    return {"id": "N2-NATIVE-REFUSES-WHERE-PYTHON-ACCEPTS",
            "kind": "native_authority_counterfactual",
            "terminal_state": terminal, "observations": observations,
            "world": str(world)}


def build_summary(run_root, conditions, guards, implementation) -> dict:
    recorded = {}
    for c in conditions:
        path = run_root / "conditions" / ("%s.json" % c["id"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(c, indent=2, sort_keys=True, default=str),
                        encoding="utf-8")
        recorded[c["id"]] = {
            "terminal_state": c["terminal_state"], "kind": c.get("kind", ""),
            "evidence_path": str(path.relative_to(run_root)),
            "observations": c.get("observations", {}),
        }
    states = [v["terminal_state"] for v in recorded.values()]
    terminal = ("OBSERVED" if states and all(s == "OBSERVED" for s in states)
                else ("FAILED" if "FAILED" in states else "BLOCKED_NOT_RUN"))
    return {
        "schema_version": "simigo-k-evidence-v1", "round": "K",
        "label": RUN_LABEL, "created_at_utc": utc_now(),
        "terminal_state": terminal,
        "research_question": (
            "Can the native result-contract engine, fed only with Information "
            "Space-verified bindings, act as the pre-settlement authority for a "
            "real model on run-time ids, agreeing with the Python gate where both "
            "implement a construct and refusing fail-closed (settling nothing) "
            "where only Python does?"),
        "primary_entry": "native SimiGoTaskRun continueTask / native gate",
        "implementation": implementation, "conditions": recorded,
        "guards": guards,
        "carrier_loop_semantics_changed": False,
        "historical_artifacts_modified": False,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-root", type=Path, default=RUN_ROOT_DEFAULT)
    ap.add_argument("--model-dir", type=Path, required=True)
    ap.add_argument("--max-tokens", type=int, default=48)
    ap.add_argument("--attempt", type=int, default=1)
    ap.add_argument("--skip-real", action="store_true")
    args = ap.parse_args()

    run_root = args.run_root
    for name in ("runs", "manifests", "conditions", "logs", "tests", "parity"):
        (run_root / name).mkdir(parents=True, exist_ok=True)
    binary = LAB_ROOT / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    bridge = LOOP_DIR / "production_runtime_bridge.py"
    model_dir = args.model_dir

    blocked = None
    for path in (binary, NATIVE_HARNESS, bridge, PARITY_CASES, model_dir):
        if not path.exists():
            blocked = "missing path: %s" % path
            break

    conditions = []
    if blocked:
        for cid in ("K0-NATIVE-AUTHORITY-3-PROCESS",
                    "N2-NATIVE-REFUSES-WHERE-PYTHON-ACCEPTS"):
            conditions.append({"id": cid, "kind": "blocked",
                               "terminal_state": "BLOCKED_NOT_RUN",
                               "observations": {"blocked": blocked}})
        summary = build_summary(run_root, conditions, {},
                                {"blocked": blocked})
        (run_root / "summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True, default=str))
        print(json.dumps({"terminal_state": "BLOCKED_NOT_RUN",
                          "blocked": blocked}))
        return 2

    # Preconditions first: no real model time is spent unless parity and the
    # regressions are green on this exact code state.
    parity = parity_precondition(run_root)
    regression = regression_precondition(run_root, args.attempt)
    preconditions_ok = (parity["verdict"] == "PASS"
                        and regression["verdict"] == "PASS")

    implementation = {
        "contract_dispatch_basis": "native_pre_settlement_declared_contract",
        "native_gate": "native.SimiGoResultContracts",
        "gate_authority": "SimiGoTaskRun.continueTask modelValue closure "
        "(before value file + execute-with-model-result)",
        "binary_sha256": e.sha256_file(binary),
        "parity_gate": parity,
        "regression": regression,
        "attempt": args.attempt,
    }

    # Trust re-provisioned against the rebuilt native binary identity.
    trust = j.provision_trust_clean(run_root)
    trust["binary_sha256"] = e.sha256_file(binary)
    trust["build_sha256"] = hashlib.sha256("\n".join([
        e.sha256_file(binary), e.sha256_file(bridge),
        e.sha256_file(LOOP_DIR / "declarative_result_contract.py"),
        e.sha256_file(LOOP_DIR / "settlement_provenance.py"),
    ]).encode()).hexdigest()
    (run_root / "trust" / "trust-root.json").write_text(
        json.dumps(trust, indent=2), encoding="utf-8")

    if args.skip_real or not preconditions_ok:
        note = ("--skip-real" if args.skip_real
                else "preconditions not green: parity=%s regression=%s" % (
                    parity["verdict"], regression["verdict"]))
        for cid in ("K0-NATIVE-AUTHORITY-3-PROCESS",
                    "N2-NATIVE-REFUSES-WHERE-PYTHON-ACCEPTS"):
            conditions.append({"id": cid, "kind": "blocked",
                               "terminal_state": "BLOCKED_NOT_RUN",
                               "observations": {"blocked": note}})
    else:
        j0_world = run_root / "runs" / "K0"
        for name in ("logs", "state", "evidence", "stdout", "stderr"):
            (j0_world / name).mkdir(parents=True, exist_ok=True)
        ids = j.define_graph(bridge, j0_world / "carrier.sqlite", run_root,
                             trust, LAB_ROOT,
                             j0_world / "logs" / "define-j-graph.log",
                             secrets.token_hex(4))
        conditions.append(run_k0(binary, bridge, LAB_ROOT, model_dir, trust,
                                 j0_world, run_root, args.max_tokens, ids))
        conditions.append(run_n2(binary, bridge, LAB_ROOT, model_dir, trust,
                                 run_root, args.max_tokens))

    summary = build_summary(run_root, conditions, {
        "parity": parity["verdict"], "regression": regression["verdict"],
    }, implementation)
    (run_root / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True, default=str),
        encoding="utf-8")
    print(json.dumps({"terminal_state": summary["terminal_state"],
                      "parity": parity["verdict"],
                      "regression": regression["verdict"],
                      "conditions": {c["id"]: c["terminal_state"]
                                     for c in conditions}},
                     indent=1))
    return 0 if summary["terminal_state"] == "OBSERVED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
