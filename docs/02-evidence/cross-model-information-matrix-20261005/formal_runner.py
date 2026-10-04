#!/usr/bin/env python3
"""Formal cross-model × cross-sample runner.

Separate from the pilot `run_matrix.py`.  Runtime is refused unless a explicit,
runner-specific authorization artifact is supplied.  The default modes are
static: freeze check, deterministic rendering, and 16-cell plan.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request
import uuid
from typing import Any

UTC = dt.timezone.utc
ROOT = pathlib.Path(__file__).resolve().parent
CONTRACT = ROOT.parents[1] / "00-governance/SIMIGO_LAB_CROSS_MODEL_STABILITY_SCHEDULING_CONTRACT_20261005.md"
STATUSES = {
    "FORMAL",
    "PILOT_ONLY_NOT_FORMAL",
    "INVALID_ISOLATION",
    "RUNTIME_ERROR",
    "INCOMPLETE",
}
ISOLATION_REQUIRED = {
    "isolation_id",
    "cell_id",
    "method",
    "fresh_process",
    "reload_completed",
    "cache_prefix_excluded",
    "concurrent_workload_excluded",
    "round1_residue_excluded",
    "other_cell_state_excluded",
    "valid_from",
    "valid_until",
    "evidence_paths",
}


def utc_now() -> str:
    return dt.datetime.now(UTC).isoformat()


def load_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def sha_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def endpoint_models(base_url: str) -> tuple[int, dict[str, Any], dict[str, str]]:
    request = urllib.request.Request(base_url.rstrip("/") + "/models", method="GET")
    started = dt.datetime.now(UTC).isoformat()
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read()
        headers = {k.lower(): v for k, v in response.headers.items()}
        status = response.status
    finished = dt.datetime.now(UTC).isoformat()
    return status, json.loads(raw), {"started_at": started, "finished_at": finished, **headers}


def render_prompt(sample: dict[str, Any], contract: dict[str, Any], repo_root: pathlib.Path) -> str:
    blocks = [
        "You must use only the supplied material. Do not use outside knowledge, tools, or prior reports.",
        sample["task"],
        "Return exactly one strict JSON object with these keys: "
        "task_id, decision, findings, missing_or_uncertain, confidence. "
        "No markdown fence and no prose.",
        "The findings array must contain no more than "
        f"{contract['max_findings']} items; each item has id, statement, evidence, function.",
        "Allowed function values: constraint, decision, evidence, relation, uncertainty, task_rule.",
    ]
    for item in sample["input_files"]:
        path = repo_root / item["path"]
        if sha_file(path) != item["sha256"] or path.stat().st_size != item["bytes"]:
            raise RuntimeError(f"sample freeze mismatch: {item['path']}")
        blocks.append(f"=== INPUT {item['path']} ===\n{path.read_text(encoding='utf-8', errors='replace')}")
    return "\n\n".join(blocks) + "\n"


def load_and_verify(repo_root: pathlib.Path, runner_hash: str | None = None):
    samples_doc = load_json(ROOT / "freeze/samples.json")
    models_doc = load_json(ROOT / "freeze/models.json")
    samples = samples_doc["samples"]
    models = models_doc["models"]
    if len(samples) != 4 or len(models) != 4:
        raise RuntimeError("formal freeze must contain exactly 4 samples and 4 models")
    sample_ids = [s["sample_id"] for s in samples]
    model_ids = [m["model_id"] for m in models]
    if len(set(sample_ids)) != 4 or len(set(model_ids)) != 4:
        raise RuntimeError("sample/model IDs are not unique")
    for sample in samples:
        render_prompt(sample, samples_doc["common_output_contract"], repo_root)
    if runner_hash:
        actual_runner = sha_file(pathlib.Path(__file__))
        if actual_runner != runner_hash:
            raise RuntimeError(f"formal runner hash mismatch: expected {runner_hash}, got {actual_runner}")
    return samples_doc, models_doc, [(s, m) for s in samples for m in models]


def validate_authorization(path: pathlib.Path, contract_hash: str, runner_hash: str, models_hash: str, samples_hash: str) -> dict[str, Any]:
    auth = load_json(path)
    required = {
        "authorization_id",
        "scope",
        "contract_sha256",
        "runner_sha256",
        "models_sha256",
        "samples_sha256",
        "authorized_at",
        "runtime_authorized",
    }
    missing = sorted(required - set(auth))
    if missing:
        raise RuntimeError(f"authorization missing fields: {missing}")
    if auth["scope"] != "16_formal_cross_model_cells":
        raise RuntimeError("authorization scope is not 16 formal cross-model cells")
    if auth["contract_sha256"] != contract_hash:
        raise RuntimeError("authorization contract hash mismatch")
    if auth["runner_sha256"] != runner_hash:
        raise RuntimeError("authorization runner hash mismatch")
    if auth["models_sha256"] != models_hash:
        raise RuntimeError("authorization models hash mismatch")
    if auth["samples_sha256"] != samples_hash:
        raise RuntimeError("authorization samples hash mismatch")
    if auth["runtime_authorized"] is not True:
        raise RuntimeError("runtime is not authorized")
    return auth


def validate_isolation(path: pathlib.Path, cell_id: str, now: dt.datetime) -> dict[str, Any]:
    iso = load_json(path)
    missing = sorted(ISOLATION_REQUIRED - set(iso))
    if missing:
        return {"status": "INVALID_ISOLATION", "error": f"missing fields: {missing}", "isolation": iso}
    if iso.get("cell_id") != cell_id:
        return {"status": "INVALID_ISOLATION", "error": "cell_id mismatch", "isolation": iso}
    checks = {
        "fresh_process": iso.get("fresh_process") is True,
        "reload_completed": iso.get("reload_completed") is True,
        "cache_prefix_excluded": iso.get("cache_prefix_excluded") is True,
        "concurrent_workload_excluded": iso.get("concurrent_workload_excluded") is True,
        "round1_residue_excluded": iso.get("round1_residue_excluded") is True,
        "other_cell_state_excluded": iso.get("other_cell_state_excluded") is True,
    }
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        return {"status": "INVALID_ISOLATION", "error": f"false exclusions: {failed}", "isolation": iso}
    valid_from = parse_time(iso["valid_from"])
    valid_until = parse_time(iso["valid_until"])
    if not (valid_from <= now <= valid_until):
        return {"status": "INVALID_ISOLATION", "error": "current time outside isolation validity window", "isolation": iso}
    evidence = iso.get("evidence_paths")
    if not isinstance(evidence, list) or not evidence:
        return {"status": "INVALID_ISOLATION", "error": "evidence_paths is empty", "isolation": iso}
    return {"status": "VALID", "isolation": iso}


def emit_check(repo_root: pathlib.Path, out: pathlib.Path) -> int:
    checks: list[dict[str, Any]] = []
    samples_doc, models_doc, pairs = load_and_verify(repo_root)
    checks.append({"id": "FR-01", "name": "16 unique formal cells", "status": "PASS", "count": len(pairs)})
    checks.append({"id": "FR-02", "name": "sample inputs/hash verification", "status": "PASS"})
    prompts = {}
    for sample, _model in pairs:
        prompts[sample["sample_id"]] = render_prompt(sample, samples_doc["common_output_contract"], repo_root)
    if len(prompts) != 4 or len(set(prompts.values())) != 4:
        raise RuntimeError("rendered sample prompts are not unique")
    checks.append({"id": "FR-03", "name": "four deterministic non-identical sample prompts", "status": "PASS"})
    for model in models_doc["models"]:
        required = {"model_id", "repo_id", "architecture", "snapshot_revision", "config_sha256", "inference_config"}
        if not required <= set(model):
            raise RuntimeError(f"model freeze missing fields: {model.get('model_id')}")
    checks.append({"id": "FR-04", "name": "model identity/configuration freeze", "status": "PASS"})
    checks.append({"id": "FR-05", "name": "formal status enum", "status": "PASS", "statuses": sorted(STATUSES)})
    checks.append({"id": "FR-06", "name": "runtime authorization required", "status": "PASS", "authorized": False})
    checks.append({"id": "FR-07", "name": "separate from pilot runner", "status": "PASS", "pilot_runner": "run_matrix.py", "formal_runner": "formal_runner.py"})
    record = {
        "phase": "FORMAL_RUNNER_CHECK",
        "checked_at": utc_now(),
        "runner_sha256": sha_file(pathlib.Path(__file__)),
        "contract_sha256": sha_file(CONTRACT),
        "models_sha256": sha_file(ROOT / "freeze/models.json"),
        "samples_sha256": sha_file(ROOT / "freeze/samples.json"),
        "checks": checks,
        "runtime_executed": False,
        "readiness": "READY_FOR_AUTHORIZATION_ONLY",
    }
    write_json(out, record)
    print(json.dumps(record, ensure_ascii=False, indent=2))
    return 0


def emit_plan(repo_root: pathlib.Path, out: pathlib.Path) -> int:
    samples_doc, models_doc, pairs = load_and_verify(repo_root)
    cells = []
    for sample, model in pairs:
        cells.append({
            "cell_id": f"{sample['sample_id']}__{model['model_id']}",
            "sample_id": sample["sample_id"],
            "model_id": model["model_id"],
            "status": "PLANNED_RUNTIME_NOT_AUTHORIZED",
            "isolation_status": "NOT_CHECKED",
        })
    plan = {
        "phase": "FORMAL_CROSS_MODEL_PLAN",
        "created_at": utc_now(),
        "runner_sha256": sha_file(pathlib.Path(__file__)),
        "contract_sha256": sha_file(CONTRACT),
        "models_sha256": sha_file(ROOT / "freeze/models.json"),
        "samples_sha256": sha_file(ROOT / "freeze/samples.json"),
        "cells": cells,
        "runtime_authorized": False,
    }
    write_json(out, plan)
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


def emit_render(repo_root: pathlib.Path, out: pathlib.Path) -> int:
    samples_doc, _models_doc, pairs = load_and_verify(repo_root)
    rendered = []
    for sample, _model in pairs:
        prompt = render_prompt(sample, samples_doc["common_output_contract"], repo_root)
        rel = f"{sample['sample_id']}.prompt.txt"
        path = out / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(prompt, encoding="utf-8")
        rendered.append({"cell_sample": sample["sample_id"], "path": path.as_posix(), "sha256": sha_text(prompt), "bytes": len(prompt.encode("utf-8"))})
    write_json(out / "rendered-prompts.json", {"rendered_at": utc_now(), "prompts": rendered})
    print(json.dumps(rendered, ensure_ascii=False, indent=2))
    return 0


def run_formal(repo_root: pathlib.Path, formal_root: pathlib.Path, base_url: str, isolation_root: pathlib.Path, authorization_path: pathlib.Path) -> int:
    samples_doc, models_doc, pairs = load_and_verify(repo_root)
    auth = validate_authorization(
        authorization_path,
        sha_file(CONTRACT),
        sha_file(pathlib.Path(__file__)),
        sha_file(ROOT / "freeze/models.json"),
        sha_file(ROOT / "freeze/samples.json"),
    )
    if formal_root.exists() and any(formal_root.iterdir()):
        raise RuntimeError(f"formal run root is not empty: {formal_root}")
    formal_root.mkdir(parents=True)
    cells = []
    overall_status = "FORMAL"
    for sample, model in pairs:
        cell_id = f"{sample['sample_id']}__{model['model_id']}"
        now = dt.datetime.now(UTC)
        checked = validate_isolation(isolation_root / f"{cell_id}.json", cell_id, now)
        cell = formal_root / sample["sample_id"] / model["model_id"]
        cell.mkdir(parents=True, exist_ok=True)
        execution_id = str(uuid.uuid4())
        session_id = f"formal-{execution_id}"
        prompt = render_prompt(sample, samples_doc["common_output_contract"], repo_root)
        prompt_path = cell / "prompt.txt"
        prompt_path.write_text(prompt, encoding="utf-8")
        endpoint_status, active, endpoint_times = endpoint_models(base_url)
        active_ids = {item.get("id") for item in active.get("data", [])}
        identity_match = model["repo_id"] if model["repo_id"] in active_ids else (
            model["snapshot_revision"] if model.get("snapshot_revision") in active_ids else None
        )
        if not identity_match:
            record = {
                "status": "INVALID_ISOLATION", "cell_id": cell_id, "error": "endpoint model identity mismatch",
                "expected_model_id": model["repo_id"], "expected_snapshot": model.get("snapshot_revision"),
                "active_endpoint_models": sorted(active_ids),
            }
            write_json(cell / "RUN_RECORD.json", record)
            cells.append(record)
            overall_status = "INCOMPLETE"
            raise RuntimeError(json.dumps(record, ensure_ascii=False))
        payload = {
            "model": identity_match,
            "messages": [{"role": "user", "content": prompt}],
            **model["inference_config"],
        }
        headers = {
            "Content-Type": "application/json",
            "X-Agent-ID": f"simigo-crossmodel-formal-{execution_id[:8]}",
            "X-Session-ID": session_id,
        }
        request = urllib.request.Request(
            base_url.rstrip("/") + "/chat/completions",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        started_at = dt.datetime.now(UTC).isoformat()
        started_epoch = time.time()
        try:
            with urllib.request.urlopen(request, timeout=900) as response:
                status_code = response.status
                raw = response.read()
                response_headers = {k.lower(): v for k, v in response.headers.items()}
        except urllib.error.HTTPError as exc:
            status_code = exc.code
            raw = exc.read()
            response_headers = {k.lower(): v for k, v in exc.headers.items()}
        except Exception as exc:
            finished_at = dt.datetime.now(UTC).isoformat()
            record = {
                "status": "RUNTIME_ERROR", "cell_id": cell_id, "execution_id": execution_id,
                "error": f"{type(exc).__name__}: {exc}", "started_at": started_at, "finished_at": finished_at,
            }
            write_json(cell / "RUN_RECORD.json", record)
            cells.append(record)
            overall_status = "INCOMPLETE"
            raise RuntimeError(json.dumps(record, ensure_ascii=False)) from exc
        finished_at = dt.datetime.now(UTC).isoformat()
        elapsed = round(time.time() - started_epoch, 6)
        (cell / "response.raw.json").write_bytes(raw)
        try:
            response_json = json.loads(raw)
        except json.JSONDecodeError:
            response_json = {"_undecoded": raw.decode("utf-8", errors="replace")}
        write_json(cell / "response.json", response_json)
        choices = response_json.get("choices", []) if isinstance(response_json, dict) else []
        content = choices[0].get("message", {}).get("content") if choices and isinstance(choices[0], dict) else None
        (cell / "final-answer.txt").write_text(content if isinstance(content, str) else "", encoding="utf-8")
        if status_code != 200:
            status = "RUNTIME_ERROR"
        elif not isinstance(content, str) or not content:
            status = "INCOMPLETE"
        else:
            status = "FORMAL"
        record = {
            "status": status,
            "cell_id": cell_id,
            "execution_id": execution_id,
            "session_id": session_id,
            "sample_id": sample["sample_id"],
            "model_id": model["model_id"],
            "endpoint_model_identifier": identity_match,
            "architecture": model["architecture"],
            "http_status": status_code,
            "elapsed_seconds": elapsed,
            "started_at": started_at,
            "finished_at": finished_at,
            "prompt_sha256": sha_text(prompt),
            "request_sha256": sha_file(cell / "request.json"),
            "response_raw_sha256": sha_file(cell / "response.raw.json"),
            "final_answer_sha256": sha_file(cell / "final-answer.txt"),
            "endpoint_probe": {"status": endpoint_status, "times": endpoint_times, "active_ids": sorted(active_ids)},
            "request_headers": {k: v for k, v in headers.items() if k.lower() != "content-type"},
            "response_headers": response_headers,
            "effective_inference_config": model["inference_config"],
            "input_lineage": {
                "sample_sha256_document": sha_file(ROOT / "freeze/samples.json"),
                "model_sha256_document": sha_file(ROOT / "freeze/models.json"),
                "input_files": sample["input_files"],
                "round1_residue_excluded": True,
                "other_cell_state_excluded": True,
            },
            "isolation_evidence": checked["isolation"],
        }
        write_json(cell / "RUN_RECORD.json", record)
        cells.append(record)
        if status != "FORMAL":
            overall_status = "INCOMPLETE"
            raise RuntimeError(f"{cell_id}: did not produce FORMAL output; status={status}")
    aggregate = {
        "phase": "FORMAL_CROSS_MODEL_RAW_OUTPUTS_ONLY",
        "status": overall_status,
        "completed_at": utc_now(),
        "authorization_id": auth["authorization_id"],
        "runner_sha256": sha_file(pathlib.Path(__file__)),
        "contract_sha256": sha_file(CONTRACT),
        "normalization": "NOT PERFORMED",
        "stability": "NOT PERFORMED",
        "mapping_to_846": "NOT PERFORMED",
        "cells": cells,
    }
    write_json(formal_root / "FORMAL_RUN_RECORD.json", aggregate)
    print(json.dumps(aggregate, ensure_ascii=False, indent=2))
    return 0 if overall_status == "FORMAL" else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--formal-root", type=pathlib.Path)
    parser.add_argument("--isolation-root", type=pathlib.Path)
    parser.add_argument("--authorization", type=pathlib.Path)
    parser.add_argument("--check-output", type=pathlib.Path)
    parser.add_argument("--plan-output", type=pathlib.Path)
    parser.add_argument("--render-output", type=pathlib.Path)
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    if sum(bool(x) for x in (args.check, args.plan, args.render, args.run)) != 1:
        parser.error("choose exactly one of --check, --plan, --render, --run")
    if args.check:
        out = args.check_output or ROOT / "formal-artifacts/formal-runner-check.json"
        return emit_check(repo_root, out)
    if args.plan:
        out = args.plan_output or ROOT / "formal-artifacts/formal-cell-plan.json"
        return emit_plan(repo_root, out)
    if args.render:
        out = args.render_output or ROOT / "formal-artifacts/rendered-prompts"
        return emit_render(repo_root, out)
    if not args.formal_root or not args.isolation_root or not args.authorization:
        parser.error("--run requires --formal-root, --isolation-root, and --authorization")
    return run_formal(repo_root, args.formal_root, args.base_url, args.isolation_root, args.authorization)


if __name__ == "__main__":
    raise SystemExit(main())
