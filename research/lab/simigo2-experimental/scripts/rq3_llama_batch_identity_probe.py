#!/usr/bin/env python3
"""No-cancel repeatability probe for llama-server concurrent greedy identity.

Each cycle fills four slots with one full-completion long request and three
greedy controls. There is no cancellation. The probe asks whether the same
same-load control batch is token-stable across repeated scheduling.
"""

from __future__ import annotations

import argparse
import json
import threading
import time
import urllib.request
from pathlib import Path
from typing import Any

from rq3_llama_cancellation import get_json, summarize
from rq3_llama_concurrency_curve import run_control_batch, run_long_completion
from rq3_llama_hotpath_ab import post_json


def join_threads(threads: list[threading.Thread], label: str) -> None:
    for thread in threads:
        thread.join(timeout=120)
    if any(thread.is_alive() for thread in threads):
        raise RuntimeError(f"{label} timed out")


def identity(response: dict[str, Any], reference: dict[str, Any]) -> bool:
    return (
        response.get("content", "") == reference.get("content", "")
        and response.get("tokens", []) == reference.get("tokens", [])
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles", type=int, default=16)
    parser.add_argument("--expected-slots", type=int, default=4)
    parser.add_argument("--long-streams", type=int, default=1)
    parser.add_argument("--prediction-tokens", type=int, default=256)
    parser.add_argument("--control-tokens", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--prompt",
        default="Count from 1 to 500. Return only numbers separated by spaces.",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    control_count = args.expected_slots - args.long_streams
    if control_count < 2:
        raise RuntimeError("identity probe needs at least two controls")

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")
    initial_slots = get_json(args.host, args.port, "/slots")
    if not isinstance(initial_slots, list) or len(initial_slots) != args.expected_slots:
        raise RuntimeError(f"expected {args.expected_slots} slots, got {initial_slots!r}")

    control_request = {
        "prompt": [5423, 6681, 799, 3299, 25, 29018],
        "n_predict": args.control_tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": False,
        "return_tokens": True,
    }
    single_reference, _ = post_json(f"{base_url}/completion", control_request)

    cycles: list[dict[str, Any]] = []
    for cycle in range(args.cycles):
        slots = get_json(args.host, args.port, "/slots")
        assert isinstance(slots, list) and len(slots) == args.expected_slots
        assert not any(slot["is_processing"] for slot in slots), slots

        longs: list[dict[str, Any]] = []
        long_threads: list[threading.Thread] = []
        started_ns = time.perf_counter_ns()
        for _ in range(args.long_streams):
            sink: dict[str, Any] = {}
            thread = threading.Thread(
                target=run_long_completion,
                args=(
                    args.host,
                    args.port,
                    args.prompt,
                    args.prediction_tokens,
                    args.seed,
                    sink,
                ),
            )
            thread.start()
            long_threads.append(thread)
            longs.append(sink)

        threads, controls = run_control_batch(
            args.host,
            args.port,
            control_request,
            control_count,
        )
        join_threads(threads, "controls")
        join_threads(long_threads, "longs")
        if any("error" in sink for sink in longs):
            raise RuntimeError(f"cycle {cycle}: long failed: {longs!r}")
        if any(sink.get("status") != 200 for sink in longs):
            raise RuntimeError(f"cycle {cycle}: long bad status: {longs!r}")

        responses = [control["response"] for control in controls]
        contents = [response.get("content", "") for response in responses]
        tokens = [response.get("tokens", []) for response in responses]
        within_cycle = [
            identity(response, responses[0]) for response in responses
        ]
        across_cycles = [
            identity(response, cycles[0]["responses"][index])
            for index, response in enumerate(responses)
        ] if cycles else [True] * len(responses)
        single_load = [
            identity(response, single_reference) for response in responses
        ]
        cycles.append(
            {
                "cycle": cycle,
                "longStreams": args.long_streams,
                "controls": control_count,
                "controlClientMeanMs": (
                    sum(control["clientNs"] for control in controls)
                    / len(controls)
                    / 1e6
                ),
                "controlClientMaxMs": max(
                    control["clientNs"] / 1e6 for control in controls
                ),
                "longClientMeanMs": (
                    sum(sink["clientNs"] for sink in longs) / len(longs) / 1e6
                ),
                "withinCycleAllIdentical": all(within_cycle),
                "acrossCyclesAllIdentical": all(across_cycles),
                "matchedSingleLoadReference": all(single_load),
                "withinCycleIdentity": within_cycle,
                "acrossCycleIdentity": across_cycles,
                "singleLoadIdentity": single_load,
                "responses": responses,
                "contents": contents,
                "tokens": tokens,
            }
        )

    across_mismatch_cycles = sum(
        not cycle["acrossCyclesAllIdentical"] for cycle in cycles
    )
    within_mismatch_cycles = sum(
        not cycle["withinCycleAllIdentical"] for cycle in cycles
    )
    single_load_match_cycles = sum(
        cycle["matchedSingleLoadReference"] for cycle in cycles
    )
    all_completed = len(cycles) == args.cycles
    output_groups: dict[str, int] = {}
    for cycle in cycles:
        for content in cycle["contents"]:
            output_groups[content] = output_groups.get(content, 0) + 1
    report = {
        "status": "COMPLETE" if all_completed else "FAIL",
        "probeCompleted": all_completed,
        "protocolVersion": "RQ3.LLAMA.BATCH.IDENTITY.PROBE.V1",
        "boundary": (
            "NO_CANCEL_SAME_LOAD_REPEAT / llama-server batch scheduling only / "
            "NO_EXECUTION_STATE_OBJECT / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "expectedSlots": args.expected_slots,
        "longStreams": args.long_streams,
        "controls": control_count,
        "cyclesRequested": args.cycles,
        "singleLoadReference": {
            "content": single_reference.get("content", ""),
            "tokens": single_reference.get("tokens", []),
        },
        "identityFinding": {
            "acrossCycleMismatchCycles": across_mismatch_cycles,
            "withinCycleMismatchCycles": within_mismatch_cycles,
            "cyclesMatchedSingleLoadReference": single_load_match_cycles,
            "cyclesCompared": len(cycles),
            "outputGroups": output_groups,
            "boundary": (
                "Token identity is recorded as a scheduling observation; content "
                "differences are not interpreted as Execution State failure or "
                "cancellation causality."
            ),
        },
        "results": {
            "batchesCompleted": len(cycles),
            "withinCycleStableBatches": len(cycles) - within_mismatch_cycles,
            "acrossCycleStableBatches": len(cycles) - across_mismatch_cycles,
            "cyclesMatchedSingleLoadReference": single_load_match_cycles,
            "controlClientMean": summarize(
                [cycle["controlClientMeanMs"] for cycle in cycles]
            ),
            "controlClientMax": summarize(
                [cycle["controlClientMaxMs"] for cycle in cycles]
            ),
            "longClientMean": summarize(
                [cycle["longClientMeanMs"] for cycle in cycles]
            ),
        },
        "cycles": cycles,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "status": report["status"],
                "batchesCompleted": report["results"]["batchesCompleted"],
                "identityFinding": report["identityFinding"],
                "results": report["results"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
