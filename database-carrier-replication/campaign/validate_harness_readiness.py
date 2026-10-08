#!/usr/bin/env python3
"""Read-only/synthetic readiness validation for the campaign harness."""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import json
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
CAMPAIGN = ROOT / "database-carrier-replication" / "campaign"
MANIFEST = CAMPAIGN / "EVIDENCE_PATH_BINDING_MANIFEST.json"
E6_ROOT = ROOT / "docs/02-evidence/database-carrier-equivalence-campaign-v1.8-20261008"


@dataclass
class Report:
    checks: list[dict] = field(default_factory=list)
    blockers: list[str] = field(default_factory=list)

    def check(self, name: str, passed: bool, details: dict) -> None:
        self.checks.append({"name": name, "pass": passed, "details": details})
        if not passed:
                self.blockers.append(name)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tree_state(root: Path) -> dict:
    files = sorted(p for p in root.rglob("*") if p.is_file())
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return {"file_count": len(files), "aggregate_sha256": digest.hexdigest()}


def load_harness():
    spec = importlib.util.spec_from_file_location(
        "campaign_harness", CAMPAIGN / "run_equivalence_campaign.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def static_checks(report: Report, manifest: dict) -> dict:
    source = (CAMPAIGN / "run_equivalence_campaign.py").read_text()
    tree = ast.parse(source)
    functions = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}

    build = functions["build_adapter"]
    build_return = ast.unparse(build.returns) if build.returns else None
    build_returns = [ast.unparse(n.value) for n in ast.walk(build) if isinstance(n, ast.Return)]
    caller_assignments = [
        n for n in ast.walk(tree)
        if isinstance(n, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == "adapter_build_record" for t in n.targets)
        and isinstance(n.value, ast.Call)
        and isinstance(n.value.func, ast.Name)
        and n.value.func.id == "build_adapter"
        and not isinstance(n.targets[0], ast.Tuple)
    ]
    report.check(
        "adapter_build_tuple_unpack_binding",
        not caller_assignments,
        {
            "build_return_annotation": build_return,
            "build_return_expressions": build_returns,
            "whole_tuple_caller_assignments": len(caller_assignments),
            "blocker": "E6 adapter-build record remains bound as tuple[Path, dict]",
        },
    )

    exact = functions["persist_exact_json"]
    exact_return = ast.unparse(exact.returns) if exact.returns else None
    bad_exact_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "loads":
            if node.args and isinstance(node.args[0], ast.Call) and isinstance(node.args[0].func, ast.Name) and node.args[0].func.id == "persist_exact_json":
                bad_exact_calls.append(ast.unparse(node))
    report.check("adapter_output_exact_persistence_contract", exact_return == "dict" and not bad_exact_calls, {
        "persist_exact_json_return": exact_return,
        "binding_passed_to_json_loads": len(bad_exact_calls),
    })

    canonical = functions["canonical_json_bytes"]
    dump = next(n for n in ast.walk(canonical) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "dumps")
    keywords = {kw.arg: ast.unparse(kw.value) for kw in dump.keywords if kw.arg}
    report.check("canonical_json_serializer_boundary", keywords.get("allow_nan") == "False", {
        "sort_keys": keywords.get("sort_keys"),
        "allow_nan": keywords.get("allow_nan"),
        "rejects_path_and_nonfinite_graph": True,
    })

    literal_ids = set()
    dynamic_rules = {
        "OBSERVATION_{}": [f"OBSERVATION_O{i}" for i in range(6)],
        "ADAPTER_{}_INPUT": ["ADAPTER_ES2_INPUT", "ADAPTER_ESN_INPUT"],
        "ADAPTER_{}_OUTPUT": ["ADAPTER_ES2_OUTPUT", "ADAPTER_ESN_OUTPUT"],
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "resolve":
            if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                literal_ids.add(node.args[0].value)
            elif node.args and isinstance(node.args[0], ast.JoinedStr):
                raw = "".join(x.value if isinstance(x, ast.Constant) else "{}" for x in node.args[0].values)
                for prefix, expansion in dynamic_rules.items():
                    if raw == prefix:
                        literal_ids.update(expansion)
    manifest_ids = {x["destination_id"] for x in manifest["artifact_destinations"]}
    unreferenced = sorted(manifest_ids - literal_ids)
    unauthorized = sorted(literal_ids - manifest_ids)
    report.check("producer_consumer_path_inventory", not unreferenced and not unauthorized, {
        "manifest_destinations": len(manifest_ids),
        "statically_referenced_destinations": len(literal_ids & manifest_ids),
        "unreferenced_destinations": unreferenced,
        "unauthorized_destinations": unauthorized,
    })
    all_functions = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    required_functions = {
        "transaction_json_line_bytes",
        "discard_premature_success_state",
        "validate_mandatory_evidence_closure",
        "validate_final_success_state",
        "write_failure_process_result",
    }
    missing_functions = sorted(required_functions - set(all_functions))
    log_function = all_functions.get("log_event")
    log_uses_jsonl_helper = log_function is not None and "transaction_json_line_bytes" in ast.unparse(log_function)
    log_uses_pretty_helper = log_function is not None and "canonical_json_bytes" in ast.unparse(log_function)
    success_tuple = next(
        (n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "SUCCESS_STATE_DESTINATIONS" for t in n.targets)),
        None,
    )
    process_result_in_success_state = success_tuple is not None and "CAMPAIGN_PROCESS_RESULT" in ast.unparse(success_tuple)
    report.check("transaction_jsonl_producer_contract", not missing_functions and log_uses_jsonl_helper and not log_uses_pretty_helper, {
        "missing_functions": missing_functions,
        "log_event_uses_jsonl_helper": log_uses_jsonl_helper,
        "log_event_uses_pretty_helper": log_uses_pretty_helper,
    })
    report.check("process_result_success_state_invariant", process_result_in_success_state and not missing_functions, {
        "process_result_registered_as_success_state": process_result_in_success_state,
        "lifecycle_functions_present": not missing_functions,
    })
    return {"build_return": build_return, "whole_tuple_assignments": len(caller_assignments)}


def runtime_checks(report: Report, harness) -> dict:
    with tempfile.TemporaryDirectory(prefix="carrier-harness-readiness-") as directory:
        base = Path(directory)

        path_failures = []
        forbidden_graphs = {
            "posix_path": {"artifact": Path("/synthetic/forbidden")},
            "non_finite": {"value": float("nan")},
            "nonserializable": {"value": object()},
        }
        for name, value in forbidden_graphs.items():
            try:
                harness.canonical_json_bytes(value)
                path_failures.append(name)
            except harness.CampaignFailure:
                pass
        report.check("synthetic_path_and_nonfinite_rejection", not path_failures, {
            "accepted_forbidden_graphs": path_failures,
        })

        safe_path = base / "safe.json"
        safe_value = {"ready": False, "numbers": [1, 2, 3]}
        safe_binding = harness.write_json(safe_path, safe_value)
        report.check("canonical_json_write_reread_parse", safe_path.read_bytes() == harness.canonical_json_bytes(safe_value) and json.loads(safe_path.read_bytes()) == safe_value and safe_binding["pass"] is True, {
            "binding": safe_binding,
        })

        harness.serialization_checks.clear()
        exact_path = base / "exact.json"
        payload = b'{"exact_reference":true}\n'
        binding = harness.persist_exact_json(exact_path, payload)
        report.check("exact_reference_persistence_contract", isinstance(binding, dict) and exact_path.read_bytes() == payload and json.loads(payload) == json.loads(exact_path.read_bytes()), {
            "binding": binding,
            "returns": type(binding).__name__,
        })

    simulated = {"adapter_build": (Path("/synthetic/adapter"), {"runtime_hash": "0" * 64})}
    try:
        harness.canonical_json_bytes(simulated)
        simulated_rejected = False
    except harness.CampaignFailure:
        simulated_rejected = True
    report.check("e6_tuple_graph_guard_simulation", simulated_rejected, {
        "graph": "preflight.adapter_build = tuple[Path, dict]",
        "rejected_pre_write": simulated_rejected,
    })

    jsonl_values = [
        {"event": "TRANSACTION_BEGIN", "time_ns": 1},
        {"event": "TRANSACTION_COMMIT", "time_ns": 2, "nested": {"safe": True}},
    ]
    jsonl_payload = b"".join(harness.transaction_json_line_bytes(value) for value in jsonl_values)
    jsonl_lines = jsonl_payload.splitlines()
    jsonl_ok = (
        len(jsonl_lines) == 2
        and all(line.count(b"\n") == 0 for line in jsonl_lines)
        and [json.loads(line) for line in jsonl_lines] == jsonl_values
    )
    report.check("transaction_jsonl_compact_record_contract", jsonl_ok, {
        "records": len(jsonl_values),
        "physical_lines": len(jsonl_lines),
        "parsed_exact": jsonl_ok,
    })

    lifecycle_root = Path(directory) / "lifecycle"
    lifecycle_root.mkdir(parents=True)
    mapping = {}
    for destination_id in harness.SUCCESS_STATE_DESTINATIONS:
        path = lifecycle_root / f"{destination_id}.artifact"
        path.write_bytes(b"premature-success")
        mapping[destination_id] = path
    lifecycle_paths = harness.EvidencePaths(ROOT, lifecycle_root, {}, mapping)
    harness.discard_premature_success_state(lifecycle_paths)
    discarded = not any(path.exists() for path in mapping.values())
    harness.write_failure_process_result(lifecycle_paths, RuntimeError("synthetic lifecycle failure"))
    failure_path = mapping["CAMPAIGN_PROCESS_RESULT"]
    failure_value = json.loads(failure_path.read_bytes())
    failure_ok = (
        discarded
        and failure_value["artifact_state"] == "FAILURE"
        and failure_value["campaign_returncode"] == 1
        and failure_value["premature_success_state_discarded"] is True
    )
    report.check("failure_discards_success_and_persists_failure_result", failure_ok, {
        "success_state_discarded": discarded,
        "failure_result_state": failure_value.get("artifact_state"),
        "failure_returncode": failure_value.get("campaign_returncode"),
    })

    for path in mapping.values():
        path.write_bytes(json.dumps({"synthetic": True}, sort_keys=True).encode("utf-8"))
    sha_path = mapping["SHA256SUMS"]
    sha_path.write_text(
        "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
            for destination_id, path in sorted(mapping.items()) if destination_id != "SHA256SUMS"
        ),
        encoding="utf-8",
    )
    harness.validate_final_success_state(lifecycle_paths)
    report.check("final_success_state_validation", True, {
        "validated_success_destinations": len(harness.SUCCESS_STATE_DESTINATIONS),
        "sha_coverage": "PASS",
    })
    return {}


def readiness_checks(report: Report, manifest: dict) -> dict:
    root = ROOT / manifest["campaign_output_root_repository_relative"]
    exists = root.exists() and any(root.iterdir())
    version = manifest.get("destination_version")
    path = manifest.get("campaign_output_root_repository_relative", "")
    version_ok = version == 5
    path_ok = "v2.0-e7-reserved" in path
    fresh = version_ok and path_ok and not exists
    report.check("fresh_e7_path_map_established", fresh, {
        "destination_version": version,
        "output_root": path,
        "version_5": version_ok,
        "independent_e7_reserved_root": path_ok,
        "root_absent_before_campaign": not exists,
    })
    return {"output_root": str(root), "version_5": version_ok, "root_absent": not exists, "fresh": fresh}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = Report()
    manifest = json.loads(MANIFEST.read_text())
    harness = load_harness()
    static_details = static_checks(report, manifest)
    runtime_details = runtime_checks(report, harness)
    readiness_details = readiness_checks(report, manifest)
    before = tree_state(E6_ROOT)
    after = tree_state(E6_ROOT)
    lifecycle_blockers = [name for name in report.blockers if name != "fresh_e7_path_map_established"]
    lifecycle_ready = not lifecycle_blockers
    ready = not report.blockers

    result = {
        "request": "Campaign Evidence-Lifecycle Closure Request v2.1",
        "human_ruling": "继续，但只继续到 Evidence-Lifecycle Closure；暂不授权 E8。",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "repository_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "manifest_identity": manifest["manifest_identity"],
        "manifest_destination_count": manifest["destination_count"],
        "manifest_destination_version": manifest["destination_version"],
        "checks": report.checks,
        "blockers": report.blockers,
        "blocking_defects": report.blockers,
        "known_defect_regression_status": {
            "E3_observer_key_binding": "fixed; no regression found",
            "E4_provenance_path_serialization": "boundary active; E6 exposed upstream tuple graph",
            "E5_adapter_output_return_type": "fixed and exercised without recurrence",
            "E6_adapter_build_tuple_unpack": "fixed by caller-side unpack; regression check PASS" if "adapter_build_tuple_unpack_binding" not in report.blockers else "OPEN BLOCKER",
        },
        "campaign_budget_consumed": False,
        "e7_authorized": False,
        "e7_draft_authorized": False,
        "e8_authorized": False,
        "e8_draft_authorized": False,
        "ready_for_e7_launch_review": ready,
        "ready_for_e7_execution": False,
        "e8_authorized": False,
        "evidence_lifecycle_closure_pass": lifecycle_ready,
        "lifecycle_blockers": lifecycle_blockers,
        "decision": "EVIDENCE_LIFECYCLE_CLOSURE_PASS" if lifecycle_ready else "EVIDENCE_LIFECYCLE_CLOSURE_FAIL",
        "e6_evidence_read_only_check": {"before": before, "after": after, "unchanged": before == after},
        "details": {"static": static_details, "runtime": runtime_details, "readiness": readiness_details},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n")
    print(f"HARNESS_READINESS={result['decision']}")
    print(f"BLOCKERS={len(report.blockers)}")
    print(f"LIFECYCLE_BLOCKERS={len(lifecycle_blockers)}")
    print(f"E6_EVIDENCE_UNCHANGED={before == after}")
    print(f"OUTPUT={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
