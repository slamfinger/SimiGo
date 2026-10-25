#!/bin/bash
# RC step 4 (primary artifact): minimal cross-process flow on the built+tested bundle.
# Equivalent to the ad-hoc /tmp launcher used for run rc1; kept here so the run
# is reproducible from the batch alone.
set -u
export SIMIGO_EXPERIMENT_TARGET=hello
export SIMIGO_COUNTERFACTUAL_BASELINE_VALUE=world
cd /Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023
exec bash driver/run_rc_g1g3.sh rc1
