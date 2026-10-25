#!/usr/bin/env python3
"""Evaluate CI-C arms, separating C4 core survival from authorization-contract validity."""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
RUNS = {
    "A-qwen3-moe": ROOT / "runs/20261005-014500-ci-c/A-qwen3-moe",
    "C-gemma4-unified": ROOT / "runs/20261005-014500-ci-c/C-gemma4-unified",
    "N-nail-qwen3-5-moe": ROOT / "runs/20261005-021500-ci-c-nail-replication/N-nail-qwen3-5-moe",
}
ARMS = ("FULL", "K1_ONLY", "K2_ONLY", "GAMMA_REDUCED", "K3_DELETED", "K3_PRECOMPUTED_F", "ID_BINDING_BROKEN")
UNAUTHORIZED_INFERENCE_ARMS = {"K1_ONLY", "K2_ONLY", "ID_BINDING_BROKEN"}


def read_core(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return {"raw": path.read_text(encoding="utf-8"), "parse_error": str(exc)}
    return value


def evaluate(answer):
    order = answer.get("deployment_order")
    blocked = [x.get("service_id") for x in answer.get("blocked_services", []) if isinstance(x, dict)]
    preserved = order == ["alpha", "beta"] and blocked == ["gamma"]
    absent = order == [] and answer.get("error") == "deployment_admissibility_relation_unavailable"
    core = "C4_PRESERVED" if preserved else ("C4_ABSENT" if absent else "C4_DEGRADED")
    return {
        "C4_core": core,
        "release_decision": answer.get("release_decision"),
        "deployment_order": order,
        "blocked_service_ids": blocked,
        "error": answer.get("error"),
    }


rows = []
for model, run_root in RUNS.items():
    for arm in ARMS:
        answer = read_core(run_root / arm / "final-answer.txt")
        observed = evaluate(answer)
        core = observed["C4_core"]
        if arm == "K3_DELETED":
            contract = "OK_ABSENCE" if core == "C4_ABSENT" else "UNEXPECTED_PRESENCE"
        elif arm in UNAUTHORIZED_INFERENCE_ARMS and core == "C4_PRESERVED":
            contract = "UNAUTHORIZED_INFERENCE"
        else:
            contract = "OK"
        rows.append({
            "model_id": model,
            "arm": arm,
            "C4_core": core,
            "authorization_contract": contract,
            "combined_status": f"{core}/{contract}",
            "observed": observed,
        })

summary = {}
for model in RUNS:
    summary[model] = {arm: next(r["combined_status"] for r in rows if r["model_id"] == model and r["arm"] == arm) for arm in ARMS}

out = ROOT / "evaluation/RESULTS.json"
out.write_text(json.dumps({
    "C4_core_criterion": "deployment_order == [alpha,beta] AND blocked_service_ids == [gamma]",
    "C4_absent_criterion": "deployment_order == [] AND error == deployment_admissibility_relation_unavailable",
    "contract_rule": "A preserved C4 in K1_ONLY/K2_ONLY/ID_BINDING_BROKEN is marked UNAUTHORIZED_INFERENCE because it requires recovering a relation/predicate explicitly marked unavailable.",
    "release_decision_note": "blocked/partial wording is not part of the C4 core criterion.",
    "summary": summary,
    "rows": rows,
}, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(summary, indent=2))
