#!/bin/bash
# Run the SimiGo App test suite against a FRESH isolated root, then prove by file
# diff that nothing outside that root changed.
#
#   usage: run_isolated_tests.sh <tag>        e.g. run4
#
# Why a runner and not "just add env vars": testF3DeviceAcceptanceBattery is NOT
# idempotent w.r.t. the prefix-pool on disk (its D4 step asserts mode=extend,
# cacheEff=1.00 only when the pool is cold and this run is the writer). Reusing
# an isolation/cache therefore fails that assertion - observed on 2026-10-23
# (isolated_tests_run2_SHARED_CACHE_FAILED.log). The fresh root is part of the
# procedure, not a convenience.
#
# The isolation root is the ONLY thing this script deletes. It refuses to touch
# anything whose path does not contain /simigo-rc1-gate-closure-20261023/isolation.
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?usage: run_isolated_tests.sh <tag>}"
ISO="$B/isolation"
APP="$B/derived/Build/Products/Debug/SimiGo.app"
XR="$B/derived/Build/Products/xctestrun_isolated.xctestrun"

case "$ISO" in
  */simigo-rc1-gate-closure-20261023/isolation) : ;;
  *) echo "REFUSING: unexpected isolation root $ISO" >&2; exit 3 ;;
esac

# --- fresh root ------------------------------------------------------------
for d in home cache state-graph; do
  if [ -e "$ISO/$d" ]; then rm -rf "$ISO/$d"; fi
  mkdir -p "$ISO/$d"
done
date -u +%FT%TZ > "$ISO/${TAG}_start.txt"
START=$(date +%s)

# --- isolate the test bundle (regenerated, differences re-measured) ---------
python3 "$B/driver/make_isolated_xctestrun.py" "$APP" "$B" || exit 4

# --- pre snapshot ----------------------------------------------------------
python3 "$B/driver/rc_noninterference.py" "pre-iso-$TAG" > "$B/noninterference_pre-iso-$TAG.stdout.json" || exit 5

# --- run -------------------------------------------------------------------
xcodebuild test-without-building \
  -xctestrun "$XR" \
  -destination 'platform=macOS,arch=arm64' \
  -resultBundlePath "$B/derived/Logs/Test/Test-$TAG.xcresult" \
  2>&1 | tee "$B/isolated_tests_$TAG.log"
RC=${PIPESTATUS[0]}

# --- post snapshot + diff --------------------------------------------------
python3 "$B/driver/rc_noninterference.py" "post-iso-$TAG" > "$B/noninterference_post-iso-$TAG.stdout.json" || exit 5
python3 "$B/driver/rc_noninterference_diff.py" \
  "$B/noninterference_pre-iso-$TAG.json" "$B/noninterference_post-iso-$TAG.json" \
  "$B/noninterference_diff_iso-$TAG-window.json" "$B"

END=$(date +%s)
python3 - "$B" "$TAG" "$RC" "$START" "$END" <<'PY'
import json, os, re, sys
B, tag, rc, start, end = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
log = open(os.path.join(B, "isolated_tests_%s.log" % tag), errors="replace").read()
m = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures?", log)
tot = tuple(int(x) for x in m[-1]) if m else None
iso = os.path.join(B, "isolation")
def du(p):
    t = 0
    for r, _, fs in os.walk(p):
        for f in fs:
            try: t += os.path.getsize(os.path.join(r, f))
            except OSError: pass
    return t
diff = json.load(open(os.path.join(B, "noninterference_diff_iso-%s-window.json" % tag)))
rec = {
 "tag": tag, "exit_code": rc, "duration_s": end - start,
 "executed_skipped_failures": tot,
 "test_execute_succeeded": "** TEST EXECUTE SUCCEEDED **" in log,
 "xcresult": os.path.join(B, "derived/Logs/Test/Test-%s.xcresult" % tag),
 "xctestrun": json.load(open(os.path.join(B, "xctestrun_isolation.json")))["isolated_sha256"],
 "fresh_isolation_root": True,
 "isolation_content_bytes": {d: du(os.path.join(iso, d)) for d in ("home", "cache", "state-graph")},
 "noninterference": {"real_user_state_write_count": diff["real_user_state_write_count"],
                     "real_user_state_write_paths": diff["real_user_state_write_paths"],
                     "violation_events": diff["violation_events"],
                     "expected_self_writes": len(diff["distinct_expected_abs_paths"])},
}
with open(os.path.join(B, "isolation_run_%s.json" % tag), "w") as f:
    json.dump(rec, f, indent=1); f.write("\n")
print(json.dumps(rec, indent=1))
if rc != 0 or diff["real_user_state_write_count"] != 0:
    sys.exit(6)
PY
