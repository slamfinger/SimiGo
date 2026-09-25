#!/usr/bin/env python3
"""G1.9-D PolicyResidency Retention Analysis (D1-D4).

Analyzes the RETENTION STRUCTURE of the existing residency policy over the
existing 20 real trace artifacts (5 models x 4 workloads) plus the
per-model inventories. No new runtime observation, no pooling, no demand
interpretation.

Labels (frozen by the G1.9-D authorization):
  R_t^policy      = policy resident set after transition t (core + retention
                    optionals) — PolicyResidency bookkeeping, byte-validated
                    by the observability audit
  allowed claim   : "PolicyResidency retention structure (byte-validated)"
  forbidden claim : natural residency demand / observed residency locality

Quantities:
  D1 retention recurrence   |Q_t|/|R_{t+1}| with Q_t = R_t ∩ R_{t+1},
                            group and byte-weighted, optional-only variants
  D2 transition retention   R_t -> R_{t+1} kept/added/removed structure
  D3 retention stability    lag-1/2/3 overlap of R_t (group and byte)
  D4 structure <-> reload economics
                            exact identity: savings(naive - policy) equals
                            the retained-optional-bytes integral minus the
                            cold-start load, verified against measured
                            cumulative reload bytes

Pre-registered verdict rule:
  STRUCTURE characterization requires (i) D4 identity to hold within
  measurement tolerance (<0.1%) on every (model, workload) pair, and
  (ii) D1-D3 patterns to be deterministic given (policy, state sequence).
  Otherwise: POLICY_RETENTION_STRUCTURE_INCONCLUSIVE -> STOP.
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


def policy_sets(inventory):
    core = sorted(
        (g for g in inventory["groups"] if g.get("alwaysResident")),
        key=lambda g: g["id"],
    )
    optional = sorted(
        (g for g in inventory["groups"] if not g.get("alwaysResident")),
        key=lambda g: g["layerRangeDescription"],
    )
    return core, optional


def resident_state_set(core, optional, state):
    ids = [g["id"] for g in core] + [optional[i]["id"] for i in STATE_OPTIONAL_INDEX[state]]
    return set(ids)


def bytes_of(ids, lookup):
    return sum(lookup[i] for i in ids)


def analyse_run(states, lookup, core, optional):
    """R_t bookkeeping reconstruction + D1-D4 for one (model, workload)."""
    optional_total = sum(g["byteCount"] for g in optional)
    n = len(states)
    R = [resident_state_set(core, optional, s) for s in states]
    R_opt = [{i for i in r if i not in {g["id"] for g in core}} for r in R]
    core_bytes = bytes_of({g["id"] for g in core}, lookup)

    # D1 recurrence over consecutive resident sets
    d1 = []
    for t in range(n - 1):
        q = R[t] & R[t + 1]
        q_opt = R_opt[t] & R_opt[t + 1]
        d1.append(
            {
                "transition": f"{t}->{t+1}",
                "groupRatio": len(q) / len(R[t + 1]),
                "byteRatio": bytes_of(q, lookup) / bytes_of(R[t + 1], lookup),
                "optionalGroupRatio": (len(q_opt) / len(R_opt[t + 1])) if R_opt[t + 1] else 1.0,
                "optionalByteRatio": (
                    bytes_of(q_opt, lookup) / bytes_of(R_opt[t + 1], lookup)
                ) if R_opt[t + 1] else 1.0,
            }
        )

    # D2 transition structure (optional part) + measured reload check
    d2 = []
    for t in range(n - 1):
        kept = R_opt[t] & R_opt[t + 1]
        added = R_opt[t + 1] - R_opt[t]
        removed = R_opt[t] - R_opt[t + 1]
        d2.append(
            {
                "transition": f"{t}->{t+1}",
                "states": f"{states[t]}->{states[t+1]}",
                "kept": sorted(kept),
                "added": sorted(added),
                "removed": sorted(removed),
                "predictedReloadBytesAtNextLoad": optional_total
                - bytes_of(R_opt[t], lookup),
            }
        )

    # D3 lag-k overlaps
    d3 = {}
    for k in (1, 2, 3):
        if n <= k:
            d3[f"lag{k}"] = None
            continue
        ratios = [
            bytes_of(R[t] & R[t - k], lookup) / bytes_of(R[t], lookup)
            for t in range(k, n)
        ]
        d3[f"lag{k}"] = {
            "meanByteOverlapRatio": sum(ratios) / len(ratios),
            "minByteOverlapRatio": min(ratios),
            "maxByteOverlapRatio": max(ratios),
        }

    # D4 economics identity:
    #   predicted policy reload bytes: t=0 -> all optionals (cold start);
    #   t>0 -> optionals not retained from previous step
    predicted_policy_reload = [optional_total] + [
        optional_total - bytes_of(R_opt[t], lookup) for t in range(n - 1)
    ]
    predicted_naive_reload = [0] + [optional_total] * (n - 1)
    predicted_savings = sum(predicted_naive_reload) - sum(predicted_policy_reload)
    # equivalently: retained-bytes integral minus one cold-start load
    integral = sum(bytes_of(R_opt[t], lookup) for t in range(n - 1))
    identity_alternative = integral - optional_total
    d4 = {
        "predictedSavingsBytes": predicted_savings,
        "identityAlternativeBytes": identity_alternative,
        "savingsAsFractionOfNaive": predicted_savings / sum(predicted_naive_reload),
        "retainedBytesIntegral": integral,
        "perTransitionRetainedOptionalBytes": [
            bytes_of(R_opt[t], lookup) for t in range(n - 1)
        ],
        "fullRetentionSteps": sum(
            1 for t in range(n) if R_opt[t] == {g["id"] for g in optional}
        ),
        "zeroRetentionSteps": sum(1 for t in range(n) if not R_opt[t]),
    }
    return {
        "states": states,
        "coreBytes": core_bytes,
        "optionalTotalBytes": optional_total,
        "D1_retentionRecurrence": d1,
        "D2_transitionRetention": d2,
        "D3_retentionStability": d3,
        "D4_reloadEconomics": d4,
    }


def main():
    out = {
        "boundary": "POLICYRESIDENCY_RETENTION_STRUCTURE / BYTE_VALIDATED_BOOKKEEPING / "
        "NOT_DEMAND / NOT_PREDICTION / NOT_RESIDENCY_LOCALITY / PER_MODEL_PER_WORKLOAD_NO_POOLING / "
        "C_MODEL_OFFSET_SEALED_AS_ACCOUNTING_ITEM",
        "protocol": "G1.9-D.RETENTION.V1",
        "models": {},
    }
    for slug, pattern in SLUGS.items():
        with open(AUDIT / f"{slug}-inventory.json") as handle:
            inventory = json.load(handle)
        core, optional = policy_sets(inventory)
        lookup = {g["id"]: g["byteCount"] for g in inventory["groups"]}
        model_entry = {}
        for trace in TRACES:
            path = TRACE / pattern.format(slug=slug, t=trace)
            with open(path) as handle:
                report = json.load(handle)
            states = [t["executionState"] for t in report["stateDriven"]["transitions"]]
            entry = analyse_run(states, lookup, core, optional)
            # attach measured economics for the D4 correspondence
            entry["D4_reloadEconomics"]["measuredNaiveCumulativeReloadBytes"] = report[
                "naiveOnDemand"
            ]["cumulativeReloadedBytes"]
            entry["D4_reloadEconomics"]["measuredPolicyCumulativeReloadBytes"] = report[
                "stateDriven"
            ]["cumulativeReloadedBytes"]
            entry["D4_reloadEconomics"]["measuredSavingsBytes"] = report[
                "naiveOnDemand"
            ]["cumulativeReloadedBytes"] - report["stateDriven"]["cumulativeReloadedBytes"]
            entry["D4_reloadEconomics"]["identityHolds"] = (
                abs(
                    entry["D4_reloadEconomics"]["predictedSavingsBytes"]
                    - entry["D4_reloadEconomics"]["measuredSavingsBytes"]
                )
                <= 0.001
                * max(
                    entry["D4_reloadEconomics"]["measuredSavingsBytes"], 1
                )
            )
            entry["D4_reloadEconomics"]["measuredReloadSecondsPolicy"] = report[
                "stateDriven"
            ]["totalReloadMilliseconds"] / 1000
            entry["D4_reloadEconomics"]["measuredReloadSecondsNaive"] = report[
                "naiveOnDemand"
            ]["totalReloadMilliseconds"] / 1000
            model_entry[WORKLOAD_NAMES[trace]] = entry
        out["models"][slug] = model_entry

    # pre-registered verdict
    identities = [
        w["D4_reloadEconomics"]["identityHolds"]
        for m in out["models"].values()
        for w in m.values()
    ]
    out["verdict"] = {
        "d4IdentityHoldsAllPairs": all(identities),
        "pairsChecked": len(identities),
        "result": (
            "POLICY_RETENTION_STRUCTURE_EMPIRICALLY_CHARACTERIZED"
            if all(identities)
            else "POLICY_RETENTION_STRUCTURE_INCONCLUSIVE"
        ),
    }

    out_path = AUDIT / "policy-retention-analysis.json"
    with open(out_path, "w") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
    print(f"wrote {out_path}")

    for slug, model in out["models"].items():
        print(f"\n== {slug}")
        for wname, w in model.items():
            d1 = w["D1_retentionRecurrence"]
            d4 = w["D4_reloadEconomics"]
            print(
                f"  {wname:<24} optByteKeepRatio={sum(x['optionalByteRatio'] for x in d1)/len(d1):.3f} "
                f"lag1={w['D3_retentionStability']['lag1']['meanByteOverlapRatio']:.3f} "
                f"savings={d4['measuredSavingsBytes']/2**30:6.2f}GiB "
                f"({d4['savingsAsFractionOfNaive']:.3f} of naive) identity={d4['identityHolds']} "
                f"fullSteps={d4['fullRetentionSteps']}/{len(w['states'])}"
            )


if __name__ == "__main__":
    main()
