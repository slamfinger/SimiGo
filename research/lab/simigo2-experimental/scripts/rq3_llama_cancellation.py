#!/usr/bin/env python3
"""Exercise explicit llama-server cancellation and short-request recovery.

Each cycle opens a resumable streaming chat request, cancels it through
DELETE /v1/stream, waits for the slot to become free, then checks that a
greedy one-token completion still matches a reference. This is a backend
control: no Execution State object participates.
"""

from __future__ import annotations

import argparse
import http.client
import json
import socket
import statistics
import time
import urllib.request
from pathlib import Path

from rq3_llama_hotpath_ab import percentile, post_json


def summarize(values: list[float]) -> dict[str, float]:
    return {
        "n": float(len(values)),
        "meanMs": statistics.fmean(values),
        "medianMs": statistics.median(values),
        "p95Ms": percentile(values, 95),
        "minMs": min(values),
        "maxMs": max(values),
    }


def get_json(host: str, port: int, path: str) -> object:
    connection = http.client.HTTPConnection(host, port, timeout=5)
    connection.request("GET", path)
    response = connection.getresponse()
    decoded = json.loads(response.read())
    connection.close()
    return decoded


def delete_stream(host: str, port: int, conversation_id: str) -> int:
    connection = http.client.HTTPConnection(host, port, timeout=5)
    connection.request("DELETE", f"/v1/stream?conv_id={conversation_id}")
    response = connection.getresponse()
    response.read()
    status = response.status
    connection.close()
    return status


def start_cancelable_request(
    host: str, port: int, conversation_id: str, prompt: str, prediction_tokens: int, seed: int
) -> socket.socket:
    payload = {
        "stream": True,
        "max_tokens": prediction_tokens,
        "temperature": 0.0,
        "seed": seed,
        "messages": [{"role": "user", "content": prompt}],
    }
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
    sock = socket.create_connection((host, port), timeout=5)
    request = (
        f"POST /v1/chat/completions HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Content-Type: application/json\r\n"
        f"X-Conversation-Id: {conversation_id}\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"Connection: close\r\n\r\n"
    ).encode() + body
    sock.sendall(request)
    return sock


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles", type=int, default=20)
    parser.add_argument("--cancel-delay-ms", type=int, default=100)
    parser.add_argument("--prediction-tokens", type=int, default=256)
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

    reference_request = {
        "prompt": [5423, 6681, 799, 3299, 25, 29018],
        "n_predict": 1,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": False,
        "return_tokens": True,
    }
    reference, _ = post_json(f"{base_url}/completion", reference_request)

    cancel_latencies: list[float] = []
    recovery_latencies: list[float] = []
    cycles: list[dict[str, object]] = []
    for cycle in range(args.cycles):
        conversation_id = f"rq3-cancel-{cycle}-{time.time_ns()}"
        slots = get_json(args.host, args.port, "/slots")
        assert isinstance(slots, list) and len(slots) == 1 and not slots[0]["is_processing"], slots

        started_ns = time.perf_counter_ns()
        sock = start_cancelable_request(
            args.host,
            args.port,
            conversation_id,
            args.prompt,
            args.prediction_tokens,
            args.seed,
        )
        delay_s = args.cancel_delay_ms / 1000.0
        remaining = delay_s - (time.perf_counter_ns() - started_ns) / 1e9
        if remaining > 0:
            time.sleep(remaining)

        delete_ns = time.perf_counter_ns()
        delete_status = delete_stream(args.host, args.port, conversation_id)
        sock.close()

        free_slot: dict[str, object] | None = None
        while (time.perf_counter_ns() - delete_ns) / 1e6 < args.free_timeout_ms:
            candidate = get_json(args.host, args.port, "/slots")
            assert isinstance(candidate, list)
            if len(candidate) == 1 and not candidate[0]["is_processing"]:
                free_slot = candidate[0]
                break
            time.sleep(0.002)
        if free_slot is None:
            raise RuntimeError(f"cancel cycle {cycle} did not free the slot")

        free_ns = time.perf_counter_ns()
        recovery, recovery_client_ns = post_json(
            f"{base_url}/completion", reference_request
        )

        cancel_latencies.append((free_ns - delete_ns) / 1e6)
        recovery_latencies.append(recovery_client_ns / 1e6)
        cycles.append(
            {
                "cycle": cycle,
                "conversationId": conversation_id,
                "cancelDelayMs": args.cancel_delay_ms,
                "deleteStatus": delete_status,
                "cancelAccepted": delete_status == 204,
                "deleteToFreeMs": cancel_latencies[-1],
                "freeSlot": free_slot,
                "recoveryClientMs": recovery_latencies[-1],
                "recoveryContent": recovery.get("content", ""),
                "recoveryTokens": recovery.get("tokens", []),
                "semanticIdentical": (
                    recovery.get("content", "") == reference.get("content", "")
                    and recovery.get("tokens", []) == reference.get("tokens", [])
                ),
            }
        )

    identical = sum(1 for cycle in cycles if cycle["semanticIdentical"])
    accepted = sum(1 for cycle in cycles if cycle["cancelAccepted"])
    report = {
        "protocolVersion": "RQ3.LLAMA.CANCELLATION.V1",
        "boundary": (
            "EXPLICIT_RESUMABLE_STREAM_CANCEL / BACKEND_RECOVERY_CONTROL / "
            "NO_EXECUTION_STATE_OBJECT / NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "serverEndpoints": {"cancel": "DELETE /v1/stream?conv_id=..."},
        "request": {
            "endpoint": "/v1/chat/completions",
            "stream": True,
            "prompt": args.prompt,
            "predictionTokens": args.prediction_tokens,
            "cancelDelayMs": args.cancel_delay_ms,
            "seed": args.seed,
        },
        "reference": {
            "endpoint": "/completion",
            "content": reference.get("content", ""),
            "tokens": reference.get("tokens", []),
        },
        "cyclesRequested": args.cycles,
        "results": {
            "cancelAccepted": accepted,
            "semanticIdentical": identical,
            "deleteToFree": summarize(cancel_latencies),
            "recoveryClient": summarize(recovery_latencies),
        },
        "cycles": cycles,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
