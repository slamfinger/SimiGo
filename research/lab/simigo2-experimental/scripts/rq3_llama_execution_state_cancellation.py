#!/usr/bin/env python3
"""RQ3 cancellation A/B with a local Execution State prefix mirror.

OFF performs the same explicit llama-server cancellation and recovery control.
ON first captures the unaffected root representation, binds and captures a
cancelled child representation, releases only the child, restores the root
snapshot, then performs the identical recovery request. The local mirror is
harness-level evidence; llama-server remains the inference and native-cache
authority.
"""

from __future__ import annotations

import argparse
import json
import statistics
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from rq3_llama_cancellation import (
    delete_stream,
    get_json,
    start_cancelable_request,
)
from rq3_llama_hotpath_ab import percentile, post_json, summarize


@dataclass
class Binding:
    prefix: list[int]
    position: int


@dataclass
class Operation:
    name: str
    duration_ms: float


class MultiRepresentationBackend:
    def __init__(self) -> None:
        self.bindings: dict[str, Binding] = {}
        self.operations: list[Operation] = []
        self.state_overhead_ns = 0

    def _record(self, name: str, started_ns: int) -> None:
        duration_ms = (time.perf_counter_ns() - started_ns) / 1e6
        self.operations.append(Operation(name=name, duration_ms=duration_ms))
        self.state_overhead_ns += int(duration_ms * 1e6)

    def bind(self, execution_id: str, representation: Binding) -> None:
        started = time.perf_counter_ns()
        self.bindings[execution_id] = Binding(
            prefix=representation.prefix.copy(), position=representation.position
        )
        self._record("bind", started)

    def capture(self, execution_id: str) -> Binding:
        started = time.perf_counter_ns()
        binding = self.bindings.get(execution_id)
        if binding is None:
            raise RuntimeError(f"no representation bound for {execution_id}")
        value = Binding(prefix=binding.prefix.copy(), position=binding.position)
        self._record("capture", started)
        return value

    def release(self, execution_id: str, representation: Binding) -> None:
        started = time.perf_counter_ns()
        current = self.bindings.get(execution_id)
        if current is not None and current.position == representation.position:
            self.bindings.pop(execution_id, None)
        self._record("release", started)

    def restore(self, execution_id: str, representation: Binding) -> Binding:
        started = time.perf_counter_ns()
        self.bind(execution_id, representation)
        self.operations.pop()
        self._record("restore", started)
        return self.bindings[execution_id]


def summarize_operations(operations: list[Operation], name: str) -> dict[str, float]:
    values = [operation.duration_ms for operation in operations if operation.name == name]
    return summarize(values)


def wait_one_slot_free(host: str, port: int, delete_ns: int, timeout_ms: int) -> dict[str, Any]:
    while (time.perf_counter_ns() - delete_ns) / 1e6 < timeout_ms:
        slots = get_json(host, port, "/slots")
        assert isinstance(slots, list)
        if len(slots) == 1 and not slots[0]["is_processing"]:
            return slots[0]
        time.sleep(0.002)
    raise RuntimeError("cancelled request did not free the sole slot")


def run_cancel_cycle(
    host: str,
    port: int,
    cycle: int,
    mode: str,
    long_prompt: str,
    args: argparse.Namespace,
    backend: MultiRepresentationBackend | None,
    child_template: Binding,
) -> dict[str, Any]:
    conversation_id = f"rq3-execstate-cancel-{mode}-{cycle}-{time.time_ns()}"
    slots = get_json(host, port, "/slots")
    assert isinstance(slots, list) and len(slots) == 1 and not slots[0]["is_processing"]

    state_ns_start = backend.state_overhead_ns if backend else 0
    if mode == "execution_state_on":
        assert backend is not None
        backend.bind("child", child_template)
        child_snapshot = backend.capture("child")
        root_snapshot = backend.capture("root")
    else:
        root_snapshot = None

    started_ns = time.perf_counter_ns()
    sock = start_cancelable_request(
        host,
        port,
        conversation_id,
        long_prompt,
        args.prediction_tokens,
        args.seed,
    )
    remaining = args.cancel_delay_ms / 1000.0 - (time.perf_counter_ns() - started_ns) / 1e9
    if remaining > 0:
        time.sleep(remaining)

    delete_ns = time.perf_counter_ns()
    delete_status = delete_stream(host, port, conversation_id)
    sock.close()
    free_slot = wait_one_slot_free(host, port, delete_ns, args.free_timeout_ms)
    free_ns = time.perf_counter_ns()

    if mode == "execution_state_on":
        assert backend is not None and root_snapshot is not None
        backend.release("child", child_snapshot)
        restored = backend.restore("root", root_snapshot)
        assert restored == root_snapshot

    recovery, recovery_ns = post_json(f"http://{host}:{port}/completion", args.reference_request)
    assert backend is None or backend.bindings.get("root") == root_snapshot
    state_overhead_ms = (
        (backend.state_overhead_ns - state_ns_start) / 1e6 if backend else 0.0
    )
    return {
        "cycle": cycle,
        "mode": mode,
        "conversationId": conversation_id,
        "deleteStatus": delete_status,
        "cancelAccepted": delete_status == 204,
        "deleteToFreeMs": (free_ns - delete_ns) / 1e6,
        "freeSlot": free_slot,
        "recoveryClientMs": recovery_ns / 1e6,
        "recoveryContent": recovery.get("content", ""),
        "recoveryTokens": recovery.get("tokens", []),
        "semanticIdentical": (
            recovery.get("content", "") == args.reference_content
            and recovery.get("tokens", []) == args.reference_tokens
        ),
        "stateOverheadMs": state_overhead_ms,
    }


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
        "--long-prompt",
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
    args.reference_request = reference_request
    args.reference_content = reference.get("content", "")
    args.reference_tokens = reference.get("tokens", [])

    child_tokens_response, _ = post_json(
        f"{base_url}/tokenize", {"content": args.long_prompt}
    )
    root_prefix: list[int] = reference_request["prompt"]
    child_prefix: list[int] = child_tokens_response["tokens"]
    child_template = Binding(prefix=child_prefix, position=0)

    # Warm both request paths once so paired measurements do not include first
    # model load. State operations are reinitialized for the measured phase.
    backend = MultiRepresentationBackend()
    backend.bind("root", Binding(prefix=root_prefix, position=0))
    backend.bind("child", Binding(prefix=child_prefix, position=0))
    backend.operations.clear()
    backend.state_overhead_ns = 0

    cycles: list[dict[str, Any]] = []
    for cycle in range(args.cycles):
        modes = (
            ("off", "execution_state_on")
            if cycle % 2 == 0
            else ("execution_state_on", "off")
        )
        for mode in modes:
            if mode == "off":
                result = run_cancel_cycle(
                    args.host,
                    args.port,
                    cycle,
                    mode,
                    args.long_prompt,
                    args,
                    None,
                    child_template,
                )
            else:
                result = run_cancel_cycle(
                    args.host,
                    args.port,
                    cycle,
                    mode,
                    args.long_prompt,
                    args,
                    backend,
                    child_template,
                )
            cycles.append(result)

    def mode_results(mode: str) -> list[dict[str, Any]]:
        return [cycle for cycle in cycles if cycle["mode"] == mode]

    paired = []
    for cycle in range(args.cycles):
        off = next(item for item in cycles if item["cycle"] == cycle and item["mode"] == "off")
        on = next(
            item
            for item in cycles
            if item["cycle"] == cycle and item["mode"] == "execution_state_on"
        )
        paired.append(on["recoveryClientMs"] - off["recoveryClientMs"])

    off_results = mode_results("off")
    on_results = mode_results("execution_state_on")
    report = {
        "protocolVersion": "RQ3.LLAMA.EXECSTATE.CANCELLATION.AB.V1",
        "boundary": (
            "LOCAL_PREFIX_REPRESENTATION_MIRROR / HARNESS_LEVEL / "
            "NO_SWIFT_LLAMA_EXECUTOR / NO_NATIVE_KV_AUTHORITY_CHANGE / "
            "NOT_A_PERFORMANCE_OR_PRODUCTION_CLAIM"
        ),
        "health": health,
        "reference": {
            "content": args.reference_content,
            "tokens": args.reference_tokens,
        },
        "state": {
            "representations": ["root", "child"],
            "operationSequence": [
                "bind child from template",
                "capture child",
                "capture root snapshot",
                "cancel child request",
                "release child",
                "restore root snapshot",
            ],
            "rootPosition": 0,
            "childPosition": 0,
        },
        "results": {
            "cyclesRequested": args.cycles,
            "offCancelAccepted": sum(item["cancelAccepted"] for item in off_results),
            "onCancelAccepted": sum(item["cancelAccepted"] for item in on_results),
            "offSemanticIdentical": sum(item["semanticIdentical"] for item in off_results),
            "onSemanticIdentical": sum(item["semanticIdentical"] for item in on_results),
            "deleteToFree": {
                "off": summarize([item["deleteToFreeMs"] for item in off_results]),
                "executionStateOn": summarize(
                    [item["deleteToFreeMs"] for item in on_results]
                ),
            },
            "recoveryClient": {
                "off": summarize([item["recoveryClientMs"] for item in off_results]),
                "executionStateOn": summarize(
                    [item["recoveryClientMs"] for item in on_results]
                ),
            },
            "pairedOnMinusOffRecoveryClient": summarize(paired),
            "stateOperation": {
                "bind": summarize_operations(backend.operations, "bind"),
                "capture": summarize_operations(backend.operations, "capture"),
                "release": summarize_operations(backend.operations, "release"),
                "restore": summarize_operations(backend.operations, "restore"),
            },
        },
        "cycles": cycles,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
