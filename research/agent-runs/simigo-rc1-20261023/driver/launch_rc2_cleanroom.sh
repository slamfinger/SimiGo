#!/bin/bash
# RC supplementary check: run the SAME minimal cross-process flow on the
# clean-room rebuild (source materialized from HEAD + tracked patch + untracked
# files), to test whether a from-clean-state build also runs the core path.
set -u
CR=/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/cleanroom
export SIMIGO_EXPERIMENT_TARGET=hello
export SIMIGO_COUNTERFACTUAL_BASELINE_VALUE=world
export RC_SRC_APP="$CR/derived/Build/Products/Debug/SimiGo.app"
export RC_REPO="$CR/repo"
cd /Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023
exec bash driver/run_rc_g1g3.sh rc2
