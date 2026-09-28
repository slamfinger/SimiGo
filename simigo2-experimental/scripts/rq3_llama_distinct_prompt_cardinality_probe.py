#!/usr/bin/env python3
"""No-cancel distinct-prompt cardinality probe for llama-server.

Each control uses a different, equal-token-length prompt. Single-load
references are established before concurrency. This tests whether prior
greedy identity instability requires duplicate prompts.
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
from rq3_llama_hotpath_ab import post_json


def identity(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return (
        left.get("content", "") == right.get("content", "")
        and left.get("tokens", []) == right.get("tokens", [])
    )


def run_payload(
    host: str,
    port: int,
    payload: dict[str, Any],
    sink: dict[str, Any],
) -> None:
    started_ns = time.perf_counter_ns()
    try:
        response, client_ns = post_json(
            f"http://{host}:{port}/completion", payload
        )
        sink.update(
            response=response,
            clientNs=client_ns,
            finishedNs=time.perf_counter_ns(),
        )
    except BaseException as error:
        sink["error"] = error


def wait_idle(host: str, port: int) -> None:
    while True:
        slots = get_json(host, port, "/slots")
        assert isinstance(slots, list)
        if not any(slot["is_processing"] for slot in slots):
            return
        time.sleep(0.002)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles-per-cardinality", type=int, default=8)
    parser.add_argument("--max-cardinality", type=int, default=4)
    parser.add_argument("--expected-slots", type=int, default=None)
    parser.add_argument("--control-tokens", type=int, default=8)
    parser.add_argument("--reference-repeats", type=int, default=3)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    prompts = [
        "Return exactly one word: ping",
        "Return exactly one word: alpha",
        "Return exactly one word: beta",
        "Return exactly one word: gamma",
    ]
    if args.max_cardinality > len(prompts):
        raise RuntimeError("not enough distinct prompts")

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")
    if args.expected_slots is None:
        args.expected_slots = args.max_cardinality
    slots = get_json(args.host, args.port, "/slots")
    if not isinstance(slots, list) or len(slots) != args.expected_slots:
        raise RuntimeError(
            f"expected {args.expected_slots} slots, got {slots!r}"
        )

    prompt_tokens: list[list[int]] = []
    for prompt in prompts[: args.max_cardinality]:
        tokenized, _ = post_json(f"{base_url}/tokenize", {"content": prompt})
        prompt_tokens.append(tokenized["tokens"])
    reference_lengths = {len(tokens) for tokens in prompt_tokens}
    if len(reference_lengths) != 1:
        raise RuntimeError(f"prompt token lengths differ: {reference_lengths}")

    references: list[list[dict[str, Any]]] = []
    reference_stable: list[bool] = []
    for tokens in prompt_tokens:
        repeats: list[dict[str, Any]] = []
        for _ in range(args.reference_repeats):
            response, _ = post_json(
                f"{base_url}/completion",
                {
                    "prompt": tokens,
                    "n_predict": args.control_tokens,
                    "temperature": 0.0,
                    "seed": args.seed,
                    "cache_prompt": False,
                    "return_tokens": True,
                },
            )
            repeats.append(response)
        references.append(repeats)
        reference_stable.append(
            all(identity(response, repeats[0]) for response in repeats)
        )

    cardinality_reports: list[dict[str, Any]] = []
    for cardinality in range(1, args.max_cardinality + 1):
        cycles: list[dict[str, Any]] = []
        for cycle in range(args.cycles_per_cardinality):
            wait_idle(args.host, args.port)
            sinks: list[dict[str, Any]] = []
            threads: list[threading.Thread] = []
            for prompt_index in range(cardinality):
                sink: dict[str, Any] = {}
                thread = threading.Thread(
                    target=run_payload,
                    args=(
                        args.host,
                        args.port,
                        {
                            "prompt": prompt_tokens[prompt_index],
                            "n_predict": args.control_tokens,
                            "temperature": 0.0,
                            "seed": args.seed,
                            "cache_prompt": False,
                            "return_tokens": True,
                        },
                        sink,
                    ),
                )
                thread.start()
                threads.append(thread)
                sinks.append(sink)
            for thread in threads:
                thread.join(timeout=30)
            if any(thread.is_alive() for thread in threads):
                raise RuntimeError(f"cycle {cycle}: controls timed out")
            if any("error" in sink for sink in sinks):
                raise RuntimeError(f"cycle {cycle}: control failed: {sinks!r}")

            responses = [sink["response"] for sink in sinks]
            compact = [
                {
                    "promptIndex": index,
                    "idSlot": response.get("id_slot"),
                    "content": response.get("content", ""),
                    "tokens": response.get("tokens", []),
                }
                for index, response in enumerate(responses)
            ]
            matched_reference = [
                identity(response, references[index][0])
                for index, response in enumerate(responses)
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
                        sum(sink["clientNs"] for sink in sinks)
                        / len(sinks)
                        / 1e6
                    ),
                    "clientMaxMs": max(
                        sink["clientNs"] / 1e6 for sink in sinks
                    ),
                    "matchedSingleLoadReference": matched_reference,
                    "acrossCycleIdentity": across_cycles,
                    "allMatchedSingleLoadReference": all(matched_reference),
                    "acrossCyclesAllIdentical": all(across_cycles),
                    "responses": compact,
                }
            )

        reference_match_cycles = sum(
            cycle["allMatchedSingleLoadReference"] for cycle in cycles
        )
        across_stable_cycles = sum(
            cycle["acrossCyclesAllIdentical"] for cycle in cycles
        )
        mismatches_by_prompt = [
            sum(not cycle["matchedSingleLoadReference"][index] for cycle in cycles)
            for index in range(cardinality)
        ]
        output_groups_by_prompt: list[dict[str, int]] = []
        for prompt_index in range(cardinality):
            groups: dict[str, int] = {}
            for cycle in cycles:
                content = cycle["responses"][prompt_index]["content"]
                groups[content] = groups.get(content, 0) + 1
            output_groups_by_prompt.append(groups)
        cardinality_reports.append(
            {
                "cardinality": cardinality,
                "cycleCount": len(cycles),
                "requests": len(cycles) * cardinality,
                "cyclesAllMatchedSingleLoadReference": reference_match_cycles,
                "acrossCycleStableCycles": across_stable_cycles,
                "mismatchesByPrompt": mismatches_by_prompt,
                "outputGroupsByPrompt": output_groups_by_prompt,
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
        if report["cyclesAllMatchedSingleLoadReference"]
        != report["cycleCount"]
        or report["acrossCycleStableCycles"] != report["cycleCount"]
    ]
    report = {
        "status": "COMPLETE",
        "probeCompleted": True,
        "protocolVersion": "RQ3.LLAMA.DISTINCT.PROMPT.CARDINALITY.PROBE.V1",
        "boundary": (
            "NO_CANCEL_NO_LONG_REQUEST / DISTINCT_EQUAL_LENGTH_PROMPTS / "
            "NO_EXECUTION_STATE_OBJECT / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "maxCardinality": args.max_cardinality,
        "expectedSlots": args.expected_slots,
        "observedSlots": len(slots),
        "cyclesPerCardinality": args.cycles_per_cardinality,
        "referenceRepeats": args.reference_repeats,
        "prompts": prompts[: args.max_cardinality],
        "promptTokenLengths": [len(tokens) for tokens in prompt_tokens],
        "singleLoadReferenceStable": reference_stable,
        "finding": {
            "batchIdentityStableAllCardinalities": not unstable_cardinalities,
            "unstableCardinalities": unstable_cardinalities,
            "boundary": (
                "Distinct prompts remove duplicate-prompt confounding; this does "
                "not identify llama.cpp internals or establish correctness."
            ),
        },
        "results": {
            "cardinalities": cardinality_reports,
            "summary": [
                {
                    "cardinality": report["cardinality"],
                    "batches": report["cycleCount"],
                    "requests": report["requests"],
                    "cyclesAllMatchedSingleLoadReference": report[
                        "cyclesAllMatchedSingleLoadReference"
                    ],
                    "acrossCycleStableCycles": report[
                        "acrossCycleStableCycles"
                    ],
                    "mismatchesByPrompt": report["mismatchesByPrompt"],
                    "outputGroupsByPrompt": report["outputGroupsByPrompt"],
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
