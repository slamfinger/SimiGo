#!/usr/bin/env python3
"""One-stage real-model smoke of the native-integrated SimiGoTaskRun.

Runs a single U1 item (ORIGIN,DEST -> U1) through the ordinary production
continuation on the REBUILT binary, so the NATIVE pre-settlement result-contract
gate executes against a real model for the first time. It records the native
validation block and whether a settlement + signature were created. This is a
runtime check of the production integration (not the pure-engine parity harness);
it spends one model load and one generation.

  python3 native_smoke_u1.py --model-dir <path> [--max-tokens 48]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import run_phase_e as e  # noqa: E402
import run_phase_j as j  # noqa: E402

LAB_ROOT = Path("/Users/mr.simi/Documents/SimiGo-Lab")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-dir", required=True, type=Path)
    ap.add_argument("--max-tokens", type=int, default=48)
    ap.add_argument("--run-root", type=Path,
                    default=Path.home() / "SimiGo-Agent-Runs" /
                    "es-is-native-result-contract-20261023k" / "smoke")
    args = ap.parse_args()

    run_root = args.run_root
    (run_root / "runs").mkdir(parents=True, exist_ok=True)
    binary = LAB_ROOT / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    bridge = LAB_ROOT / "execution-information-loop/production_runtime_bridge.py"
    loop_dir = LAB_ROOT / "execution-information-loop"

    trust = j.provision_trust_clean(run_root)
    trust["binary_sha256"] = e.sha256_file(binary)
    trust["build_sha256"] = hashlib.sha256("\n".join([
        e.sha256_file(binary), e.sha256_file(bridge),
        e.sha256_file(loop_dir / "declarative_result_contract.py"),
        e.sha256_file(loop_dir / "settlement_provenance.py"),
    ]).encode()).hexdigest()
    trust_dir = run_root / "trust"
    trust_dir.mkdir(parents=True, exist_ok=True)
    (trust_dir / "trust-root.json").write_text(json.dumps(trust, indent=2))

    world = run_root / "runs" / "SMOKE"
    for name in ("logs", "state", "evidence", "stdout", "stderr"):
        (world / name).mkdir(parents=True, exist_ok=True)
    token = secrets.token_hex(4)
    ids = j.define_graph(bridge, world / "carrier.sqlite", run_root, trust,
                         LAB_ROOT, world / "logs" / "define-j-graph.log", token)
    env = e.child_environment(LAB_ROOT, trust, "smoke-p1",
                              "SMOKE-P1-%s" % ids["u1"], with_key=True)
    entry = j.launch(binary, world, run_root, LAB_ROOT, args.model_dir,
                     ids["u1"], ids["demand_u1"], "smoke-p1", "smoke-p1",
                     args.max_tokens, env)
    ev = entry.get("evidence") or {}
    native = ev.get("native_result_contract_validation") or {}
    db = world / "carrier.sqlite"
    settled = j.settlement_exists(db, ids["u1"])
    signed = j.signature_exists(db, ids["u1"])
    summary = {
        "item": ids["u1"],
        "exit_code": entry["exit_code"],
        "terminal_state": ev.get("terminal_state"),
        "input_admission_status": ev.get("input_admission_status"),
        "contract_dispatch_basis": ev.get("contract_dispatch_basis"),
        "native_gate_ran": bool(native),
        "native_gate": native.get("gate"),
        "native_status": native.get("native_validation_status"),
        "native_values": native.get("native_values"),
        "native_verified_bindings_count": len(
            native.get("verified_bindings") or []),
        "native_rejection": ev.get("native_result_contract_rejection"),
        "failure": ev.get("failure"),
        "settlement_created": settled,
        "signature_created": signed,
        "generated_text": ev.get("generated_text"),
        "stderr_tail": Path(entry["child_stderr"]["path"]).read_text(
            encoding="utf-8", errors="replace")[-800:]
        if Path(entry["child_stderr"]["path"]).exists() else "",
    }
    out = run_root / "smoke-u1-result.json"
    out.write_text(json.dumps(summary, indent=2, sort_keys=True, default=str))
    print(json.dumps(summary, indent=2, sort_keys=True, default=str))
    ok = (summary["native_gate_ran"] and summary["native_status"] == "VALID"
          and settled and signed and summary["exit_code"] == 0)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
