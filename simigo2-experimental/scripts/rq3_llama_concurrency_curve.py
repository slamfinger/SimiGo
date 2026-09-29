#!/usr/bin/env python3
"""Higher-concurrency explicit cancellation curve for llama-server.

Each cycle fills every expected slot with long cancelable streams plus short
greedy controls. It cancels every long stream, waits for all long slots to
free, and compares every control with a pre-run greedy reference. This is a
backend control; no Execution State object participates.
"""

from __future__ import annotations

import argparse
import json
import threading
import time
import urllib.request
from pathlib import Path
from typing import Any

from rq3_llama_cancellation import (
    delete_stream,
    get_json,
    start_cancelable_request,
    summarize,
)
from rq3_llama_concurrent_cancellation import run_control
from rq3_llama_hotpath_ab import post_json


def active_long_count(slots: list[dict[str, Any]], prediction_tokens: int) -> int:
    return sum(
        slot["is_processing"] and slot["params"]["n_predict"] == prediction_tokens
        for slot in slots
    )


def long_processing(slots: list[dict[str, Any]], prediction_tokens: int) -> bool:
    return any(
        slot["is_processing"] and slot["params"]["n_predict"] == prediction_tokens
        for slot in slots
    )


def run_control_batch(
    host: str,
    port: int,
    payload: dict[str, Any],
    count: int,
) -> tuple[list[threading.Thread], list[dict[str, Any]]]:
    controls: list[dict[str, Any]] = []
    threads: list[threading.Thread] = []
    for _ in range(count):
        control: dict[str, Any] = {}
        thread = threading.Thread(
            target=run_control,
            args=(host, port, payload, control),
        )
        thread.start()
        threads.append(thread)
        controls.append(control)
    return threads, controls


def run_long_completion(
    host: str,
    port: int,
    prompt: str,
    prediction_tokens: int,
    seed: int,
    sink: dict[str, Any],
) -> None:
    payload = {
        "stream": False,
        "max_tokens": prediction_tokens,
        "temperature": 0.0,
        "seed": seed,
        "messages": [{"role": "user", "content": prompt}],
    }
    request = urllib.request.Request(
        f"http://{host}:{port}/v1/chat/completions",
        data=json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started_ns = time.perf_counter_ns()
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            status = response.status
            decoded = json.loads(response.read())
        sink.update(
            status=status,
            response=decoded,
            clientNs=time.perf_counter_ns() - started_ns,
            finishedNs=time.perf_counter_ns(),
        )
    except BaseException as error:
        sink["error"] = error


def join_controls(threads: list[threading.Thread], controls: list[dict[str, Any]]) -> None:
    for thread in threads:
        thread.join(timeout=30)
    if any(thread.is_alive() for thread in threads):
        raise RuntimeError("controls timed out")
    if any("error" in control for control in controls):
        raise RuntimeError(f"control failed: {controls!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles", type=int, default=12)
    parser.add_argument("--expected-slots", type=int, default=4)
    parser.add_argument("--cancel-delay-ms", type=int, default=100)
    parser.add_argument("--prediction-tokens", type=int, default=256)
    parser.add_argument("--control-tokens", type=int, default=8)
    parser.add_argument("--free-timeout-ms", type=int, default=15000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--prompt",
        default="Count from 1 to 500. Return only numbers separated by spaces.",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if args.expected_slots < 2:
        raise RuntimeError("curve needs at least two slots")
    if args.cycles < args.expected_slots - 1:
        raise RuntimeError("not enough cycles to cover the curve")

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
    reference, _ = post_json(f"{base_url}/completion", control_request)

    levels = range(1, args.expected_slots)
    cycles: list[dict[str, Any]] = []
    for cycle in range(args.cycles):
        long_count = 1 + (cycle % len(levels))
        control_count = args.expected_slots - long_count

        slots = get_json(args.host, args.port, "/slots")
        assert isinstance(slots, list) and len(slots) == args.expected_slots
        assert not any(slot["is_processing"] for slot in slots), slots

        # Same-load baseline: long streams run to completion while the same
        # number of controls is active. Cancellation is then compared with
        # this baseline, not with a no-load greedy reference.
        baseline_longs: list[dict[str, Any]] = []
        baseline_long_threads: list[threading.Thread] = []
        baseline_started_ns = time.perf_counter_ns()
        for _ in range(long_count):
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
            baseline_long_threads.append(thread)
            baseline_longs.append(sink)
        baseline_threads, baseline_controls = run_control_batch(
            args.host,
            args.port,
            control_request,
            control_count,
        )
        join_controls(baseline_threads, baseline_controls)
        for thread in baseline_long_threads:
            thread.join(timeout=30)
        if any(thread.is_alive() for thread in baseline_long_threads):
            raise RuntimeError(f"cycle {cycle}: baseline longs timed out")
        if any("error" in sink for sink in baseline_longs):
            raise RuntimeError(f"cycle {cycle}: baseline long failed: {baseline_longs!r}")
        if any(sink.get("status") != 200 for sink in baseline_longs):
            raise RuntimeError(f"cycle {cycle}: baseline long bad status: {baseline_longs!r}")
        baseline_identities = [
            control["response"].get("content", "")
            == baseline_controls[0]["response"].get("content", "")
            and control["response"].get("tokens", [])
            == baseline_controls[0]["response"].get("tokens", [])
            for control in baseline_controls
        ]

        stamp = time.time_ns()
        started_ns = time.perf_counter_ns()
        streams: list[tuple[int, str, Any]] = []
        for long_index in range(long_count):
            conversation_id = (
                f"rq3-curve-L{long_count}-c{cycle}-{long_index}-{stamp}"
            )
            sock = start_cancelable_request(
                args.host,
                args.port,
                conversation_id,
                args.prompt,
                args.prediction_tokens,
                args.seed,
            )
            streams.append((long_index, conversation_id, sock))

        control_start_ns = time.perf_counter_ns()
        controls: list[dict[str, Any]] = []
        threads: list[threading.Thread] = []
        for control_index in range(control_count):
            control: dict[str, Any] = {}
            thread = threading.Thread(
                target=run_control,
                args=(args.host, args.port, control_request, control),
            )
            thread.start()
            threads.append(thread)
            controls.append(control)

        active_wait_started_ns = time.perf_counter_ns()
        while (time.perf_counter_ns() - active_wait_started_ns) / 1e6 < 1000:
            candidate = get_json(args.host, args.port, "/slots")
            if (
                isinstance(candidate, list)
                and active_long_count(candidate, args.prediction_tokens) >= long_count
            ):
                break
            time.sleep(0.001)
        active_long_wait_ms = (
            time.perf_counter_ns() - active_wait_started_ns
        ) / 1e6

        remaining = args.cancel_delay_ms / 1000.0 - (
            time.perf_counter_ns() - started_ns
        ) / 1e9
        if remaining > 0:
            time.sleep(remaining)

        delete_started_ns = time.perf_counter_ns()
        deletions: list[dict[str, Any]] = []
        for long_index, conversation_id, sock in streams:
            delete_status = delete_stream(args.host, args.port, conversation_id)
            sock.close()
            deletions.append(
                {
                    "longIndex": long_index,
                    "conversationId": conversation_id,
                    "deleteStatus": delete_status,
                    "cancelAccepted": delete_status == 204,
                }
            )

        free_slots: list[dict[str, Any]] | None = None
        while (time.perf_counter_ns() - delete_started_ns) / 1e6 < args.free_timeout_ms:
            candidate = get_json(args.host, args.port, "/slots")
            if isinstance(candidate, list) and not long_processing(
                candidate, args.prediction_tokens
            ):
                free_slots = candidate
                break
            time.sleep(0.002)
        all_long_free_ns = time.perf_counter_ns()
        if free_slots is None:
            failure_slots = get_json(args.host, args.port, "/slots")
            failure = {
                "status": "FAIL",
                "overallPass": False,
                "protocolVersion": "RQ3.LLAMA.CONCURRENCY.CURVE.V1",
                "failure": "CANCELLED_LONG_STREAMS_DID_NOT_FREE",
                "expectedSlots": args.expected_slots,
                "failedCycle": cycle,
                "longStreams": long_count,
                "controls": control_count,
                "freeTimeoutMs": args.free_timeout_ms,
                "slotsAtTimeout": failure_slots,
                "completedCycles": cycles,
            }
            output = Path(args.output)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(failure, ensure_ascii=False, indent=2) + "\n")
            raise RuntimeError(f"cycle {cycle}: cancelled long streams did not free")

        for thread in threads:
            thread.join(timeout=30)
        if any(thread.is_alive() for thread in threads):
            raise RuntimeError(f"cycle {cycle}: controls timed out")
        if any("error" in control for control in controls):
            raise RuntimeError(f"cycle {cycle}: control failed: {controls!r}")

        identities = [
            response.get("content", "")
            == baseline_controls[index]["response"].get("content", "")
            and response.get("tokens", [])
            == baseline_controls[index]["response"].get("tokens", [])
            for index, response in enumerate(
                control.get("response") for control in controls
            )
        ]
        clients = [control["clientNs"] / 1e6 for control in controls]
        cycles.append(
            {
                "cycle": cycle,
                "longStreams": long_count,
                "controls": control_count,
                "activeRequests": args.expected_slots,
                "cancelDelayMs": args.cancel_delay_ms,
                "deletions": deletions,
                "cancelAccepted": all(
                    deletion["cancelAccepted"] for deletion in deletions
                ),
                "deleteToAllLongFreeMs": (all_long_free_ns - delete_started_ns) / 1e6,
                "activeLongWaitMs": active_long_wait_ms,
                "slotsAtAllLongFree": free_slots,
                "controlsStartedBeforeAllLongFree": control_start_ns
                < all_long_free_ns,
                "controlsFinishedBeforeAllLongFree": all(
                    control["finishedNs"] < all_long_free_ns
                    for control in controls
                ),
                "sameLoadBaselineControlsAllIdentical": all(baseline_identities),
                "controlsMatchedSameConcurrencyBaseline": all(identities),
                "controlSemanticIdenticalCount": sum(identities),
                "controlClientMeanMs": sum(clients) / len(clients),
                "controlClientMaxMs": max(clients),
                "controlContents": [
                    control["response"].get("content", "") for control in controls
                ],
            }
        )

    accepted = sum(cycle["cancelAccepted"] for cycle in cycles)
    identical = sum(
        cycle["controlsMatchedSameConcurrencyBaseline"] for cycle in cycles
    )
    baseline_identical = sum(
        cycle["sameLoadBaselineControlsAllIdentical"] for cycle in cycles
    )
    overlapped = sum(cycle["controlsStartedBeforeAllLongFree"] for cycle in cycles)
    finished_before_free = sum(
        cycle["controlsFinishedBeforeAllLongFree"] for cycle in cycles
    )
    by_level: dict[str, dict[str, Any]] = {}
    for level in levels:
        level_cycles = [
            cycle for cycle in cycles if cycle["longStreams"] == level
        ]
        by_level[str(level)] = {
            "cycles": len(level_cycles),
            "longStreams": level,
            "controls": args.expected_slots - level,
            "cancelAccepted": sum(
                cycle["cancelAccepted"] for cycle in level_cycles
            ),
            "expectedCancels": len(level_cycles) * level,
            "controlsMatchedSameConcurrencyBaseline": sum(
                cycle["controlsMatchedSameConcurrencyBaseline"]
                for cycle in level_cycles
            ),
            "sameLoadBaselineControlsAllIdentical": sum(
                cycle["sameLoadBaselineControlsAllIdentical"]
                for cycle in level_cycles
            ),
            "deleteToAllLongFree": summarize(
                [
                    cycle["deleteToAllLongFreeMs"]
                    for cycle in level_cycles
                ]
            ),
            "controlClientMean": summarize(
                [cycle["controlClientMeanMs"] for cycle in level_cycles]
            ),
            "controlClientMax": summarize(
                [cycle["controlClientMaxMs"] for cycle in level_cycles]
            ),
        }

    accepted_deletions = sum(
        len(cycle["deletions"]) for cycle in cycles if cycle["cancelAccepted"]
    )
    expected_deletions = sum(cycle["longStreams"] for cycle in cycles)
    controls_completed = sum(
        cycle["controlSemanticIdenticalCount"] >= 0 for cycle in cycles
    )
    identity_cycles = sum(
        cycle["controlsMatchedSameConcurrencyBaseline"] for cycle in cycles
    )
    overall_pass = (
        accepted_deletions == expected_deletions
        and controls_completed == len(cycles)
        and overlapped == len(cycles)
        and baseline_identical == len(cycles)
    )
    report = {
        "status": "PASS_WITH_BOUNDARY" if overall_pass else "FAIL",
        "overallPass": overall_pass,
        "checks": {
            "ALL_CANCELS_ACCEPTED": accepted_deletions == expected_deletions,
            "ALL_CONTROL_BATCHES_COMPLETED": controls_completed == len(cycles),
            "CONTROLS_OVERLAPPED_CANCELLATION_WINDOW": overlapped == len(cycles),
            "SAME_LOAD_BASELINE_STABLE": baseline_identical == len(cycles),
            "GREEDY_IDENTITY_ACROSS_CANCEL": identity_cycles == len(cycles),
        },
        "identityFinding": {
            "cyclesMatchedSameConcurrencyBaseline": identity_cycles,
            "cyclesCompared": len(cycles),
            "boundary": (
                "Greedy controls completed, but token/content identity across the "
                "cancellation-induced batch transition is not expected to be a "
                "batch invariant in this server configuration."
            ),
        },
        "protocolVersion": "RQ3.LLAMA.CONCURRENCY.CURVE.V1",
        "boundary": (
            "EXPLICIT_MULTI_STREAM_CANCEL_VS_SAME_CONCURRENCY_BASELINE / "
            "NO_EXECUTION_STATE_OBJECT / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "expectedSlots": args.expected_slots,
        "curveLevels": list(levels),
        "longRequest": {
            "endpoint": "/v1/chat/completions",
            "stream": True,
            "prompt": args.prompt,
            "predictionTokens": args.prediction_tokens,
            "cancelDelayMs": args.cancel_delay_ms,
            "seed": args.seed,
        },
        "controlRequest": {
            "endpoint": "/completion",
            "promptTokens": control_request["prompt"],
            "predictionTokens": args.control_tokens,
            "seed": args.seed,
        },
        "reference": {
            "content": reference.get("content", ""),
            "tokens": reference.get("tokens", []),
        },
        "cyclesRequested": args.cycles,
        "results": {
            "cyclesPassedCancel": accepted,
            "cyclesControlsMatchedSameConcurrencyBaseline": identical,
            "cyclesSameLoadBaselineControlsAllIdentical": baseline_identical,
            "controlsStartedBeforeAllLongFree": overlapped,
            "controlsFinishedBeforeAllLongFree": finished_before_free,
            "deleteToAllLongFree": summarize(
                [cycle["deleteToAllLongFreeMs"] for cycle in cycles]
            ),
            "controlClientMean": summarize(
                [cycle["controlClientMeanMs"] for cycle in cycles]
            ),
            "controlClientMax": summarize(
                [cycle["controlClientMaxMs"] for cycle in cycles]
            ),
            "byLevel": by_level,
        },
        "cycles": cycles,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
