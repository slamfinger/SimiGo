#!/bin/zsh
# Verification-only pass after the closing documentation/diff additions.
# It does NOT rebuild, does NOT re-execute any condition and does NOT overwrite the
# guard manifests whose result summary.json embeds; the fresh manifests go to
# manifests/closing-diff-pass/ so the embedded record stays consistent.
set -e
REPO=/Users/mr.simi/Documents/SimiGo-Lab
RUN="$HOME/SimiGo-Agent-Runs/es-is-detached-continuation-20261022f"
PACK="$RUN/simigo_detached_continuation_agent_pack"
OUT="$RUN/manifests/closing-diff-pass"
mkdir -p "$OUT"

cd "$REPO"
/usr/bin/python3 "$PACK/workspace_guard.py" verify --repo "$REPO" \
  --before "$RUN/manifests/workspace-before.json" \
  --out "$OUT/workspace-verify.json" \
  --allow-change 'simigo2-experimental/Package.swift' \
  --allow-change 'simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift' \
  --allow-change 'simigo2-experimental/Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift' \
  --allow-change 'simigo2-experimental/Sources/SimiGoDetachedDriver/*' \
  --allow-change 'simigo2-experimental/Sources/SimiGoTaskRun/*' \
  --allow-change 'simigo2-experimental/scripts/ordinary_task/run_phase_f.py' \
  --allow-change 'simigo2-experimental/Tests/SimiGo2ExperimentalTests/*'

/usr/bin/python3 "$PACK/artifact_guard.py" verify \
  --before "$RUN/manifests/artifacts-before.json" \
  --out "$OUT/artifacts-verify.json"

/usr/bin/python3 "$PACK/validate_evidence.py" "$RUN/summary.json" \
  --acceptance "$OUT/acceptance.json"

/usr/bin/python3 - "$OUT" <<'PY'
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
w = json.loads((out / "workspace-verify.json").read_text())
a = json.loads((out / "artifacts-verify.json").read_text())
v = json.loads((out / "acceptance.json").read_text())
print("workspace guard :", w["result"], "changed", w["changed_file_count"],
      "issues", len(w["issues"]), "head/branch/staged unchanged",
      w["head_unchanged"], w["branch_unchanged"], w["staged_diff_unchanged"])
print("artifact guard  :", a["result"], "issues", len(a["issues"]))
print("evidence        :", v["result"], "errors", v["errors"])
PY
