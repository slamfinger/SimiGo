#!/usr/bin/env python3
"""Launch the installed candidate as a GUI app and record what is reachable.

Why this exists
  The GUI gate needs one real user operation inside the installed candidate. This
  host has Accessibility but not Screen Recording (evidence/gui_prerequisite_probe.json),
  so a visual capture cannot be produced here. What CAN be produced is everything
  else: the process identity, the accessibility tree, whether a window or popover
  can be opened at all, and the non-interference bracket around the launch.

  That matters because the previous batch's notes said "no window appears" on a
  different binary. Whether the panel is reachable is a property of the product,
  not of the permission, and it has to be measured on this candidate.

What this script does NOT do
  It never types a prompt, never claims the gate passed, and does not ask for any
  permission. If no window opens it records that, with the attempts, and stops.

usage: run_gui_probe.py [tag]
Exit codes: 0 evidence written, 3 setup failed.
"""
import json
import os
import subprocess
import sys
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B, "install/SimiGo.app")
REPO = "/Users/mr.simi/Documents/SimiGo"
TAG = sys.argv[1] if len(sys.argv) > 1 else "gui1"
RUN = os.path.join(B, "runs", TAG)
EVID = os.path.join(B, "evidence")


def run(argv, timeout=60):
    start = time.time()
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return {"argv": argv, "exit_code": p.returncode,
                "stdout": p.stdout[:4000], "stderr": p.stderr[:4000],
                "wall_seconds": round(time.time() - start, 2)}
    except subprocess.TimeoutExpired:
        return {"argv": argv, "exit_code": None, "error": "timeout",
                "wall_seconds": round(time.time() - start, 2)}


def jxa(script, timeout=60):
    """Run a JXA one-liner and keep the raw result."""
    return run(["osascript", "-l", "JavaScript", "-e", script], timeout=timeout)


def pids_for(exe):
    p = subprocess.run(["pgrep", "-f", exe], capture_output=True, text=True)
    return [int(x) for x in p.stdout.split() if x.strip().isdigit()]


def main():
    for path in (os.path.join(RUN, "home"), os.path.join(RUN, "cache"),
                 os.path.join(RUN, "state-graph"), os.path.join(RUN, "logs")):
        os.makedirs(path, exist_ok=True)
    exe = os.path.join(APP, "Contents/MacOS/SimiGo")
    if not os.path.exists(exe):
        print("candidate app missing at %s" % APP, file=sys.stderr)
        return 3

    env = {
        "SIMIGO_HOME": os.path.join(RUN, "home"),
        "SIMIGO_CACHE_ROOT": os.path.join(RUN, "cache"),
        "SIMIGO_STATE_GRAPH_STORE": os.path.join(RUN, "state-graph/reference-graph-v1.json"),
    }
    pre = os.path.join(EVID, "gui_%s_snapshot_pre.json" % TAG)
    run([sys.executable, os.path.join(REPO, "tools/rc_noninterference.py"),
         "--phase", "gui_%s_pre" % TAG, "--out", pre], timeout=300)

    launch_argv = ["open", "-n", "-F"]
    for key, value in env.items():
        launch_argv += ["--env", "%s=%s" % (key, value)]
    launch_argv += ["--stdout", os.path.join(RUN, "logs/gui_stdout.log"),
                    "--stderr", os.path.join(RUN, "logs/gui_stderr.log"), APP]
    launched = run(launch_argv, timeout=60)

    pids = []
    for _ in range(40):
        pids = pids_for(exe)
        if pids:
            break
        time.sleep(0.25)

    result = {
        "tag": TAG,
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "candidate": APP,
        "candidate_exe_sha256": None,
        "launch": {"argv": launch_argv, "result": launched,
                   "isolated_roots": env, "pids": pids,
                   "launch_style": ("LaunchServices `open -n -F --env`, i.e. the same "
                                    "path a user's click takes, not a pty exec")},
        "attempts": [],
        "screen_recording": None,
    }
    if not pids:
        result["finding"] = "the candidate did not stay up when opened via LaunchServices"
        write(result)
        return 0
    pid = pids[0]
    result["candidate_exe_sha256"] = sha256_of(exe)
    result["launch"]["pid"] = pid
    result["launch"]["ps"] = run(["ps", "-o", "pid,etime,stat,command", "-p", str(pid)])
    result["launch"]["env_seen"] = run(["ps", "eww", "-p", str(pid)])
    time.sleep(3)

    scripts = [
        ("A1 process + activation policy",
         'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
         'JSON.stringify({exists: p.exists(), frontmost: p.frontmost(), backgroundOnly: p.backgroundOnly()})'),
        ("A2 AX menu bars / items / windows",
         'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
         'const out = {bars: [], windows: 0, windowTitles: [], error: null};'
         'try { for (let b = 0; b < p.menuBars.length; b++) { const bar = p.menuBars[b];'
         ' const rec = {bar: b, items: 0, titles: [], itemRoles: []};'
         ' try { rec.items = bar.menuBarItems.length;'
         '  for (let i = 0; i < rec.items; i++) { const item = bar.menuBarItems[i];'
         '   try { rec.titles.push(String(item.title())); } catch (e) { rec.titles.push("ERR"); }'
         '   try { rec.itemRoles.push(String(item.role())); } catch (e) { rec.itemRoles.push("ERR"); } } }'
         ' catch (e) { rec.error = String(e); } out.bars.push(rec); } } catch (e) { out.error = String(e); }'
         'try { out.windows = p.windows.length;'
         ' for (let i = 0; i < out.windows; i++) { out.windowTitles.push(String(p.windows[i].name())); } }'
         ' catch (e) { out.error = (out.error || "") + " windows:" + e; }'
         'JSON.stringify(out)'),
        ("A2b status item identity (the extras bar, not the main menu bar)",
         'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
         'const out = {found: false, role: null, description: null, position: null, size: null, actions: []};'
         'try { const item = p.menuBars[1].menuBarItems[0]; out.found = true;'
         ' out.role = String(item.role());'
         ' try { out.description = String(item.description()); } catch (e) {}\n'
         ' try { out.position = item.position(); } catch (e) { out.position = String(e); }'
         ' try { out.size = item.size(); } catch (e) { out.size = String(e); }'
         ' const acts = item.actions(); for (let i = 0; i < acts.length; i++) out.actions.push(String(acts[i].name())); }'
         ' catch (e) { out.error = String(e); }'
         'JSON.stringify(out)'),
        ("A3 AXPress the status item, then look for a new window/popover",
         'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
         'const before = p.windows.length; let pressError = null;'
         'try { p.menuBars[1].menuBarItems[0].actions[0].perform(); } catch (e) { pressError = String(e); }'
         'delay(2.5); JSON.stringify({windowsBefore: before, windowsAfter: p.windows.length, pressError: pressError})'),
        ("A4 CGWindowList for this pid",
         'ObjC.import("CoreGraphics"); const pid = %d;'
         'const arr = ObjC.deepUnwrap($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID));'
         'if (!arr) { JSON.stringify({callerSeesWindows: 0, note: "the list itself is empty: this process cannot see any window on screen"}); }'
         'else { let mine = []; for (let i = 0; i < arr.length; i++) { if (arr[i].kCGWindowOwnerPID === pid) mine.push({name: arr[i].kCGWindowName, layer: arr[i].kCGWindowLayer}); }'
         ' JSON.stringify({callerSeesWindows: arr.length, mine: mine}); }' % pid),
        ("A5 does AXPress dispatch at all? press the app's own Quit item",
         'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
         'let pressed = null; let error = null;'
         'try { const items = p.menuBars[0].menuBarItems[1].menus[0].menuItems();'
         ' for (let i = 0; i < items.length; i++) { const t = String(items[i].title());'
         '  if (t.indexOf("Quit") >= 0) { items[i].actions[0].perform(); pressed = t; } } }'
         'catch (e) { error = String(e); }'
         'delay(3); JSON.stringify({pressed: pressed, error: error, stillRunning: p.exists(),'
         ' interpretation: "if the app is still running after pressing its own Quit item, AXPress is accepted but the action never dispatches"})'),
    ]
    for name, script in scripts:
        result["attempts"].append({"attempt": name, "result": jxa(script)})

    shot = os.path.join(EVID, "gui_%s_shot.png" % TAG)
    if os.path.exists(shot):
        os.unlink(shot)
    capture = run(["screencapture", "-x", shot], timeout=60)
    result["screen_recording"] = {
        "argv": capture["argv"], "exit_code": capture["exit_code"],
        "stderr": capture.get("stderr", ""),
        "file_exists": os.path.exists(shot),
        "bytes": os.path.getsize(shot) if os.path.exists(shot) else 0,
        # screencapture writes into evidence/ only when it worked; never claim a
        # picture of the product from a zero-byte file
    }

    quit_result = run(["osascript", "-e", 'tell application "SimiGo" to quit'], timeout=30)
    for _ in range(20):
        if not pids_for(exe):
            break
        time.sleep(0.25)
    result["quit"] = {"result": quit_result, "still_running": bool(pids_for(exe))}

    post = os.path.join(EVID, "gui_%s_snapshot_post.json" % TAG)
    run([sys.executable, os.path.join(REPO, "tools/rc_noninterference.py"),
         "--phase", "gui_%s_post" % TAG, "--out", post], timeout=300)
    diff = os.path.join(EVID, "gui_%s_snapshot_diff.json" % TAG)
    result["noninterference"] = {
        "pre": os.path.basename(pre), "post": os.path.basename(post),
        "diff": os.path.basename(diff),
        "diff_result": run([sys.executable,
                            os.path.join(REPO, "tools/rc_noninterference_diff.py"),
                            pre, post, diff, "--allow-prefix", EVID], timeout=120),
    }

    windows_after = 0
    dispatch = None
    for attempt in result["attempts"]:
        name = attempt["attempt"]
        if name.startswith("A3"):
            try:
                windows_after = json.loads(attempt["result"]["stdout"]).get("windowsAfter", 0)
            except Exception:
                pass
        if name.startswith("A5"):
            try:
                dispatch = json.loads(attempt["result"]["stdout"])
            except Exception:
                pass
    result["dispatch"] = dispatch
    if windows_after:
        result["finding"] = ("a window is reachable through accessibility; the remaining "
                            "gap is the visual capture and the prompt itself")
    elif dispatch and dispatch.get("stillRunning") and dispatch.get("pressed"):
        result["finding"] = (
            "AXPress is accepted but never dispatches: pressing the app's own Quit item "
            "(%r) left it running. So nothing can be driven through accessibility on this "
            "host - not the status item, not the menu, so not a prompt. Two independent "
            "reasons, both measured: no Screen Recording (no visual proof) and no dispatch "
            "(no interaction)." % dispatch.get("pressed"))
    else:
        result["finding"] = ("no window or popover became reachable through accessibility "
                            "on this candidate, so there is nothing to type a prompt into; "
                            "recorded as a reachability finding, not as a permission excuse")
    write(result)
    return 0


def sha256_of(path):
    import hashlib
    with open(path, "rb") as handle:
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write(payload):
    out = os.path.join(B, "evidence/gui_%s_ax_probe.json" % TAG)
    with open(out, "w") as handle:
        json.dump(payload, handle, indent=1)
        handle.write("\n")
    print(json.dumps({"out": os.path.basename(out),
                      "pids": payload["launch"].get("pids"),
                      "finding": payload.get("finding"),
                      "screen_recording": payload.get("screen_recording", {}).get("exit_code")
                      if payload.get("screen_recording") else None}, indent=1))


if __name__ == "__main__":
    sys.exit(main())
