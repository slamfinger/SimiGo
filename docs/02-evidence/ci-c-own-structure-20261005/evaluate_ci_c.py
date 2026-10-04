#!/usr/bin/env python3
"""Evaluate whether the executable continuation core C4 survives each CI-C arm."""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
RUN = ROOT / "runs/20261005-014500-ci-c"
MODELS = ("A-qwen3-moe", "C-gemma4-unified")
ARMS = ("FULL", "K1_ONLY", "K2_ONLY", "GAMMA_REDUCED", "K3_DELETED", "K3_PRECOMPUTED_F", "ID_BINDING_BROKEN")
EXPECTED_C4_LOSS = {"K1_ONLY", "K2_ONLY", "ID_BINDING_BROKEN", "K3_DELETED"}


def core(answer):
    try:
        value = json.loads(answer)
    except json.JSONDecodeError as exc:
        return {"C4": "UNPARSEABLE", "error": str(exc)}
    order = value.get("deployment_order")
    blocked = [x.get("service_id") for x in value.get("blocked_services", []) if isinstance(x, dict)]
    preserved = order == ["alpha", "beta"] and blocked == ["gamma"]
    absent = order == [] and value.get("error") == "deployment_admissibility_relation_unavailable"
    observed = "C4_PRESERVED" if preserved else ("C4_ABSENT" if absent else "C4_DEGRADED")
    return {
        "C4": observed,
        "release_decision": value.get("release_decision"),
        "deployment_order": order,
        "blocked_service_ids": blocked,
        "error": value.get("error"),
    }


rows = []
for model in MODELS:
    for arm in ARMS:
        answer = (RUN / model / arm / "final-answer.txt").read_text(encoding="utf-8")
        observed = core(answer)
        expected = "C4_ABSENT" if arm in EXPECTED_C4_LOSS else "C4_PRESERVED"
        rows.append({
            "model_id": model,
            "arm": arm,
            "expected_if_hypothesis_true": expected,
            "observed": observed,
            "component_necessity_reading": {
                "C4_PRESERVED": "arm did not eliminate the executable continuation core",
                "C4_ABSENT": "arm eliminated the executable continuation core",
                "C4_DEGRADED": "arm changed or degraded the continuation core",
            }[observed["C4"]],
            "final_answer": answer,
        })

out = ROOT / "evaluation/RESULTS.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({
    "c4_core_criterion": "deployment_order == [alpha,beta] AND blocked_service_ids == [gamma]",
    "c4_absent_criterion": "deployment_order == [] AND error == deployment_admissibility_relation_unavailable",
    "note": "release_decision wording is not part of the executable continuation core criterion",
    "rows": rows,
}, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"rows": len(rows), "out": str(out)}))
