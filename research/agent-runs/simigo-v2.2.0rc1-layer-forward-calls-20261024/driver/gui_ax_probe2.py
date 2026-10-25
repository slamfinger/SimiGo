#!/usr/bin/env python3
"""Follow-up to run_gui_ax_probe.py: settle two questions the first probe could not.

Question 1 - is the status item really off-screen?
  The first probe read position [-1, 1068] size [20, 24] on a 1920x1080 logical
  screen and called it "x = -1 is outside the screen". That reading was never
  calibrated: no other status item was measured for comparison, and the coordinate
  space was assumed rather than checked. This script measures the frames of the
  other menu bar extras (Control Center, SystemUIServer) and the NSScreen frames in
  the same run, so the SimiGo frame can be compared instead of interpreted by eye.

Question 2 - does AX dispatch, or did the first probe's test just miss?
  The first probe pressed the app's own "Quit SimiGo" menu item without opening the
  parent menu first, saw the process still running, and concluded "AXPress is
  accepted but never dispatches". That conclusion is too strong: on macOS a menu
  item generally only dispatches after its parent menu has been opened
  (AXShowMenu). So this script does it properly - AXShowMenu on the app menu, then
  press "Settings...", and checks whether an NSWindow appears - and separately tries
  AXShowMenu on the status item itself.

What it will not do
  No typing, no synthetic mouse/keyboard events, no permission request, no product
  change. Only AX reads and AX actions addressed to this one app, in an isolated
  root, with a non-interference bracket around it.

usage: gui_ax_probe2.py [tag]
Exit codes: 0 evidence written, 3 the candidate is missing.
"""
import json
import os
import subprocess
import sys
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B, "install/SimiGo.app")
EXE = os.path.join(APP, "Contents/MacOS/SimiGo")
REPO = "/Users/mr.simi/Documents/SimiGo"
TAG = sys.argv[1] if len(sys.argv) > 1 else "gui5"
RUN = os.path.join(B, "runs", TAG)
EVID = os.path.join(B, "evidence")


def run(argv, timeout=120):
    start = time.time()
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return {"argv": argv, "exit_code": p.returncode,
                "stdout": p.stdout[:12000], "stderr": p.stderr[:4000],
                "wall_seconds": round(time.time() - start, 2)}
    except subprocess.TimeoutExpired:
        return {"argv": argv, "exit_code": None, "error": "timeout"}


def jxa(script, timeout=120):
    return run(["osascript", "-l", "JavaScript", "-e", script], timeout=timeout)


def pids_for(exe):
    p = subprocess.run(["pgrep", "-f", exe], capture_output=True, text=True)
    return [int(x) for x in p.stdout.split() if x.strip().isdigit()]


def sha256_of(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


SCRIPTS = [
    ("P1 enumerate every menu bar item of the candidate, with frame and children",
     'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
     'const out = {bars: 0, items: [], error: null};'
     'try { out.bars = p.menuBars.length;'
     ' for (let b = 0; b < out.bars; b++) { const bar = p.menuBars[b];'
     '  const n = bar.menuBarItems.length;'
     '  for (let i = 0; i < n; i++) { const it = bar.menuBarItems[i];'
     '   const rec = {bar: b, index: i, title: null, description: null, position: null,'
     '                size: null, actions: [], children: [], childErrors: []};'
     '   try { rec.title = String(it.title()); } catch (e) {}'
     '   try { rec.description = String(it.description()); } catch (e) {}'
     '   try { rec.position = it.position(); } catch (e) { rec.position = String(e); }'
     '   try { rec.size = it.size(); } catch (e) { rec.size = String(e); }'
     '   try { const a = it.actions(); for (let k = 0; k < a.length; k++) rec.actions.push(String(a[k].name())); } catch (e) {}'
     '   try { const items = it.menus[0].menuItems();'
     '    for (let j = 0; j < items.length; j++) { try { rec.children.push(String(items[j].title())); }'
     '     catch (e) { rec.childErrors.push(String(e)); } } } catch (e) {}'
     '   out.items.push(rec); } } } catch (e) { out.error = String(e); }'
     'JSON.stringify(out)'),
    ("P2 calibration: NSScreen frames + frames of the OTHER menu bar extras",
     'ObjC.import("AppKit"); ObjC.import("Foundation");'
     'const screens = []; const ss = $.NSScreen.screens;'
     'for (let i = 0; i < ss.count; i++) { const f = ss.objectAtIndex(i).frame;'
     ' screens.push({x: f.origin.x, y: f.origin.y, w: f.size.width, h: f.size.height}); }'
     'const se = Application("System Events"); const names = ["SimiGo", "Control Center", "SystemUIServer"];'
     'const procs = [];'
     'for (let n = 0; n < names.length; n++) { const nm = names[n];'
     ' try { const p = se.processes.byName(nm);'
     '  if (!p.exists()) { procs.push({name: nm, exists: false}); continue; }'
     '  const rec = {name: nm, exists: true, bars: p.menuBars.length, extras: []};'
     '  for (let b = 0; b < rec.bars; b++) { const bar = p.menuBars[b]; const cnt = bar.menuBarItems.length;'
     '   for (let i = 0; i < cnt; i++) { const it = bar.menuBarItems[i];'
     '    const e = {bar: b, i: i, pos: null, size: null, desc: null};'
     '    try { e.pos = it.position(); } catch (err) {}'
     '    try { e.size = it.size(); } catch (err) {}'
     '    try { e.desc = String(it.description()); } catch (err) {}'
     '    rec.extras.push(e); } }'
     '  procs.push(rec); } catch (e) { procs.push({name: nm, error: String(e)}); } }'
     'JSON.stringify({screens: screens, processes: procs})'),
    ("P3 proper dispatch test: AXShowMenu on the app menu, then press Settings...",
     'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
     'const out = {windowsBefore: p.windows.length, showError: null, pressError: null,'
     '             pressed: null, windowsAfter: null, windowTitles: [], menusOpenAfterShow: null};'
     'try { p.menuBars[0].menuBarItems[1].actions.byName("AXShowMenu").perform(); }'
     'catch (e) { out.showError = String(e); }'
     'delay(1.2);'
     'try { out.menusOpenAfterShow = p.menuBars[0].menuBarItems[1].menus.length; } catch (e) {}'
     'try { const items = p.menuBars[0].menuBarItems[1].menus[0].menuItems();'
     ' for (let i = 0; i < items.length; i++) { const t = String(items[i].title());'
     '  if (t.indexOf("Settings") >= 0) { items[i].actions[0].perform(); out.pressed = t; } } }'
     'catch (e) { out.pressError = String(e); }'
     'delay(2.5);'
     'out.windowsAfter = p.windows.length;'
     'for (let i = 0; i < out.windowsAfter; i++) { try { out.windowTitles.push(String(p.windows[i].name())); }'
     ' catch (e) { out.windowTitles.push("ERR"); } }'
     'JSON.stringify(out)'),
    ("P4 AXShowMenu on the status item itself, then look for a window or a popover",
     'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
     'const out = {windowsBefore: p.windows.length, error: null, windowsAfter: null,'
     '             stillRunning: null, menuActionTried: "AXShowMenu"};'
     'try { p.menuBars[1].menuBarItems[0].actions.byName("AXShowMenu").perform(); }'
     'catch (e) { out.error = String(e); }'
     'delay(2.5); out.windowsAfter = p.windows.length; out.stillRunning = p.exists();'
     'JSON.stringify(out)'),
]


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
         "--phase", "gui_%s_pre" % TAG, "--out", pre], timeout=300)

    launch_argv = ["open", "-n", "-F"]
    for key, value in env.items():
        launch_argv += ["--env", "%s=%s" % (key, value)]
    launch_argv += ["--stdout", os.path.join(RUN, "logs/gui_stdout.log"),
                    "--stderr", os.path.join(RUN, "logs/gui_stderr.log"), APP]
    launched = run(launch_argv, timeout=60)

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
        "launch": {"argv": launch_argv, "result": launched, "isolated_roots": env,
                   "pids": pids},
        "attempts": [],
    }
    if not pids:
        result["finding"] = "the candidate did not stay up when opened via LaunchServices"
        return write(result)
    pid = pids[0]
    result["launch"]["pid"] = pid
    result["launch"]["ps"] = run(["ps", "-o", "pid,etime,stat,command", "-p", str(pid)])
    time.sleep(3)

    for name, script in SCRIPTS:
        result["attempts"].append({"attempt": name, "result": jxa(script)})

    shot = os.path.join(EVID, "gui_%s_shot.png" % TAG)
    if os.path.exists(shot):
        os.unlink(shot)
    capture = run(["screencapture", "-x", shot], timeout=60)
    result["screen_recording"] = {"exit_code": capture["exit_code"],
                                  "stderr": capture.get("stderr", ""),
                                  "bytes": os.path.getsize(shot) if os.path.exists(shot) else 0}

    result["quit"] = {"result": run(["osascript", "-e", 'tell application "SimiGo" to quit'],
                                    timeout=30)}
    for _ in range(40):
        if not pids_for(EXE):
            break
        time.sleep(0.25)
    result["quit"]["still_running_after_quit"] = bool(pids_for(EXE))

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

    result["finding"] = analyse(result)
    return write(result)


def payload(result, prefix):
    for attempt in result["attempts"]:
        if attempt["attempt"].startswith(prefix):
            try:
                return json.loads(attempt["result"]["stdout"])
            except Exception:
                return None
    return None


def analyse(result):
    """State what the two probes measured, and revise the earlier conclusion only
    where the measurement forces it."""
    p1, p2, p3, p4 = payload(result, "P1"), payload(result, "P2"), payload(result, "P3"), payload(result, "P4")
    notes = []
    if p3 and p3.get("windowsAfter"):
        notes.append(
            "P3 opened %d window(s) (%s) after AXShowMenu + press, so AX CAN drive "
            "this app: the first probe's 'AXPress never dispatches' was too strong - it "
            "pressed a menu item without opening its parent menu."
            % (p3["windowsAfter"], ", ".join(p3.get("windowTitles") or [])))
    elif p3:
        notes.append(
            "P3 still produced no window after AXShowMenu + press (showError=%r, "
            "pressError=%r, pressed=%r), so the app's menu path does not respond to AX "
            "actions on this host even when done correctly." %
            (p3.get("showError"), p3.get("pressError"), p3.get("pressed")))
    if p4 is not None:
        notes.append("P4 AXShowMenu on the status item: windows %r -> %r, error=%r."
                     % (p4.get("windowsBefore"), p4.get("windowsAfter"), p4.get("error")))
    if p1 and p2:
        screen = (p2.get("screens") or [{}])[0]
        mine = next((i for i in p1.get("items", [])
                     if i.get("bar") == 1), None)
        others = []
        for proc in p2.get("processes", []):
            if proc.get("name") == "SimiGo":
                continue
            for e in proc.get("extras", []):
                if e.get("bar") == 1 and isinstance(e.get("pos"), list):
                    others.append(e)
        if mine and others:
            mx, my = mine["position"][:2] if isinstance(mine.get("position"), list) else (None, None)
            notes.append(
                "Geometry: NSScreen %rx%r; SimiGo status item at %r size %r; %d other "
                "extras measured at %r. A real-user click needs the item inside the "
                "screen rect." % (screen.get("w"), screen.get("h"), mine.get("position"),
                                  mine.get("size"), len(others),
                                  [e["pos"] for e in others[:6]]))
    return " ".join(notes) if notes else "probes recorded without a decisive answer"


def write(result):
    out = os.path.join(EVID, "gui_%s_ax_probe2.json" % TAG)
    with open(out, "w") as handle:
        json.dump(result, handle, indent=1)
        handle.write("\n")
    print(json.dumps({"out": os.path.basename(out),
                      "finding": result.get("finding"),
                      "screenshot_bytes": (result.get("screen_recording") or {}).get("bytes")},
                     indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
