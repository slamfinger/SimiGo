#!/usr/bin/env python3
"""Measured-locality analysis over G1.9-C collection artifacts.

Consumes g19-collect reports (five models x four registered workloads) and
computes, per (model, workload), the four registered quantities on the
MEASURED line only, plus the declared-vs-measured divergence:

  C1 recurrence          |M_t intersect M_{t+1}| across consecutive steps
  C2 transition locality |M_t intersect M_{t+1}| / |M_{t+1}|
  C3 temporal stability  overlap of M_{t-k} with M_t for k = 1, 2, 3
  C4 working-set breadth |M_t| distribution

No pooling across models or workloads. No demand interpretation: M_t is the
set of groups whose layers were observed to execute in step t; the declared
sets are scenario labels kept in a separate field.
"""

import json
from pathlib import Path

RESULTS = Path(__file__).resolve().parents[1] / "results" / "g19-collect"
SLUGS = [
    "qwen3-coder-30b",
    "nail-qwen36-35b",
    "cyber-tiel-35b",
    "gemma4-12b-coder",
    "muse-glimmer-30b",
]
TRACES = ["T1_DOCUMENT_SESSION", "T2_COMPUTER_OPERATION", "T3_AGENTIC_MULTI_TURN", "T4_LONG_CONTEXT"]


def mean(values):
    return sum(values) / len(values) if values else None


def sets_overlap(a, b):
    return len(a & b)


def analyse_workload(steps):
    measured = [set(s["measuredGroupIDs"]) for s in steps]
    declared = [set(s["declaredOptionalGroupIDs"]) for s in steps]

    c1_intersections = [
        sets_overlap(measured[t], measured[t + 1]) for t in range(len(measured) - 1)
    ]
    c2 = [
        sets_overlap(measured[t], measured[t + 1]) / len(measured[t + 1])
        if measured[t + 1]
        else 1.0
        for t in range(len(measured) - 1)
    ]
    c3 = {}
    for k in (1, 2, 3):
        pairs = [
            sets_overlap(measured[t - k], measured[t]) / len(measured[t])
            if measured[t]
            else 1.0
            for t in range(k, len(measured))
        ]
        c3[f"lag{k}_meanOverlapRatio"] = round(mean(pairs), 4) if pairs else None

    breadths = [len(m) for m in measured]
    max_breadth = max(breadths) if breadths else 0

    declared_subset_of_measured = all(
        d <= m for d, m in zip(declared, measured)
    )
    measured_minus_declared = [
        sorted(m - d) for d, m in zip(declared, measured)
    ]
    steps_with_excess = sum(1 for excess in measured_minus_declared if excess)

    return {
        "stepCount": len(steps),
        "C1_recurrence": {
            "meanIntersectionSize": round(mean(c1_intersections), 3)
            if c1_intersections
            else None,
            "allTransitionsNonEmpty": all(v > 0 for v in c1_intersections)
            if c1_intersections
            else None,
        },
        "C2_transitionLocality": {
            "meanRatio": round(mean(c2), 4) if c2 else None,
            "minRatio": round(min(c2), 4) if c2 else None,
            "maxRatio": round(max(c2), 4) if c2 else None,
        },
        "C3_temporalStability": c3,
        "C4_workingSetBreadth": {
            "min": min(breadths) if breadths else None,
            "max": max_breadth,
            "mean": round(mean(breadths), 3) if breadths else None,
            "fractionAtMax": round(
                sum(1 for b in breadths if b == max_breadth) / len(breadths), 4
            )
            if breadths
            else None,
        },
        "declaredVsMeasured": {
            "declaredAlwaysSubsetOfMeasured": declared_subset_of_measured,
            "stepsWithMeasuredExcess": steps_with_excess,
            "sampleExcess": measured_minus_declared[0] if measured_minus_declared else [],
        },
    }


def main():
    analysis = {
        "boundary": "MEASURED_LAYER_ENTERED_ONLY / NOT_DEMAND / NOT_PREDICTION / "
        "DECLARED_LINE_IS_SCENARIO / PER_MODEL_PER_WORKLOAD_NO_POOLING",
        "models": {},
    }
    for slug in SLUGS:
        path = RESULTS / f"{slug}.json"
        if not path.exists():
            continue
        with open(path) as handle:
            report = json.load(handle)
        entry = {
            "modelType": report["modelType"],
            "instrumentedModuleCount": report["instrumentedModuleCount"],
            "preambleIdentityPass": report["preamble"]["identityPass"],
            "workloads": {},
        }
        for workload in report["workloads"]:
            entry["workloads"][workload["traceID"]] = analyse_workload(
                workload["steps"]
            )
        analysis["models"][slug] = entry

    out_dir = RESULTS / "analysis"
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / "measured-locality.json"
    with open(out_path, "w") as handle:
        json.dump(analysis, handle, indent=2, sort_keys=True)
    print(f"wrote {out_path}")

    for slug, entry in analysis["models"].items():
        print(f"\n== {slug} ({entry['modelType']}, modules={entry['instrumentedModuleCount']}, "
              f"preambleIdentity={entry['preambleIdentityPass']})")
        for trace, w in entry["workloads"].items():
            c2 = w["C2_transitionLocality"]["meanRatio"]
            c4 = w["C4_workingSetBreadth"]
            div = w["declaredVsMeasured"]
            print(
                f"  {trace:<24} steps={w['stepCount']:>2} "
                f"C1_nonEmpty={w['C1_recurrence']['allTransitionsNonEmpty']} "
                f"C2={c2} C4breadth={c4['min']}-{c4['max']} (atMax {c4['fractionAtMax']}) "
                f"declaredSubset={div['declaredAlwaysSubsetOfMeasured']} "
                f"excessSteps={div['stepsWithMeasuredExcess']}"
            )


if __name__ == "__main__":
    main()
