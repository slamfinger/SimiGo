#!/usr/bin/env python3
"""Record the two macOS permissions GUI acceptance depends on. Read-only.

The GUI gate cannot be closed by the agent alone: its preconditions are two
system privacy grants that only the machine owner can give. This script records
which of them are currently in place, so "BLOCKED_PREREQUISITE" is a measured
statement rather than a remembered one.

It does not ask for a grant, does not try to bypass TCC, and does not launch the
candidate app.

usage: probe_gui_prerequisites.py [out.json]
Exit codes: 0 written (whatever the result), 3 could not write.
"""
import json
import os
import subprocess
import sys
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(B, "evidence/gui_prerequisite_probe.json")


def run(argv, timeout=30):
    start = time.time()
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return {
            "argv": argv,
            "exit_code": p.returncode,
            "stdout": p.stdout[:2000],
            "stderr": p.stderr[:2000],
            "wall_seconds": round(time.time() - start, 2),
        }
    except subprocess.TimeoutExpired:
        return {"argv": argv, "exit_code": None, "error": "timeout",
                "wall_seconds": round(time.time() - start, 2)}


def main():
    # Accessibility: Automation/System Events needs the caller to be trusted.
    # A successful enumeration means the grant is in place.
    ax = run(["osascript", "-e",
              'tell application "System Events" to count processes'])

    # Screen recording: every capture path goes through the same TCC grant.
    shot = "/tmp/simigo_gui_probe_shot.png"
    if os.path.exists(shot):
        os.unlink(shot)
    screen = run(["screencapture", "-x", shot])
    shot_exists = os.path.exists(shot)
    shot_bytes = os.path.getsize(shot) if shot_exists else 0

    accessibility_ok = ax.get("exit_code") == 0 and ax.get("stdout", "").strip().isdigit()
    screen_recording_ok = screen.get("exit_code") == 0 and shot_bytes > 0

    payload = {
        "purpose": ("record which macOS privacy grants the GUI gate depends on are "
                    "actually in place on this machine, so the gate's status is "
                    "measured, not assumed"),
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "accessibility": {
            "probe": "osascript: tell application \"System Events\" to count processes",
            "granted": bool(accessibility_ok),
            "result": ax,
        },
        "screen_recording": {
            "probe": "screencapture -x /tmp/simigo_gui_probe_shot.png",
            "granted": bool(screen_recording_ok),
            "screenshot_exists": shot_exists,
            "screenshot_bytes": shot_bytes,
            "result": screen,
        },
        "what_this_probe_cannot_do": (
            "it cannot grant either permission, and it does not launch the candidate "
            "app: a capture that fails here proves nothing about the product's GUI"),
        "consequence": (
            "the GUI gate stays BLOCKED_PREREQUISITE" if not screen_recording_ok
            else "prerequisites appear in place; the gate still needs one real user "
                 "operation inside the installed candidate before it can be judged"),
        "required_user_action": None if screen_recording_ok else (
            "System Settings > Privacy & Security > Screen & System Audio Recording: "
            "enable the app that hosts this agent (Terminal / the IDE), then re-run "
            "this probe"),
    }
    try:
        with open(OUT, "w") as handle:
            json.dump(payload, handle, indent=1)
            handle.write("\n")
    except OSError as error:
        print("could not write %s: %s" % (OUT, error), file=sys.stderr)
        return 3
    print(json.dumps({"accessibility_granted": payload["accessibility"]["granted"],
                      "screen_recording_granted": payload["screen_recording"]["granted"],
                      "consequence": payload["consequence"],
                      "out": os.path.basename(OUT)}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
