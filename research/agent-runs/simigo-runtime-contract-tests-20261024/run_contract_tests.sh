#!/bin/bash
# Reproduce the SimiGoRuntimeContractTests evidence run from a clean checkout.
# usage: run_contract_tests.sh <run-dir>
# Writes: identity.txt logs/ isolation/ scratch/ pre|post_snapshot.json
#         noninterference_diff.json summary.json
set -u
REPO=${REPO:-/Users/mr.simi/Documents/SimiGo}
COMMIT=${COMMIT:-f18d65f8f312ffbb837fdf5e07125af044833854}
RUN=${1:-}
if [ -z "$RUN" ]; then echo "usage: $0 <run-dir>" >&2; exit 2; fi
mkdir -p "$RUN"/logs "$RUN"/isolation/home "$RUN"/isolation/cache \
         "$RUN"/isolation/state-graph "$RUN"/scratch "$RUN"/src || exit 3
cd "$RUN" || exit 3

git clone --quiet "$REPO" src/contract-checkout || exit 3
git -C src/contract-checkout checkout --quiet "$COMMIT" || exit 3
HEAD=$(git -C src/contract-checkout rev-parse HEAD)
[ "$HEAD" = "$COMMIT" ] || { echo "HEAD mismatch: $HEAD" >&2; exit 3; }

{
  echo "run_dir: $RUN"; echo "captured_at: $(date -Iseconds)"
  echo "host: $(hostname)"; echo "arch: $(uname -m)"; echo "macos: $(sw_vers -productVersion)"
  echo "source_repo: $REPO"; echo "source_commit: $COMMIT"; echo "checkout_head: $HEAD"
  echo "checkout_dirty_lines: $(git -C src/contract-checkout status --porcelain | wc -l | tr -d ' ')"
  shasum -a 256 src/contract-checkout/Packages/SimiGoRuntime/Package.swift \
                src/contract-checkout/Packages/SimiGoRuntime/Package.resolved
  xcodebuild -version; swift --version 2>&1 | head -3
} > identity.txt

export SIMIGO_HOME="$RUN/isolation/home"
export SIMIGO_CACHE_ROOT="$RUN/isolation/cache"
export SIMIGO_STATE_GRAPH_STORE="$RUN/isolation/state-graph"
printf 'SIMIGO_HOME=%s\nSIMIGO_CACHE_ROOT=%s\nSIMIGO_STATE_GRAPH_STORE=%s\ncd %s/src/contract-checkout\nswift test --package-path Packages/SimiGoRuntime --scratch-path %s/scratch\n' \
  "$SIMIGO_HOME" "$SIMIGO_CACHE_ROOT" "$SIMIGO_STATE_GRAPH_STORE" "$RUN" "$RUN" > command.txt

python3 src/contract-checkout/tools/rc_noninterference.py \
  --phase contract_tests_pre --out "$RUN/pre_snapshot.json" > logs/pre_snapshot.stdout.log 2>&1
PRE=$?

cd src/contract-checkout || exit 3
/usr/bin/time -p swift test --package-path Packages/SimiGoRuntime \
  --scratch-path "$RUN/scratch" > "$RUN/logs/swift_test.stdout.log" 2> "$RUN/logs/swift_test.stderr.log"
RC=$?
cd "$RUN" || exit 3
echo "$RC" > logs/swift_test.rc
grep -E '^(real|user|sys) ' logs/swift_test.stderr.log > logs/swift_test.time.txt

python3 src/contract-checkout/tools/rc_noninterference.py \
  --phase contract_tests_post --out "$RUN/post_snapshot.json" > logs/post_snapshot.stdout.log 2>&1
python3 src/contract-checkout/tools/rc_noninterference_diff.py \
  "$RUN/pre_snapshot.json" "$RUN/post_snapshot.json" "$RUN/noninterference_diff.json" \
  > logs/noninterference_diff.stdout.log 2>&1
DIFF=$?

python3 - "$RUN" <<'PY'
import json, os, re, sys, hashlib, collections
run = sys.argv[1]
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''): h.update(c)
    return h.hexdigest()
log = os.path.join(run, 'logs/swift_test.stdout.log')
txt = open(log, encoding='utf-8', errors='replace').read()
suites, cur = collections.OrderedDict(), None
for ln in txt.splitlines():
    m = re.match(r"Test Suite '([^']+)' (started|passed|failed) at", ln)
    if m:
        cur = m.group(1) if m.group(2) == 'started' else None
        if m.group(2) == 'started': suites.setdefault(cur, [])
        continue
    m = re.match(r"Test Case '-\[([\w.]+) (test\w+)\]' (passed|failed|skipped)", ln)
    if m and cur: suites[cur].append([m.group(2), m.group(3)])
suites = {k: v for k, v in suites.items() if v}
m = re.search(r"Executed (\d+) tests?, with (\d+) failures?.*?in ([\d.]+)", txt)
out = {
  "run_dir": run,
  "rc": int(open(os.path.join(run, 'logs/swift_test.rc')).read().strip()),
  "suites": {k: {"executed": len(v),
                 "passed": sum(1 for _, s in v if s == 'passed'),
                 "failed": sum(1 for _, s in v if s == 'failed'),
                 "skipped": sum(1 for _, s in v if s == 'skipped')} for k, v in suites.items()},
  "executed": int(m.group(1)) if m else None,
  "failures": int(m.group(2)) if m else None,
  "test_binary": os.path.join(run, 'scratch/out/Products/Debug/SimiGoRuntimeContractTests.xctest/Contents/MacOS/SimiGoRuntimeContractTests'),
  "isolation_files": sum(len(f) for _, _, f in os.walk(os.path.join(run, 'isolation'))),
  "log_sha256": {os.path.basename(p): sha(p) for p in
                 [os.path.join(run, 'logs', x) for x in ('swift_test.stdout.log', 'swift_test.stderr.log')]},
}
bp = out['test_binary']
out['test_binary_sha256'] = sha(bp) if os.path.exists(bp) else None
d = json.load(open(os.path.join(run, 'noninterference_diff.json')))
out['real_user_state_write_count'] = d['real_user_state_write_count']
out['violation_events'] = d['violation_events']
out['reference_changes'] = len(d['reference_change_paths'])
json.dump(out, open(os.path.join(run, 'summary.json'), 'w'), indent=1)
print(json.dumps({k: out[k] for k in ('rc', 'executed', 'failures',
      'real_user_state_write_count', 'violation_events', 'isolation_files')}))
PY

echo "SWIFT_TEST_RC=$RC PRE_SNAPSHOT_RC=$PRE DIFF_RC=$DIFF"
[ "$RC" -eq 0 ] && [ "$PRE" -eq 0 ] && [ "$DIFF" -eq 0 ]
