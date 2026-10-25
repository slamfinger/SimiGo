#!/usr/bin/env python3
"""Collect the GUI gate in one pass, with the machine's owner doing the one thing
an agent cannot: click the status item and send a prompt.

Why this exists
  The GUI gate (`install_and_operate`) needs one ordinary user operation inside the
  installed candidate. Two independent obstacles were measured on this host
  (REPORT sec. 10.1-10.2): no Screen Recording, and AXPress is accepted but never
  dispatched, so no automation channel can drive the app. The operator's own click
  is therefore the only path left - but a click alone is not evidence unless the
  identity, the generation trace and the isolation bracket are captured in the same
  isolated roots. This script is that bracket.

What it does
  1. pre-snapshot of real user state (tools/rc_noninterference.py)
  2. launches the installed candidate through LaunchServices (`open -n -F --env`)
     with SIMIGO_HOME / cache / state-graph pointed into runs/<tag>/
  3. prints what the operator should do, then waits for them
  4. captures: screenshot (screencapture -x), the product's own generation trace
     (<SIMIGO_HOME>/logs/native_mlx_trace.log), app stdout/stderr, post-snapshot,
     and the pre/post differential
  5. writes evidence/gui_walkthrough.json with the raw numbers and, ONLY when every
     condition holds, also writes evidence/m3_stage_b_gui_inference.json with
     real_model_output=true - the file the existing gate reads.

What it will not do
  It never types into the app, never presses an AX action, never edits product code,
  and never sets real_model_output from anything except (operator attestation AND a
  non-empty screenshot AND at least one generation in the isolated trace AND zero
  real-user-state writes). A missing condition leaves the gate input file absent on
  purpose: an absent file is read as BLOCKED by verify_batch.py, which is correct.

usage:
  gui_walkthrough.py [tag] [--operator NAME]            interactive, waits for you
  gui_walkthrough.py [tag] --wait-seconds 8             no human; still BLOCKED
Exit codes: 0 evidence written, 3 the candidate is missing.
"""
import hashlib
import json
import os
import subprocess
import sys
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Which binary the operator is being asked to operate. Explicit override, because
# the batch now holds two installed candidates and a GUI run against the older
# one cannot close the gate for the newer one.
APP = os.path.abspath(os.environ.get("GUI_APP") or os.path.join(B, "install/SimiGo.app"))
EXE = os.path.join(APP, "Contents/MacOS/SimiGo")
REPO = "/Users/mr.simi/Documents/SimiGo"
EVID = os.path.join(B, "evidence")
# a permitted-but-uniform 4K frame compresses to tens of KB; a real desktop
# capture on this host measured 5.2 MB. The floor rejects the degenerate case.
MIN_SCREENSHOT_BYTES = 200_000

ARGS = sys.argv[1:]
TAG = "walk1"
OPERATOR = None
WAIT_SECONDS = None
i = 0
while i < len(ARGS):
    a = ARGS[i]
    if a == "--operator" and i + 1 < len(ARGS):
        OPERATOR = ARGS[i + 1]
        i += 2
    elif a == "--wait-seconds" and i + 1 < len(ARGS):
        WAIT_SECONDS = float(ARGS[i + 1])
        i += 2
    else:
        TAG = a
        i += 1
RUN = os.path.join(B, "runs", TAG)


def run(argv, timeout=300):
    start = time.time()
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return {"argv": argv, "exit_code": p.returncode,
                "stdout": p.stdout[:8000], "stderr": p.stderr[:8000],
                "wall_seconds": round(time.time() - start, 2)}
    except subprocess.TimeoutExpired:
        return {"argv": argv, "exit_code": None, "error": "timeout",
                "wall_seconds": round(time.time() - start, 2)}


def pids_for(exe):
    p = subprocess.run(["pgrep", "-f", exe], capture_output=True, text=True)
    return [int(x) for x in p.stdout.split() if x.strip().isdigit()]


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def count_trace(path):
    """Count the product's own trace events. arrive == request entered the
    protocol layer; session= == one generation actually ran.

    `[NODE] backend=` and `[READY] ` are emitted by Service.log from inside the start
    path only (Service.swift:949 / :897,:989), so they can only appear if the Service
    facade actually started - not if someone called NativeMLX directly. `[CFG]` is
    deliberately NOT used: resolveConfig runs at launch too and fired with nobody
    clicking start (see gui_walk2), so it would be a false positive."""
    out = {"trace_file": path, "exists": os.path.exists(path),
           "bytes": 0, "request_events": 0, "generation_events": 0,
           "service_markers": [], "service_facade_observed": False,
           "models": [], "sessions": []}
    if not out["exists"]:
        return out
    out["bytes"] = os.path.getsize(path)
    with open(path, errors="replace") as handle:
        for line in handle:
            if "[PROTOCOL] arrive" in line:
                out["request_events"] += 1
            if "[MLX] session=" in line:
                out["generation_events"] += 1
                out["sessions"].append(line.strip()[-260:])
            if "[NODE] backend=" in line or "[READY] " in line:
                out["service_markers"].append(line.strip()[-220:])
    out["service_facade_observed"] = bool(out["service_markers"])
    out["service_markers"] = out["service_markers"][:6]
    out["models"] = sorted({s.split("model=")[1].split()[0]
                            for s in out["sessions"] if "model=" in s})
    return out


def instructions(env):
    print("""
------------------------------------------------------------------
GUI gate: one ordinary operation, by you, in the installed candidate.
------------------------------------------------------------------
The app is being opened from %s
  executable SHA-256 %s
  (this is the exact binary your click will be attributed to; if it is not the
  candidate you meant to judge, stop and re-run with GUI_APP=<path>)

with isolated roots (nothing touches your real ~/.simigo, Application Support,
defaults or login Keychain):

  SIMIGO_HOME            = %s
  SIMIGO_CACHE_ROOT      = %s
  SIMIGO_STATE_GRAPH_STORE = %s

Please do, in this order:
  1. find the SimiGo item in the menu bar (if you cannot see it, that itself is
     the finding - say so below) and click it; the panel should drop down
  2. type any ordinary prompt and send it; wait for the answer to appear
  3. optionally open Settings... once, then close it

Then come back to this terminal and press Return. I will capture the screenshot,
the app's own generation trace, and the isolation differential from here.
""" % (APP, sha256_of(EXE), env["SIMIGO_HOME"], env["SIMIGO_CACHE_ROOT"],
       env["SIMIGO_STATE_GRAPH_STORE"]))


def main():
    if not os.path.exists(EXE):
        print("candidate app missing at %s" % APP, file=sys.stderr)
        return 3
    for path in (os.path.join(RUN, "home"), os.path.join(RUN, "cache"),
                 os.path.join(RUN, "state-graph"), os.path.join(RUN, "logs")):
        os.makedirs(path, exist_ok=True)

    env = {
        "SIMIGO_HOME": os.path.join(RUN, "home"),
        "SIMIGO_CACHE_ROOT": os.path.join(RUN, "cache"),
        "SIMIGO_STATE_GRAPH_STORE": os.path.join(RUN, "state-graph/reference-graph-v1.json"),
    }
    pre = os.path.join(EVID, "gui_%s_snapshot_pre.json" % TAG)
    run([sys.executable, os.path.join(REPO, "tools/rc_noninterference.py"),
         "--phase", "gui_%s_pre" % TAG, "--out", pre])

    launch_argv = ["open", "-n", "-F"]
    for key, value in env.items():
        launch_argv += ["--env", "%s=%s" % (key, value)]
    launch_argv += ["--stdout", os.path.join(RUN, "logs/gui_stdout.log"),
                    "--stderr", os.path.join(RUN, "logs/gui_stderr.log"), APP]
    launched = run(launch_argv, timeout=120)

    pids = []
    for _ in range(60):
        pids = pids_for(EXE)
        if pids:
            break
        time.sleep(0.25)

    result = {
        "tag": TAG,
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "candidate": APP,
        "candidate_exe_sha256": sha256_of(EXE),
        "candidate_identity_match": next(
            (name for name, path in (
                ("install_identity_v5_candidate.json", "evidence/install_identity_v5_candidate.json"),
                ("install_identity_new_candidate.json", "evidence/install_identity_new_candidate.json"))
             if os.path.exists(os.path.join(B, path))
             and json.load(open(os.path.join(B, path))).get("executable_sha256") == sha256_of(EXE)),
            None),
        "launch": {"argv": launch_argv, "result": launched,
                   "isolated_roots": env, "pids": pids,
                   "launch_style": "LaunchServices `open -n -F --env`, the path a "
                                   "user's double-click takes"},
        "operator": {"label": OPERATOR, "attestation": None,
                     "waited_seconds": None, "mode": None},
    }
    if not pids:
        result["finding"] = "the candidate did not stay up when opened via LaunchServices"
        return write(result)
    pid = pids[0]
    result["launch"]["pid"] = pid
    result["launch"]["ps"] = run(["ps", "-o", "pid,etime,stat,command", "-p", str(pid)])
    ps_env = run(["ps", "eww", "-p", str(pid)])
    result["launch"]["isolated_home_seen_by_app"] = (
        "SIMIGO_HOME=%s" % env["SIMIGO_HOME"]) in ps_env.get("stdout", "")
    result["launch"]["env_seen"] = {"exit_code": ps_env.get("exit_code"),
                                    "matched": result["launch"]["isolated_home_seen_by_app"]}
    time.sleep(3)

    instructions(env)
    started = time.time()
    if WAIT_SECONDS is not None:
        result["operator"]["mode"] = "non-interactive (--wait-seconds)"
        time.sleep(WAIT_SECONDS)
        result["operator"]["attestation"] = None
    elif sys.stdin.isatty():
        result["operator"]["mode"] = "interactive"
        try:
            answer = input("Press Return when you are done (or type a note first): ").strip()
        except EOFError:
            answer = ""
        result["operator"]["attestation"] = answer or "operator pressed Return"
    else:
        result["operator"]["mode"] = "stdin not a tty; nobody operated the app"
    result["operator"]["waited_seconds"] = round(time.time() - started, 1)

    shot = os.path.join(EVID, "gui_%s_shot.png" % TAG)
    if os.path.exists(shot):
        os.unlink(shot)
    capture = run(["screencapture", "-x", shot], timeout=120)
    # Screen Recording is now granted on this host, so "the file has bytes" no
    # longer separates a real capture from a permitted-but-black one. A granted
    # capture of an unowned display can succeed and still be uniform; that must
    # not become the picture that closes a product GUI gate. Two captures a
    # second apart are compared (a live desktop changes: menu bar clock), and the
    # pixel shape plus a byte floor are recorded next to them.
    shot_b = os.path.join(EVID, "gui_%s_shot_b.png" % TAG)
    if os.path.exists(shot_b):
        os.unlink(shot_b)
    time.sleep(1.0)
    capture_b = run(["screencapture", "-x", shot_b], timeout=120)
    shape = run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", shot], timeout=30)
    shape_text = (shape.get("stdout") or "").replace("\n", " ").strip()
    bytes_a = os.path.getsize(shot) if os.path.exists(shot) else 0
    bytes_b = os.path.getsize(shot_b) if os.path.exists(shot_b) else 0
    sha_a = sha256_of(shot) if bytes_a else None
    sha_b = sha256_of(shot_b) if bytes_b else None
    result["screenshot"] = {
        "argv": capture["argv"], "exit_code": capture["exit_code"],
        "stderr": capture.get("stderr", ""),
        "file_exists": os.path.exists(shot),
        "bytes": bytes_a,
        "sha256": sha_a,
        "pixel_shape": shape_text,
        "min_bytes_floor": MIN_SCREENSHOT_BYTES,
        "second_argv": capture_b["argv"],
        "second_exit_code": capture_b["exit_code"],
        "second_bytes": bytes_b,
        "second_sha256": sha_b,
        "consecutive_captures_differ": bool(sha_a) and bool(sha_b) and sha_a != sha_b,
    }

    result["app_logs"] = {
        "stdout": tail(os.path.join(RUN, "logs/gui_stdout.log")),
        "stderr": tail(os.path.join(RUN, "logs/gui_stderr.log")),
    }
    result["native_mlx_trace"] = count_trace(
        os.path.join(env["SIMIGO_HOME"], "logs/native_mlx_trace.log"))
    result["service_facade"] = {
        "observed": result["native_mlx_trace"]["service_facade_observed"],
        "evidence": ("[NODE] backend= / [READY] lines in the same isolated trace. Both are "
                     "emitted from inside Service.start's own path (Service.swift:949, :989), "
                     "so they mean the facade started, not just NativeMLX. [CFG] is excluded "
                     "on purpose: it also fires at launch with nobody clicking start"),
        "markers": result["native_mlx_trace"]["service_markers"],
    }
    result["bootstrap_report"] = read_json(
        os.path.join(env["SIMIGO_HOME"], "manifests/bootstrap-report.json"))

    alive = bool(pids_for(EXE))
    result["quit"] = {
        "still_running_before_quit": alive,
        "result": run(["osascript", "-e", 'tell application "SimiGo" to quit'], timeout=60),
    }
    for _ in range(40):
        if not pids_for(EXE):
            break
        time.sleep(0.25)
    result["quit"]["still_running_after_quit"] = bool(pids_for(EXE))

    post = os.path.join(EVID, "gui_%s_snapshot_post.json" % TAG)
    run([sys.executable, os.path.join(REPO, "tools/rc_noninterference.py"),
         "--phase", "gui_%s_post" % TAG, "--out", post])
    diff = os.path.join(EVID, "gui_%s_snapshot_diff.json" % TAG)
    diff_run = run([sys.executable,
                    os.path.join(REPO, "tools/rc_noninterference_diff.py"),
                    pre, post, diff, "--allow-prefix", EVID], timeout=180)
    result["noninterference"] = {
        "pre": os.path.basename(pre), "post": os.path.basename(post),
        "diff": os.path.basename(diff), "diff_result": diff_run,
        "diff_payload": read_json(diff),
    }
    return write(result)


def tail(path, limit=6000):
    if not os.path.exists(path):
        return {"exists": False}
    with open(path, errors="replace") as handle:
        data = handle.read()
    return {"exists": True, "bytes": len(data), "tail": data[-limit:]}


def read_json(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path) as handle:
            return json.load(handle)
    except Exception as exc:
        return {"unreadable": str(exc)}


def write(result):
    """Decide the verdict from the recorded numbers, then write.

    Every condition below is a measurement, not an argument: the operator's own
    attestation, a screenshot with bytes in it, at least one generation in the
    product's own trace for THIS isolated root, and a clean differential."""
    trace = result.get("native_mlx_trace") or {}
    diff = (result.get("noninterference") or {}).get("diff_payload") or {}
    checks = {
        "process_stayed_up": bool(result["launch"].get("pids")),
        "isolated_home_seen_by_app": bool(result["launch"].get("isolated_home_seen_by_app")),
        "operator_attested": bool((result.get("operator") or {}).get("attestation")),
        "screenshot_present": bool((result.get("screenshot") or {}).get("bytes"))
        and (result.get("screenshot") or {}).get("bytes", 0) >= MIN_SCREENSHOT_BYTES,
        "generation_observed": bool(trace.get("generation_events")),
        "real_user_state_write_count_zero": diff.get("real_user_state_write_count") == 0,
        "violation_events_zero": diff.get("violation_events") == 0,
    }
    result["checks"] = checks
    shot = result.get("screenshot") or {}
    # an observation, not a condition: identical consecutive captures do not
    # disprove a real screenshot, they just mean this run cannot rule out a
    # uniform frame, and the operator should know that before trusting the image
    result["screenshot_content_signal"] = {
        "meets_byte_floor": (shot.get("bytes") or 0) >= MIN_SCREENSHOT_BYTES,
        "consecutive_captures_differ": shot.get("consecutive_captures_differ"),
        "uniform_frame_not_excluded": shot.get("consecutive_captures_differ") is False,
        "note": ("a permitted capture of an unowned display can be all black and still "
                 "have bytes; the byte floor and the second capture are here so a "
                 "blank frame is visible in the record rather than silently accepted"),
    }
    missing = [k for k, v in checks.items() if not v]
    result["real_model_output"] = not missing
    result["also_closes"] = {
        "service_facade_executed": bool(result.get("service_facade", {}).get("observed")),
        "note": ("a GUI start runs Service.startSelected() -> Service.internalStart(), "
                 "which is the facade the Service/HTTP gate deliberately did not execute; "
                 "no test target and no headless entry calls it "
                 "(evidence/service_facade_inventory.json)"),
    }
    if missing:
        result["finding"] = (
            "GUI gate stays BLOCKED: %s. An absent gate input file is read as BLOCKED "
            "by verify_batch.py, which is the intended behaviour." % ", ".join(missing))
        result["how_to_close"] = [
            "grant Screen Recording to the app that runs this script (System Settings > "
            "Privacy & Security > Screen & System Audio Recording)",
            "re-run: driver/gui_walkthrough.py walked --operator <your name>",
            "click the SimiGo menu bar item, send one ordinary prompt, come back and "
            "press Return",
        ]
    else:
        result["finding"] = ("GUI gate inputs satisfied in one pass: the operator's own "
                            "click produced %d generation(s) through the installed "
                            "candidate while the real user state stayed untouched."
                            % trace.get("generation_events"))

    out = os.path.join(EVID, "gui_%s_walkthrough.json" % result["tag"])
    with open(out, "w") as handle:
        json.dump(result, handle, indent=1)
        handle.write("\n")

    gate_input = os.path.join(EVID, "m3_stage_b_gui_inference.json")
    if result["real_model_output"]:
        payload = {
            "real_model_output": True,
            "source": os.path.basename(out),
            "captured_at": result["captured_at"],
            "candidate_exe_sha256": result["candidate_exe_sha256"],
            "operator_attestation": result["operator"]["attestation"],
            "screenshot": result["screenshot"],
            "native_mlx_trace": result["native_mlx_trace"],
            "service_facade": result.get("service_facade"),
            "noninterference": {k: v for k, v in result["noninterference"].items()
                                if k != "diff_payload"},
            "checks": result["checks"],
            "note": ("written by driver/gui_walkthrough.py only after all conditions "
                     "held; this file is the input the install_and_operate gate reads"),
        }
        with open(gate_input, "w") as handle:
            json.dump(payload, handle, indent=1)
            handle.write("\n")
    elif os.path.exists(gate_input):
        # never leave a stale PASS-shaped input behind from an earlier attempt
        os.unlink(gate_input)

    print(json.dumps({"out": os.path.basename(out),
                      "real_model_output": result["real_model_output"],
                      "checks": checks,
                      "generation_events": trace.get("generation_events"),
                      "service_facade_observed": trace.get("service_facade_observed"),
                      "screenshot_bytes": (result.get("screenshot") or {}).get("bytes"),
                      "finding": result["finding"]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
