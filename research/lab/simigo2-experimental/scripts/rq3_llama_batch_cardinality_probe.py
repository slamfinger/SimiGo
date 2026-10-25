#!/usr/bin/env python3
"""No-cancel batch-cardinality probe for llama-server greedy identity.

For each cardinality 1..N, repeatedly launch that many identical greedy
controls. There is no long request and no cancellation. This isolates whether
token instability is associated with concurrent batch size alone.
"""

from __future__ import annotations

import argparse
import json
import urllib.request
from pathlib import Path
from typing import Any

from rq3_llama_cancellation import get_json, summarize
from rq3_llama_concurrency_curve import join_controls, run_control_batch
from rq3_llama_hotpath_ab import post_json


def identity(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return (
        left.get("content", "") == right.get("content", "")
        and left.get("tokens", []) == right.get("tokens", [])
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles-per-cardinality", type=int, default=8)
    parser.add_argument("--max-cardinality", type=int, default=4)
    parser.add_argument("--control-tokens", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if args.max_cardinality < 1 or args.cycles_per_cardinality < 1:
        raise RuntimeError("cardinality and cycles must be positive")
    cardinalities = list(range(1, args.max_cardinality + 1))

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")
    slots = get_json(args.host, args.port, "/slots")
    if not isinstance(slots, list) or len(slots) < args.max_cardinality:
        raise RuntimeError(f"need {args.max_cardinality} slots, got {slots!r}")

    control_request = {
        "prompt": [5423, 6681, 799, 3299, 25, 29018],
        "n_predict": args.control_tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": False,
        "return_tokens": True,
    }
    single_reference, _ = post_json(f"{base_url}/completion", control_request)

    cardinality_reports: list[dict[str, Any]] = []
    for cardinality in cardinalities:
        cycles: list[dict[str, Any]] = []
        for cycle in range(args.cycles_per_cardinality):
            slots = get_json(args.host, args.port, "/slots")
            assert isinstance(slots, list)
            assert not any(slot["is_processing"] for slot in slots), slots

            threads, controls = run_control_batch(
                args.host,
                args.port,
                control_request,
                cardinality,
            )
            join_controls(threads, controls)
            raw_responses = [control["response"] for control in controls]
            responses = [
                {
                    "index": index,
                    "idSlot": response.get("id_slot"),
                    "content": response.get("content", ""),
                    "tokens": response.get("tokens", []),
                }
                for index, response in enumerate(raw_responses)
            ]
            contents = [response.get("content", "") for response in responses]
            tokens = [response.get("tokens", []) for response in responses]
            within_cycle = [
                identity(response, responses[0]) for response in responses
            ]
            matched_single = [
                identity(response, single_reference) for response in responses
            ]
            across_cycles = (
                [
                    identity(response, cycles[0]["responses"][index])
                    for index, response in enumerate(responses)
                ]
                if cycles
                else [True] * len(responses)
            )
            cycles.append(
                {
                    "cycle": cycle,
                    "cardinality": cardinality,
                    "clientMeanMs": (
                        sum(control["clientNs"] for control in controls)
                        / len(controls)
                        / 1e6
                    ),
                    "clientMaxMs": max(
                        control["clientNs"] / 1e6 for control in controls
                    ),
                    "withinCycleIdentity": within_cycle,
                    "acrossCycleIdentity": across_cycles,
                    "singleLoadIdentity": matched_single,
                    "withinCycleAllIdentical": all(within_cycle),
                    "acrossCyclesAllIdentical": all(across_cycles),
                    "allMatchedSingleLoadReference": all(matched_single),
                    "responses": responses,
                    "contents": contents,
                    "tokens": tokens,
                }
            )

        within_stable = sum(cycle["withinCycleAllIdentical"] for cycle in cycles)
        across_stable = sum(cycle["acrossCyclesAllIdentical"] for cycle in cycles)
        single_stable = sum(
            cycle["allMatchedSingleLoadReference"] for cycle in cycles
        )
        output_groups: dict[str, int] = {}
        for cycle in cycles:
            for content in cycle["contents"]:
                output_groups[content] = output_groups.get(content, 0) + 1
        cardinality_reports.append(
            {
                "cardinality": cardinality,
                "cycleCount": len(cycles),
                "requests": len(cycles) * cardinality,
                "withinCycleStableBatches": within_stable,
                "withinCycleUnstableBatches": len(cycles) - within_stable,
                "acrossCycleStableBatches": across_stable,
                "acrossCycleUnstableBatches": len(cycles) - across_stable,
                "batchesAllMatchedSingleLoadReference": single_stable,
                "outputGroups": output_groups,
                "controlClientMean": summarize(
                    [cycle["clientMeanMs"] for cycle in cycles]
                ),
                "controlClientMax": summarize(
                    [cycle["clientMaxMs"] for cycle in cycles]
                ),
                "cycles": cycles,
            }
        )

    unstable_cardinalities = [
        report["cardinality"]
        for report in cardinality_reports
        if report["withinCycleUnstableBatches"]
        or report["acrossCycleUnstableBatches"]
    ]
    stable_all = not unstable_cardinalities
    report = {
        "status": "COMPLETE",
        "probeCompleted": True,
        "protocolVersion": "RQ3.LLAMA.BATCH.CARDINALITY.PROBE.V1",
        "boundary": (
            "NO_CANCEL_NO_LONG_REQUEST / IDENTICAL_GREEDY_CONTROL_CARDINALITY / "
            "NO_EXECUTION_STATE_OBJECT / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "maxCardinality": args.max_cardinality,
        "cyclesPerCardinality": args.cycles_per_cardinality,
        "controlRequest": {
            "endpoint": "/completion",
            "promptTokens": control_request["prompt"],
            "predictionTokens": args.control_tokens,
            "seed": args.seed,
        },
        "singleLoadReference": {
            "content": single_reference.get("content", ""),
            "tokens": single_reference.get("tokens", []),
        },
        "finding": {
            "batchIdentityStableAllCardinalities": stable_all,
            "unstableCardinalities": unstable_cardinalities,
            "boundary": (
                "This probe only localizes instability to a control cardinality; "
                "it does not identify llama.cpp internals or establish correctness."
            ),
        },
        "results": {
            "cardinalities": cardinality_reports,
            "summary": [
                {
                    "cardinality": report["cardinality"],
                    "batches": report["cycleCount"],
                    "requests": report["requests"],
                    "withinCycleStableBatches": report[
                        "withinCycleStableBatches"
                    ],
                    "withinCycleUnstableBatches": report[
                        "withinCycleUnstableBatches"
                    ],
                    "acrossCycleStableBatches": report[
                        "acrossCycleStableBatches"
                    ],
                    "acrossCycleUnstableBatches": report[
                        "acrossCycleUnstableBatches"
                    ],
                    "outputGroups": report["outputGroups"],
                }
                for report in cardinality_reports
            ],
        },
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "status": report["status"],
                "finding": report["finding"],
                "results": report["results"]["summary"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
