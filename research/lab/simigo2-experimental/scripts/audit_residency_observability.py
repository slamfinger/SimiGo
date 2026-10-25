#!/usr/bin/env python3
"""Residency observability audit: byte-level validation.

Question audited: is the policy bookkeeping of the resident set validated by
an independent observation?

Mechanism: the Gate 5 harness measures MLX aggregate active memory between
generations (`idleActiveBytes`), which is an independent runtime observation.
The retention bookkeeping predicts that idle residency equals
core + the policy's retention set for the transition's state. This script
reconstructs the predicted byte counts from the per-model inventory and
compares them against the measured idle bytes across all 20 real trace runs
(5 models x 4 workloads) and all three policies.

Verdict inputs (no pooling):
  predictedBytes  = sum of group byteCounts of the bookkeeping resident set
  measuredBytes   = MLX idleActiveBytes snapshot
  deviation       = measured - predicted
"""

import json
from pathlib import Path

RESULTS = Path(__file__).resolve().parents[1] / "results"
AUDIT = RESULTS / "residency-audit"
TRACE = RESULTS / "workload-trace"

SLUG_FILES = {
    "qwen3-coder-30b": "qwen3-coder-real-{t}.json",
    "nail-qwen36-35b": "{slug}-real-{t}.json",
    "cyber-tiel-35b": "{slug}-real-{t}.json",
    "gemma4-12b-coder": "{slug}-real-{t}.json",
    "muse-glimmer-30b": "{slug}-real-{t}.json",
}
TRACES = ["T1", "T2", "T3", "T4"]
POLICIES = ["allResident", "naiveOnDemand", "stateDriven"]


def resident_groups(inventory, policy, state=None):
    core = [g for g in inventory["groups"] if g.get("alwaysResident")]
    optional = sorted(
        (g for g in inventory["groups"] if not g.get("alwaysResident")),
        key=lambda g: g["layerRangeDescription"],
    )
    if policy == "allResident":
        chosen = optional
    elif policy == "naiveOnDemand":
        # every optional group is released after each generation; idle
        # residency is core only
        chosen = []
    else:  # stateDriven retention set
        mapping = {
            "STATE_A": [0], "STATE_B": [1], "STATE_C": [2],
            "STATE_AB": [0, 1], "STATE_BC": [1, 2],
            "STATE_ALL": [0, 1, 2],
        }
        chosen = [optional[i] for i in mapping.get(state, [])]
    return core + chosen


def byte_sum(groups):
    return sum(g["byteCount"] for g in groups)


def main():
    out = {
        "boundary": "OBSERVABILITY_AUDIT / BYTE_LEVEL_VALIDATION / "
        "GROUP_RESIDENT_SET_IS_POLICY_BOOKKEEPING / NOT_DEMAND",
        "models": {},
    }
    for slug, name_pattern in SLUG_FILES.items():
        with open(AUDIT / f"{slug}-inventory.json") as handle:
            inventory = json.load(handle)
        rows = []
        for trace in TRACES:
            path = TRACE / name_pattern.format(slug=slug, t=trace)
            with open(path) as handle:
                report = json.load(handle)
            for policy in POLICIES:
                pass_report = report[policy]
                for index, transition in enumerate(pass_report["transitions"]):
                    state = (
                        transition["executionState"]
                        if policy == "stateDriven"
                        else None
                    )
                    predicted = byte_sum(resident_groups(inventory, policy, state))
                    measured = transition["idleActiveBytes"]
                    rows.append(
                        {
                            "trace": trace,
                            "policy": policy,
                            "transitionIndex": index,
                            "state": state,
                            "predictedBytes": predicted,
                            "measuredBytes": measured,
                            "deviationBytes": measured - predicted,
                            "relativeDeviation": (measured - predicted) / predicted
                            if predicted
                            else 0.0,
                        }
                    )
        deviations = [abs(r["deviationBytes"]) for r in rows]
        relatives = [abs(r["relativeDeviation"]) for r in rows]
        worst = max(rows, key=lambda r: abs(r["deviationBytes"]))
        per_policy = {}
        for policy in POLICIES:
            prows = [r for r in rows if r["policy"] == policy]
            prels = [abs(r["relativeDeviation"]) for r in prows]
            per_policy[policy] = {
                "rows": len(prows),
                "maxAbsDeviationBytes": max(abs(r["deviationBytes"]) for r in prows),
                "maxAbsRelativeDeviation": max(prels),
                "meanAbsRelativeDeviation": sum(prels) / len(prels),
            }
        out["models"][slug] = {
            "transitionCount": len(rows),
            "maxAbsDeviationBytes": max(deviations),
            "maxAbsRelativeDeviation": max(relatives),
            "meanAbsRelativeDeviation": sum(relatives) / len(relatives),
            "perPolicy": per_policy,
            "worstRow": worst,
        }
        print(
            f"{slug:<18} n={len(rows):>3} maxAbsDev={max(deviations)/2**20:8.3f} MiB "
            f"maxRel={max(relatives):.6f} meanRel={sum(relatives)/len(relatives):.6f} "
            f"worst=({worst['trace']}/{worst['policy']}/#{worst['transitionIndex']})"
        )
        for policy, stats in per_policy.items():
            print(
                f"    {policy:<16} maxRel={stats['maxAbsRelativeDeviation']:.6f} "
                f"meanRel={stats['meanAbsRelativeDeviation']:.6f}"
            )

    out_path = AUDIT / "byte-validation.json"
    with open(out_path, "w") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
