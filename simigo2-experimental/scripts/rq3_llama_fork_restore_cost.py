#!/usr/bin/env python3
"""RQ3 fork/restore cost and semantics characterization for llama-server.

Each sample executes:

  bind parent checkpoint
    -> reference generation
    -> fork/derive child at checkpoint
    -> divergent child generation
    -> release divergent child representation
    -> restore child to fork point
    -> replay reference continuation

The server receives token-ID prompts. Fork/restore operations are local
Execution State representation operations; inference remains owned by
llama-server. This is a cost characterization, not a universal performance
claim.
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

from rq3_llama_hotpath_ab import Binding, percentile, post_json, summarize


@dataclass
class Operation:
    name: str
    duration_ms: float


class MultiPrefixStateBackend:
    """Python mirror of the contract's prefix representation operations."""

    def __init__(self) -> None:
        self.bindings: dict[str, Binding] = {}
        self.operations: list[Operation] = []

    def _record(self, name: str, started_ns: int) -> None:
        self.operations.append(
            Operation(name=name, duration_ms=(time.perf_counter_ns() - started_ns) / 1e6)
        )

    def bind(self, execution_id: str, prefix: list[int], position: int) -> None:
        started = time.perf_counter_ns()
        self.bindings[execution_id] = Binding(prefix=prefix.copy(), position=position)
        self._record("bind", started)

    def capture(self, execution_id: str) -> Binding:
        started = time.perf_counter_ns()
        binding = self.bindings.get(execution_id)
        if binding is None:
            raise RuntimeError(f"no binding for {execution_id}")
        value = Binding(prefix=binding.prefix.copy(), position=binding.position)
        self._record("capture", started)
        return value

    def derive(self, representation: Binding, child_id: str) -> Binding:
        started = time.perf_counter_ns()
        value = Binding(prefix=representation.prefix.copy(), position=representation.position)
        self.bindings[child_id] = value
        self._record("derive", started)
        return value

    def release(self, execution_id: str, representation: Binding) -> None:
        started = time.perf_counter_ns()
        current = self.bindings.get(execution_id)
        if current is not None and current.position == representation.position:
            self.bindings.pop(execution_id, None)
        self._record("release", started)

    def restore(self, execution_id: str, representation: Binding) -> Binding:
        started = time.perf_counter_ns()
        value = Binding(prefix=representation.prefix.copy(), position=representation.position)
        self.bindings[execution_id] = value
        self._record("restore", started)
        return value


def summarize_operations(operations: list[Operation], name: str) -> dict[str, float]:
    values = [operation.duration_ms for operation in operations if operation.name == name]
    return summarize(values)


def request_timings(response: dict[str, Any]) -> dict[str, Any]:
    timings = response.get("timings", {})
    return {
        "promptN": timings.get("prompt_n"),
        "cachedN": timings.get("cache_n"),
        "predictedMs": timings.get("predicted_ms"),
        "promptMs": timings.get("prompt_ms"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--tokens", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")

    parent_prompt = "Return exactly one word: ping"
    divergent_prompt = "Ignore the old request. Return exactly: alpha beta"
    tokenize = lambda text: post_json(  # noqa: E731
        f"{base_url}/tokenize", {"content": text}
    )[0]["tokens"]

    parent_prompt_tokens = tokenize(parent_prompt)
    divergent_prompt_tokens = tokenize(divergent_prompt)
    request = {
        "n_predict": args.tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": True,
        "return_tokens": True,
    }

    def generate(prompt_tokens: list[int]) -> tuple[dict[str, Any], float]:
        payload = {**request, "prompt": prompt_tokens}
        response, client_ns = post_json(f"{base_url}/completion", payload)
        return response, client_ns / 1e6

    # Warm the model and llama.cpp graph cache without recording measurements.
    generate(parent_prompt_tokens)

    backend = MultiPrefixStateBackend()
    all_operations: list[Operation] = []
    samples: list[dict[str, Any]] = []
    for index in range(args.samples):
        backend.bindings.clear()
        backend.operations.clear()

        backend.bind("parent", parent_prompt_tokens, 0)
        parent_checkpoint = backend.capture("parent")
        reference_response, reference_client_ms = generate(parent_prompt_tokens)
        reference_tokens: list[int] = reference_response.get("tokens", [])
        parent_after_reference = parent_prompt_tokens + reference_tokens
        backend.bind("parent", parent_after_reference, 1)

        child_at_fork = backend.derive(parent_checkpoint, "child")
        child_divergence_prompt = child_at_fork.prefix + divergent_prompt_tokens
        divergence_response, divergence_client_ms = generate(child_divergence_prompt)
        divergence_tokens: list[int] = divergence_response.get("tokens", [])
        child_after_divergence = child_divergence_prompt + divergence_tokens
        backend.bind("child", child_after_divergence, 1)
        divergent_representation = backend.capture("child")

        backend.release("child", divergent_representation)
        child_after_restore = backend.restore("child", child_at_fork)
        replay_response, replay_client_ms = generate(child_at_fork.prefix)
        replay_tokens: list[int] = replay_response.get("tokens", [])
        backend.bind("child", child_at_fork.prefix + replay_tokens, 1)
        all_operations.extend(backend.operations)

        parent_binding = backend.bindings["parent"]
        samples.append(
            {
                "sample": index,
                "operations": [
                    {"name": operation.name, "durationMs": operation.duration_ms}
                    for operation in backend.operations
                ],
                "reference": {
                    "content": reference_response.get("content", ""),
                    "tokens": reference_tokens,
                    "clientWallMs": reference_client_ms,
                    "server": request_timings(reference_response),
                },
                "divergence": {
                    "promptTokens": child_divergence_prompt,
                    "content": divergence_response.get("content", ""),
                    "tokens": divergence_tokens,
                    "clientWallMs": divergence_client_ms,
                    "server": request_timings(divergence_response),
                },
                "replayAfterRestore": {
                    "content": replay_response.get("content", ""),
                    "tokens": replay_tokens,
                    "clientWallMs": replay_client_ms,
                    "server": request_timings(replay_response),
                },
                "checks": {
                    "restoreReplayIdentical": (
                        replay_tokens == reference_tokens
                        and replay_response.get("content", "")
                        == reference_response.get("content", "")
                    ),
                    "branchDiverged": (
                        divergence_tokens != reference_tokens
                        or divergence_response.get("content", "")
                        != reference_response.get("content", "")
                    ),
                    "parentPrefixNonInterference": (
                        parent_binding.prefix == parent_after_reference
                        and parent_binding.position == 1
                    ),
                    "childRestoredToForkPoint": (
                        child_after_restore.prefix == parent_prompt_tokens
                        and child_after_restore.position == 0
                    ),
                },
            }
        )

    references_client = [sample["reference"]["clientWallMs"] for sample in samples]
    divergences_client = [sample["divergence"]["clientWallMs"] for sample in samples]
    replays_client = [
        sample["replayAfterRestore"]["clientWallMs"] for sample in samples
    ]
    replay_reference_client_delta = [
        sample["replayAfterRestore"]["clientWallMs"]
        - sample["reference"]["clientWallMs"]
        for sample in samples
    ]
    replay_reference_client_abs_delta = [
        abs(value) for value in replay_reference_client_delta
    ]
    references_predicted = [
        float(sample["reference"]["server"]["predictedMs"]) for sample in samples
    ]
    divergences_predicted = [
        float(sample["divergence"]["server"]["predictedMs"]) for sample in samples
    ]
    replays_predicted = [
        float(sample["replayAfterRestore"]["server"]["predictedMs"])
        for sample in samples
    ]
    replay_reference_predicted_delta = [
        sample["replayAfterRestore"]["server"]["predictedMs"]
        - sample["reference"]["server"]["predictedMs"]
        for sample in samples
    ]

    checks = {
        name: sum(1 for sample in samples if sample["checks"][name])
        for name in samples[0]["checks"]
    }
    operation_names = [
        "bind",
        "capture",
        "derive",
        "release",
        "restore",
    ]
    assert len(all_operations) == len(samples) * 9
    fork_restore_local_ms = [
        sum(
            operation["durationMs"]
            for operation in sample["operations"]
            if operation["name"] in {"derive", "restore", "release"}
        )
        for sample in samples
    ]
    fork_restore_local_vs_abs_noise_ratio = (
        statistics.fmean(fork_restore_local_ms)
        / statistics.fmean(replay_reference_client_abs_delta)
    )

    report = {
        "protocolVersion": "RQ3.LLAMA.FORK.RESTORE.COST.V1",
        "boundary": (
            "FORK_DIVERGE_RELEASE_RESTORE_REPLAY / TOKEN_PREFIX_REPRESENTATION "
            "/ LOCAL_STATE_COST_AND_INFERENCE_COST_SEPARATE "
            "/ NOT_A_UNIVERSAL_PERFORMANCE_CLAIM"
        ),
        "health": health,
        "request": request,
        "prompts": {
            "parent": parent_prompt,
            "divergent": divergent_prompt,
            "parentTokens": parent_prompt_tokens,
            "divergentTokens": divergent_prompt_tokens,
        },
        "samplesRequested": args.samples,
        "sequence": (
            "parent bind/capture -> reference -> derive child -> diverge -> "
            "release divergent -> restore fork point -> replay reference"
        ),
        "results": {
            "checks": checks,
            "operationCostsMs": {
                name: summarize_operations(all_operations, name)
                for name in operation_names
            },
            "forkRestoreReleaseLocalCostMs": summarize(fork_restore_local_ms),
            "forkRestoreReleaseLocalVsAbsClientNoiseRatio": (
                fork_restore_local_vs_abs_noise_ratio
            ),
            "inferenceClientWallMs": {
                "reference": summarize(references_client),
                "divergence": summarize(divergences_client),
                "replayAfterRestore": summarize(replays_client),
                "replayMinusReference": summarize(replay_reference_client_delta),
                "replayMinusReferenceAbsolute": summarize(
                    replay_reference_client_abs_delta
                ),
            },
            "inferenceServerPredictedMs": {
                "reference": summarize(references_predicted),
                "divergence": summarize(divergences_predicted),
                "replayAfterRestore": summarize(replays_predicted),
                "replayMinusReference": summarize(replay_reference_predicted_delta),
            },
        },
        "samples": samples,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
