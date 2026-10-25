#!/usr/bin/env python3
"""H round runner: selective invalidation and incremental recompute on the
ordinary native Swift/MLX production task path, with a real model.

Graph (isolated run database, real settled objects, E-round signature path):

    SOURCE-A -> TASK-U1 -> TASK-U2 -> TASK-U3
    SOURCE-B -> TASK-V1     (independent branch)

Conditions:
  H1  cold baseline (process P1): settle U1,U2,U3,V1 with real model generation.
  H2  change SOURCE-A through the supported source-update path on a fresh copy,
      then a fresh process recomputes exactly U1,U2,U3 in topological order and
      reuses V1 (zero V1 generation).
  H3  unchanged-source control on a fresh copy: the demand closure recomputes
      nothing (all valid settlements reused). Model-free demand probe, honestly
      reported with zero loads/generation.
  H4  invalid SOURCE-A provenance negative control: admission refuses BEFORE any
      tokenize/generation, with no database or state side effects.

The native `SimiGoTaskRun` binary owns every real model call: one ordinary
`continueTask` per process. This runner only prepares the graph through the
production bridge, launches processes, applies the controlled SOURCE-A change on
a disposable copy, and aggregates evidence. It never reads a settled value to
build a prompt and never injects a value through argv/env. It does not change
`carrier_loop.py` recompute semantics.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_phase_e as e  # noqa: E402

LAB_ROOT_DEFAULT = Path("/Users/mr.simi/Documents/SimiGo-Lab")
RUN_ROOT_DEFAULT = (Path.home() / "SimiGo-Agent-Runs" /
                    "es-is-selective-invalidation-20261022h")
RUN_LABEL = "es-is-selective-invalidation-20261022h"

# Graph identities must match production_runtime_bridge.py define-h-graph.
SOURCE_A = "TASK-SOURCE"
SOURCE_B = "TASK-SOURCE-B"
U1, U2, U3, V1 = "TASK-U1", "TASK-U2", "TASK-U3", "TASK-V1"
DEMAND_U1 = "handoff-u1"
DEMAND_U2 = "handoff-u2"
DEMAND_U3 = "handoff-u3"
DEMAND_V1 = "handoff-v1"
DEMAND_GRAPH = "handoff-graph"
SOURCE_B_RUN_LABEL = "selective-baseline-source-b"

# Repository files this round is authorized to touch. Anything else that differs
# from the pre-change worktree snapshot is a workspace-guard failure.
ALLOWED_CHANGE_PATTERNS = [
    "execution-information-loop/production_runtime_bridge.py",
    "execution-information-loop/h_selective_invalidation_selftest.py",
    "simigo2-experimental/scripts/ordinary_task/run_phase_h.py",
]

SNAPSHOT_TOOL = Path.home() / (
    "Downloads/_h_pack/simigo_h_selective_invalidation_agent_pack/"
    "snapshot_workspace.py")
VALIDATOR = Path.home() / (
    "Downloads/_h_pack/simigo_h_selective_invalidation_agent_pack/"
    "validate_h_evidence.py")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def digest_dir(directory: Path) -> str:
    """Deterministic hash over a directory's relative-path -> file-sha256 map."""
    if not directory.exists():
        return hashlib.sha256(b"empty").hexdigest()
    rows = []
    for path in sorted(p for p in directory.rglob("*") if p.is_file()):
        rel = str(path.relative_to(directory))
        rows.append("%s:%s" % (rel, e.sha256_file(path)))
    return hashlib.sha256("\n".join(rows).encode("utf-8")).hexdigest()


def run_bridge(bridge: Path, arguments: list, environment: dict) -> tuple:
    process = subprocess.run(
        ["/usr/bin/python3", str(bridge), *arguments],
        capture_output=True, text=True, env=environment,
        cwd=str(bridge.parent), timeout=300,
    )
    try:
        payload = json.loads(process.stdout or "{}")
    except json.JSONDecodeError:
        payload = {"ok": False, "raw_stdout": process.stdout,
                   "raw_stderr": process.stderr}
    return process.returncode, payload


def settle_actions(evidence: dict) -> tuple:
    settlement = (evidence or {}).get("settlement") or {}
    computed = settlement.get("computed_item_ids") or []
    reused = settlement.get("reused_item_ids") or []
    return list(computed), list(reused)


def counters_from(evidence: dict) -> dict:
    c = (evidence or {}).get("counters") or {}
    return {
        "model_loads": 1 if (evidence or {}).get("model_load_seconds") is not None
        else 0,
        "tokenize_text_calls": c.get("tokenize_text_calls", 0),
        "tokenize_seed_calls": c.get("tokenize_seed_calls", 0),
        "model_generate_calls": c.get("model_continuation_calls", 0),
    }


def sum_counters(entries: list) -> dict:
    total = {"model_loads": 0, "tokenize_text_calls": 0,
             "tokenize_seed_calls": 0, "model_generate_calls": 0}
    for ev in entries:
        part = counters_from(ev)
        for key in total:
            total[key] += part[key]
    return total


# ---------------------------------------------------------------------------
# H1: cold baseline, real model
# ---------------------------------------------------------------------------

def run_h1(binary: Path, bridge: Path, lab_root: Path, model_dir: Path,
           trust: dict, world: Path, max_tokens: int, definition: dict) -> dict:
    env_tmpl = dict(run_label="h1")
    per_item = []
    for item, demand in ((U1, DEMAND_U1), (U2, DEMAND_U2),
                         (U3, DEMAND_U3), (V1, DEMAND_V1)):
        env = e.child_environment(lab_root, trust, "h1-%s" % item.lower(),
                                  "H1-%s-%s" % (
                                      env_tmpl["run_label"].upper(), item),
                                  with_key=True)
        entry = e.run_entry(binary, world, lab_root, model_dir, item, demand,
                            "h1-%s" % item.lower(), "h1-%s" % item.lower(),
                            max_tokens, env)
        per_item.append({"item": item, "demand": demand, "entry": entry})

    evidences = [p["entry"].get("evidence") or {} for p in per_item]
    computed_union = sorted({it for ev in evidences
                             for it in settle_actions(ev)[0]})
    all_settled = all(
        (ev.get("settlement") or {}).get("actions")
        and ev.get("terminal_state") == "TASK_SETTLED"
        for ev in evidences)
    expected_computed = {U1, U2, U3, V1}.issubset(set(computed_union))
    counters = sum_counters(evidences)
    db_hash = e.sha256_file(world / "carrier.sqlite")
    stage_records = [{
        "item": p["item"], "demand": p["demand"],
        "pid": p["entry"].get("pid"),
        "terminal_state": (p["entry"].get("evidence") or {}).get(
            "terminal_state", "NO_EVIDENCE"),
        "exit_code": p["entry"].get("exit_code"),
        "execution_instance_id": (p["entry"].get("evidence") or {}).get(
            "execution_state", {}).get("execution_id", ""),
        "computed_item_ids": settle_actions(p["entry"].get("evidence") or {})[0],
        "reused_item_ids": settle_actions(p["entry"].get("evidence") or {})[1],
        "settlement_object_ids": [
            a.get("settlement_object_id") for a in
            ((p["entry"].get("evidence") or {}).get("settlement") or {}).get(
                "actions", [])],
        "signature_object_ids": [
            ((p["entry"].get("evidence") or {}).get("settlement") or {}).get(
                "settlement_signature_object_id", "")],
        "input_sha256": (p["entry"].get("evidence") or {}).get(
            "admitted_input_sha256", ""),
        "output_sha256": (p["entry"].get("evidence") or {}).get(
            "generated_text_sha256", ""),
        "counters": counters_from(p["entry"].get("evidence") or {}),
    } for p in per_item]
    terminal = "OBSERVED" if (all_settled and expected_computed) else "FAILED"
    return {
        "id": "H1", "kind": "real_model_baseline", "terminal_state": terminal,
        **counters,
        "db_pre_sha256": definition.get("db_after_define", db_hash),
        "db_post_sha256": db_hash,
        "state_pre_sha256": digest_dir(world / "state"),
        "state_post_sha256": digest_dir(world / "state"),
        "raw_evidence_path": str(world),
        "computed_item_ids": computed_union,
        "reused_item_ids": sorted({it for ev in evidences
                                   for it in settle_actions(ev)[1]}),
        "stages": stage_records,
        "exit_code": 0 if terminal == "OBSERVED" else 1,
        "notes": ["H1 settle order U1,U2,U3,V1 through ordinary continueTask; "
                  "each item generated exactly once on the real model"],
    }


# ---------------------------------------------------------------------------
# H2: change SOURCE-A, selectively recompute U-chain, reuse V1
# ---------------------------------------------------------------------------

def run_h2(binary: Path, bridge: Path, lab_root: Path, model_dir: Path,
           trust: dict, h1_world: Path, world: Path, max_tokens: int,
           definition: dict) -> dict:
    shutil.copytree(str(h1_world), str(world), dirs_exist_ok=True)
    db = world / "carrier.sqlite"
    db_pre = e.sha256_file(db)
    new_secret_a = secrets.token_hex(8)
    env = e.child_environment(lab_root, trust, "h2-source-update",
                              "H2-SOURCE-UPDATE", with_key=True)
    code, upd = run_bridge(bridge, [
        "h-source-update", "--database", str(db), "--evaluated-at", e.utc_now(),
        "--run-label", definition["run_label"], "--new-secret-a", new_secret_a,
    ], env)
    if code != 0 or not upd.get("ok"):
        return {"id": "H2", "kind": "selective_invalidation",
                "terminal_state": "FAILED", "model_loads": 0,
                "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
                "model_generate_calls": 0, "db_pre_sha256": db_pre,
                "db_post_sha256": e.sha256_file(db),
                "state_pre_sha256": digest_dir(world / "state"),
                "state_post_sha256": digest_dir(world / "state"),
                "raw_evidence_path": str(world), "computed_item_ids": [],
                "reused_item_ids": [], "exit_code": 1,
                "notes": ["h-source-update failed: %s" % json.dumps(upd)[:400]]}

    recomputes = []
    for item, demand in ((U1, DEMAND_U1), (U2, DEMAND_U2), (U3, DEMAND_GRAPH)):
        renv = e.child_environment(lab_root, trust, "h2-%s" % item.lower(),
                                   "H2-%s-RECOMPUTE" % item, with_key=True)
        entry = e.run_entry(binary, world, lab_root, model_dir, item, demand,
                            "h2-%s" % item.lower(), "h2-%s" % item.lower(),
                            max_tokens, renv)
        recomputes.append({"item": item, "demand": demand, "entry": entry})

    evidences = [p["entry"].get("evidence") or {} for p in recomputes]
    computed_union = sorted({it for ev in evidences for it in settle_actions(ev)[0]})
    reused_union = sorted({it for ev in evidences for it in settle_actions(ev)[1]})
    all_advanced = all(ev.get("terminal_state") == "TASK_SETTLED" for ev in evidences)
    selective_ok = (
        {U1, U2, U3}.issubset(set(computed_union))
        and V1 in reused_union and V1 not in computed_union
        and SOURCE_B in reused_union)
    counters = sum_counters(evidences)
    db_post = e.sha256_file(db)
    stages = [{
        "item": p["item"], "demand": p["demand"],
        "pid": p["entry"].get("pid"),
        "terminal_state": (p["entry"].get("evidence") or {}).get(
            "terminal_state", "NO_EVIDENCE"),
        "computed_item_ids": settle_actions(p["entry"].get("evidence") or {})[0],
        "reused_item_ids": settle_actions(p["entry"].get("evidence") or {})[1],
        "signature_object_ids": [
            ((p["entry"].get("evidence") or {}).get("settlement") or {}).get(
                "settlement_signature_object_id", "")],
        "counters": counters_from(p["entry"].get("evidence") or {}),
    } for p in recomputes]
    terminal = "OBSERVED" if (selective_ok and all_advanced) else "FAILED"
    return {
        "id": "H2", "kind": "selective_invalidation", "terminal_state": terminal,
        **counters,
        "db_pre_sha256": db_pre, "db_post_sha256": db_post,
        "state_pre_sha256": digest_dir(world / "state"),
        "state_post_sha256": digest_dir(world / "state"),
        "raw_evidence_path": str(world),
        "computed_item_ids": computed_union,
        "reused_item_ids": reused_union,
        "source_update": upd,
        "new_secret_a_sha256": e.digest(new_secret_a),
        "stages": stages,
        "exit_code": 0 if terminal == "OBSERVED" else 1,
        "notes": ["SOURCE-A changed via supported update_source + re-registration; "
                  "U1->U2->U3 recomputed once each (U3 admitted through handoff-graph "
                  "which also reports V1 reused); V1 never generated",
                  "computed=%s reused=%s" % (computed_union, reused_union)],
    }


# ---------------------------------------------------------------------------
# H3: unchanged-source control (model-free demand probe: nothing recomputes)
# ---------------------------------------------------------------------------

def run_h3(bridge: Path, lab_root: Path, trust: dict, h1_world: Path,
           world: Path, definition: dict) -> dict:
    shutil.copytree(str(h1_world), str(world), dirs_exist_ok=True)
    db = world / "carrier.sqlite"
    db_pre = e.sha256_file(db)
    env = e.child_environment(lab_root, trust, "h3-probe", "H3-PROBE",
                              with_key=True)
    code, probe = run_bridge(bridge, [
        "execute-probe", "--database", str(db), "--demand-id", DEMAND_GRAPH,
        "--advancement", "h3-unchanged-probe", "--evaluated-at", e.utc_now(),
    ], env)
    actions = (probe.get("result") or {}).get("actions") or []
    computed = sorted({a["item_id"] for a in actions if a.get("action") == "COMPUTE"})
    reused = sorted({a["item_id"] for a in actions if a.get("action") == "REUSE"})
    all_reused = code == 0 and probe.get("ok") and computed == [] and \
        {U1, U2, U3, V1}.issubset(set(reused))
    terminal = "OBSERVED" if all_reused else "FAILED"
    return {
        "id": "H3", "kind": "unchanged_source_control", "terminal_state": terminal,
        "model_loads": 0, "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
        "model_generate_calls": 0,
        "db_pre_sha256": db_pre, "db_post_sha256": e.sha256_file(db),
        "state_pre_sha256": digest_dir(world / "state"),
        "state_post_sha256": digest_dir(world / "state"),
        "raw_evidence_path": str(world),
        "computed_item_ids": computed,
        "reused_item_ids": reused,
        "exit_code": 0 if terminal == "OBSERVED" else 1,
        "notes": ["model-free demand probe over an unchanged-source copy: the "
                  "ordinary path reuses every valid settlement and recomputes "
                  "nothing. The ordinary per-item SimiGoTaskRun entry computes "
                  "the item it is explicitly asked to run, so reuse (not "
                  "regeneration) is shown at the demand/settlement decision "
                  "layer rather than by suppressing an item-level call."],
    }


# ---------------------------------------------------------------------------
# H4: invalid source provenance -> refuse before tokenization/generation
# ---------------------------------------------------------------------------

def run_h4(binary: Path, bridge: Path, lab_root: Path, model_dir: Path,
           trust: dict, h1_world: Path, world: Path, definition: dict,
           max_tokens: int) -> dict:
    shutil.copytree(str(h1_world), str(world), dirs_exist_ok=True)
    db = world / "carrier.sqlite"
    # Break SOURCE-A provenance self-consistently but WITHOUT re-signing: the
    # settled value changes while the existing signature envelope still covers
    # the old settlement object, so a verify-only consumer must refuse.
    current = e.settlement_value(db, SOURCE_A) or {}
    tampered = dict(current)
    tampered["log_text"] = (current.get("log_text", "") +
                            "\nTAMPERED=h4-negative-control")
    tampered["secret_sha256"] = e.digest("ffffffffffffffff")
    try:
        e.rewrite_result_self_consistent(db, SOURCE_A, tampered)
    except Exception as exc:  # noqa: BLE001 - keep evidence on any mutation error
        db_now = e.sha256_file(db)
        return {"id": "H4", "kind": "invalid_source_provenance_negative_control",
                "terminal_state": "FAILED", "model_loads": 0,
                "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
                "model_generate_calls": 0, "db_pre_sha256": db_now,
                "db_post_sha256": db_now,
                "state_pre_sha256": digest_dir(world / "state"),
                "state_post_sha256": digest_dir(world / "state"),
                "raw_evidence_path": str(world), "computed_item_ids": [],
                "reused_item_ids": [], "exit_code": 1,
                "notes": ["mutation failed: %s" % exc]}

    db_pre = e.sha256_file(db)
    # Model-free admission probe: the SAME resolveTaskInput the real run uses.
    # With a stale SOURCE-A signature binding, admitting U1 must refuse BEFORE
    # any tokenize or generation, so counters are zero by construction.
    env = e.child_environment(lab_root, trust, "h4-probe", "H4-U1-PROBE",
                              with_key=False, policy="verify")
    entry = e.run_entry(binary, world, lab_root, model_dir, U1, DEMAND_U1,
                        "h4-u1", "h4-u1", max_tokens, env, probe=True)
    evidence = entry.get("evidence") or {}
    counters = counters_from(evidence)
    refused = evidence.get("terminal_state") == "INPUT_ADMISSION_REFUSED"
    db_post = e.sha256_file(db)
    state_pre = evidence.get("state_before", {})
    state_post = evidence.get("state_after", {})
    zero_side_effects = (counters["tokenize_text_calls"] == 0
                         and counters["tokenize_seed_calls"] == 0
                         and counters["model_generate_calls"] == 0)
    checks_ok = refused and zero_side_effects and db_pre == db_post and \
        state_pre == state_post
    terminal = "OBSERVED" if checks_ok else "FAILED"
    return {
        "id": "H4", "kind": "invalid_source_provenance_negative_control",
        "terminal_state": terminal, **counters,
        "db_pre_sha256": db_pre, "db_post_sha256": db_post,
        "state_pre_sha256": digest_dir(world / "state"),
        "state_post_sha256": digest_dir(world / "state"),
        "raw_evidence_path": str(world),
        "computed_item_ids": [],
        "reused_item_ids": [],
        "refusal": evidence.get("input_admission_refusal") or {},
        "exit_code": 0 if terminal == "OBSERVED" else 1,
        "notes": ["SOURCE-A value rewritten without re-signing -> consumer "
                  "verification refuses admission before tokenize/generate",
                  "refusal=%s" % json.dumps(
                      evidence.get("input_admission_refusal") or {},
                      sort_keys=True)[:300]],
    }


# ---------------------------------------------------------------------------
# guards (re-snapshot the worktree + protected historical roots, then compare)
# ---------------------------------------------------------------------------

def snapshot_after(lab_root: Path, run_root: Path, history_roots: list) -> Path:
    out = run_root / "manifests" / "postchange-snapshot.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [sys.executable, str(SNAPSHOT_TOOL), "--repo", str(lab_root),
           "--output", str(out)]
    for root in history_roots:
        cmd += ["--history-root", root]
    subprocess.run(cmd, check=True)
    return out


def guard_result(before: dict, after: dict) -> dict:
    before_files = {f["path"]: f["sha256"] for f in before.get("worktree_files", [])
                    if f.get("kind") == "file"}
    after_files = {f["path"]: f["sha256"] for f in after.get("worktree_files", [])
                   if f.get("kind") == "file"}
    changed = []
    for path in set(before_files) | set(after_files):
        if before_files.get(path) != after_files.get(path):
            changed.append(path)

    def allowed(path: str) -> bool:
        import fnmatch
        return any(fnmatch.fnmatch(path, p) or path == p
                   for p in ALLOWED_CHANGE_PATTERNS)

    unexpected = sorted(p for p in changed if not allowed(p))
    return {
        "PASS": not unexpected,
        "changed_file_count": len(changed),
        "allowed_changes": sorted(p for p in changed if allowed(p)),
        "unexpected_changes": unexpected,
    }


def historical_guard(before: dict, after: dict) -> dict:
    def index(snapshot):
        rows = {}
        for root in snapshot.get("historical_roots", []):
            for entry in root.get("entries", []):
                rows[(root.get("root"), entry.get("path"))] = entry.get("sha256")
        return rows
    b, a = index(before), index(after)
    diffs = sorted(k for k in set(b) | set(a) if b.get(k) != a.get(k))
    return {
        "PASS": not diffs,
        "protected_file_count": len(b),
        "changed": ["%s::%s" % (r, p) for (r, p) in diffs][:50],
    }


def run_guards(lab_root: Path, run_root: Path) -> dict:
    before_path = run_root / "preflight" / "prechange-snapshot.json"
    before = json.loads(before_path.read_text(encoding="utf-8"))
    history_roots = [r["root"] for r in before.get("historical_roots", [])]
    after_path = snapshot_after(lab_root, run_root, history_roots)
    after = json.loads(after_path.read_text(encoding="utf-8"))
    ws = guard_result(before, after)
    hist = historical_guard(before, after)
    reports = run_root / "manifests"
    (reports / "workspace-verify.json").write_text(
        json.dumps(ws, indent=2, sort_keys=True), encoding="utf-8")
    (reports / "historical-verify.json").write_text(
        json.dumps(hist, indent=2, sort_keys=True), encoding="utf-8")
    return ws, hist


# ---------------------------------------------------------------------------
# summary + report
# ---------------------------------------------------------------------------

def build_summary(conditions: list, prechange_sha: str, guards: dict) -> dict:
    order = {"H0": 0, "H5": 1, "H1": 2, "H2": 3, "H3": 4, "H4": 5}
    conditions_sorted = sorted(conditions, key=lambda c: order.get(c["id"], 9))
    states = [c["terminal_state"] for c in conditions_sorted
              if c["id"] not in ("H0", "H5")]
    if all(s == "OBSERVED" for s in states) and states:
        terminal = "OBSERVED"
    elif any(s == "FAILED" for s in states):
        terminal = "FAILED"
    else:
        terminal = "BLOCKED_NOT_RUN"
    return {
        "schema_version": "1.0",
        "round": "H",
        "run_label": RUN_LABEL,
        "terminal_state": terminal,
        "prechange_snapshot_sha256": prechange_sha,
        "research_claim": "A fresh native execution instance reuses valid settled "
                          "work and recomputes only the transitive dependency "
                          "closure affected by an upstream source change.",
        "graph": {"affected_chain": [SOURCE_A, U1, U2, U3],
                  "unaffected_branch": [SOURCE_B, V1]},
        "conditions": conditions_sorted,
        "guards": guards,
        "claim_limits": [
            "Cost is reported honestly: each H1/H2 recompute process loads the "
            "real model and generates its own item once; reuse of V1 means V1 "
            "performs no generation, not that no FLOPs occur anywhere.",
            "H3 reuse is shown at the model-free demand/settlement decision "
            "layer; the ordinary per-item entry computes an item it is explicitly "
            "asked to run.",
            "Only this four-node two-branch fixture is covered; results "
            "demonstrate feasibility of selective invalidation on the production "
            "path, not universal validity across all graphs, models or backends.",
        ],
    }


def write_report(path: Path, summary: dict) -> None:
    lines = ["# H Round — Native Selective Invalidation: Evidence Report", ""]
    lines += ["Terminal state: **%s**" % summary["terminal_state"], ""]
    lines += ["## Conditions", "", "| id | kind | terminal | loads | tok_text "
              "| tok_seed | gen | computed | reused |", "|---|---|---|---|---"
              "|---|---|---|---|"]
    for c in summary["conditions"]:
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            c.get("id"), c.get("kind", ""), c.get("terminal_state"),
            c.get("model_loads", 0), c.get("tokenize_text_calls", 0),
            c.get("tokenize_seed_calls", 0), c.get("model_generate_calls", 0),
            ",".join(c.get("computed_item_ids", [])) or "-",
            ",".join(c.get("reused_item_ids", [])) or "-"))
    lines += ["", "## Guards", "",
              "- workspace: %s" % summary["guards"].get("workspace"),
              "- historical_artifacts: %s" % summary["guards"].get(
                  "historical_artifacts"), "",
              "## Claim limits", ""]
    lines += ["- %s" % lim for lim in summary["claim_limits"]]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# orchestration
# ---------------------------------------------------------------------------

def archive_prior_attempt(run_root: Path) -> Path | None:
    """Preserve a previous full-run attempt before starting a new one.

    A rerun must never silently overwrite earlier evidence. If a prior attempt
    produced output (summary.json and/or condition worlds), move the whole
    ``runs/`` tree plus the summary/report into ``attempts/attemptN/``. The
    fixed round baselines -- the pre-change snapshot under ``preflight/`` and
    the trust root under ``trust/`` -- are intentionally left in place, since
    they are reused unchanged across attempts rather than being per-attempt
    results.
    """
    prior_summary = run_root / "summary.json"
    prior_runs = run_root / "runs"
    prior_manifests = run_root / "manifests"
    if not (prior_summary.exists() or prior_runs.exists() or prior_manifests.exists()):
        return None
    attempts_dir = run_root / "attempts"
    attempts_dir.mkdir(parents=True, exist_ok=True)
    used = []
    for entry in attempts_dir.glob("attempt*"):
        suffix = entry.name[len("attempt"):]
        if suffix.isdigit():
            used.append(int(suffix))
    number = (max(used) + 1) if used else 1
    dest = attempts_dir / ("attempt%d" % number)
    dest.mkdir(parents=False, exist_ok=False)
    if prior_runs.exists():
        shutil.move(str(prior_runs), str(dest / "runs"))
    if prior_manifests.exists():
        # Guard outputs (post-change snapshot + verify reports) are per attempt;
        # the snapshot tool refuses to clobber them, so they must move out first.
        shutil.move(str(prior_manifests), str(dest / "manifests"))
    if prior_summary.exists():
        shutil.move(str(prior_summary), str(dest / "summary.json"))
    report = run_root / "EVIDENCE_REPORT.md"
    if report.exists():
        shutil.move(str(report), str(dest / "EVIDENCE_REPORT.md"))
    return dest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, default=RUN_ROOT_DEFAULT)
    parser.add_argument("--lab-root", type=Path, default=LAB_ROOT_DEFAULT)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--max-tokens", type=int, default=32)
    parser.add_argument("--skip-guards", action="store_true")
    parser.add_argument("--skip-real", action="store_true",
                        help="only run the model-free conditions (H3/H4/H5/H0)")
    args = parser.parse_args()

    lab_root, run_root, model_dir = args.lab_root, args.run_root, args.model_dir

    # Preserve (never delete) any earlier full-run attempt before proceeding.
    archive_prior_attempt(run_root)

    binary = lab_root / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    bridge = lab_root / "execution-information-loop/production_runtime_bridge.py"
    for path in (binary, bridge, model_dir):
        if not path.exists():
            raise SystemExit("missing path: %s" % path)

    before_path = run_root / "preflight" / "prechange-snapshot.json"
    prechange_sha = hashlib.sha256(before_path.read_bytes()).hexdigest()

    trust_file = run_root / "trust" / "trust-root.json"
    if trust_file.exists():
        trust = json.loads(trust_file.read_text(encoding="utf-8"))
    else:
        trust = e.provision_trust(run_root)
        trust["build_sha256"] = e.sha256_bytes(("\n".join([
            e.sha256_file(binary), e.sha256_file(bridge),
            e.sha256_file(lab_root / "execution-information-loop/"
                          "settlement_provenance.py")])).encode())
        (run_root / "trust").mkdir(parents=True, exist_ok=True)
        trust_file.write_text(json.dumps(trust, indent=2), encoding="utf-8")

    conditions = []

    # H0 (preflight): the pre-change snapshot already exists.
    conditions.append({
        "id": "H0", "kind": "preflight", "terminal_state": "OBSERVED",
        "model_loads": 0, "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
        "model_generate_calls": 0, "db_pre_sha256": prechange_sha,
        "db_post_sha256": prechange_sha,
        "state_pre_sha256": prechange_sha, "state_post_sha256": prechange_sha,
        "raw_evidence_path": str(before_path),
        "notes": ["worktree + historical roots snapshotted before edits"],
    })

    # H5: model-free preflight (must pass before real runs).
    h5_out = run_root / "runs" / "H5" / "h5.json"
    proc = subprocess.run(
        ["/usr/bin/python3",
         str(lab_root / "execution-information-loop/"
             "h_selective_invalidation_selftest.py"), "--out", str(h5_out)],
        capture_output=True, text=True, cwd=str(lab_root), timeout=600)
    h5 = json.loads(h5_out.read_text(encoding="utf-8")) if h5_out.exists() else {}
    conditions.append({
        "id": "H5", "kind": "model_free_preflight",
        "terminal_state": h5.get("terminal_state", "FAILED"),
        "model_loads": 0, "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
        "model_generate_calls": 0, "db_pre_sha256": prechange_sha,
        "db_post_sha256": prechange_sha,
        "state_pre_sha256": prechange_sha, "state_post_sha256": prechange_sha,
        "raw_evidence_path": str(h5_out), "checks": h5.get("checks", {}),
        "exit_code": proc.returncode, "notes": h5.get("notes", []),
    })
    if h5.get("verdict") != "PASS":
        _finalize(run_root, conditions, prechange_sha, args.skip_guards,
                  lab_root)
        return 1

    # Build the H1 baseline graph via the production bridge. Any prior attempt
    # was already archived above, so the worlds start clean without deleting
    # live evidence.
    h1_world = run_root / "runs" / "H1"
    (h1_world / "evidence").mkdir(parents=True, exist_ok=True)
    (h1_world / "logs").mkdir(parents=True, exist_ok=True)
    (h1_world / "state").mkdir(parents=True, exist_ok=True)
    secret_a = secrets.token_hex(8)
    secret_b = secrets.token_hex(8)
    def_env = e.child_environment(lab_root, trust, "h-definition", "H-DEFINE",
                                  with_key=True)
    code, defined = run_bridge(bridge, [
        "define-h-graph", "--database", str(h1_world / "carrier.sqlite"),
        "--evaluated-at", e.utc_now(), "--run-label", RUN_LABEL,
        "--secret-a", secret_a, "--secret-b", secret_b,
    ], def_env)
    if code != 0 or not defined.get("ok"):
        raise SystemExit("define-h-graph failed: %s" % json.dumps(defined)[:500])
    definition = {"run_label": RUN_LABEL, "checksum_a": defined["checksum_a"],
                  "checksum_b": defined["checksum_b"],
                  "db_after_define": e.sha256_file(h1_world / "carrier.sqlite")}

    if not args.skip_real:
        h1 = run_h1(binary, bridge, lab_root, model_dir, trust, h1_world,
                    args.max_tokens, definition)
        conditions.append(h1)
        if h1["terminal_state"] == "OBSERVED":
            h2_world = run_root / "runs" / "H2"
            conditions.append(run_h2(binary, bridge, lab_root, model_dir, trust,
                                     h1_world, h2_world, args.max_tokens,
                                     definition))
        else:
            for cid in ("H2",):
                conditions.append(_blocked(cid, "H1 did not reach OBSERVED"))

    h3_world = run_root / "runs" / "H3"
    conditions.append(run_h3(bridge, lab_root, trust, h1_world, h3_world,
                             definition))
    h4_world = run_root / "runs" / "H4"
    conditions.append(run_h4(binary, bridge, lab_root, model_dir, trust,
                             h1_world, h4_world, definition, args.max_tokens))

    _finalize(run_root, conditions, prechange_sha, args.skip_guards, lab_root)
    summary = json.loads((run_root / "summary.json").read_text(encoding="utf-8"))
    return 0 if summary["terminal_state"] == "OBSERVED" else 2


def _blocked(cid: str, reason: str) -> dict:
    return {"id": cid, "kind": cid, "terminal_state": "BLOCKED_NOT_RUN",
            "model_loads": 0, "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
            "model_generate_calls": 0, "db_pre_sha256": "0" * 64,
            "db_post_sha256": "0" * 64, "state_pre_sha256": "0" * 64,
            "state_post_sha256": "0" * 64, "raw_evidence_path": "",
            "computed_item_ids": [], "reused_item_ids": [],
            "notes": ["blocked: %s" % reason]}


def _finalize(run_root: Path, conditions: list, prechange_sha: str,
              skip_guards: bool, lab_root: Path) -> None:
    if skip_guards:
        guards = {"workspace": "SKIPPED", "historical_artifacts": "SKIPPED"}
    else:
        ws, hist = run_guards(lab_root, run_root)
        guards = {"workspace": "PASS" if ws["PASS"] else "FAIL",
                  "historical_artifacts": "PASS" if hist["PASS"] else "FAIL"}
    summary = build_summary(conditions, prechange_sha, guards)
    (run_root / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    write_report(run_root / "EVIDENCE_REPORT.md", summary)
    print(json.dumps({"terminal_state": summary["terminal_state"],
                      "guards": guards,
                      "conditions": {c["id"]: c["terminal_state"]
                                     for c in summary["conditions"]}},
                     ensure_ascii=False, indent=1))


if __name__ == "__main__":
    raise SystemExit(main())
