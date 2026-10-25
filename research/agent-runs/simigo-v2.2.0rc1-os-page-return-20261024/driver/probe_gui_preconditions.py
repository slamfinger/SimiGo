#!/usr/bin/env python3
"""Fresh probe of the two GUI preconditions the operator named.

The GUI leg cannot be *made* to pass from here: it needs Screen Recording and
Accessibility granted to the driving terminal, and a live, unlocked desktop
session, then a real human-shaped interaction with the installed candidate.
This probe records, with timestamps and raw output, whether those preconditions
exist right now, so the gate can state its blocker from today's evidence instead
of repeating an older paragraph.

Writes evidence/gui_preconditions.json. Verdict values:
  READY                       both channels usable and the session is interactive
  BLOCKED_PREREQUISITE        a named precondition failed (details per check)
"""
import json
import os
import subprocess
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(B, "evidence/gui_preconditions.json")


def run(cmd, timeout=60):
    started = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return {"cmd": cmd if isinstance(cmd, str) else " ".join(cmd),
                "rc": p.returncode,
                "stdout": p.stdout.strip()[:2000],
                "stderr": p.stderr.strip()[:2000],
                "seconds": round(time.time() - started, 2)}
    except subprocess.TimeoutExpired:
        return {"cmd": cmd if isinstance(cmd, str) else " ".join(cmd),
                "rc": "timeout", "stdout": "", "stderr": "", "seconds": timeout}


def osa(script):
    return run(["osascript", "-e", script])


checks = {}

# 1. Screen Recording: the only honest test is to ask the WindowServer for a frame.
shot = "/tmp/simigo_gui_probe.png"
if os.path.exists(shot):
    os.unlink(shot)
cap = run(["screencapture", "-x", shot])
checks["screen_capture"] = {
    "result": cap,
    "file_written": os.path.exists(shot),
    "file_bytes": os.path.getsize(shot) if os.path.exists(shot) else 0,
    "usable": os.path.exists(shot) and os.path.getsize(shot) > 0,
}

# 2. Accessibility: driving another app's UI tree requires the AX permission.
ax = osa('tell application "System Events" to get name of first process')
checks["accessibility_ui_tree"] = {
    "result": ax,
    "usable": ax["rc"] == 0 and bool(ax["stdout"]),
    "denied_code_1743": "-1743" in (ax["stderr"] or ""),
}

# 3. Is there an interactive session to drive at all?
front = osa('tell application "System Events" to get name of first process whose frontmost is true')
checks["frontmost_process"] = {"result": front, "name": front["stdout"]}
checks["session_is_interactive"] = {
    "frontmost": front["stdout"],
    "locked_or_loginwindow": front["stdout"] == "loginwindow",
    "usable": front["rc"] == 0 and front["stdout"] not in ("", "loginwindow"),
}
checks["console_user"] = {"result": run(["stat", "-f", "%Su", "/dev/console"])}
checks["who"] = {"result": run(["who"])}

# 4. Installed candidate the GUI leg must run from (identity only, no launch).
app = os.path.join(B, "..", "simigo-v2.2.0rc1-service-http-20261024", "install/SimiGo.app")
app = os.path.abspath(app)
bin_path = os.path.join(app, "Contents/MacOS/SimiGo")
checks["candidate"] = {
    "app": app,
    "exists": os.path.isdir(app),
    "exe_sha256": run(["shasum", "-a", "256", bin_path])["stdout"].split()[0]
    if os.path.exists(bin_path) else None,
}

blockers = []
if not checks["screen_capture"]["usable"]:
    blockers.append("screen_capture: screencapture could not create an image "
                    "(Screen Recording not granted to the driving process, or no "
                    "capturable display)")
if not checks["accessibility_ui_tree"]["usable"]:
    blockers.append("accessibility_ui_tree: System Events could not enumerate processes")
if not checks["session_is_interactive"]["usable"]:
    blockers.append("session_is_interactive: frontmost process is %r - the desktop is "
                    "locked or sitting on the login window, so no user-shaped "
                    "interaction can be performed" % checks["session_is_interactive"]["frontmost"])

verdict = "READY" if not blockers else "BLOCKED_PREREQUISITE"
payload = {
    "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "verdict": verdict,
    "blockers": blockers,
    "checks": checks,
    "note": ("This probe does not close the GUI gate and does not stand in for a "
             "typed user operation. It records whether the preconditions for that "
             "operation exist on this machine right now."),
}
with open(OUT, "w") as handle:
    json.dump(payload, handle, indent=1, ensure_ascii=False)
print(json.dumps({"verdict": verdict, "blockers": blockers}, indent=1, ensure_ascii=False))
