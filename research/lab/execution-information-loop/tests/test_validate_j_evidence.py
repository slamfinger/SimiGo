import hashlib, importlib.util, json, tempfile, unittest
from pathlib import Path

HERE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("validate_j_evidence", HERE/"validate_j_evidence.py")
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def make_summary(root):
    cond={}
    def artifact(name, content):
        p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(content); return p
    stages=[]
    items=["J-random-11-U1","J-random-11-U2","J-random-11-U3"]
    for ix,(st,item) in enumerate(zip(("P1","P2","P3"),items)):
        ev=artifact(f"conditions/J0/{st}.json",json.dumps({"stage":st,"pid":100+ix}))
        lg=artifact(f"logs/J0/{st}.log",f"driver evidence {st}\n")
        stages.append({"stage":st,"pid":100+ix,"logical_es_id":f"es-{ix}","runtime_execution_instance_id":f"runtime-{ix}","state_empty_at_start":True,"old_state_or_prefix_copied":False,"generation_calls":1,"task_item_id":item,"contract_dispatch_basis":"declared_contract","computed_item_ids":[item],"reused_item_ids": (["SOURCE-A","SOURCE-B"] if ix==0 else ([items[0],"SOURCE-A","SOURCE-B"] if ix==1 else [items[0],items[1],"SOURCE-A","SOURCE-B"])),"recomputed_upstream_item_ids":[],"settlement_object_id":f"settle-{ix}","signature_envelope_id":f"sig-{ix}","result_digest":f"digest-{ix}"})
        cond.setdefault("J0-UNSEEN-ID-CHAIN", {"terminal_state":"OBSERVED","evidence_path":"conditions/J0/P1.json","evidence_sha256":h(ev),"driver_log_path":"logs/J0/P1.log","driver_log_sha256":h(lg)})
    trace={"source_a":{"payload":{"origin_code":"NORTH"}},"source_b":{"payload":{"destination_code":"EAST","priority":5}},"u1_settlement":{"object_id":"settle-0","signature_envelope_id":"sig-0","signature_verified":True,"result":{"route_key":"NORTH>EAST","priority":5}},"u2_input":{"constructed_by_harness":False,"source_settlement_object_id":"settle-0","values":{"route_key":"NORTH>EAST"}},"u2_settlement":{"object_id":"settle-1","signature_envelope_id":"sig-1","signature_verified":True,"result":{"route_key":"NORTH>EAST"}},"u3_input":{"constructed_by_harness":False,"source_settlement_object_id":"settle-1","values":{"route_key":"NORTH>EAST"}},"u3_settlement":{"object_id":"settle-2","signature_envelope_id":"sig-2","signature_verified":True,"result":{"route_key":"NORTH>EAST"}},"contract_validation_reports":[{"stage":f"P{ix+1}","task_item_id":item,"contract_dispatch_basis":"declared_contract","contract_read":True,"declared_contract_schema_version":"simigo.result-contract/v1","declared_fields":["origin_code","destination_code","route_key","priority"],"declared_match_policy":{"route_key":"first"},"reextracted_fields":{"route_key":"NORTH>EAST"},"redeclared_extraction_matches_settled_value":True} for ix,item in enumerate(items)]}
    j0=cond["J0-UNSEEN-ID-CHAIN"]; j0.update({"contract_dispatch_basis":"declared_contract","harness_direct_result_reads":0,"old_state_or_prefix_copied":False,"stage_records":stages,"semantic_trace":trace})
    for cid in ("J1-INCOMPLETE-FIELD","J2-BINDING-MISMATCH","J3-UNKNOWN-CONTRACT","J4-UNCHANGED-REUSE","J5-MISSING-TRANSITIVE-DEPENDENCY"):
        ev=artifact(f"conditions/{cid}/evidence.json",cid); lg=artifact(f"logs/{cid}.log",cid+" driver log\n")
        c={"terminal_state":"OBSERVED","evidence_path":str(ev.relative_to(root)),"evidence_sha256":h(ev),"driver_log_path":str(lg.relative_to(root)),"driver_log_sha256":h(lg)}
        if cid in ("J1-INCOMPLETE-FIELD","J2-BINDING-MISMATCH"): c.update(producer_contract_rejects=True,valid_settlement_created=False,signature_created=False)
        elif cid=="J3-UNKNOWN-CONTRACT": c.update(fail_closed=True,model_loads=0,text_tokenize_calls=0,seed_tokenize_calls=0,generation_calls=0)
        elif cid=="J4-UNCHANGED-REUSE": c.update(all_eligible_items_reused=True,model_loads=0,generation_calls=0)
        else: c.update(refusal_before_tokenize=True,database_unchanged=True,state_unchanged=True,generation_calls=0,text_tokenize_calls=0,seed_tokenize_calls=0)
        cond[cid]=c
    s={"schema_version":"simigo-j-evidence-v1","round":"J","run_label":"es-is-declarative-result-contract-20261023j","terminal_state":"OBSERVED","implementation":{"contract_dispatch_basis":"declared_contract","task_id_semantic_branches_remaining":[],"model_snapshot_id":"model-snapshot","binary_sha256":"a"*64,"source_snapshot_id":"pre-snapshot","regression_suite":{"verdict":"PASS","artifact":"tests/regression-attempt1","members":{m:{"exit_code":0,"verdict":"PASS","check_count":3,"failed_checks":[]} for m in ("j_contract_selftest","h_selective_invalidation_selftest","i_semantic_sufficiency_selftest","admission_selftest","<unit>")}}},"conditions":cond,"guards":{"workspace":"PASS","historical":"PASS","evidence_validator":"PASS"},"carrier_loop_semantics_changed":False,"historical_artifacts_modified":False,"claim_limits":[]}
    (root/"summary.json").write_text(json.dumps(s,indent=2)); return s

class ValidatorTests(unittest.TestCase):
    def test_canonical_synthetic_evidence_passes(self):
        with tempfile.TemporaryDirectory() as d: make_summary(Path(d)); self.assertEqual(mod.validate(Path(d)),[])
    def test_repeated_pid_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["stage_records"][1]["pid"]=100; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("pid not unique" in x for x in mod.validate(Path(d))))
    def test_hardcoded_id_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["stage_records"][0]["task_item_id"]="TASK-IU1"; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("unseen runtime ID" in x for x in mod.validate(Path(d))))
    def test_harness_spliced_input_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["semantic_trace"]["u2_input"]["constructed_by_harness"]=True; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("constructed_by_harness" in x for x in mod.validate(Path(d))))
    def test_bad_source_derivation_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["semantic_trace"]["u1_settlement"]["result"]["route_key"]="WEST>NORTH"; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("route_key does not derive" in x for x in mod.validate(Path(d))))
    def test_signature_false_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["semantic_trace"]["u3_settlement"]["signature_verified"]=False; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("signature not verified" in x for x in mod.validate(Path(d))))
    def test_negative_generation_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J5-MISSING-TRANSITIVE-DEPENDENCY"]["generation_calls"]=1; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("work occurred before dependency refusal" in x for x in mod.validate(Path(d))))
    def test_artifact_tampering_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); (Path(d)/"logs/J0/P1.log").write_text("tampered"); self.assertTrue(any("driver_log_sha256 mismatch" in x for x in mod.validate(Path(d))))
    def test_historical_mutation_flag_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["historical_artifacts_modified"]=True; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("historical_artifacts_modified must be false" in x for x in mod.validate(Path(d))))
    def test_empty_stdout_must_be_recorded_truthfully(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); s=make_summary(root); p=root/"logs/child.stdout"; p.write_bytes(b""); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["child_stdout"]={"path":"logs/child.stdout","bytes":0,"sha256":h(p)}; (root/"summary.json").write_text(json.dumps(s)); self.assertEqual(mod.validate(root),[])

    def test_empty_contract_report_placeholder_fails(self):
        # A placeholder {} proves nothing about which contract gated the result,
        # so the strict acceptance must reject it instead of passing a void field.
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["semantic_trace"]["contract_validation_reports"]=[{},{},{}]; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("empty contract validation report placeholder" in x for x in mod.validate(Path(d))))
    def test_missing_contract_report_stages_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["semantic_trace"]["contract_validation_reports"]=[]; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("must cover P1/P2/P3" in x for x in mod.validate(Path(d))))
    def test_contract_report_reextraction_disagreement_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["conditions"]["J0-UNSEEN-ID-CHAIN"]["semantic_trace"]["contract_validation_reports"][1]["redeclared_extraction_matches_settled_value"]=False; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("does not reproduce the settled value" in x for x in mod.validate(Path(d))))
    def test_regression_suite_failure_fails(self):
        # H/I/admission green is an acceptance requirement of this round, so a
        # recorded failing member must be refused rather than summarised away.
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["implementation"]["regression_suite"]["members"]["i_semantic_sufficiency_selftest"]["exit_code"]=1; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("i_semantic_sufficiency_selftest exited 1" in x for x in mod.validate(Path(d))))
    def test_regression_suite_absent_member_fails(self):
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["implementation"]["regression_suite"]["verdict"]="FAIL"; del s["implementation"]["regression_suite"]["members"]["admission_selftest"]; (Path(d)/"summary.json").write_text(json.dumps(s)); r=mod.validate(Path(d)); self.assertTrue(any("verdict is not PASS" in x for x in r) and any("admission_selftest has no recorded result" in x for x in r))
    def test_regression_member_without_named_checks_fails(self):
        # A green-looking member that recorded zero checks proves nothing, so the
        # acceptance must refuse it rather than read it as coverage.
        with tempfile.TemporaryDirectory() as d:
            s=make_summary(Path(d)); s["implementation"]["regression_suite"]["members"]["j_contract_selftest"]["check_count"]=0; (Path(d)/"summary.json").write_text(json.dumps(s)); self.assertTrue(any("recorded no named checks" in x for x in mod.validate(Path(d))))

if __name__=="__main__": unittest.main()
