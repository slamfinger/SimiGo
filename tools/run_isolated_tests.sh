#!/bin/bash
# Run the SimiGo App test suite against a FRESH isolation root, then prove by file
# diff that no user state changed.
#
#   tools/run_isolated_tests.sh [--app PATH] [--evidence-dir DIR] [--tag NAME]
#                               [--base-xctestrun PATH] [--destination DEST]
#                               [--extra-root PATH]... [--only TEST]...
#                               [--target-env TARGET:KEY=VALUE]...
#
# --only passes -only-testing to xcodebuild (repeatable, SimiGoTests/Class/method
# or SimiGoTests/Class). Targeted selections have NOT been measured for user-state
# writes the way the full suite has; the snapshot diff still runs and still fails
# the run on any real-root write. Only the cache-root redirection check is mode
# dependent: a narrow selection may never touch the cache, so in targeted runs it
# is reported in isolation_cache_used_by_app without gating. run_mode records
# which rule applied.
#
# First-run wizard: the test host runs the real app delegate, and a managed root
# without manifests/first-run-done.json opens the visible wizard, whose "移动并重启"
# button moves the test host into /Applications (observed 2026-10-31, it overwrote
# the installed Release app). The harness therefore pre-provisions the marker
# inside the isolation home before the run, so no human click is part of the
# procedure. The marker file is only ever written under the isolation root.
#
# Why a runner and not "just add env vars": testF3DeviceAcceptanceBattery is NOT
# idempotent w.r.t. the prefix pool on disk (its D4 step asserts mode=extend and
# cacheEff=1.00 only when the pool is cold and this run is the writer). A reused
# isolation/cache therefore fails that assertion - observed 2026-10-23. The fresh
# root is part of the procedure, not a convenience. Do not "optimise" it away.
#
# Fail-closed: unresolvable layout, an unsafe isolation root, a plist that changed
# beyond the three roots, a failing suite, a missing test count, or ANY user-state
# write outside the isolation root all end in a non-zero exit. Nothing here ever
# deletes a real user directory: the only tree it removes is the isolation root it
# created itself (marked by .isolation-root).
#
# exit: 0 ok · 2 usage · 3 unsafe layout · 4 xctestrun generation
#       5 snapshot/diff · 6 run or isolation audit failed
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
usage() { sed -n '2,/^set -u/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'; }

if [ ! -f "$ROOT/SimiGo.xcodeproj/project.pbxproj" ]; then
  echo "RUN_ISOLATED: not a SimiGo checkout: $ROOT" >&2; exit 3
fi
HOME_DIR="${HOME:-}"
if [ "${HOME_DIR#/}" = "$HOME_DIR" ]; then
  echo "RUN_ISOLATED: HOME is not an absolute path; refusing" >&2; exit 3
fi
command -v xcodebuild >/dev/null || { echo "RUN_ISOLATED: xcodebuild not found" >&2; exit 3; }

APP="$ROOT/build/test/Build/Products/Debug/SimiGo.app"
EVIDENCE=""
TAG=""
BASE=""
DEST="platform=macOS,arch=arm64"
EXTRA=()
ONLY=()
TARGET_ENV=()
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --base-xctestrun) BASE="$2"; shift 2 ;;
    --destination) DEST="$2"; shift 2 ;;
    --extra-root) EXTRA+=("$2"); shift 2 ;;
    --only) ONLY+=("$2"); shift 2 ;;
    --target-env) TARGET_ENV+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "RUN_ISOLATED: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Keep opt-in knobs explicit and allowlisted before creating evidence or isolation state.
for spec in "${TARGET_ENV[@]:-}"; do
  case "$spec" in
    *:SIMIGO_PREFIX_POOL=1|*:SIMIGO_BRANCH_CHECKPOINTS=1|*:SIMIGO_REQUEST_BUDGET_MS=0) ;;
    *) echo "RUN_ISOLATED: unsupported --target-env $spec" >&2; exit 2 ;;
  esac
  target="${spec%%:*}"
  if [ -z "$target" ] || [ "$target" = "$spec" ]; then
    echo "RUN_ISOLATED: --target-env must be TARGET:KEY=VALUE" >&2; exit 2
  fi
done

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
[ -n "$EVIDENCE" ] || EVIDENCE="$ROOT/build/test-isolation/$stamp"
[ -n "$TAG" ] || TAG="run-$stamp"

under() { case "$1" in "$2"|"$2"/*) return 0 ;; *) return 1 ;; esac; }
REAL_ROOTS=("$HOME_DIR/.simigo" "$HOME_DIR/Library/Application Support/SimiGo"
            "$HOME_DIR/Library/Preferences/SwiftUI.SimiGo.plist"
            "$HOME_DIR/Library/Preferences/SimiGo.plist")

# Every layout rule is checked on the path TEXT first and again after symlink
# resolution. Nothing is created before the text check passes, so a rejected
# --evidence-dir can never leave a directory behind inside a protected root.
check_evidence() {
  local ev="$1" r
  if [ "$ev" = "/" ] || [ "$ev" = "$HOME_DIR" ] || [ "$ev" = "$ROOT" ]; then
    echo "RUN_ISOLATED: refusing to use $ev as evidence dir" >&2; return 1
  fi
  for r in "${REAL_ROOTS[@]}" "${EXTRA[@]:-}"; do
    [ -n "$r" ] || continue
    if under "$ev" "$r" || under "$r" "$ev"; then
      echo "RUN_ISOLATED: evidence dir and protected root overlap: $r" >&2; return 1
    fi
  done
  if under "$ev" "$ROOT" && ! under "$ev" "$ROOT/build"; then
    echo "RUN_ISOLATED: evidence dir inside the repo must live under build/" >&2; return 1
  fi
  return 0
}

# --- preconditions: every input is validated before anything is created ------
# A rejected run must leave the filesystem exactly as it found it, so the app
# and the base xctestrun are checked before the evidence dir is even mkdir'ed.
if ! APP_RESOLVED="$(cd "$APP" 2>/dev/null && pwd -P)"; then
  echo "RUN_ISOLATED: app bundle missing: $APP" >&2; exit 3
fi
APP="$APP_RESOLVED"
if [ -n "$BASE" ] && [ ! -f "$BASE" ]; then
  echo "RUN_ISOLATED: base xctestrun missing: $BASE" >&2; exit 3
fi

EVIDENCE="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$EVIDENCE")" || exit 3
check_evidence "$EVIDENCE" || exit 3
mkdir -p "$EVIDENCE" || exit 3
EVIDENCE="$(cd "$EVIDENCE" && pwd -P)" || exit 3
check_evidence "$EVIDENCE" || exit 3

ISO="$EVIDENCE/isolation"
case "$ISO" in
  */isolation) : ;;
  *) echo "RUN_ISOLATED: isolation root must end in /isolation: $ISO" >&2; exit 3 ;;
esac

# --- isolation root sentinel: we only ever delete what we created ------------
SENTINEL="$EVIDENCE/.isolation-root"
if [ -f "$SENTINEL" ]; then
  if [ "$(cat "$SENTINEL")" != "$EVIDENCE" ]; then
    echo "RUN_ISOLATED: sentinel mismatch, refusing to clean: $SENTINEL" >&2; exit 3
  fi
else
  mkdir -p "$ISO"
  printf '%s\n' "$EVIDENCE" > "$SENTINEL"
fi

# --- fresh root (D4 depends on it) ------------------------------------------
for d in home cache state-graph qoder-projects; do
  if [ -e "$ISO/$d" ]; then rm -rf "$ISO/$d"; fi
  mkdir -p "$ISO/$d"
done

# --- pre-provision the first-run marker inside the isolation home -----------
# The test host runs the real app delegate, and without the marker
# FirstRunWizard opens a visible window; the suite would then depend on a human
# clicking it. One of those clicks ("移动并重启") moves the test host into
# /Applications, so the marker is written here instead. It is written only under
# the isolation home, never under a real user root.
mkdir -p "$ISO/home/manifests"
printf '{\n  "finished_at": "%s",\n  "version": "isolated-test-host",\n  "work_roots": [],\n  "binaries": []\n}\n' \
  "$(date -u +%FT%TZ)" > "$ISO/home/manifests/first-run-done.json"
date -u +%FT%TZ > "$EVIDENCE/started_at.txt"
START=$(date +%s)

# --- isolate the test bundle (differences re-measured) ----------------------
GEN=(python3 "$ROOT/tools/make_isolated_xctestrun.py" --app "$APP"
     --isolation-root "$ISO" --record "$EVIDENCE/xctestrun_isolation.json")
[ -n "$BASE" ] && GEN+=(--base-xctestrun "$BASE")
for v in "${TARGET_ENV[@]:-}"; do GEN+=(--target-env "$v"); done
"${GEN[@]}" || exit 4
XR="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["isolated_xctestrun"])' \
      "$EVIDENCE/xctestrun_isolation.json")" || exit 4

# --- pre snapshot -----------------------------------------------------------
SNAP=(python3 "$ROOT/tools/rc_noninterference.py")
for r in "${REAL_ROOTS[@]}"; do SNAP+=(--real-root "$r"); done
for r in "${EXTRA[@]:-}"; do [ -n "$r" ] && SNAP+=(--real-root "$r"); done
"${SNAP[@]}" --phase "pre-$TAG" --out "$EVIDENCE/snapshot_pre.json" || exit 5

# --- run --------------------------------------------------------------------
rm -rf "$EVIDENCE/Test-$TAG.xcresult"
XCBUILD=(test-without-building
         -xctestrun "$XR"
         -destination "$DEST"
         -resultBundlePath "$EVIDENCE/Test-$TAG.xcresult")
for t in "${ONLY[@]:-}"; do
  [ -n "$t" ] && XCBUILD+=("-only-testing:$t")
done
xcodebuild "${XCBUILD[@]}" \
  2>&1 | tee "$EVIDENCE/isolated_tests_$TAG.log"
RC=${PIPESTATUS[0]}

# --- post snapshot + diff ---------------------------------------------------
"${SNAP[@]}" --phase "post-$TAG" --out "$EVIDENCE/snapshot_post.json" || exit 5
python3 "$ROOT/tools/rc_noninterference_diff.py" \
  "$EVIDENCE/snapshot_pre.json" "$EVIDENCE/snapshot_post.json" \
  "$EVIDENCE/snapshot_diff.json" --allow-prefix "$EVIDENCE" || exit 5

END=$(date +%s)
python3 - "$EVIDENCE" "$TAG" "$RC" "$START" "$END" "${#ONLY[@]}" <<'PY'
import json, os, re, subprocess, sys
ev, tag, rc, start, end = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
only_count = int(sys.argv[6])
targeted = only_count > 0
log = open(os.path.join(ev, "isolated_tests_%s.log" % tag), errors="replace").read()
iso = os.path.join(ev, "isolation")

def counts_from_xcresult(path):
    """(executed, skipped, failures) from the result bundle; authoritative."""
    if not os.path.isdir(path):
        return None
    try:
        out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                             "--path", path], capture_output=True, text=True, timeout=300)
        if out.returncode != 0:
            return None
        s = json.loads(out.stdout)
        return (s["totalTestCount"], s["skippedTests"], s["failedTests"])
    except Exception:
        return None

def counts_from_log(text):
    m = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures?", text)
    if m:
        return tuple(int(x) for x in m[-1])
    agg = [(int(a), int(b)) for a, b in
           re.findall(r"Executed (\d+) tests?, with (\d+) failures", text)]
    if not agg:
        return None
    skipped = len(re.findall(r"^Test Case .*skipped", text, re.M))
    return (max(agg)[0], skipped, max(agg)[1])

counts = counts_from_xcresult(os.path.join(ev, "Test-%s.xcresult" % tag))
source = "xcresulttool" if counts else None
if counts is None:
    counts = counts_from_log(log)
    source = "log" if counts else None

def du(p):
    total = 0
    for r, _, fs in os.walk(p):
        for f in fs:
            try:
                total += os.path.getsize(os.path.join(r, f))
            except OSError:
                pass
    return total

diff = json.load(open(os.path.join(ev, "snapshot_diff.json")))
xr = json.load(open(os.path.join(ev, "xctestrun_isolation.json")))
content = {d: du(os.path.join(iso, d))
           for d in ("home", "cache", "state-graph", "qoder-projects")}
checks = {
    "test_execute_succeeded": "** TEST EXECUTE SUCCEEDED **" in log,
    "exit_code_zero": rc == 0,
    "counts_parsed": counts is not None,
    "no_failures": bool(counts) and counts[2] == 0,
    "xctestrun_only_three_roots": xr["other_differences"] == [],
    "isolation_home_used_by_app": os.path.exists(os.path.join(iso, "home", "simigo.sqlite3")),
    "first_run_marker_preprovisioned": os.path.exists(
        os.path.join(iso, "home", "manifests", "first-run-done.json")),
    "qoder_scan_root_preprovisioned": os.path.isdir(os.path.join(iso, "qoder-projects")),
    "no_real_user_state_write": diff["real_user_state_write_count"] == 0,
    "no_unexpected_write": diff["distinct_violation_count"] == 0,
}
# The cache-root gate proves the full suite really redirects writes into the
# isolated cache. A targeted selection can legitimately leave it untouched, so
# in that mode it is recorded as an observation below instead of a gate. No
# write-audit gate is relaxed by the run mode.
if not targeted:
    checks["isolation_cache_used_by_app"] = content["cache"] > 0
# Observation, not a gate: the GUI app delegate starts the Qoder collector on
# every launch, so a test host built from a tree that mounts it collects during
# the run. Recorded here so the contamination is measured rather than assumed.
collector = os.path.join(iso, "home", "collectors")
rec = {
    "tag": tag, "evidence_dir": ev, "exit_code": rc, "duration_s": end - start,
    "executed_skipped_failures": counts,
    "counts_source": source,
    "run_mode": "targeted" if targeted else "full",
    "targeted_selections": only_count,
    "xctestrun_isolated_sha256": xr["isolated_sha256"],
    "fresh_isolation_root": True,
    "isolation_content_bytes": content,
    "isolation_cache_used_by_app": content["cache"] > 0,
    "qoder_scan_root": {
        "path": os.path.join(iso, "qoder-projects"),
        "present": os.path.isdir(os.path.join(iso, "qoder-projects")),
        "files": sum(len(fs) for _, _, fs in os.walk(os.path.join(iso, "qoder-projects"))),
        "bytes": du(os.path.join(iso, "qoder-projects")),
    },
    "target_env_requested": TARGET_ENV,
    "target_env_applied": xr.get("target_env_applied", []),
    "collector_state_observed": {
        "path": collector,
        "present": os.path.isdir(collector),
        "bytes": du(collector) if os.path.isdir(collector) else 0,
    },
    "noninterference": {
        "real_user_state_write_count": diff["real_user_state_write_count"],
        "real_user_state_write_paths": diff["real_user_state_write_paths"],
        "violation_events": diff["violation_events"],
        "distinct_violation_count": diff["distinct_violation_count"],
        "expected_self_writes": len(diff["distinct_expected_abs_paths"]),
        "reference_changes": len(diff["reference_change_paths"]),
        "swept_real_roots": diff["real_roots"],
    },
    "checks": checks,
    "passed": all(checks.values()),
}
with open(os.path.join(ev, "isolation_run_%s.json" % tag), "w") as f:
    json.dump(rec, f, indent=1)
    f.write("\n")
print(json.dumps(rec, indent=1))
if not rec["passed"]:
    failed = [k for k, v in checks.items() if not v]
    sys.stderr.write("RUN_ISOLATED: FAILED checks: %s\n" % ", ".join(failed))
    sys.exit(6)
PY
