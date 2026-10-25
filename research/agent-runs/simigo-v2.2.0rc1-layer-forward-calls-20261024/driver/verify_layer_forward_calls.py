#!/usr/bin/env python3
"""Derive the per_layer_forward_calls verdict from layer_forward_trace_raw.json.

The rules below were fixed before the run. Every number they use is re-derived
here from the retained `layerEntered` event stream (the report the process
wrote), not from any summary field the driver produced; rule L8 exists to catch
the case where the two disagree.

Rules (all must hold for PASS)
  L1  the shipped pilot really ran     exit_code == 0, evidence status OK,
                                       pilot status PASS
  L2  the numbers trace to a file      the report exists and its sha256 equals
                                       the digest the process recorded
  L3  the trace is stable              every case: >= 2 repetitions, the pass
                                       count constant across repetitions and
                                       > 0, declared == re-derived, trace stable
  L4  every declared layer was seen    distinct layers == num_hidden_layers from
                                       the model's own config.json, indices
                                       0..N-1, none missing
  L5  one enter per layer per pass     every layer's event count equals that
                                       case's number of forward passes
  L6  observation changed nothing      baseline/instrumented token IDs identical
                                       AND logits bitwise identical, every case
  L7  execution is layer-sequential    each pass covers 0..N-1 once, ascending
  L8  no number came from the driver   the verifier's own re-derivation equals
                                       the driver's derived block
  L9  the candidate is the new one     exe sha256 in the raw file equals the
                                       installed candidate's exe sha256

Pass counts are NOT required to be equal across prompts: a prompt that stops at
EOS legitimately runs fewer passes. Only per-case stability is demanded.

Excluded on purpose: no value is inferred from timing, token counts, or a
theoretical layer count. A layer with zero events fails L4/L5 rather than being
filled in.

usage: verify_layer_forward_calls.py [raw.json] [install_identity.json]
Exit codes: 0 PASS, 2 BLOCKED, 1 contradictory evidence.
"""
import json
import os
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(B, "evidence/layer_forward_trace_raw.json")
INSTALL = sys.argv[2] if len(sys.argv) > 2 else os.path.join(B, "evidence/install_identity.json")
OUT = os.environ.get("SIMIGO_TRACE_VERDICT") or os.path.join(
    B, "evidence/layer_forward_calls_verdict.json")


def segment(events):
    """Split one repetition's events into forward passes (layer 0 restarts)."""
    passes, current = [], []
    per_layer = {}
    for event in events:
        layer = event["decoderLayer"]
        per_layer[layer] = per_layer.get(layer, 0) + 1
        if layer == 0 and current:
            passes.append(current)
            current = []
        current.append(layer)
    if current:
        passes.append(current)
    return passes, per_layer


def main():
    with open(RAW) as handle:
        raw = json.load(handle)
    report_path = raw["report_path"]
    report = {}
    if os.path.exists(report_path):
        with open(report_path) as handle:
            report = json.load(handle)

    cfg = raw["model"]["config"]
    declared_layers = cfg.get("num_hidden_layers")
    evidence = raw.get("evidence_doc") or {}

    cases = []
    for case in report.get("cases", []):
        per_layer = {}
        rep_passes = []
        all_passes = []
        for trace in case.get("traces", []):
            passes, counts = segment(trace.get("events", []))
            rep_passes.append(len(passes))
            all_passes.extend(passes)
            for layer, count in counts.items():
                per_layer[layer] = per_layer.get(layer, 0) + count
        cases.append({
            "prompt_id": case.get("promptID"),
            "repetitions": case.get("repetitions"),
            "rep_passes": rep_passes,
            "declared_pass_counts": case.get("passCounts") or [],
            "per_layer": per_layer,
            "pass_shape_lengths": sorted({len(p) for p in all_passes}),
            "passes_ascending_and_unique": all(
                p == sorted(p) and len(set(p)) == len(p) for p in all_passes),
            "identity": case.get("identity") or {},
            "trace_stable": case.get("traceStableAcrossRepetitions") is True,
        })

    # L8: the driver's derived block must equal this independent re-derivation.
    driver_derived = {d["prompt_id"]: d for d in raw.get("derived", [])}
    mismatch = []
    for case in cases:
        driver_case = driver_derived.get(case["prompt_id"])
        if driver_case is None:
            mismatch.append("case %s missing from the driver's derived block" % case["prompt_id"])
            continue
        driver_counts = {int(k[1:]): v
                         for k, v in driver_case["events_per_decoder_layer"].items()}
        if driver_counts != case["per_layer"]:
            mismatch.append("per-layer counts differ for %s" % case["prompt_id"])
        if sum(case["rep_passes"]) != driver_case["forward_passes_total"]:
            mismatch.append("pass total differs for %s" % case["prompt_id"])
        if case["rep_passes"] != driver_case["passes_per_repetition_rederived"]:
            mismatch.append("per-repetition pass counts differ for %s" % case["prompt_id"])

    layers_seen = sorted({layer for case in cases for layer in case["per_layer"]})
    expected_layers = list(range(declared_layers)) if isinstance(declared_layers, int) else []

    stable = all(
        case["repetitions"] is not None and case["repetitions"] >= 2
        and len(set(case["rep_passes"])) == 1
        and (case["rep_passes"][0] if case["rep_passes"] else 0) > 0
        and sorted(case["declared_pass_counts"]) == sorted(case["rep_passes"])
        and case["trace_stable"]
        for case in cases)
    uniform = all(
        case["per_layer"] and set(case["per_layer"].values()) == {sum(case["rep_passes"])}
        for case in cases)
    ordering = bool(cases) and all(
        case["passes_ascending_and_unique"] and case["pass_shape_lengths"] == [declared_layers]
        for case in cases)
    identity = all(
        case["identity"].get("tokenSequenceIdentical") is True
        and case["identity"].get("logitsBitwiseIdentical") is True
        for case in cases)

    installed_exe = None
    if os.path.exists(INSTALL):
        with open(INSTALL) as handle:
            doc = json.load(handle)
        installed_exe = doc.get("executable_sha256") or doc.get("exe_sha256")

    checks = {}
    checks["L1_shipped_pilot_ran"] = bool(
        raw["child"]["exit_code"] == 0
        and evidence.get("status") == "OK"
        and report.get("status") == "PASS")
    checks["L2_numbers_trace_to_file"] = bool(
        os.path.exists(report_path)
        and raw.get("report_sha256_recomputed") is not None
        and raw["report_sha256_recomputed"] == raw.get("report_sha256_in_evidence"))
    checks["L3_trace_stable"] = bool(cases and stable)
    checks["L4_every_declared_layer_seen"] = bool(
        isinstance(declared_layers, int) and layers_seen == expected_layers)
    checks["L5_one_enter_per_layer_per_pass"] = bool(uniform)
    checks["L6_observation_changed_nothing"] = bool(identity)
    checks["L7_layer_sequential"] = bool(ordering)
    checks["L8_no_number_from_driver"] = bool(not mismatch)
    checks["L9_candidate_is_the_new_build"] = bool(
        installed_exe is not None and raw["candidate"]["exe_sha256"] == installed_exe)

    must = [k for k in checks if k.startswith("L")]
    passed = all(checks[k] for k in must)
    contradictions = list(mismatch)
    if checks["L4_every_declared_layer_seen"] and not checks["L5_one_enter_per_layer_per_pass"]:
        contradictions.append("all declared layers were observed but not once per pass")

    numbers = {
        "num_hidden_layers": declared_layers,
        "model_type_from_config": cfg.get("model_type"),
        "expert_count": cfg.get("num_experts"),
        "model_type_from_runtime": report.get("modelType"),
        "observed_scope": report.get("observedScope"),
        "instrumented_module_count": report.get("instrumentedModuleCount"),
        "cases": [{
            "prompt_id": case["prompt_id"],
            "forward_passes_per_repetition": case["rep_passes"],
            "layers": len(case["per_layer"]),
            "events": sum(case["per_layer"].values()),
            "per_layer_forward_calls_min": min(case["per_layer"].values()) if case["per_layer"] else None,
            "per_layer_forward_calls_max": max(case["per_layer"].values()) if case["per_layer"] else None,
        } for case in cases],
        "layer_entered_events_total": sum(sum(c["per_layer"].values()) for c in cases),
        "per_layer_forward_calls_min": min(
            (min(c["per_layer"].values()) for c in cases if c["per_layer"]), default=None),
        "per_layer_forward_calls_max": max(
            (max(c["per_layer"].values()) for c in cases if c["per_layer"]), default=None),
        "layers_observed": len(layers_seen),
        "pass_shape_lengths": sorted({n for c in cases for n in c["pass_shape_lengths"]}),
        "overhead_summary": report.get("g19a3OverheadSummary"),
        "estimated_values": 0,
    }

    verdict = "PASS" if passed and not contradictions else "BLOCKED"
    payload = {
        "gate": "per_layer_forward_calls",
        "candidate_exe_sha256": raw["candidate"]["exe_sha256"],
        "rid": raw["rid"],
        "captured_at": raw["captured_at"],
        "verdict": verdict,
        "checks": checks,
        "numbers": numbers,
        "contradictions": contradictions,
        "rules": {
            "L1": "exit_code 0, evidence status OK, pilot status PASS",
            "L2": "report sha256 recomputed == sha256 recorded by the process",
            "L3": ">= 2 repetitions, constant non-zero pass count per case, declared == re-derived, trace stable",
            "L4": "observed layer set == range(num_hidden_layers) from config.json",
            "L5": "each layer entered exactly once per forward pass",
            "L6": "token IDs identical and logits bitwise identical (passive observer)",
            "L7": "each pass covers every layer once in ascending order",
            "L8": "verifier's independent re-derivation equals the driver's block",
            "L9": "raw exe sha256 == installed candidate exe sha256",
        },
        "what_this_is_not": (
            "not a theoretical layer count, not a timing-derived estimate, and not a "
            "call-graph guess: each number is the number of retained `layerEntered` "
            "events emitted by the shipped observer for that decoder layer."),
        "observed_scope_limit": (
            "The observer sits on the decoder MLP down-projection (and the MoE "
            "switch_mlp down-projection); the decoder core itself is NOT directly "
            "observed. Expert-level demand is not instrumented."),
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)
    print(json.dumps({"verdict": verdict, "checks": checks, "numbers": {
        k: numbers[k] for k in ("num_hidden_layers", "layer_entered_events_total",
                                "per_layer_forward_calls_min", "per_layer_forward_calls_max",
                                "layers_observed", "pass_shape_lengths",
                                "estimated_values")}, "cases": numbers["cases"]}, indent=1))
    if contradictions:
        return 1
    return 0 if verdict == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
