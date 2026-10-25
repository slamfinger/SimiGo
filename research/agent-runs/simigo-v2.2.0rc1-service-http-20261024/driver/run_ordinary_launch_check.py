#!/usr/bin/env python3
"""Ordinary-launch check: the installed candidate must NOT activate itself.

Launches the shipped app bundle with an isolated SIMIGO_HOME and NO management
environment variable (i.e. the way a user starts it), waits, and records whether
the product created any LOCALB host material or opened a listener on its own.
The point is the negative: prepare/activate/pairing must stay operator-initiated.
"""
import json
import os
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.request

B2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B2, "install", "SimiGo.app")
BIN = os.path.join(APP, "Contents", "MacOS", "SimiGo")
OUT = os.path.join(B2, "evidence", "ordinary_launch_no_auto_activation.json")
PORT = 8120
WAIT = 45


def main():
    root = os.path.join(B2, "m3_ordinary")
    if os.path.exists(root):
        shutil.rmtree(root)
    for sub in ("home", "cache", "state-graph"):
        os.makedirs(os.path.join(root, sub))
    env = {k: v for k, v in os.environ.items() if not k.startswith("SIMIGO_")}
    env.update({"SIMIGO_HOME": os.path.join(root, "home"),
                "SIMIGO_CACHE_ROOT": os.path.join(root, "cache"),
                "SIMIGO_STATE_GRAPH_STORE": os.path.join(root, "state-graph", "reference-graph-v1.json"),
                "SIMIGO_LOCALB_SERVE_PORT": str(PORT)})
    log = open(os.path.join(B2, "logs", "ordinary_launch.out"), "w")
    err = open(os.path.join(B2, "logs", "ordinary_launch.err"), "w")
    proc = subprocess.Popen([BIN], env=env, stdout=log, stderr=err)

    listener = None
    deadline = time.time() + WAIT
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    while time.time() < deadline:
        try:
            with urllib.request.urlopen("https://127.0.0.1:%d/health" % PORT,
                                        context=ctx, timeout=2) as rsp:
                listener = rsp.status
                break
        except Exception:  # noqa: BLE001 - absence is the expected result
            pass
        if proc.poll() is not None:
            break
        time.sleep(2)

    localb = os.path.join(root, "home", "localb")
    checkpoint = os.path.join(localb, "trusted-checkpoint.json")
    identities = sorted(os.listdir(localb)) if os.path.isdir(localb) else []
    alive = proc.poll() is None
    if alive:
        proc.terminate()
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=30)
    doc = {
        "candidate": APP,
        "isolated_home": env["SIMIGO_HOME"],
        "management_env_present": any(k == "SIMIGO_LOCALB_MGMT" for k in env),
        "waited_seconds": WAIT,
        "health_status_on_serve_port": listener,
        "localb_directory_created": os.path.isdir(localb),
        "localb_directory_entries": identities,
        "trusted_checkpoint_present": os.path.exists(checkpoint),
        "process_still_running_after_wait": alive,
        "process_exit_code": proc.returncode,
        "verdict": ("no auto-activation" if not os.path.isdir(localb)
                    and listener is None else "UNEXPECTED auto-activation"),
    }
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1, sort_keys=True)
    print(json.dumps(doc, indent=1))
    return 0 if doc["verdict"] == "no auto-activation" else 6


if __name__ == "__main__":
    sys.exit(main())
