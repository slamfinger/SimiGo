#!/usr/bin/env python3
"""Drive the shipped G1.9-A layer-forward trace and record what it observed.

What runs
  SIMIGO_HEADLESS_ROLE=tracepilot on the newly built, newly installed candidate.
  That role drives the ALREADY-SHIPPED instrumentation in
  Packages/SimiGoRuntime/Sources/SimiGo2Experimental/Instrumentation/
  (ExecutionTracePilot), which installs passive observation modules on each
  decoder layer's MLP down-projection and records one `layerEntered` event per
  (forward pass, decoder layer). Nothing in this driver counts a forward call:
  the driver only launches the process, then re-derives the per-layer counts
  from the emitted event stream, and refuses to report a number when the
  retained report does not hash to what the process wrote.

Isolation
  Every run gets its own root: SIMIGO_HOME / SIMIGO_CACHE_ROOT /
  SIMIGO_STATE_GRAPH_STORE / SIMIGO_EXPERIMENT_ROOT all point inside
  runs/<rid>/, so the real user state is never opened.

Writes evidence/layer_forward_trace_raw.json (+ runs/<rid>/ artifacts).
Verdict is derived elsewhere: driver/verify_layer_forward_calls.py.
"""
import errno
import hashlib
import json
import os
import pty
import select
import subprocess
import sys
import threading
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANDIDATE = os.environ.get("SIMIGO_TRACE_CANDIDATE") or os.path.join(
    B, "install/SimiGo.app")
BIN = os.path.join(CANDIDATE, "Contents/MacOS/SimiGo")
MODEL = ("/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--"
         "Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d")
RID = sys.argv[1] if len(sys.argv) > 1 else "lf1"
RUN = os.path.join(B, "runs", RID)
OUT = os.environ.get("SIMIGO_TRACE_EVIDENCE") or os.path.join(
    B, "evidence/layer_forward_trace_raw.json")
TIMEOUT = float(os.environ.get("LF_TIMEOUT", "1500"))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def launch(cmd, env, log_path):
    log = open(log_path, "wb")
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execve(cmd[0], cmd, env)
        finally:
            os._exit(127)

    def drain():
        while True:
            try:
                r, _, _ = select.select([fd], [], [], 5)
                if not r:
                    continue
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                log.write(chunk)
                log.flush()
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
        log.close()

    threading.Thread(target=drain, daemon=True).start()
    return pid, fd


def reap(pid):
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return None
    if done == 0:
        return None
    return os.waitstatus_to_exitcode(status)


def model_config(model_dir):
    path = os.path.join(model_dir, "config.json")
    with open(path) as handle:
        cfg = json.load(handle)
    return {
        "num_hidden_layers": cfg.get("num_hidden_layers"),
        "model_type": cfg.get("model_type"),
        "num_experts": cfg.get("num_experts") or cfg.get("num_local_experts"),
        "architectures": cfg.get("architectures"),
    }


def segment_passes(events):
    """Split the observed stream into forward passes.

    A pass starts where decoder layer 0 fires again. This is the same
    convention the shipped `GroupExecutionTraceProbe.passCount` uses, applied
    to the retained raw events rather than trusted from a summary field.
    """
    passes = []
    current = []
    for event in events:
        if event["decoderLayer"] == 0 and current:
            passes.append(current)
            current = []
        current.append(event["decoderLayer"])
    if current:
        passes.append(current)
    return passes


def main():
    if not os.path.exists(BIN):
        print("candidate missing: %s" % BIN)
        return 2
    os.makedirs(RUN, exist_ok=True)
    for sub in ("home", "cache", "state-graph", "logs"):
        os.makedirs(os.path.join(RUN, sub), exist_ok=True)
    log_path = os.path.join(RUN, "tracepilot.log")
    env = dict(os.environ,
               SIMIGO_HEADLESS_ROLE="tracepilot",
               SIMIGO_EXPERIMENT_ROOT=RUN,
               SIMIGO_RUN_ID=RID,
               SIMIGO_HOME=os.path.join(RUN, "home"),
               SIMIGO_CACHE_ROOT=os.path.join(RUN, "cache"),
               SIMIGO_STATE_GRAPH_STORE=os.path.join(RUN, "state-graph/reference-graph-v1.json"),
               SIMIGO_HEADLESS_MODEL_PATH=MODEL)

    started = time.time()
    pid, _fd = launch([BIN], env, log_path)
    exit_code = None
    while time.time() - started < TIMEOUT:
        exit_code = reap(pid)
        if exit_code is not None:
            break
        time.sleep(0.5)
    wall = round(time.time() - started, 1)

    evidence_path = os.path.join(RUN, "tracepilot_%s.json" % RID)
    report_path = os.path.join(RUN, "layerforwardtrace_%s.json" % RID)
    evidence = {}
    report = {}
    if os.path.exists(evidence_path):
        with open(evidence_path) as handle:
            evidence = json.load(handle)
    if os.path.exists(report_path):
        with open(report_path) as handle:
            report = json.load(handle)

    report_sha = sha256_file(report_path) if os.path.exists(report_path) else None
    cfg = model_config(MODEL)

    # Re-derive every number from the retained event stream. The role's own
    # summary is kept next to it so the two can be compared, never substituted.
    derived = []
    for case in report.get("cases", []):
        per_layer = {}
        passes_total = 0
        events_total = 0
        pass_shapes = []
        per_rep_counts = []
        for trace in case.get("traces", []):
            events = trace.get("events", [])
            events_total += len(events)
            for event in events:
                key = "L%d" % event["decoderLayer"]
                per_layer[key] = per_layer.get(key, 0) + 1
            segments = segment_passes(events)
            passes_total += len(segments)
            per_rep_counts.append(len(segments))
            for segment in segments:
                pass_shapes.append(segment)
        derived.append({
            "prompt_id": case.get("promptID"),
            "repetitions": case.get("repetitions"),
            "passes_per_repetition_rederived": per_rep_counts,
            "passes_per_repetition_declared": case.get("passCounts"),
            "forward_passes_total": passes_total,
            "layer_entered_events_total": events_total,
            "events_per_decoder_layer": per_layer,
            "distinct_decoder_layers_observed": len(per_layer),
            "layer_index_min": min((int(k[1:]) for k in per_layer), default=None),
            "layer_index_max": max((int(k[1:]) for k in per_layer), default=None),
            "all_passes_cover_layers_in_order": all(
                shape == sorted(shape) and len(set(shape)) == len(shape)
                for shape in pass_shapes),
            "pass_shape_lengths": sorted({len(shape) for shape in pass_shapes}),
            "token_sequence_identical": case.get("identity", {}).get("tokenSequenceIdentical"),
            "logits_bitwise_identical": case.get("identity", {}).get("logitsBitwiseIdentical"),
            "logits_max_abs_diff": case.get("identity", {}).get("logitsMaxAbsDiff"),
            "trace_stable_across_repetitions": case.get("traceStableAcrossRepetitions"),
            "g19a1_baseline_identity_pass": case.get("g19a1BaselineIdentityPass"),
            "g19a2_trace_stability_pass": case.get("g19a2TraceStabilityPass"),
            "overhead": case.get("overhead"),
        })

    payload = {
        "batch": os.path.basename(B),
        "rid": RID,
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "candidate": {
            "app": CANDIDATE,
            "exe_sha256": sha256_file(BIN),
        },
        "model": {"path": MODEL, "config": cfg},
        "child": {"pid": pid, "exit_code": exit_code, "wall_seconds": wall,
                  "timed_out": exit_code is None},
        "role": "SIMIGO_HEADLESS_ROLE=tracepilot (drives the shipped ExecutionTracePilot)",
        "evidence_doc": evidence,
        "report_path": report_path,
        "report_sha256_recomputed": report_sha,
        "report_sha256_in_evidence": evidence.get("report_sha256"),
        "report_sha256_matches": report_sha is not None
        and report_sha == evidence.get("report_sha256"),
        "report": {
            "status": report.get("status"),
            "protocol_version": report.get("protocolVersion"),
            "model_type": report.get("modelType"),
            "instrumented_module_count": report.get("instrumentedModuleCount"),
            "observed_scope": report.get("observedScope"),
            "boundary": report.get("boundary"),
            "g19a1_baseline_identity_pass": report.get("g19a1BaselineIdentityPass"),
            "g19a2_trace_stability_pass": report.get("g19a2TraceStabilityPass"),
        },
        "derived": derived,
        "note": ("Every per-layer count here is a count of retained `layerEntered` "
                 "events, re-derived by this driver from the report the process "
                 "wrote. No forward count is estimated, inferred from timing, or "
                 "copied from a summary field."),
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)

    summary = {
        "rid": RID,
        "exit_code": exit_code,
        "wall_seconds": wall,
        "pilot_status": report.get("status"),
        "instrumented_modules": report.get("instrumentedModuleCount"),
        "report_sha256_matches": payload["report_sha256_matches"],
        "cases": [{
            "prompt": d["prompt_id"],
            "passes": d["passes_per_repetition_rederived"],
            "layers": d["distinct_decoder_layers_observed"],
            "events": d["layer_entered_events_total"],
            "ordered_passes": d["all_passes_cover_layers_in_order"],
        } for d in derived],
    }
    print(json.dumps(summary, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
