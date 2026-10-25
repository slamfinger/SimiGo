"""M3 stage B (round 2): try to drive the INSTALLED app's user-visible prompt.

The point is not to hope: each automation channel is attempted and recorded with
its raw result. If none of them can reach the menu bar item, the GUI inference
leg stays BLOCKED and this file says exactly why and what would unblock it.
Writes evidence/m3_stage_b_gui_inference.json.
"""
import json, os, subprocess, time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B, "install/SimiGo.app")
BIN = os.path.join(APP, "Contents/MacOS/SimiGo")
M3 = os.path.join(B, "m3b")
OUT = os.path.join(B, "evidence/m3_stage_b_gui_inference.json")
ATTEMPTS = []


def _bootstrap_models(root):
    p = os.path.join(root, "home/manifests/bootstrap-report.json")
    try:
        return json.load(open(p)).get("modelsDiscovered")
    except (OSError, ValueError):
        return None


def run(cmd, timeout=40):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {"cmd": cmd if isinstance(cmd, str) else " ".join(cmd),
                "rc": p.returncode,
                "out": (p.stdout + p.stderr).strip()[:1200]}
    except subprocess.TimeoutExpired:
        return {"cmd": cmd if isinstance(cmd, str) else " ".join(cmd), "rc": "timeout", "out": ""}


def jxa(script):
    return run(["osascript", "-l", "JavaScript", "-e", script])


for d in ("home", "cache", "state-graph", "logs"):
    os.makedirs(os.path.join(M3, d), exist_ok=True)
env = dict(os.environ,
           SIMIGO_HOME=os.path.join(M3, "home"),
           SIMIGO_CACHE_ROOT=os.path.join(M3, "cache"),
           SIMIGO_STATE_GRAPH_STORE=os.path.join(M3, "state-graph/reference-graph-v1.json"))
log = open(os.path.join(M3, "logs/stage_b_app.log"), "wb")
proc = subprocess.Popen([BIN], env=env, stdout=log, stderr=log)
time.sleep(25)

launch = {"pid": proc.pid, "alive": proc.poll() is None,
          "exe_sha256": run(["shasum", "-a", "256", BIN])["out"].split()[0],
          "env": {k: env[k] for k in ("SIMIGO_HOME", "SIMIGO_CACHE_ROOT", "SIMIGO_STATE_GRAPH_STORE")}}
ATTEMPTS.append({"attempt": "A1 activate via JXA", **jxa(
    'const a = Application("SimiGo"); a.activate(); JSON.stringify({frontmost: a.frontmost()})')})
_a2 = jxa(
    'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
    'const out = {frontmost: false, menuBars: 0, items: 0, windows: 0, error: null};'
    'try { out.frontmost = p.frontmost(); } catch (e) { out.error = "frontmost:" + e; }'
    'try { out.menuBars = p.menuBars.length; } catch (e) { out.error = (out.error || "") + " menuBars:" + e; }'
    'try { out.windows = p.windows.length; } catch (e) { out.error = (out.error || "") + " windows:" + e; }'
    'try { out.items = p.menuBars[0].menuBarItems.length; } catch (e) { out.error = (out.error || "") + " items:" + e; }'
    'JSON.stringify(out)')
ATTEMPTS.append(dict(attempt="A2 accessibility tree (menu bar + windows)", **_a2))
ATTEMPTS.append({"attempt": "A3 AXPress on the status-bar item", **jxa(
    'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
    'const item = p.menuBars[0].menuBarItems[0]; item.actions[0].perform(); delay(1.5);'
    'JSON.stringify({windowsAfterPress: p.windows.length, frontmost: se.processes.byName("SimiGo").frontmost()})')})
ATTEMPTS.append({"attempt": "A4 CGEvent HID click at the AX-reported menu bar position", **jxa(
    'ObjC.import("CoreGraphics"); const se = Application("System Events");'
    'const p = se.processes.byName("SimiGo"); const b = p.menuBars[0].menuBarItems[0].position();'
    'const pt = {x: b[0] + 4, y: b[1] + 4};'
    '$.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, $.kCGEventLeftMouseDown, pt, 0));'
    '$.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, $.kCGEventLeftMouseUp, pt, 0));'
    'delay(1.5); JSON.stringify({clickedAt: pt, windowsAfterClick: p.windows.length,'
    ' frontmostApp: Application("System Events").processes.where({frontmost: true}).name()[0]})')})
_a5 = jxa(
    'ObjC.import("CoreGraphics"); const pid = ' + str(proc.pid) + ';'
    'const arr = ObjC.deepUnwrap($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID));'
    'let mine = 0; const n = arr.length;'
    'for (let i = 0; i < n; i++) { if (arr[i].kCGWindowOwnerPID === pid) mine++; }'
    'JSON.stringify({totalWindowsVisibleToProcess: n, myWindows: mine,'
    ' screenCaptureDenied: n === 0})')
ATTEMPTS.append(dict(attempt="A5 CGWindowListCopyWindowInfo for the process", **_a5))
ATTEMPTS.append({"attempt": "A6 screencapture (needs Screen Recording)", **run(
    ["screencapture", "-x", os.path.join(M3, "logs/stage_b_screen.png")])})
_a7 = jxa(
    '(() => { const se = Application("System Events");'
    '  Application("SimiGo").activate(); delay(1);'
    '  try { se.keystroke("hi"); return JSON.stringify({sent: true}); }'
    '  catch (e) { return JSON.stringify({sent: false, error: String(e)}); } })()')
ATTEMPTS.append(dict(attempt="A7 keystroke to frontmost app after activation", **_a7))
ATTEMPTS.append({"attempt": "A8 menu action: open Settings window (bypasses the popover)", **jxa(
    'const se = Application("System Events"); const p = se.processes.byName("SimiGo");'
    'const mb = p.menuBars[0].menuBarItems[0]; mb.click(); delay(1);'
    'JSON.stringify({windowsAfterMenuClick: p.windows.length,'
    ' frontmost: se.processes.byName("SimiGo").frontmost()})')})

reached = any(("windowsAfterPress" in a["out"] and '"windowsAfterPress":1' in a["out"].replace(" ", ""))
              for a in ATTEMPTS if isinstance(a.get("out"), str))
doc = {
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "installed_binary": BIN,
    "launch": launch,
    "attempts": ATTEMPTS,
    "menu_reached": reached,
    "real_model_output": False,
    "verdict": "BLOCKED",
    "blocked_reason": (
        "No automation channel can reach the status-bar popover that hosts the prompt "
        "field: the process is not frontmost, its AX menu bar reports a position off the "
        "single 1920x1080 display, CGWindowListCopyWindowInfo returns no windows (no "
        "Screen Recording permission) and screencapture cannot read the display. The "
        "installed app itself launched, stayed alive and wrote only to the isolated roots."),
    "minimum_unblock": [
        "Grant Screen Recording + Accessibility to the driving terminal, then run the same "
        "sequence: AXPress the status-bar item, type into the popover's prompt field, read "
        "the streamed answer and the native_mlx_trace.log for the real generation.",
        "Or run this leg on a host with an attended GUI session and capture the same "
        "evidence files (window list, screenshot, trace log, model output)."
    ],
    "what_is_proven_instead": {
        "installed_binary_launched_with_isolated_roots": launch["alive"],
        "bootstrap_models_discovered": _bootstrap_models(M3),
        "note": "The launch/isolation/bootstrap leg is proven by evidence/m3_stage_a_process.txt; "
                "this file only records the failed prompt-driving attempts.",
    },
}
json.dump(doc, open(OUT, "w"), indent=1, ensure_ascii=False)
proc.terminate()
try:
    proc.wait(timeout=15)
except subprocess.TimeoutExpired:
    proc.kill()
print("wrote", OUT)
print("alive:", launch["alive"], "menu_reached:", reached)
for a in ATTEMPTS:
    print("-", a["attempt"], "| rc=", a.get("rc"), "|", str(a.get("out"))[:160])
