#!/usr/bin/env python3
"""G1.9-E0 Retention Optimization Feasibility Audit (offline).

Purely offline over existing artifacts: state sequences from the 20 real
trace runs, group bytes from the per-model inventories. No runtime
observation, no model execution, no optimizer construction.

Question (as authorized): does a candidate retention policy P' != P exist
with lower reload bytes, without increasing the resident budget, while
execution correctness is preserved?

Structural facts used (all previously measured/validated):
  - execution set = ALL at every generation (G1.9-C): every generation must
    find all optional groups resident, so the harness's load-all-missing
    step makes reload(t) = optionalTotal - retainedOptionalBytes(t-1).
  - therefore total reload = (n-1)*optionalTotal - sum_t retainedBytes(t):
    total reload is EXACTLY determined by the retention time-integral.
  - output correctness: guaranteed offline by the load-before-generation
    semantics given execution = ALL; empirically verified only for the
    three measured policies (output identity PASS on all 20 runs).

Candidate family (no optimality vocabulary — candidates, not optima):
  POLICY_STATE_RETENTION   current policy (retention = declared state groups)
  CANDIDATE_FILL_PEAK      state-independent: retain the largest optional
                           groups filling the current policy's peak budget
  CANDIDATE_ALL_RESIDENT   retain all optionals (ceiling reference)
  CANDIDATE_CORE_ONLY      retain nothing (floor reference = naive)
"""

import json
from pathlib import Path

RESULTS = Path(__file__).resolve().parents[1] / "results"
AUDIT = RESULTS / "residency-audit"
TRACE = RESULTS / "workload-trace"

SLUGS = {
    "qwen3-coder-30b": "qwen3-coder-real-{t}.json",
    "nail-qwen36-35b": "{slug}-real-{t}.json",
    "cyber-tiel-35b": "{slug}-real-{t}.json",
    "gemma4-12b-coder": "{slug}-real-{t}.json",
    "muse-glimmer-30b": "{slug}-real-{t}.json",
}
TRACES = ["T1", "T2", "T3", "T4"]
WORKLOAD_NAMES = {
    "T1": "T1_DOCUMENT_SESSION",
    "T2": "T2_COMPUTER_OPERATION",
    "T3": "T3_AGENTIC_MULTI_TURN",
    "T4": "T4_LONG_CONTEXT",
}
STATE_OPTIONAL_INDEX = {
    "STATE_A": [0], "STATE_B": [1], "STATE_C": [2],
    "STATE_AB": [0, 1], "STATE_BC": [1, 2], "STATE_ALL": [0, 1, 2],
}


def optional_groups(inventory):
    return sorted(
        (g for g in inventory["groups"] if not g.get("alwaysResident")),
        key=lambda g: g["layerRangeDescription"],
    )


def candidate_sets(name, states, core_ids, optional, peak_opt_bytes):
    """Return the retention-optional-set sequence for a candidate."""
    n = len(states)
    opt_ids = [g["id"] for g in optional]
    if name == "POLICY_STATE_RETENTION":
        return [
            {optional[i]["id"] for i in STATE_OPTIONAL_INDEX[s]} for s in states
        ]
    if name == "CANDIDATE_FILL_PEAK":
        chosen, filled = [], 0
        by_size = sorted(optional, key=lambda g: -g["byteCount"])
        for g in by_size:
            if filled + g["byteCount"] <= peak_opt_bytes + 1e-6:
                chosen.append(g["id"])
                filled += g["byteCount"]
        return [set(chosen)] * n
    if name == "CANDIDATE_ALL_RESIDENT":
        return [set(opt_ids)] * n
    if name == "CANDIDATE_CORE_ONLY":
        return [set()] * n
    raise ValueError(name)


def metrics(retained_sets, retained_bytes, core_bytes, optional_total):
    n = len(retained_bytes)
    reloads = [optional_total] + [
        optional_total - retained_bytes[t - 1] for t in range(1, n)
    ]
    peak = core_bytes + max(retained_bytes)
    mean = core_bytes + sum(retained_bytes) / n
    integral = sum(retained_bytes)
    # the frontier integral runs over the first n-1 steps only: the last
    # step's retention has no successor to pay into
    leading_integral = sum(retained_bytes[: n - 1])
    load_transitions = sum(1 for r in reloads if r > 0)
    evict_transitions = sum(
        1 for t in range(1, n) if retained_sets[t] != retained_sets[t - 1]
    )
    return {
        "reloadTotalBytes": sum(reloads),
        "peakResidentBytes": peak,
        "meanResidentBytes": mean,
        "retainedIntegralBytes": integral,
        "retainedLeadingIntegralBytes": leading_integral,
        "frontierIdentityHolds": (
            sum(reloads) == n * optional_total - leading_integral
        ),
        "loadTransitions": load_transitions,
        "evictTransitions": evict_transitions,
    }


def main():
    out = {
        "boundary": "OFFLINE_FEASIBILITY_AUDIT / CANDIDATE_POLICIES_NOT_OPTIMA / "
        "NOT_DEMAND / NOT_PREDICTION / NO_NEW_RUNTIME_OBSERVATION / "
        "PER_MODEL_PER_WORKLOAD_NO_POOLING",
        "protocol": "G1.9-E0.FEASIBILITY.V1",
        "models": {},
    }
    for slug, pattern in SLUGS.items():
        with open(AUDIT / f"{slug}-inventory.json") as handle:
            inventory = json.load(handle)
        core = [g for g in inventory["groups"] if g.get("alwaysResident")]
        optional = optional_groups(inventory)
        core_ids = {g["id"] for g in core}
        core_bytes = sum(g["byteCount"] for g in core)
        lookup = {g["id"]: g["byteCount"] for g in inventory["groups"]}
        optional_total = sum(g["byteCount"] for g in optional)
        opt_ids = {g["id"] for g in optional}
        model_entry = {}
        for trace in TRACES:
            with open(TRACE / pattern.format(slug=slug, t=trace)) as handle:
                report = json.load(handle)
            states = [
                t["executionState"] for t in report["stateDriven"]["transitions"]
            ]
            n = len(states)

            def retained_bytes_of(sets):
                return [bytes_of(s, lookup) for s in sets]

            def bytes_of(ids, lookup):
                return sum(lookup[i] for i in ids)

            # current policy peak budget (optional part)
            current_sets = candidate_sets(
                "POLICY_STATE_RETENTION", states, core_ids, optional, 0
            )
            current_bytes = retained_bytes_of(current_sets)
            peak_opt = max(current_bytes)

            candidates = {
                "POLICY_STATE_RETENTION": current_sets,
                "CANDIDATE_FILL_PEAK": candidate_sets(
                    "CANDIDATE_FILL_PEAK", states, core_ids, optional, peak_opt
                ),
                "CANDIDATE_ALL_RESIDENT": candidate_sets(
                    "CANDIDATE_ALL_RESIDENT", states, core_ids, optional, 0
                ),
                "CANDIDATE_CORE_ONLY": candidate_sets(
                    "CANDIDATE_CORE_ONLY", states, core_ids, optional, 0
                ),
            }

            table = {}
            for name, sets in candidates.items():
                rb = retained_bytes_of(sets)
                m = metrics(sets, rb, core_bytes, optional_total)
                table[name] = m

            current = table["POLICY_STATE_RETENTION"]

            # V1: equal-peak-budget improvement space
            equal_peak_candidates = {
                name: m
                for name, m in table.items()
                if m["peakResidentBytes"] <= current["peakResidentBytes"]
            }
            v1_improvers = {
                name: m
                for name, m in equal_peak_candidates.items()
                if m["reloadTotalBytes"] < current["reloadTotalBytes"]
            }

            # V2: equal-integral improvement space (structural: impossible)
            v2 = {
                "frontierRelation":
                    "reloadTotal = n*optionalTotal - retainedLeadingIntegral",
                "identityHoldsAllCandidates": all(
                    m["frontierIdentityHolds"] for m in table.values()
                ),
                "consequence":
                    "at equal retention time-integral (first n-1 steps) no "
                    "policy can have lower total reload; improvement "
                    "requires a higher resident-byte integral",
            }

            # V3: domination check against the current policy
            dominators = {
                name: m
                for name, m in table.items()
                if name != "POLICY_STATE_RETENTION"
                and m["reloadTotalBytes"] <= current["reloadTotalBytes"]
                and m["meanResidentBytes"] <= current["meanResidentBytes"]
                and m["peakResidentBytes"] <= current["peakResidentBytes"]
            }

            model_entry[WORKLOAD_NAMES[trace]] = {
                "states": states,
                "optionalTotalBytes": optional_total,
                "currentPeakOptionalBytes": peak_opt,
                "candidates": table,
                "V1_equalPeakBudget": {
                    "improversExist": bool(v1_improvers),
                    "improvers": {
                        name: {
                            "reloadReductionBytes":
                                current["reloadTotalBytes"] - m["reloadTotalBytes"],
                            "meanResidencyIncreaseBytes":
                                m["meanResidentBytes"] - current["meanResidentBytes"],
                        }
                        for name, m in v1_improvers.items()
                    },
                },
                "V2_equalIntegralBudget": v2,
                "V3_dominance": {
                    "dominatingCandidatesExist": bool(dominators),
                    "consequence":
                        "the current policy is not dominated on "
                        "(reload, mean residency, peak); any reload gain "
                        "pays with higher mean residency",
                },
            }
        out["models"][slug] = model_entry

    # aggregate verdict
    v1_any = any(
        w["V1_equalPeakBudget"]["improversExist"]
        for m in out["models"].values()
        for w in m.values()
    )
    v2_all = all(
        w["V2_equalIntegralBudget"]["identityHoldsAllCandidates"]
        for m in out["models"].values()
        for w in m.values()
    )
    v3_none = not any(
        w["V3_dominance"]["dominatingCandidatesExist"]
        for m in out["models"].values()
        for w in m.values()
    )
    out["verdict"] = {
        "pairsChecked": sum(
            len(m) for m in out["models"].values()
        ),
        "V1_equalPeak_improversExist": v1_any,
        "V2_equalIntegral_frontierExact": v2_all,
        "V3_noDominationOfCurrentPolicy": v3_none,
        "result": (
            "FEASIBLE_TRADEOFF_SPACE_ONLY_NO_FREE_IMPROVEMENT"
            if v1_any and v2_all and v3_none
            else "MIXED_SEE_PER_PAIR_RESULTS"
        ),
    }

    out_path = AUDIT / "retention-feasibility.json"
    with open(out_path, "w") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
    print(f"wrote {out_path}")

    for slug, model in out["models"].items():
        print(f"\n== {slug}")
        for wname, w in model.items():
            cur = w["candidates"]["POLICY_STATE_RETENTION"]
            fill = w["candidates"]["CANDIDATE_FILL_PEAK"]
            print(
                f"  {wname:<24} current: reload={cur['reloadTotalBytes']/2**30:6.2f}GiB "
                f"mean={cur['meanResidentBytes']/2**30:5.2f} peak={cur['peakResidentBytes']/2**30:5.2f} | "
                f"fill@peak: reload={fill['reloadTotalBytes']/2**30:6.2f} "
                f"mean={fill['meanResidentBytes']/2**30:5.2f} peak={fill['peakResidentBytes']/2**30:5.2f} | "
                f"V1={w['V1_equalPeakBudget']['improversExist']} V3dom={w['V3_dominance']['dominatingCandidatesExist']}"
            )
    print("\nverdict:", json.dumps(out["verdict"], indent=2))


if __name__ == "__main__":
    main()
