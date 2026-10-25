#!/usr/bin/env python3
"""Static validation for the detached-continuation agent pack."""
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
plan = json.loads((HERE / "experiment_plan.json").read_text())
schema = json.loads((HERE / "evidence_schema.json").read_text())
required_conditions = {"W-A", "W-B", "N1-MISSING-SETTLEMENT", "N2-INVALID-SIGNATURE-OR-BYTE-TAMPER", "N3-DEPENDENCY-MISMATCH", "N4-PREFIX-AND-CROSS-WORLD-AUDIT"}
found = set()
for phase in plan.get("phases", []):
    for cond in phase.get("conditions", []):
        if isinstance(cond, dict) and "id" in cond:
            found.add(cond["id"])
        elif isinstance(cond, str):
            found.add(cond)
errors = []
missing = sorted(required_conditions - found)
if missing:
    errors.append(f"missing plan conditions: {missing}")
if plan.get("run_policy", {}).get("no_silent_retry") is not True:
    errors.append("no_silent_retry must be true")
if plan.get("run_policy", {}).get("preserve_all_preexisting_A_to_E_run_artifacts") is not True:
    errors.append("historical A-E run preservation must be true")
if plan.get("run_policy", {}).get("evidence_root_outside_repository") is not True:
    errors.append("evidence must stay outside repository")
if not schema.get("required") or "conditions" not in schema.get("properties", {}):
    errors.append("evidence schema missing required condition records")
if errors:
    print("FAIL\n" + "\n".join(errors))
    sys.exit(2)
print(json.dumps({"result": "PASS", "condition_count": len(required_conditions), "plan_phases": len(plan["phases"]), "schema": schema["title"]}, indent=2))
