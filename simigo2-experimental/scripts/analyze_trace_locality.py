#!/usr/bin/env python3
"""Locality analysis over workload-trace artifacts (plan step 7).

Consumes simulator trace-replay reports (*-sim.json) and real Gate 5 trace
benchmarks (*-real-T*.json) and produces per-model, per-trace locality
descriptors. No pooling across traces or models: every number is attributable
to one (model, trace) pair.

Boundary: DECLARED_TRACE_STATE_MAPPING / DESCRIPTIVE_RECENCY_HINTS /
NOT_PREDICTION / NOT_DEMAND_CLAIM. This script measures properties of the
declared traces and the planner response to them; it does not predict future
demand and does not authorize a Predictor.
"""

import json
import sys
from pathlib import Path

RESULTS = Path(__file__).resolve().parents[1] / "results" / "workload-trace"

MODEL_SIM = {
    "qwen3-coder-30b": "qwen3-coder-default.json",
    "gemma4-12b-coder": "gemma4-12b-coder-sim.json",
    "nail-qwen36-35b": "nail-qwen36-35b-sim.json",
    "cyber-tiel-35b": "cyber-tiel-35b-sim.json",
    "muse-glimmer-30b": "muse-glimmer-30b-sim.json",
}

TRACES = ["T1", "T2", "T3", "T4"]
GIB = 2**30


def load(path):
    with open(path) as handle:
        return json.load(handle)


def run_for_budget(sim_run, percent):
    return sim_run


def optional_required_sets(core_bytes, step_records):
    sets = []
    for record in step_records:
        groups = set(record["requiredGroupIDs"])
        # Optional part: everything whose cumulative required bytes exceed the
        # core marker cannot be derived here; instead use the budget-independent
        # rule that the sim replay stores required sets including core. We mark
        # optional groups as those appearing in optionalGroupRequiredStepIndices.
        sets.append(groups)
    return sets


def analyse_model(slug, sim_path):
    sim = load(sim_path)
    runs = sim["runs"]
    by_trace = {}
    for trace in TRACES:
        trace_runs = [r for r in runs if r["traceID"].startswith(trace + "_")]
        if not trace_runs:
            continue
        # required sets are budget-independent: take any run's records
        records = trace_runs[0]["stepRecords"]
        required = [set(r["requiredGroupIDs"]) for r in records]
        # optional groups are those tracked by the replay
        optional_index = trace_runs[0]["optionalGroupRequiredStepIndices"]
        optional_groups = set(optional_index.keys())

        # transition locality over optional parts
        overlaps, containments = [], []
        for a, b in zip(required, required[1:]):
            oa = {g for g in a if g in optional_groups}
            ob = {g for g in b if g in optional_groups}
            union = oa | ob
            overlaps.append(len(oa & ob) / len(union) if union else 1.0)
            containments.append(1.0 if ob <= oa else 0.0)

        # reuse gaps per optional group
        gaps = {}
        for group, indices in optional_index.items():
            gaps[group] = [b - a for a, b in zip(indices, indices[1:])]

        budgets = {
            str(int(r["budgetPercent"])): {
                "requiredHitRatio": round(r["requiredHitRatio"], 3),
                "loadedGiB": round(r["cumulativeLoadedBytes"] / GIB, 2),
                "evictedGiB": round(r["cumulativeEvictedBytes"] / GIB, 2),
                "overflowSteps": r["overflowStepCount"],
                "plannerMissGiB": round(r["requiredMissBytesTotal"] / GIB, 2),
                "zeroRetentionMissGiB": round(
                    r["zeroRetentionMissBytesTotal"] / GIB, 2
                ),
                "reloadSavedVsZeroRetentionGiB": round(
                    r["reloadReductionVsZeroRetentionBytes"] / GIB, 2
                ),
            }
            for r in trace_runs
        }

        by_trace[trace] = {
            "steps": len(records),
            "optionalTransitionOverlapMean": round(sum(overlaps) / len(overlaps), 3)
            if overlaps
            else None,
            "optionalNextSubsetPrevRatio": round(
                sum(containments) / len(containments), 3
            )
            if containments
            else None,
            "reuseGaps": gaps,
            "budgets": budgets,
        }
    return by_trace


def analyse_real(slug):
    out = {}
    for trace in TRACES:
        path = RESULTS / f"{slug}-real-{trace}.json"
        if slug == "qwen3-coder-30b":
            path = RESULTS / f"qwen3-coder-real-{trace}.json"
        if not path.exists():
            out[trace] = None
            continue
        d = load(path)
        naive = d["naiveOnDemand"]
        state = d["stateDriven"]
        out[trace] = {
            "benchmarkPass": d["benchmarkPass"],
            "outputIdentityPass": d["outputIdentityPass"],
            "idleReductionGiB": round(d["idleReductionBytes"] / GIB, 2),
            "naiveReloadGiB": round(naive["cumulativeReloadedBytes"] / GIB, 2),
            "stateReloadGiB": round(state["cumulativeReloadedBytes"] / GIB, 2),
            "reloadReductionGiB": round(d["reloadReductionVsNaiveBytes"] / GIB, 2),
            "reloadReductionRatio": round(
                d["reloadReductionVsNaiveBytes"] / naive["cumulativeReloadedBytes"], 3
            )
            if naive["cumulativeReloadedBytes"]
            else None,
            "naiveReloadSeconds": round(naive["totalReloadMilliseconds"] / 1000, 2),
            "stateReloadSeconds": round(state["totalReloadMilliseconds"] / 1000, 2),
            "stateIdleGiB": round(
                min(t["idleActiveBytes"] for t in state["transitions"]) / GIB, 2
            ),
        }
    return out


def main():
    analysis = {
        "boundary": "DECLARED_TRACE_STATE_MAPPING / DESCRIPTIVE_RECENCY_HINTS / "
        "NOT_PREDICTION / NOT_DEMAND_CLAIM / PER_MODEL_PER_TRACE_NO_POOLING",
        "models": {},
    }
    for slug, sim_name in MODEL_SIM.items():
        sim_path = RESULTS / sim_name
        if not sim_path.exists():
            continue
        entry = {"traces": analyse_model(slug, sim_path), "real": analyse_real(slug)}
        analysis["models"][slug] = entry

    out_dir = RESULTS / "analysis"
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / "locality-analysis.json"
    with open(out_path, "w") as handle:
        json.dump(analysis, handle, indent=2, sort_keys=True)
    print(f"wrote {out_path}")

    # console summary
    for slug, entry in analysis["models"].items():
        print(f"\n== {slug}")
        for trace, t in entry["traces"].items():
            b100 = t["budgets"].get("100", {})
            b70 = t["budgets"].get("70", {})
            real = entry["real"].get(trace) or {}
            print(
                f"  {trace}: overlap={t['optionalTransitionOverlapMean']} "
                f"subsetPrev={t['optionalNextSubsetPrevRatio']} "
                f"hit@70={b70.get('requiredHitRatio')} hit@100={b100.get('requiredHitRatio')} "
                f"saved_sim@100={b100.get('reloadSavedVsZeroRetentionGiB')}GiB "
                f"real_saved={real.get('reloadReductionGiB')}GiB "
                f"({real.get('reloadReductionRatio')}) pass={real.get('benchmarkPass')}"
            )


if __name__ == "__main__":
    sys.exit(main())
