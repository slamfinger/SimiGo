#!/bin/bash
# Replay of the fail-closed cases in negatives-final/transcript.txt against the
# committed bytes at f18d65f (working tree clean at the time of replay).
#
# Why a script: the original case list was driven ad hoc. A reviewer needs to be
# able to re-derive every rc without trusting the transcript. Each case below is
# expected to be REJECTED before any filesystem effect, so the only writes are
# scratch paths under $S plus this transcript - never the real user state, never
# the repo, never the clean2 build products (their digests are re-checked).
#
# exit: 0 all cases matched the expected rc and left no residue - 1 deviation
set -u
REPO=${REPO:-/Users/mr.simi/Documents/SimiGo}
BATCH=$(cd "$(dirname "$0")/.." && pwd)
CLEAN2=${CLEAN2:-$BATCH/clean2}
APP=${APP:-$CLEAN2/build/test/Build/Products/Debug/SimiGo.app}
BASE=${BASE:-$CLEAN2/build/test/Build/Products/SimiGo_SimiGo_macosx27.0-arm64.xctestrun}
S=${S:-$BATCH/negatives-replay-20261023}
T=$S/transcript.txt
RUN=$REPO/tools/run_isolated_tests.sh
GEN=$REPO/tools/make_isolated_xctestrun.py
DIFF=$REPO/tools/rc_noninterference_diff.py
XR_ISO=$CLEAN2/build/test/Build/Products/xctestrun_isolated.xctestrun

mkdir -p "$S" "$S/n1" "$S/n2" "$S/n8/isolation" "$S/n9/isolation" "$S/n11" "$S/n12"
: > "$T"
printf 'not a plist\n' > "$S/n9/bad.xctestrun"

say() { printf '%s\n' "$*" | tee -a "$T"; }
line1() { printf '%s' "$1" | sed -n '1p'; }
fails=0
capture() { OUT=$("$@" 2>&1); RC=$?; }

say "# negatives replay against the committed bytes at $(git -C "$REPO" rev-parse --short HEAD)"
say "# repo=$REPO clean2=$CLEAN2"

capture "$RUN" --app "$S/no-app/SimiGo.app" --evidence-dir "$S/n1/evidence" --tag n1
[ "$RC" -eq 3 ] && say "[N1 app missing] rc=$RC OK :: $(line1 "$OUT")" || { say "[N1 app missing] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }
[ -e "$S/n1/evidence" ] && { say "    evidence dir created? YES - DEVIATION"; fails=$((fails+1)); } || say "    evidence dir created? NO"

capture "$RUN" --app "$APP" --base-xctestrun "$S/nope.xctestrun" --evidence-dir "$S/n2/evidence" --tag n2
[ "$RC" -eq 3 ] && say "[N2 base xctestrun missing] rc=$RC OK :: $(line1 "$OUT")" || { say "[N2 base xctestrun missing] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }
[ -e "$S/n2/evidence" ] && { say "    evidence dir created? YES - DEVIATION"; fails=$((fails+1)); } || say "    evidence dir created? NO"

EV3="$HOME/.simigo/replay-evidence-20261023"
capture "$RUN" --app "$APP" --evidence-dir "$EV3" --tag n3
[ "$RC" -eq 3 ] && say "[N3 evidence inside real root] rc=$RC OK :: $(line1 "$OUT")" || { say "[N3 evidence inside real root] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }
[ -e "$EV3" ] && { say "    created? YES - DEVIATION"; fails=$((fails+1)); } || say "    created? NO"

capture "$RUN" --app "$APP" --evidence-dir "$HOME" --tag n4
[ "$RC" -eq 3 ] && say "[N4 evidence = HOME] rc=$RC OK :: $(line1 "$OUT")" || { say "[N4 evidence = HOME] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }

capture "$RUN" --app "$APP" --evidence-dir "$REPO" --tag n5
[ "$RC" -eq 3 ] && say "[N5 evidence = repo root] rc=$RC OK :: $(line1 "$OUT")" || { say "[N5 evidence = repo root] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }

capture "$RUN" --app "$APP" --evidence-dir / --tag n6
[ "$RC" -eq 3 ] && say "[N6 evidence = /] rc=$RC OK :: $(line1 "$OUT")" || { say "[N6 evidence = /] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }

capture "$RUN" --bogus
[ "$RC" -eq 2 ] && say "[N7 unknown flag] rc=$RC OK :: $(line1 "$OUT")" || { say "[N7 unknown flag] rc=$RC DEVIATION (want 2) :: $(line1 "$OUT")"; fails=$((fails+1)); }

capture python3 "$GEN" --app "$APP" --isolation-root "$S/n8/isolation" --base-xctestrun "$BASE" --out "$S/n8/elsewhere/x.xctestrun"
[ "$RC" -eq 3 ] && say "[N8 generator out escapes base dir] rc=$RC OK :: $(line1 "$OUT")" || { say "[N8 generator out escapes base dir] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }
[ -e "$S/n8/elsewhere/x.xctestrun" ] && { say "    output written? YES - DEVIATION"; fails=$((fails+1)); } || say "    output written? NO"

BEFORE=$(shasum -a 256 "$XR_ISO" 2>/dev/null | awk '{print $1}')
capture python3 "$GEN" --app "$APP" --isolation-root "$S/n9/isolation" --base-xctestrun "$S/n9/bad.xctestrun" --out "$S/n9/xctestrun_isolated.xctestrun"
AFTER=$(shasum -a 256 "$XR_ISO" 2>/dev/null | awk '{print $1}')
[ "$RC" -eq 3 ] && say "[N9 generator unparsable baseline] rc=$RC OK :: $(line1 "$OUT")" || { say "[N9 generator unparsable baseline] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }
[ -e "$S/n9/xctestrun_isolated.xctestrun" ] && { say "    output written? YES - DEVIATION"; fails=$((fails+1)); } || say "    output written? NO"
[ "$BEFORE" = "$AFTER" ] && say "    clean2 isolated xctestrun untouched? YES ($BEFORE)" || { say "    clean2 isolated xctestrun touched - DEVIATION ($BEFORE -> $AFTER)"; fails=$((fails+1)); }

cp "$BASE" "$S/n10-base.xctestrun"
capture "$RUN" --app "$APP" --base-xctestrun "$S/n10-base.xctestrun" --evidence-dir "$S/n10/evidence" --tag n10
[ "$RC" -eq 4 ] && say "[N10 runner: base outside products] rc=$RC OK :: $(line1 "$OUT")" || { say "[N10 runner: base outside products] rc=$RC DEVIATION (want 4) :: $(line1 "$OUT")"; fails=$((fails+1)); }

capture python3 "$DIFF" "$BATCH/run3/snapshot_pre.json" "$BATCH/run3/snapshot_post.json" "$S/n11/diff_bad.json" --allow-prefix "$HOME"
[ "$RC" -eq 3 ] && say "[N11 diff allow-prefix covers real root] rc=$RC OK :: $(line1 "$OUT")" || { say "[N11 diff allow-prefix covers real root] rc=$RC DEVIATION (want 3) :: $(line1 "$OUT")"; fails=$((fails+1)); }
[ -e "$S/n11/diff_bad.json" ] && { say "    output written? YES - DEVIATION"; fails=$((fails+1)); } || say "    output written? NO"

capture python3 "$DIFF" "$BATCH/run3/snapshot_pre.json" "$BATCH/run3/snapshot_post.json" "$S/n12/diff_ok.json" --allow-prefix "$BATCH/run3"
[ "$RC" -eq 0 ] && say "[N12 diff control] rc=$RC OK :: $(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("real_user_state_write_count=%d distinct_violation_count=%d"%(d["real_user_state_write_count"],d["distinct_violation_count"]))' "$S/n12/diff_ok.json" 2>/dev/null)" || { say "[N12 diff control] rc=$RC DEVIATION (want 0) :: $(line1 "$OUT")"; fails=$((fails+1)); }

say ""
say "# deviations: $fails"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
