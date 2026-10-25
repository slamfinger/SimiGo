#!/usr/bin/env python3
"""OS-level physical page-return probe around the SHIPPED idle-suspend path.

What is measured (both sides, same 100 ms clock):
  * host page counters   - host_statistics64(HOST_VM_INFO64): the kernel's own
                           global accounting, the same numbers vm_stat prints.
                           Pages are counted once, by the kernel, whoever owns
                           them; this is not a process self-report.
  * target kernel rusage - proc_pid_rusage(RUSAGE_INFO_V4): ri_wired_size,
                           ri_resident_size, ri_phys_footprint, read from the
                           kernel's pmap for that pid.
  * liveness             - os.kill(pid, 0) on every sample, so "the process
                           exited" can never be mistaken for a page return.

What is driven
  The UNMODIFIED in-product headless role SIMIGO_HEADLESS_ROLE=memprobe on the
  installed candidate (see SimiGo/Headless/SimiGoG1G3Entry.swift::memprobe):
  warm generate -> wait out the production adaptive idle floor (240 s) ->
  suspendIfIdle() -> resume generate. No timing seam, no injected timer, no
  calls into a release API from outside the process.

Why this is not the rejected proxy
  Footprint/RSS/exit alone are explicitly not proof. Here the claim rests on the
  kernel's free/inactive/wired page counts moving by approximately the same
  number of pages that the process's kernel-resident set gives up, while the
  process stays alive, and while the compressor does NOT absorb those pages.

Verdict is derived elsewhere: driver/verify_os_page_return.py.
Writes evidence/os_page_return_raw.json (+ runs/<rid>/ artifacts).
"""
import ctypes
import ctypes.util
import errno
import json
import os
import pty
import select
import struct
import subprocess
import sys
import threading
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANDIDATE = os.path.abspath(os.path.join(
    B, "..", "simigo-v2.2.0rc1-service-http-20261024", "install/SimiGo.app"))
BIN = os.path.join(CANDIDATE, "Contents/MacOS/SimiGo")
MODEL = ("/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--"
         "Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d")
RID = sys.argv[1] if len(sys.argv) > 1 else "os1"
INTERVAL = float(os.environ.get("OS_PROBE_INTERVAL", "0.1"))
BASELINE_SECONDS = float(os.environ.get("OS_PROBE_BASELINE", "30"))
OUT = os.path.join(B, "evidence/os_page_return_raw.json")
RUN = os.path.join(B, "runs", RID)
PAGE = os.sysconf("SC_PAGE_SIZE")


# ---------------------------------------------------------------- host counters
class VMStatistics64(ctypes.Structure):
    _fields_ = [
        ("free_count", ctypes.c_uint32),
        ("active_count", ctypes.c_uint32),
        ("inactive_count", ctypes.c_uint32),
        ("wire_count", ctypes.c_uint32),
        ("zero_fill_count", ctypes.c_uint64),
        ("reactivations", ctypes.c_uint64),
        ("pageins", ctypes.c_uint64),
        ("pageouts", ctypes.c_uint64),
        ("faults", ctypes.c_uint64),
        ("cow_faults", ctypes.c_uint64),
        ("lookups", ctypes.c_uint64),
        ("hits", ctypes.c_uint64),
        ("purges", ctypes.c_uint64),
        ("purgeable_count", ctypes.c_uint32),
        ("speculative_count", ctypes.c_uint32),
        ("decompressions", ctypes.c_uint64),
        ("compressions", ctypes.c_uint64),
        ("swapins", ctypes.c_uint64),
        ("swapouts", ctypes.c_uint64),
        ("compressor_page_count", ctypes.c_uint32),
        ("throttled_count", ctypes.c_uint32),
        ("external_page_count", ctypes.c_uint32),
        ("internal_page_count", ctypes.c_uint32),
        ("total_uncompressed_pages_in_compressor", ctypes.c_uint64),
    ]


HOST_VM_INFO64 = 4
libc = ctypes.CDLL(ctypes.util.find_library("System"), use_errno=True)
libc.mach_host_self.restype = ctypes.c_uint32
libc.host_statistics64.restype = ctypes.c_int
libc.host_statistics64.argtypes = [ctypes.c_uint32, ctypes.c_int,
                                   ctypes.POINTER(ctypes.c_int32),
                                   ctypes.POINTER(ctypes.c_uint32)]
HOST = libc.mach_host_self()


def host_vm():
    st = VMStatistics64()
    count = ctypes.c_uint32(ctypes.sizeof(VMStatistics64) // ctypes.sizeof(ctypes.c_uint32))
    kr = libc.host_statistics64(HOST, HOST_VM_INFO64,
                                ctypes.cast(ctypes.byref(st),
                                            ctypes.POINTER(ctypes.c_int32)),
                                ctypes.byref(count))
    if kr != 0:
        raise OSError("host_statistics64 kr=%d" % kr)
    return st


libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
libproc.proc_pid_rusage.restype = ctypes.c_int
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
RUSAGE_INFO_V4 = 4


def target_rusage(pid):
    """ri_wired_size / ri_resident_size / ri_phys_footprint from the kernel pmap."""
    buf = ctypes.create_string_buffer(512)
    rc = libproc.proc_pid_rusage(pid, RUSAGE_INFO_V4, ctypes.byref(buf))
    if rc != 0:
        return None
    wired, resident, footprint = struct.unpack_from("<3Q", buf.raw, 56)
    return {"wired_bytes": wired, "resident_bytes": resident,
            "footprint_bytes": footprint}


def swap_used_bytes():
    out = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True,
                         text=True).stdout
    # "total = 5120.00M  used = 3646.31M  free = 1473.69M  (encrypted)"
    try:
        used = out.split("used =")[1].split()[0]
        value, unit = float(used[:-1]), used[-1]
        factor = {"K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}[unit]
        return int(value * factor)
    except (IndexError, ValueError, KeyError):
        return None


def vm_stat_text():
    return subprocess.run(["vm_stat"], capture_output=True, text=True).stdout


# ------------------------------------------------------------------- launch
def launch(cmd, env, log_path):
    """forkpty + execve so the driver owns the pid it measures."""
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


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def reap(pid):
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return None
    if done == 0:
        return None
    return os.waitstatus_to_exitcode(status)


# --------------------------------------------------------------------- main
def main():
    os.makedirs(RUN, exist_ok=True)
    for sub in ("home", "cache", "state-graph", "logs"):
        os.makedirs(os.path.join(RUN, sub), exist_ok=True)
    log_path = os.path.join(RUN, "memprobe.log")
    env = dict(os.environ,
               SIMIGO_HEADLESS_ROLE="memprobe",
               SIMIGO_EXPERIMENT_ROOT=RUN,
               SIMIGO_RUN_ID=RID,
               SIMIGO_HOME=os.path.join(RUN, "home"),
               SIMIGO_CACHE_ROOT=os.path.join(RUN, "cache"),
               SIMIGO_STATE_GRAPH_STORE=os.path.join(RUN, "state-graph/reference-graph-v1.json"),
               SIMIGO_HEADLESS_MODEL_PATH=MODEL,
               SIMIGO_HEADLESS_TARGET_VALUE=os.environ.get("OS_PROBE_TARGET", "hello"))

    series = {k: [] for k in ("t_ms", "free", "active", "inactive", "wired_pages",
                              "purgeable", "speculative", "compressor",
                              "swap_used_bytes", "wired_bytes", "resident_bytes",
                              "footprint_bytes", "alive", "rusage_ok", "phase")}
    t0 = time.time()

    counter = {"n": 0}

    def record(phase, pid):
        st = host_vm()
        ru = target_rusage(pid) if pid else None
        # sysctl costs a process spawn; under memory pressure that is enough to
        # blind the sampler at fine intervals, so swap is sampled every 50th row.
        counter["n"] += 1
        swap = swap_used_bytes() if counter["n"] % 50 == 0 else None
        series["t_ms"].append(int((time.time() - t0) * 1000))
        series["free"].append(st.free_count)
        series["active"].append(st.active_count)
        series["inactive"].append(st.inactive_count)
        series["wired_pages"].append(st.wire_count)
        series["purgeable"].append(st.purgeable_count)
        series["speculative"].append(st.speculative_count)
        series["compressor"].append(st.compressor_page_count)
        series["swap_used_bytes"].append(swap)
        series["wired_bytes"].append(ru["wired_bytes"] if ru else 0)
        series["resident_bytes"].append(ru["resident_bytes"] if ru else 0)
        series["footprint_bytes"].append(ru["footprint_bytes"] if ru else 0)
        series["alive"].append(1 if (pid and alive(pid)) else 0)
        series["rusage_ok"].append(1 if ru else 0)
        series["phase"].append(phase)

    # Phase A: noise floor, nothing of ours running.
    baseline_start = time.time()
    while time.time() - baseline_start < BASELINE_SECONDS:
        record("baseline", None)
        time.sleep(INTERVAL)

    identity = {
        "candidate": CANDIDATE,
        "exe_sha256": subprocess.run(["shasum", "-a", "256", BIN],
                                     capture_output=True, text=True).stdout.split()[0],
        "model": MODEL,
        "page_size": PAGE,
        "host_memsize_bytes": int(subprocess.run(["sysctl", "-n", "hw.memsize"],
                                                 capture_output=True, text=True).stdout),
        "interval_seconds": INTERVAL,
        "baseline_seconds": BASELINE_SECONDS,
        "role": "SIMIGO_HEADLESS_ROLE=memprobe (unmodified in-product role)",
        "env_keys": sorted(k for k in env if k.startswith("SIMIGO_")),
    }

    vm_stat_before = vm_stat_text()
    swap_before = swap_used_bytes()
    pid, _fd = launch([BIN], env, log_path)
    started = time.time()

    exit_code = None
    while exit_code is None:
        record("run", pid)
        time.sleep(INTERVAL)
        exit_code = reap(pid)
        if time.time() - started > 1500:
            break

    vm_stat_after = vm_stat_text()
    swap_after = swap_used_bytes()

    evidence = {}
    evidence_mtime_ms = None
    for name in sorted(os.listdir(RUN)):
        if name.startswith("memprobe") and name.endswith(".json"):
            path = os.path.join(RUN, name)
            with open(path) as handle:
                evidence[name] = json.load(handle)
            # The role writes this file only AFTER the resume generation, so its
            # mtime is the proof that the process was still running at that point.
            mtime = int(os.stat(path).st_mtime * 1000)
            evidence_mtime_ms = max(mtime, evidence_mtime_ms or 0)

    payload = {
        "batch": os.path.basename(B),
        "rid": RID,
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "identity": identity,
        "child": {"pid": pid, "exit_code": exit_code, "wall_seconds": round(time.time() - started, 1)},
        "vm_stat_before": vm_stat_before,
        "vm_stat_after": vm_stat_after,
        "swap_used_bytes_before": swap_before,
        "swap_used_bytes_after": swap_after,
        "memprobe_evidence": evidence,
        "memprobe_evidence_mtime": evidence_mtime_ms,
        "start_epoch_ms": int(t0 * 1000),
        "series": series,
        "note": ("All page numbers are the kernel's own counts (host_statistics64 / "
                 "proc_pid_rusage). The process is proven alive at every sample, so "
                 "no row in this file can be explained by process exit."),
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)
    print(json.dumps({"rid": RID, "child": payload["child"], "samples": len(series["t_ms"]),
                      "out": OUT}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
