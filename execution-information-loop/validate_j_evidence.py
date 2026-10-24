#!/usr/bin/env python3
"""Strict verifier for SimiGo J evidence; validates observed artifacts, not plans."""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED = {"J0-UNSEEN-ID-CHAIN", "J1-INCOMPLETE-FIELD", "J2-BINDING-MISMATCH", "J3-UNKNOWN-CONTRACT", "J4-UNCHANGED-REUSE", "J5-MISSING-TRANSITIVE-DEPENDENCY"}

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def fail(msg, issues): issues.append(msg)

def safe_child(root: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute():
        raise ValueError("artifact paths must be relative to the run root")
    resolved_root = root.resolve()
    resolved = (root / candidate).resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ValueError("artifact path escapes the run root")
    return resolved

def validate(root: Path):
    issues=[]
    summary_path=root/"summary.json"
    if not summary_path.is_file(): return [f"missing {summary_path}"]
    try: s=json.loads(summary_path.read_text())
    except Exception as e: return [f"invalid summary JSON: {e}"]
    if s.get("schema_version") != "simigo-j-evidence-v1": fail("schema_version mismatch", issues)
    if s.get("round") != "J": fail("round must be J", issues)
    if s.get("run_label") != "es-is-declarative-result-contract-20261023j": fail("run_label mismatch", issues)
    if s.get("carrier_loop_semantics_changed") is not False: fail("carrier_loop_semantics_changed must be false", issues)
    if s.get("historical_artifacts_modified") is not False: fail("historical_artifacts_modified must be false", issues)
    impl=s.get("implementation", {})
    if impl.get("contract_dispatch_basis") != "declared_contract": fail("implementation not declared-contract driven", issues)
    if impl.get("task_id_semantic_branches_remaining") != []: fail("task-id semantic branches remain or are not audited empty", issues)
    if not HEX64.match(str(impl.get("binary_sha256", ""))): fail("binary_sha256 missing/invalid", issues)
    # The prior rounds' tests are part of this round's acceptance, not a footnote:
    # J changes the production result-validation path, so the J gate plus the H, I
    # and admission selftests and the unit tests must be green on this code state,
    # each with a zero exit code and no failed check names.
    reg=impl.get("regression_suite", {})
    if reg.get("verdict") != "PASS": fail("regression suite verdict is not PASS", issues)
    reg_members=reg.get("members", {})
    for m in ("j_contract_selftest", "h_selective_invalidation_selftest", "i_semantic_sufficiency_selftest", "admission_selftest", "<unit>"):
        e=reg_members.get(m)
        if not e: fail(f"regression member {m} has no recorded result", issues); continue
        if e.get("exit_code") != 0: fail(f"regression member {m} exited {e.get('exit_code')}", issues)
        if e.get("verdict") != "PASS": fail(f"regression member {m} verdict is {e.get('verdict')}", issues)
        if e.get("failed_checks"): fail(f"regression member {m} has failed checks: {e.get('failed_checks')}", issues)
    # The selftests that report named checks must actually have run some, or a
    # vacuous payload would look like a green suite.
    for m in ("j_contract_selftest", "h_selective_invalidation_selftest", "i_semantic_sufficiency_selftest"):
        e=reg_members.get(m) or {}
        if not e.get("check_count"): fail(f"regression member {m} recorded no named checks", issues)
    if not reg.get("artifact"): fail("regression suite artifact path not recorded", issues)
    cond=s.get("conditions", {})
    missing=EXPECTED-set(cond)
    if missing: fail(f"missing conditions: {sorted(missing)}", issues)
    if s.get("terminal_state") == "OBSERVED":
        not_observed = {cid: cond.get(cid, {}).get("terminal_state") for cid in EXPECTED if cond.get(cid, {}).get("terminal_state") != "OBSERVED"}
        if not_observed: fail(f"top-level OBSERVED requires all conditions OBSERVED: {not_observed}", issues)
    for cid in EXPECTED & set(cond):
        c=cond[cid]
        if c.get("terminal_state") not in {"OBSERVED", "FAILED", "BLOCKED_NOT_RUN"}: fail(f"{cid}: invalid terminal_state", issues)
        for field in ("evidence_path","evidence_sha256","driver_log_path","driver_log_sha256"):
            if not c.get(field): fail(f"{cid}: missing {field}", issues)
        for path_field, hash_field in (("evidence_path","evidence_sha256"),("driver_log_path","driver_log_sha256")):
            expected=c.get(hash_field, "")
            try:
                p=safe_child(root, c.get(path_field, ""))
            except Exception as e:
                fail(f"{cid}: unsafe {path_field}: {e}", issues)
                continue
            if not p.is_file(): fail(f"{cid}: missing artifact {path_field}={p}", issues)
            elif path_field == "driver_log_path" and p.stat().st_size == 0: fail(f"{cid}: driver audit log is empty", issues)
            elif not HEX64.match(str(expected)) or sha(p)!=expected: fail(f"{cid}: {hash_field} mismatch", issues)
        # Native stdout may truthfully be empty. It must be reported as stdout, not faked from evidence JSON.
        stdout=c.get("child_stdout", {})
        if stdout:
            try:
                p=safe_child(root, stdout.get("path", ""))
            except Exception as e:
                fail(f"{cid}: unsafe child stdout path: {e}", issues)
                p=None
            if p is None or not p.is_file(): fail(f"{cid}: missing child stdout file", issues)
            else:
                actual=sha(p)
                if actual != stdout.get("sha256"): fail(f"{cid}: child stdout SHA mismatch", issues)
                if p.stat().st_size != stdout.get("bytes"): fail(f"{cid}: child stdout byte length mismatch", issues)
    c=cond.get("J0-UNSEEN-ID-CHAIN", {})
    if c.get("terminal_state")=="OBSERVED":
        if c.get("contract_dispatch_basis")!="declared_contract": fail("J0: contract dispatch not declared_contract", issues)
        if c.get("harness_direct_result_reads")!=0: fail("J0: harness direct result reads must be zero", issues)
        if c.get("old_state_or_prefix_copied") is not False: fail("J0: old state/prefix copied", issues)
        stages=c.get("stage_records", [])
        if [x.get("stage") for x in stages] != ["P1","P2","P3"]: fail("J0: stage_records must be ordered P1/P2/P3", issues)
        for f in ("pid","logical_es_id","runtime_execution_instance_id"):
            vals=[x.get(f) for x in stages]
            if len(vals)!=3 or None in vals or len(set(map(str,vals)))!=3: fail(f"J0: {f} not unique across P1/P2/P3", issues)
        stage_ids = {x.get("stage"): x for x in stages}
        for x in stages:
            if x.get("state_empty_at_start") is not True: fail(f"J0 {x.get('stage')}: state not empty at start", issues)
            if x.get("old_state_or_prefix_copied") is not False: fail(f"J0 {x.get('stage')}: old state/prefix copied", issues)
            if x.get("generation_calls")!=1: fail(f"J0 {x.get('stage')}: expected one generation", issues)
            if not x.get("task_item_id") or x.get("task_item_id") in {"TASK-IU1","TASK-IU2","TASK-IU3","TASK-U1","TASK-U2","TASK-U3"}:
                fail(f"J0 {x.get('stage')}: task ID is not an unseen runtime ID", issues)
            if x.get("contract_dispatch_basis")!="declared_contract": fail(f"J0 {x.get('stage')}: not contract-dispatched", issues)
            for idf in ("settlement_object_id","signature_envelope_id","result_digest"):
                if not x.get(idf): fail(f"J0 {x.get('stage')}: missing {idf}", issues)
        pids=[x.get("pid") for x in stages]
        if len(set(pids))==3:
            by_stage={x.get("stage"):x for x in stages}
            if by_stage.get("P2",{}).get("computed_item_ids") != [by_stage.get("P2",{}).get("task_item_id")]: fail("J0 P2 must compute only its own task", issues)
            if by_stage.get("P3",{}).get("computed_item_ids") != [by_stage.get("P3",{}).get("task_item_id")]: fail("J0 P3 must compute only its own task", issues)
            if by_stage.get("P2",{}).get("recomputed_upstream_item_ids") != []: fail("J0 P2 recomputed upstream items", issues)
            if by_stage.get("P3",{}).get("recomputed_upstream_item_ids") != []: fail("J0 P3 recomputed upstream items", issues)
            p2 = by_stage.get("P2", {})
            p3 = by_stage.get("P3", {})
            if p2.get("reused_item_ids") is None or p2.get("reused_item_ids")==[]: fail("J0 P2 has no evidence of U1 reuse", issues)
            if p3.get("reused_item_ids") is None or p3.get("reused_item_ids")==[]: fail("J0 P3 has no evidence of U1/U2 reuse", issues)
        trace=c.get("semantic_trace", {})
        a=trace.get("source_a",{}).get("payload",{})
        b=trace.get("source_b",{}).get("payload",{})
        u1=trace.get("u1_settlement",{}).get("result",{})
        u2=trace.get("u2_settlement",{}).get("result",{})
        u3=trace.get("u3_settlement",{}).get("result",{})
        if u1.get("route_key") != f"{a.get('origin_code')}>{b.get('destination_code')}": fail("J0 semantic trace: U1 route_key does not derive from source A/B", issues)
        if u1.get("priority") != b.get("priority"): fail("J0 semantic trace: U1 priority not inherited from source B", issues)
        for key, obj, result in (("u2_input",trace.get("u2_input",{}),u1),("u3_input",trace.get("u3_input",{}),u2)):
            if obj.get("constructed_by_harness") is not False: fail(f"J0 {key}: constructed_by_harness must be false", issues)
            expected_id=trace.get("u1_settlement",{}).get("object_id") if key=="u2_input" else trace.get("u2_settlement",{}).get("object_id")
            if obj.get("source_settlement_object_id") != expected_id: fail(f"J0 {key}: wrong source settlement object", issues)
            if obj.get("values",{}).get("route_key") != result.get("route_key"): fail(f"J0 {key}: route_key value not bound to settlement", issues)
        if u2.get("route_key") != u1.get("route_key"): fail("J0 U2 route_key does not preserve U1 result", issues)
        if u3.get("route_key") != u2.get("route_key"): fail("J0 U3 route_key does not preserve U2 result", issues)
        for name in ("u1_settlement","u2_settlement","u3_settlement"):
            if trace.get(name,{}).get("signature_verified") is not True: fail(f"J0 {name}: signature not verified", issues)
        trace_stage_map = {"u1_settlement":"P1", "u2_settlement":"P2", "u3_settlement":"P3"}
        for name, stage in trace_stage_map.items():
            obj=trace.get(name,{})
            rec=stage_ids.get(stage,{})
            if obj.get("object_id") != rec.get("settlement_object_id"): fail(f"J0 {name}: settlement object ID mismatch with stage record", issues)
            if obj.get("signature_envelope_id") != rec.get("signature_envelope_id"): fail(f"J0 {name}: signature envelope ID mismatch with stage record", issues)
        # Result validation must be evidenced by the item's OWN declaration, not a
        # placeholder: the native producer writes no result_contract_validation
        # block, so the round records the declared contract it read back from the
        # Information Space plus an independent re-extraction of the real model
        # text. An empty or absent report here would mean the acceptance never saw
        # the contract that actually gated the settlement.
        reports=trace.get("contract_validation_reports", [])
        if not isinstance(reports, list) or len(reports)!=3: fail("J0: contract_validation_reports must cover P1/P2/P3", issues)
        seen_stages=[]
        for r in reports:
            if not isinstance(r, dict) or not r: fail("J0: empty contract validation report placeholder", issues); continue
            stage=r.get("stage"); seen_stages.append(stage)
            if r.get("contract_dispatch_basis")!="declared_contract": fail(f"J0 contract report {stage}: dispatch basis not declared_contract", issues)
            if r.get("declared_contract_schema_version")!="simigo.result-contract/v1": fail(f"J0 contract report {stage}: declared contract schema version absent or unknown", issues)
            if not r.get("declared_fields"): fail(f"J0 contract report {stage}: no declared fields recorded", issues)
            if not r.get("reextracted_fields"): fail(f"J0 contract report {stage}: no re-extracted field values recorded", issues)
            if r.get("redeclared_extraction_matches_settled_value") is not True: fail(f"J0 contract report {stage}: re-applying the declared contract does not reproduce the settled value", issues)
        if sorted(seen_stages)!= ["P1","P2","P3"]: fail("J0: contract validation reports are not keyed to the three real stages", issues)
    # Negative/model-free conditions: assert declared semantics when observed.
    for cid in ("J1-INCOMPLETE-FIELD","J2-BINDING-MISMATCH"):
        c=cond.get(cid,{})
        if c.get("terminal_state")=="OBSERVED":
            if c.get("producer_contract_rejects") is not True: fail(f"{cid}: producer contract did not reject", issues)
            if c.get("valid_settlement_created") is not False: fail(f"{cid}: invalid settlement was created", issues)
            if c.get("signature_created") is not False: fail(f"{cid}: signature was created for invalid result", issues)
    c=cond.get("J3-UNKNOWN-CONTRACT",{})
    if c.get("terminal_state")=="OBSERVED":
        if c.get("fail_closed") is not True or any(c.get(k)!=0 for k in ("model_loads","text_tokenize_calls","seed_tokenize_calls","generation_calls")): fail("J3: unknown contract did not fail closed before model work", issues)
    c=cond.get("J4-UNCHANGED-REUSE",{})
    if c.get("terminal_state")=="OBSERVED":
        if c.get("all_eligible_items_reused") is not True or c.get("model_loads")!=0 or c.get("generation_calls")!=0: fail("J4: unchanged reuse control failed", issues)
    c=cond.get("J5-MISSING-TRANSITIVE-DEPENDENCY",{})
    if c.get("terminal_state")=="OBSERVED":
        for f in ("refusal_before_tokenize","database_unchanged","state_unchanged"):
            if c.get(f) is not True: fail(f"J5: {f} must be true", issues)
        if c.get("generation_calls")!=0 or c.get("text_tokenize_calls")!=0 or c.get("seed_tokenize_calls")!=0: fail("J5: work occurred before dependency refusal", issues)
    guards=s.get("guards",{})
    for f in ("workspace","historical","evidence_validator"):
        if guards.get(f)!="PASS": fail(f"guard {f} not PASS", issues)
    return issues

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("run_root", type=Path); args=ap.parse_args()
    issues=validate(args.run_root)
    result={"result":"PASS" if not issues else "FAIL","issue_count":len(issues),"issues":issues}
    print(json.dumps(result,indent=2))
    return 0 if not issues else 1
if __name__=="__main__": sys.exit(main())
