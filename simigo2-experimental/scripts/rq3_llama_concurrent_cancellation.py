#!/usr/bin/env python3
"""Cancel one llama-server stream while an unaffected control completes.

Each cycle launches a long resumable-stream request and a short greedy
completion together, explicitly cancels the long request, waits for its slot
to free, and compares the short control with a pre-run reference. This is a
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
from rq3_llama_hotpath_ab import post_json


def run_control(
    host: str, port: int, payload: dict[str, Any], sink: dict[str, Any]
) -> None:
    started_ns = time.perf_counter_ns()
    try:
        response, client_ns = post_json(f"http://{host}:{port}/completion", payload)
        sink.update(
            response=response,
            clientNs=client_ns,
            startedNs=started_ns,
            finishedNs=time.perf_counter_ns(),
        )
    except BaseException as error:  # propagate the worker failure after join
        sink["error"] = error


def long_is_processing(slots: list[dict[str, Any]], prediction_tokens: int) -> bool:
    return any(
        slot["is_processing"] and slot["params"]["n_predict"] == prediction_tokens
        for slot in slots
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles", type=int, default=20)
    parser.add_argument("--expected-slots", type=int, default=2)
    parser.add_argument("--cancel-delay-ms", type=int, default=100)
    parser.add_argument("--prediction-tokens", type=int, default=256)
    parser.add_argument("--control-tokens", type=int, default=8)
    parser.add_argument("--free-timeout-ms", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--prompt",
        default="Count from 1 to 500. Return only numbers separated by spaces.",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")

    initial_slots = get_json(args.host, args.port, "/slots")
    if not isinstance(initial_slots, list) or len(initial_slots) != args.expected_slots:
        raise RuntimeError(
            f"expected {args.expected_slots} slots, got {initial_slots!r}"
        )

    control_request = {
        "prompt": [5423, 6681, 799, 3299, 25, 29018],
        "n_predict": args.control_tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": False,
        "return_tokens": True,
    }
    reference, _ = post_json(f"{base_url}/completion", control_request)

    cycles: list[dict[str, Any]] = []
    for cycle in range(args.cycles):
        slots = get_json(args.host, args.port, "/slots")
        assert isinstance(slots, list) and len(slots) == args.expected_slots
        assert not any(slot["is_processing"] for slot in slots), slots

        conversation_id = f"rq3-concurrent-cancel-{cycle}-{time.time_ns()}"
        started_ns = time.perf_counter_ns()
        long_sock = start_cancelable_request(
            args.host,
            args.port,
            conversation_id,
            args.prompt,
            args.prediction_tokens,
            args.seed,
        )

        control: dict[str, Any] = {}
        control_thread = threading.Thread(
            target=run_control,
            args=(args.host, args.port, control_request, control),
        )
        control_start_ns = time.perf_counter_ns()
        control_thread.start()

        remaining = args.cancel_delay_ms / 1000.0 - (
            time.perf_counter_ns() - started_ns
        ) / 1e9
        if remaining > 0:
            time.sleep(remaining)

        delete_ns = time.perf_counter_ns()
        delete_status = delete_stream(args.host, args.port, conversation_id)
        long_sock.close()

        free_slots: list[dict[str, Any]] | None = None
        while (time.perf_counter_ns() - delete_ns) / 1e6 < args.free_timeout_ms:
            candidate = get_json(args.host, args.port, "/slots")
            if isinstance(candidate, list) and not long_is_processing(
                candidate, args.prediction_tokens
            ):
                free_slots = candidate
                break
            time.sleep(0.002)
        long_free_ns = time.perf_counter_ns()
        if free_slots is None:
            raise RuntimeError(f"cycle {cycle}: cancelled request did not free")

        control_thread.join(timeout=30)
        if control_thread.is_alive() or "error" in control:
            raise RuntimeError(f"cycle {cycle}: control failed: {control}")
        response = control["response"]
        semantic_identical = (
            response.get("content", "") == reference.get("content", "")
            and response.get("tokens", []) == reference.get("tokens", [])
        )

        cycles.append(
            {
                "cycle": cycle,
                "conversationId": conversation_id,
                "controlStartedDeltaMs": (control_start_ns - started_ns) / 1e6,
                "cancelDelayMs": args.cancel_delay_ms,
                "deleteStatus": delete_status,
                "cancelAccepted": delete_status == 204,
                "deleteToLongFreeMs": (long_free_ns - delete_ns) / 1e6,
                "slotsAtLongFree": free_slots,
                "controlStartedBeforeLongFree": control_start_ns < long_free_ns,
                "controlFinishedWhileLongActive": control["finishedNs"]
                < long_free_ns,
                "controlClientMs": control["clientNs"] / 1e6,
                "controlContent": response.get("content", ""),
                "controlTokens": response.get("tokens", []),
                "semanticIdentical": semantic_identical,
            }
        )

    accepted = sum(cycle["cancelAccepted"] for cycle in cycles)
    identical = sum(cycle["semanticIdentical"] for cycle in cycles)
    overlapped = sum(cycle["controlStartedBeforeLongFree"] for cycle in cycles)
    active_at_control_end = sum(
        cycle["controlFinishedWhileLongActive"] for cycle in cycles
    )
    report = {
        "protocolVersion": "RQ3.LLAMA.CONCURRENT.CANCELLATION.V1",
        "boundary": (
            "EXPLICIT_ONE_STREAM_CANCEL_WITH_UNAFFECTED_CONTROL / "
            "NO_EXECUTION_STATE_OBJECT / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "expectedSlots": args.expected_slots,
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
            "cancelAccepted": accepted,
            "controlSemanticIdentical": identical,
            "controlStartedBeforeLongFree": overlapped,
            "controlFinishedWhileLongActive": active_at_control_end,
            "deleteToLongFree": summarize(
                [cycle["deleteToLongFreeMs"] for cycle in cycles]
            ),
            "controlClient": summarize(
                [cycle["controlClientMs"] for cycle in cycles]
            ),
        },
        "cycles": cycles,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
