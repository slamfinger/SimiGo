#!/usr/bin/env python3
"""H-round model-free selective-invalidation preflight (condition H5).

Every check runs against the SAME production machinery the real model uses:
``production_runtime_bridge.py`` over the carrier-loop settlement/signature path.
No model is loaded here, so ``model_loads``/``tokenize``/``generate`` counters are
honestly zero for this condition; the point of H5 is the dependency graph, the
signed closure, and the reuse-vs-recompute DECISION, all of which are model-free.

It proves:
  A. the baseline closure (SOURCE-A->U1->U2->U3, SOURCE-B->V1) is fully reusable;
  B. changing SOURCE-A makes exactly U1/U2/U3 stale while V1 stays reused;
  C. U3's declared dependency U2 expands to the signed transitive closure that
     contains U1 and U2;
  D. a stale U1 cannot be admitted underneath a U2 settlement (fail closed, no
     side effects) before any model work;
  E. a consumer that holds only the trust anchor (no signing key) can still
     resolve/verify the signed closure.

Usage:
  python3 h_selective_invalidation_selftest.py --out <path/h5.json>
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from admission_selftest import (  # noqa: E402
    ENV, provision_trust, run_bridge, sha256_bytes, sha256_file, utc_now,
)

RUN_LABEL = "h-selective-selftest"
SOURCE_B_RUN_LABEL = "selective-baseline-source-b"
U1, U2, U3, V1 = "TASK-U1", "TASK-U2", "TASK-U3", "TASK-V1"
SOURCE_A, SOURCE_B = "TASK-SOURCE", "TASK-SOURCE-B"


def run_bridge_env(arguments, env):
    """Run the bridge with an explicit environment (for the no-key consumer)."""
    import subprocess

    process = subprocess.run(
        ["/usr/bin/python3", str(HERE / "production_runtime_bridge.py"), *arguments],
        capture_output=True, text=True, env=env, cwd=str(HERE), timeout=120,
    )
    try:
        payload = json.loads(process.stdout or "{}")
    except json.JSONDecodeError:
        payload = {"ok": False, "raw_stdout": process.stdout,
                   "raw_stderr": process.stderr}
    return process.returncode, payload


def settle_item(directory, database, item_id, demand_id, advancement, core_value):
    """Settle one model item through the ordinary execute-with-model-result path.

    The value is synthetic (model-free) but still satisfies the production
    ``_validate_model_value`` for that item, so the fixture reaches a lawful
    signed settlement graph. This mirrors admission_selftest._settle_model_item.
    """
    value = {
        "generated_token_ids": [7, 8, 9],
        "model_snapshot_revision": "h-fixture-revision",
        "model_weights_manifest_sha256": "h-fixture-weights",
        "model_call_index": 1,
        **core_value,
    }
    value_path = directory / ("%s-value.json" % item_id)
    value_path.write_text(json.dumps(value), encoding="utf-8")
    token_ids = json.dumps(value["generated_token_ids"], separators=(",", ":"))
    provenance = {
        "producer": {
            "kind": "model_task",
            "run_id": ENV["SIMIGO_SETTLEMENT_RUN_ID"],
            "execution_id": ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
            "process_id": str(os.getpid()),
            "build_sha256": ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        },
        "model": {
            "snapshot_revision": value["model_snapshot_revision"],
            "weights_manifest_sha256": value["model_weights_manifest_sha256"],
        },
        "output": {
            "generated_token_ids_sha256": sha256_bytes(token_ids.encode("utf-8")),
            "generated_token_count": len(value["generated_token_ids"]),
        },
    }
    provenance_path = directory / ("%s-provenance.json" % item_id)
    provenance_path.write_text(json.dumps(provenance), encoding="utf-8")
    code, settled = run_bridge(
        "execute-with-model-result",
        "--database", str(database),
        "--demand-id", demand_id,
        "--advancement", advancement,
        "--evaluated-at", utc_now(),
        "--item-id", item_id,
        "--value-file", str(value_path),
        "--provenance-file", str(provenance_path),
        "--run-id", ENV["SIMIGO_SETTLEMENT_RUN_ID"],
        "--execution-id", ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
        "--build-sha256", ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        "--producer-process-id", str(os.getpid()),
    )
    if code != 0 or not settled.get("ok"):
        raise RuntimeError("settle %s failed: %s" % (item_id, settled))
    state_id = ((settled.get("result") or {}).get(
        "execution_state") or {}).get("state_id")
    if state_id:
        cc, confirm = run_bridge(
            "confirm-runtime-application", "--database", str(database),
            "--state-id", state_id)
        if cc != 0 or not confirm.get("ok"):
            raise RuntimeError("confirm %s failed: %s" % (item_id, confirm))
    return settled


def probe_actions(database, evaluated_at):
    """Return (computed_set, reused_set, actions) from a model-free graph probe."""
    code, out = run_bridge(
        "execute-probe", "--database", str(database),
        "--demand-id", "handoff-graph", "--advancement", "h5-probe",
        "--evaluated-at", evaluated_at,
    )
    if code != 0 or not out.get("ok"):
        raise RuntimeError("execute-probe failed: %s" % out)
    actions = (out.get("result") or {}).get("actions") or []
    computed = {a["item_id"] for a in actions if a.get("action") == "COMPUTE"}
    reused = {a["item_id"] for a in actions if a.get("action") == "REUSE"}
    return computed, reused, actions


def snapshot(database, destination):
    if destination.exists():
        destination.unlink()
    code, out = run_bridge(
        "snapshot-database", "--database", str(database),
        "--destination", str(destination))
    if code != 0 or not out.get("ok"):
        raise RuntimeError("snapshot-database failed: %s" % out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    work = Path(tempfile.mkdtemp(prefix="simigo-h5-selftest-"))
    checks = {}
    notes = []
    try:
        provision_trust(work / "trust")
        secret_a = "a" + sha256_bytes(b"secret-a")[:12]
        secret_b = "b" + sha256_bytes(b"secret-b")[:12]

        database = work / "graph.sqlite"
        evaluated_at = utc_now()
        code, defined = run_bridge(
            "define-h-graph", "--database", str(database),
            "--evaluated-at", evaluated_at, "--run-label", RUN_LABEL,
            "--secret-a", secret_a, "--secret-b", secret_b,
        )
        if code != 0 or not defined.get("ok"):
            raise RuntimeError("define-h-graph failed: %s" % defined)
        checksum_a = defined["checksum_a"]
        checksum_b = defined["checksum_b"]

        # H1-equivalent baseline: settle the whole graph model-free in
        # topological order (each recompute requires its dependency reusable).
        settle_item(work, database, U1, "handoff-u1", "h5-u1",
                    {"secret": secret_a, "raw_generated_text": "SECRET=" + secret_a})
        answer = "%s-%s" % (secret_a, checksum_a)
        settle_item(work, database, U2, "handoff-u2", "h5-u2",
                    {"answer": answer, "raw_generated_text": "ANSWER=" + answer})
        settle_item(work, database, U3, "handoff-u3", "h5-u3",
                    {"stamp": secret_a, "raw_generated_text": "STAMP=" + secret_a})
        # V1 is the independent branch: it echoes SOURCE-B's own checksum,
        # exactly as the real-model ordinary path now does (short, source-
        # specific extraction that does not touch the U chain).
        settle_item(work, database, V1, "handoff-v1", "h5-v1",
                    {"vcheck": checksum_b,
                     "raw_generated_text": "VCHECKSUM=" + checksum_b})

        # A. Baseline closure is fully reusable: nothing recomputes.
        base_db = work / "base-probe.sqlite"
        snapshot(database, base_db)
        base_computed, base_reused, base_actions = probe_actions(
            base_db, utc_now())
        checks["A_baseline_all_reusable"] = (
            base_computed == set()
            and {U1, U2, U3, V1}.issubset(base_reused))
        notes.append("A_computed=%s A_reused=%s" % (
            sorted(base_computed), sorted(base_reused)))

        # B. Selective invalidation: only the SOURCE-A closure goes stale.
        upd_db = work / "selective.sqlite"
        snapshot(database, upd_db)
        new_secret_a = "c" + sha256_bytes(b"secret-a-updated")[:12]
        code, upd = run_bridge(
            "h-source-update", "--database", str(upd_db),
            "--evaluated-at", utc_now(), "--run-label", RUN_LABEL,
            "--new-secret-a", new_secret_a,
        )
        if code != 0 or not upd.get("ok"):
            raise RuntimeError("h-source-update failed: %s" % upd)
        sel_computed, sel_reused, sel_actions = probe_actions(upd_db, utc_now())
        checks["B_selective_only_uchain_stale"] = (
            sel_computed == {U1, U2, U3}
            and V1 in sel_reused
            and V1 not in sel_computed
            and SOURCE_B in sel_reused)
        notes.append("B_computed=%s B_reused=%s" % (
            sorted(sel_computed), sorted(sel_reused)))

        # C. U3 declared dependency U2 expands to the signed transitive closure
        #    containing U1 and U2. The resolver's `dependencies` field is built
        #    from `_resolve_settled_dependency`, which recurses through every
        #    declared dependency and admits each through the SAME reuse decision
        #    as execute_demand -- so it IS the transitive closure, whereas
        #    `bindings` only carries U3's direct template placeholder (U2).
        code, resolved = run_bridge(
            "resolve-model-input", "--database", str(database),
            "--item-id", U3, "--evaluated-at", utc_now())
        closure_ids = set()
        if code == 0 and resolved.get("ok"):
            for dep in (resolved.get("dependencies") or []):
                if isinstance(dep, dict) and dep.get("item_id"):
                    closure_ids.add(dep["item_id"])
        checks["C_u3_closure_has_u1_u2"] = (
            {U1, U2}.issubset(closure_ids)
            # the closure must be signed and admit the source it derives from
            and SOURCE_A in closure_ids
            and bool(resolved.get("settlement_signatures")))
        notes.append("C_closure=%s" % sorted(x for x in closure_ids if x))

        # D. Stale U1 cannot be admitted underneath U2 (fail closed, no effect).
        stale_db = work / "stale-refuse.sqlite"
        snapshot(database, stale_db)
        code, _ = run_bridge(
            "h-source-update", "--database", str(stale_db),
            "--evaluated-at", utc_now(), "--run-label", RUN_LABEL,
            "--new-secret-a", new_secret_a)
        stale_pre = sha256_file(stale_db)
        value_path = work / "u2-stale-value.json"
        stale_answer = "%s-%s" % (new_secret_a, checksum_a)
        value_path.write_text(json.dumps({
            "secret": new_secret_a, "answer": stale_answer,
            "raw_generated_text": "ANSWER=" + stale_answer,
            "generated_token_ids": [7, 8, 9],
            "model_snapshot_revision": "h-fixture-revision",
            "model_weights_manifest_sha256": "h-fixture-weights",
            "model_call_index": 1,
        }), encoding="utf-8")
        prov_path = work / "u2-stale-prov.json"
        token_ids = json.dumps([7, 8, 9], separators=(",", ":"))
        prov_path.write_text(json.dumps({
            "producer": {"kind": "model_task",
                         "run_id": ENV["SIMIGO_SETTLEMENT_RUN_ID"],
                         "execution_id": ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
                         "process_id": str(os.getpid()),
                         "build_sha256": ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"]},
            "model": {"snapshot_revision": "h-fixture-revision",
                      "weights_manifest_sha256": "h-fixture-weights"},
            "output": {"generated_token_ids_sha256": sha256_bytes(token_ids.encode()),
                       "generated_token_count": 3},
        }), encoding="utf-8")
        code, refused = run_bridge(
            "execute-with-model-result", "--database", str(stale_db),
            "--demand-id", "handoff-u2", "--advancement", "h5-u2-stale",
            "--evaluated-at", utc_now(), "--item-id", U2,
            "--value-file", str(value_path), "--provenance-file", str(prov_path),
            "--run-id", ENV["SIMIGO_SETTLEMENT_RUN_ID"],
            "--execution-id", ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
            "--build-sha256", ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
            "--producer-process-id", str(os.getpid()),
        )
        stale_post = sha256_file(stale_db)
        checks["D_stale_u1_refuses_u2"] = (
            (code != 0 or not refused.get("ok")) and stale_pre == stale_post)
        notes.append("D_refused=%s db_unchanged=%s" % (
            not (code == 0 and refused.get("ok")), stale_pre == stale_post))

        # E. Consumer with only the trust anchor (no signing key) verifies.
        consumer_env = dict(ENV)
        consumer_env.pop("SIMIGO_SETTLEMENT_SIGNING_KEY", None)
        consumer_db = work / "consumer-no-key.sqlite"
        snapshot(database, consumer_db)
        code, ck = run_bridge_env(
            ["resolve-model-input", "--database", str(consumer_db),
             "--item-id", U3, "--evaluated-at", utc_now()], consumer_env)
        checks["E_consumer_no_key_verifies"] = code == 0 and bool(ck.get("ok"))
        notes.append("E_ok=%s" % bool(ck.get("ok")))

        verdict = "PASS" if all(checks.values()) else "FAIL"
        out = {
            "schema_id": "SIMIGO-H5-SELECTIVE-INVALIDATION-V1",
            "created_at_utc": utc_now(),
            "terminal_state": "OBSERVED" if verdict == "PASS" else "FAILED",
            "model_loads": 0,
            "tokenize_text_calls": 0,
            "tokenize_seed_calls": 0,
            "model_generate_calls": 0,
            "graph": {
                "affected_chain": [SOURCE_A, U1, U2, U3],
                "unaffected_branch": [SOURCE_B, V1],
            },
            "checks": checks,
            "notes": notes,
            "verdict": verdict,
        }
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps(out, indent=2, sort_keys=True),
                                  encoding="utf-8")
        print(json.dumps(out, indent=2, sort_keys=True))
        return 0 if verdict == "PASS" else 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
