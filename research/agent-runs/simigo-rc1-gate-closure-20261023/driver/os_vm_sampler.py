#!/usr/bin/env python3
"""Independent OS-level VM sampler for the G3 memory tiers (gate-closure batch).

WHY THIS EXISTS: the product's memprobe evidence is a SELF-report (task_vm_info
read by the app itself). A self-report can show that the app's own accounting
dropped; it cannot by itself prove that physical pages went back to the system.
This sampler reads the SYSTEM side (vm_stat free/inactive/speculative pages,
vm.swapusage, compressor pages, and the target process RSS from `ps`) at a fixed
interval from a SEPARATE process, so the tier-D question has an external
corroborating series.

VERDICT RULES ARE NOT CHANGED BY THIS: per the standing gate definition, a
footprint/RSS delta alone cannot PASS physical_page_return; this series is
recorded as SUPPORTING evidence and the check stays BLOCKED unless a qualified
OS-level page-reclaim proof exists.
"""
import json, subprocess, sys, time, os

PIDFILE = sys.argv[1] if len(sys.argv) > 1 else None
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/os_vm_sampler.jsonl"
DURATION = float(sys.argv[3]) if len(sys.argv) > 3 else 900.0
INTERVAL = float(sys.argv[4]) if len(sys.argv) > 4 else 2.0
# BUNDLE_PATH = the exact product bundle under test (argv[5]); only processes
# whose executable path contains it are sampled.
MATCH = sys.argv[5] if len(sys.argv) > 5 else "SimiGo.app/Contents/MacOS/SimiGo"
PAGE = 16384  # arm64 Apple Silicon page size; re-read below to avoid a stale constant


def page_size():
    try:
        return int(subprocess.run(["sysctl", "-n", "hw.pagesize"], capture_output=True, text=True).stdout.strip())
    except Exception:
        return 16384


def vm_stat(ps):
    out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
    d = {}
    for line in out.splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        v = v.strip().rstrip(".")
        if v.isdigit():
            d[k.strip().lower().replace(" ", "_")] = int(v) * ps
    return d


def one(ps):
    rec = {"ts": time.strftime("%FT%T%z")}
    rec["vm_stat_bytes"] = vm_stat(ps)
    sw = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True).stdout.strip()
    rec["swap"] = sw
    pid = None
    if PIDFILE and os.path.exists(PIDFILE):
        try:
            pid = open(PIDFILE).read().strip() or None
        except Exception:
            pid = None
    if pid:
        try:
            # find the running headless process by name (pid file holds the launcher pid,
            # which may have exited; match the actual app process instead)
            # MATCH ON THE FULL BUNDLE PATH, NOT "SimiGo.app": an unrelated
            # /Applications/SimiGo.app GUI instance is running on this machine and the
            # loose pattern matched IT (rss ~8.5 MB) instead of the experiment process,
            # which would have made the external series meaningless.
            ps_out = subprocess.run(["ps", "-axo", "pid,rss,comm"], capture_output=True, text=True).stdout
            hits = [l.split(None, 2) for l in ps_out.splitlines() if MATCH in l]
            if hits:
                rec["pid"] = hits[0][0]
                rec["rss_bytes"] = int(hits[0][1]) * 1024
                rec["proc_count"] = len(hits)
            else:
                rec["pid"] = None
                rec["rss_bytes"] = None
        except Exception as e:
            rec["ps_err"] = str(e)
    return rec


def main():
    ps = page_size()
    end = time.time() + DURATION
    with open(OUT, "w") as f:
        f.write(json.dumps({"event": "start", "page_size": ps, "interval": INTERVAL}) + "\n")
        while time.time() < end:
            f.write(json.dumps(one(ps)) + "\n")
            f.flush()
            time.sleep(INTERVAL)
        f.write(json.dumps({"event": "end"}) + "\n")


if __name__ == "__main__":
    main()
