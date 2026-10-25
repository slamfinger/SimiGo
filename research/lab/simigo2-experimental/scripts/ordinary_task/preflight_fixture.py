#!/usr/bin/env python3
"""Model-free preflight for the D-round ordinary-task fixture.

Creates a fresh carrier database with the ordinary task definition, then asks
the production bridge to resolve TASK-U1's model input. Success proves the
source registration, validity policy and dependency basis are admissible
before any model load is paid for. TASK-U2 must refuse at this point because
TASK-U1 has not been settled yet.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_phase_d as runner  # noqa: E402


def resolve(lab_root: Path, database: Path, item_id: str) -> dict:
    policy = lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
    environment = os.environ.copy()
    environment["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(policy)
    completed = subprocess.run(
        [
            "/usr/bin/python3",
            str(lab_root / "execution-information-loop/production_runtime_bridge.py"),
            "resolve-model-input",
            "--database", str(database),
            "--item-id", item_id,
            "--evaluated-at", runner.utc_now(),
        ],
        capture_output=True,
        text=True,
        env=environment,
        check=False,
    )
    output = None
    for line in completed.stdout.splitlines():
        if line.strip().startswith("{"):
            output = json.loads(line)
    return {
        "item_id": item_id,
        "exit_code": completed.returncode,
        "stderr": completed.stderr.strip(),
        "response": output,
    }


def main() -> int:
    lab_root = Path(sys.argv[1]).expanduser().resolve()
    work = Path(sys.argv[2]).expanduser().resolve()
    work.mkdir(parents=True, exist_ok=True)
    database = work / "carrier.sqlite"
    if database.exists():
        raise SystemExit("refusing to reuse %s" % database)

    definition = runner.define_ordinary_task(database, lab_root, "d-preflight")
    u1 = resolve(lab_root, database, "TASK-U1")
    u2 = resolve(lab_root, database, "TASK-U2")
    response = u1["response"] or {}
    checks = response.get("checks") or {}
    record = {
        "schema_id": "SIMIGO-ORDINARY-TASK-PREFLIGHT-V1",
        "definition": definition,
        "u1": {
            "exit_code": u1["exit_code"],
            "declared_dependencies": response.get("declared_dependencies"),
            "input_sha256": response.get("input_sha256"),
            "input_byte_length": response.get("input_byte_length"),
            "checks": checks,
            "binding_item_ids": [item.get("item_id") for item in response.get("bindings") or []],
            "dependency_object_ids": {
                item.get("item_id"): item.get("settlement_object_id")
                for item in response.get("dependencies") or []
            },
            "stderr": u1["stderr"],
        },
        "u2_before_u1": {
            "exit_code": u2["exit_code"],
            "refusal_stage": ((u2["response"] or {}).get("refusal") or {}).get("stage"),
            "refusal_reason": ((u2["response"] or {}).get("refusal") or {}).get("reason"),
        },
        "checks": {
            "u1_admitted": u1["exit_code"] == 0 and bool(checks) and all(checks.values()),
            "u1_bound_to_source": [item.get("item_id") for item in response.get("bindings") or []]
            == [runner.ITEM_SOURCE],
            "u2_refused_before_u1_settlement": u2["exit_code"] == 1
            and ((u2["response"] or {}).get("refusal") or {}).get("stage")
            == "SETTLEMENT_NOT_ADMITTED",
        },
    }
    record["verdict"] = "PASS" if all(record["checks"].values()) else "FAIL"
    runner.write_json(work / "preflight.json", record)
    print(json.dumps(record["checks"], indent=1, sort_keys=True))
    print(record["verdict"])
    return 0 if record["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
