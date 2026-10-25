#!/usr/bin/env python3
"""Semantic validator for the G-round summary contract; does not run experiments."""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path
from datetime import datetime
ALLOWED = {"OBSERVED", "INVALID_CONDITION", "BLOCKED_NOT_RUN", "OBSERVED_FORMAT_FAILURE"}
HEX64 = re.compile(r"^[0-9a-f]{64}$")

def require(test: bool, msg: str, issues: list[str]):
    if not test: issues.append(msg)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("summary", type=Path)
    args = ap.parse_args()
    try: d = json.loads(args.summary.read_text())
    except Exception as e:
        print(json.dumps({"result":"FAIL","issues":[f"cannot read JSON: {e}"]}, indent=2)); return 2
    issues=[]
    require(d.get("schema_version")=="1.0", "schema_version must be '1.0'", issues)
    require(d.get("round_id")=="G", "round_id must be G", issues)
    require(bool(d.get("source_head")), "source_head missing", issues)
    require(d.get("terminal_state") in ALLOWED, "invalid top terminal_state", issues)
    cond=d.get("conditions", {})
    for name in ("G0_CHAIN_3_HOPS","G1_MISSING_TRANSITIVE_DEPENDENCY","N4_NONCE_AND_PREFIX_ISOLATION_AUDIT"):
        require(name in cond, f"missing condition {name}", issues)
    chain=cond.get("G0_CHAIN_3_HOPS", {})
    require(chain.get("terminal_state") in ALLOWED, "G0 invalid terminal_state", issues)
    stages=chain.get("stages", [])
    require(len(stages)==3, "G0 must contain exactly P1/P2/P3 stage evidence", issues)
    expected=[("P1_U1","TASK-U1",1), ("P2_U2","TASK-U2",1), ("P3_U3","TASK-U3",1)]
    pids=[]; esids=[]
    for i,s in enumerate(stages[:3]):
        stage,item,calls=expected[i]
        require(s.get("stage")==stage, f"stage {i} must be {stage}", issues)
        require(isinstance(s.get("pid"), int) and s.get("pid")>0, f"{stage} PID missing", issues)
        pids.append(s.get("pid"))
        require(bool(s.get("execution_state_id")), f"{stage} execution_state_id missing", issues)
        esids.append(s.get("execution_state_id"))
        require(s.get("state_position_start")==0, f"{stage} must start at position 0", issues)
        require(s.get("state_starts_empty") is True, f"{stage} state must be verified empty", issues)
        require(s.get("model_generate_calls")==calls, f"{stage} must generate exactly once", issues)
        require(HEX64.fullmatch(str(s.get("input_sha256",""))) is not None, f"{stage} input SHA256 invalid", issues)
        require(HEX64.fullmatch(str(s.get("output_sha256",""))) is not None, f"{stage} output SHA256 invalid", issues)
        require(s.get("harness_direct_is_reads")==0, f"{stage} harness direct IS reads must be zero", issues)
        require(s.get("prefix_replay_tokens")==0, f"{stage} prefix replay must be zero", issues)
        require(s.get("old_checkpoint_reads")==0, f"{stage} old checkpoint reads must be zero", issues)
        require(isinstance(s.get("computed_item_ids"),list), f"{stage} computed_item_ids missing", issues)
        require(isinstance(s.get("reused_item_ids"),list), f"{stage} reused_item_ids missing", issues)
        if i>0:
            require(s.get("producer_exit_observed_before_next_process") is True, f"{stage} did not prove prior producer exit before start", issues)
    require(len(set(pids))==3 and None not in pids, "P1/P2/P3 PIDs must be distinct", issues)
    require(len(set(esids))==3 and None not in esids, "P1/P2/P3 execution_state_ids must be distinct", issues)
    if len(stages)>=3:
        require("TASK-U1" in stages[1].get("reused_item_ids",[]), "P2 must reuse U1", issues)
        require("TASK-U1" not in stages[1].get("computed_item_ids",[]), "P2 must not compute U1", issues)
        require("TASK-U2" in stages[1].get("computed_item_ids",[]), "P2 must compute U2", issues)
        require(("TASK-U1" in stages[2].get("reused_item_ids",[]) or "TASK-U1" in stages[2].get("verified_dependency_closure_item_ids",[])), "P3 verified dependency closure must include U1", issues)
        require(("TASK-U2" in stages[2].get("reused_item_ids",[]) or "TASK-U2" in stages[2].get("verified_dependency_closure_item_ids",[])), "P3 must reuse U2 via IS/dependency closure", issues)
        require("TASK-U1" not in stages[2].get("computed_item_ids",[]), "P3 must not compute U1", issues)
        require("TASK-U2" not in stages[2].get("computed_item_ids",[]), "P3 must not compute U2", issues)
        require("TASK-U3" in stages[2].get("computed_item_ids",[]), "P3 must compute U3", issues)
    require(chain.get("full_dependency_closure_verified") is True, "full dependency closure not verified", issues)
    require(chain.get("all_previous_processes_exited") is True, "prior process exit chain not verified", issues)
    require(chain.get("no_prior_item_regeneration") is True, "prior item non-regeneration not proven", issues)
    neg=cond.get("G1_MISSING_TRANSITIVE_DEPENDENCY", {})
    require(neg.get("terminal_state") in ALLOWED, "G1 invalid terminal_state", issues)
    if neg.get("terminal_state")=="OBSERVED":
        require(neg.get("refusal_observed") is True, "G1 must observe refusal", issues)
        require(neg.get("tokenize_text_calls")==0, "G1 text tokenize must be zero", issues)
        require(neg.get("tokenize_seed_calls")==0, "G1 seed tokenize must be zero", issues)
        require(neg.get("model_generate_calls")==0, "G1 generate must be zero", issues)
        require(neg.get("database_side_effects") is False, "G1 DB must have no side effects", issues)
        require(neg.get("state_side_effects") is False, "G1 state must have no side effects", issues)
        require(neg.get("fallback_reads")==0, "G1 fallback reads must be zero", issues)
    iso=cond.get("N4_NONCE_AND_PREFIX_ISOLATION_AUDIT", {})
    require(iso.get("terminal_state") in ALLOWED, "N4 invalid terminal_state", issues)
    if iso.get("terminal_state")=="OBSERVED":
        require(bool(iso.get("scan_scope_manifest")), "N4 scope manifest missing", issues)
        for k in ("unapproved_occurrences","cross_stage_nonce_leakage","unapproved_prefix_or_completion_copy"):
            require(iso.get(k)==0, f"N4 {k} must be zero", issues)
    ident=d.get("identity",{})
    require(bool(ident.get("logical_lineage_id")), "logical_lineage_id missing", issues)
    require(HEX64.fullmatch(str(ident.get("model_identity_sha256",""))) is not None, "model identity hash invalid", issues)
    proc=ident.get("processes",[])
    require(len(proc)>=3, "identity.processes must contain P1/P2/P3 records", issues)
    require(len(set(p.get("pid") for p in proc[:3]))==3, "identity process PIDs not unique", issues)
    require(len(set(ident.get("execution_state_ids",[])))==3, "identity state IDs not unique", issues)
    if len(proc)>=3:
        try:
            t1x=datetime.fromisoformat(proc[0]["exit_utc"].replace("Z","+00:00"))
            t2s=datetime.fromisoformat(proc[1]["start_utc"].replace("Z","+00:00"))
            t2x=datetime.fromisoformat(proc[1]["exit_utc"].replace("Z","+00:00"))
            t3s=datetime.fromisoformat(proc[2]["start_utc"].replace("Z","+00:00"))
            require(t2s > t1x, "P2 must start after P1 exit", issues)
            require(t3s > t2x, "P3 must start after P2 exit", issues)
        except Exception as e:
            issues.append(f"cannot verify process ordering timestamps: {e}")
    costs=d.get("costs",{})
    for k in ("model_generate_calls","tokenize_text_calls","tokenize_seed_calls","model_loads"):
        require(isinstance(costs.get(k),int) and costs.get(k)>=0, f"costs.{k} missing/invalid", issues)
    require(costs.get("prefix_replay_tokens")==0, "top-level prefix replay must be 0", issues)
    require(costs.get("model_generate_calls")==3, "positive three-stage chain must total exactly 3 model generation calls", issues)
    guards=d.get("guards",{})
    require(guards.get("workspace_guard") in {"PASS","FAIL","BLOCKED_NOT_RUN"}, "workspace guard status missing", issues)
    require(guards.get("artifact_guard") in {"PASS","FAIL","BLOCKED_NOT_RUN"}, "artifact guard status missing", issues)
    require(HEX64.fullmatch(str(d.get("artifact_manifest_sha256",""))) is not None, "artifact manifest hash missing/invalid", issues)
    print(json.dumps({"result":"PASS" if not issues else "FAIL", "issue_count":len(issues), "issues":issues}, indent=2))
    return 0 if not issues else 2
if __name__=="__main__": raise SystemExit(main())
