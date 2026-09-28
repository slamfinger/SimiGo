#!/usr/bin/env python3
"""RQ3 ordinary-generation hot-path A/B for llama-server.

OFF sends the request directly. ON performs the identical request through a
local Execution State prefix binding: capture before inference, bind returned
tokens after inference, then release the prior representation. There is no
fork and no extra model call. The server sees byte-identical JSON in both
modes; only local state bookkeeping differs.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Binding:
    prefix: list[int]
    position: int


class PrefixStateBackend:
    """Minimal Python mirror of the ExecutionStateBackend no-fork path."""

    def __init__(self) -> None:
        self.binding: Binding | None = None
        self.state_overhead_ns = 0

    def _clock(self) -> int:
        return time.perf_counter_ns()

    def bind(self, prefix: list[int], position: int) -> None:
        start = self._clock()
        self.binding = Binding(prefix=prefix.copy(), position=position)
        self.state_overhead_ns += self._clock() - start

    def capture(self) -> Binding:
        start = self._clock()
        if self.binding is None:
            raise RuntimeError("no bound representation")
        value = Binding(prefix=self.binding.prefix.copy(), position=self.binding.position)
        self.state_overhead_ns += self._clock() - start
        return value

    def release(self, representation: Binding) -> None:
        start = self._clock()
        if (
            self.binding is not None
            and self.binding.position == representation.position
        ):
            self.binding = None
        self.state_overhead_ns += self._clock() - start


def post_json(url: str, payload: dict[str, Any]) -> tuple[dict[str, Any], int]:
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter_ns()
    with urllib.request.urlopen(request, timeout=120) as response:
        decoded = json.loads(response.read())
    return decoded, time.perf_counter_ns() - started


def percentile(values: list[float], percent: float) -> float:
    if not values:
        return math.nan
    ordered = sorted(values)
    index = (len(ordered) - 1) * percent / 100.0
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower)


def summarize(values_ms: list[float]) -> dict[str, float]:
    return {
        "n": float(len(values_ms)),
        "meanMs": statistics.fmean(values_ms),
        "medianMs": statistics.median(values_ms),
        "p95Ms": percentile(values_ms, 95),
        "minMs": min(values_ms),
        "maxMs": max(values_ms),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--prompt", default="Return exactly one word: ping")
    parser.add_argument("--tokens", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")

    tokenize_payload = {"content": args.prompt}
    tokenized, _ = post_json(f"{base_url}/tokenize", tokenize_payload)
    prompt_tokens: list[int] = tokenized["tokens"]
    request_payload = {
        "prompt": args.prompt,
        "n_predict": args.tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": True,
        "return_tokens": True,
    }

    warmup, _ = post_json(f"{base_url}/completion", request_payload)
    backend = PrefixStateBackend()
    backend.bind(prefix=prompt_tokens, position=0)
    samples: list[dict[str, Any]] = []

    for index in range(args.samples):
        state_on_first = index % 2 == 0
        modes = ("state_on", "off") if state_on_first else ("off", "state_on")
        pair: dict[str, dict[str, Any]] = {}
        for mode in modes:
            state_ns_start = backend.state_overhead_ns
            captured = backend.capture() if mode == "state_on" else None
            decoded, wall_ns = post_json(f"{base_url}/completion", request_payload)
            generated: list[int] = decoded.get("tokens", [])
            state_ns = 0
            if mode == "state_on":
                prior = captured
                assert prior is not None
                next_position = prior.position + 1
                next_prefix = prior.prefix + generated
                backend.bind(prefix=next_prefix, position=next_position)
                backend.release(prior)
                state_ns = backend.state_overhead_ns - state_ns_start
            pair[mode] = {
                "content": decoded.get("content", ""),
                "generatedTokens": generated,
                "serverTimings": decoded.get("timings", {}),
                "clientWallMs": wall_ns / 1_000_000.0,
                "stateOverheadMs": state_ns / 1_000_000.0,
            }

        off = pair["off"]
        on = pair["state_on"]
        samples.append(
            {
                "sample": index,
                "order": "ON,OFF" if state_on_first else "OFF,ON",
                "semanticIdentical": on["content"] == off["content"]
                and on["generatedTokens"] == off["generatedTokens"],
                "off": off,
                "stateOn": on,
                "pairedClientDeltaMs": on["clientWallMs"] - off["clientWallMs"],
                "pairedPredictedDeltaMs": (
                    on["serverTimings"]["predicted_ms"]
                    - off["serverTimings"]["predicted_ms"]
                ),
            }
        )

    off_wall = [sample["off"]["clientWallMs"] for sample in samples]
    on_wall = [sample["stateOn"]["clientWallMs"] for sample in samples]
    off_predicted = [
        sample["off"]["serverTimings"]["predicted_ms"] for sample in samples
    ]
    on_predicted = [
        sample["stateOn"]["serverTimings"]["predicted_ms"] for sample in samples
    ]
    state_overhead = [
        sample["stateOn"]["stateOverheadMs"] for sample in samples
    ]
    identical = sum(1 for sample in samples if sample["semanticIdentical"])
    paired_wall = [sample["pairedClientDeltaMs"] for sample in samples]
    paired_wall_abs = [abs(value) for value in paired_wall]
    paired_predicted = [
        sample["pairedPredictedDeltaMs"] for sample in samples
    ]
    paired_predicted_abs = [abs(value) for value in paired_predicted]

    report = {
        "protocolVersion": "RQ3.LLAMA.HOTPATH.AB.V1",
        "boundary": (
            "ORDINARY_GENERATION_NO_FORK / LOCAL_EXECUTION_STATE_BOOKKEEPING "
            "/ SERVER_PAYLOAD_IDENTICAL / NOT_A_UNIVERSAL_PERFORMANCE_CLAIM"
        ),
        "health": health,
        "request": request_payload,
        "promptTokens": prompt_tokens,
        "samplesRequested": args.samples,
        "alternation": "even=ON,OFF odd=OFF,ON",
        "results": {
            "semanticIdentical": identical,
            "semanticIdenticalRatio": identical / len(samples),
            "offClient": summarize(off_wall),
            "stateOnClient": summarize(on_wall),
            "offServerPredicted": summarize(off_predicted),
            "stateOnServerPredicted": summarize(on_predicted),
            "pairedClientDeltaOnMinusOff": summarize(paired_wall),
            "pairedClientAbsoluteDelta": summarize(paired_wall_abs),
            "pairedServerPredictedDeltaOnMinusOff": summarize(paired_predicted),
            "pairedServerPredictedAbsoluteDelta": summarize(paired_predicted_abs),
            "stateOverhead": summarize(state_overhead),
            "stateOverheadVsMeanRequestRatio": (
                statistics.fmean(state_overhead) / statistics.fmean(off_wall)
            ),
            "stateOverheadVsMeanAbsolutePairedDeltaRatio": (
                statistics.fmean(state_overhead) / statistics.fmean(paired_wall_abs)
            ),
            "meanClientOverheadRatio": (
                statistics.fmean(on_wall) / statistics.fmean(off_wall) - 1.0
            ),
            "meanServerPredictedOverheadRatio": (
                statistics.fmean(on_predicted) / statistics.fmean(off_predicted)
                - 1.0
            ),
        },
        "samples": samples,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["results"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
