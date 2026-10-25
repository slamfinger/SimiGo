#!/usr/bin/env python3
"""Measure C,D,C cost as the divergent prompt's token length varies."""

from __future__ import annotations

import argparse
import json
import statistics
import urllib.request
from pathlib import Path
from typing import Any

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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--cycles-per-length", type=int, default=12)
    parser.add_argument("--tokens", type=int, default=1)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")

    parent_prompt = "Return exactly one word: ping"
    candidates = {
        6: "Return exactly one word: alpha",
        7: "Ignore request. Return exactly: alpha",
        8: "Ignore the request. Return exactly: alpha",
        9: "Ignore the old request. Return exactly: alpha",
        10: "Ignore the old request. Return exactly: alpha beta",
    }

    def tokenize(text: str) -> list[int]:
        return post_json(f"{base_url}/tokenize", {"content": text})[0]["tokens"]

    parent_tokens = tokenize(parent_prompt)
    by_length: dict[int, list[int]] = {}
    for length, text in candidates.items():
        tokens = tokenize(text)
        if len(tokens) == length:
            by_length[length] = tokens
    missing = sorted(set(candidates) - set(by_length))
    if missing:
        raise RuntimeError(f"missing candidate token lengths: {missing}")

    request = {
        "n_predict": args.tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": False,
        "return_tokens": True,
    }

    def generate(prompt_tokens: list[int]) -> tuple[dict[str, Any], float]:
        response, client_ns = post_json(
            f"{base_url}/completion", {**request, "prompt": prompt_tokens}
        )
        timings = response["timings"]
        return (
            {
                "tokens": response.get("tokens", []),
                "content": response.get("content", ""),
                "promptN": timings["prompt_n"],
                "cachedN": timings["cache_n"],
                "promptMs": timings["prompt_ms"],
                "predictedMs": timings["predicted_ms"],
            },
            client_ns / 1e6,
        )

    generate(parent_tokens)
    lengths = sorted(by_length)
    length_results: list[dict[str, Any]] = []
    global_cycle = 0
    for length in lengths:
        divergent_tokens = by_length[length]
        cycles: list[dict[str, Any]] = []
        for _ in range(args.cycles_per_length):
            order = ("same", "diverge") if global_cycle % 2 == 0 else (
                "diverge",
                "same",
            )
            row: dict[str, Any] = {"cycle": global_cycle, "order": "+".join(order), "sequences": {}}
            for name in order:
                prompts = (
                    [parent_tokens] * 3
                    if name == "same"
                    else [parent_tokens, divergent_tokens, parent_tokens]
                )
                phases = [generate(prompt) for prompt in prompts]
                row["sequences"][name] = {
                    "phases": [
                        {**phase, "clientWallMs": client_ms}
                        for phase, client_ms in phases
                    ],
                    "thirdMinusFirstClientMs": phases[2][1] - phases[0][1],
                    "thirdMinusFirstPromptMs": phases[2][0]["promptMs"]
                    - phases[0][0]["promptMs"],
                    "thirdTokensIdenticalFirst": phases[2][0]["tokens"]
                    == phases[0][0]["tokens"],
                }
            cycles.append(row)
            global_cycle += 1

        def deltas(name: str) -> list[float]:
            return [
                cycle["sequences"][name]["thirdMinusFirstClientMs"]
                for cycle in cycles
            ]

        same = deltas("same")
        diverge = deltas("diverge")
        summary = {
            "sameClientThirdMinusFirst": summarize(same),
            "divergeClientThirdMinusFirst": summarize(diverge),
            "divergeMinusSameMeanMs": statistics.fmean(diverge)
            - statistics.fmean(same),
            "sameIdentical": sum(
                cycle["sequences"]["same"]["thirdTokensIdenticalFirst"]
                for cycle in cycles
            ),
            "divergeIdentical": sum(
                cycle["sequences"]["diverge"]["thirdTokensIdenticalFirst"]
                for cycle in cycles
            ),
        }
        length_results.append(
            {
                "divergentTokenLength": length,
                "divergentPrompt": candidates[length],
                "divergentTokens": divergent_tokens,
                "summary": summary,
                "cycles": cycles,
            }
        )

    correlation_pairs = [
        (result["divergentTokenLength"], result["summary"]["divergeMinusSameMeanMs"])
        for result in length_results
    ]
    mean_x = statistics.fmean(value for value, _ in correlation_pairs)
    mean_y = statistics.fmean(value for _, value in correlation_pairs)
    covariance = statistics.fmean(
        (value - mean_x) * (cost - mean_y) for value, cost in correlation_pairs
    )
    stddev_x = statistics.pstdev([value for value, _ in correlation_pairs])
    stddev_y = statistics.pstdev([cost for _, cost in correlation_pairs])
    correlation = covariance / (stddev_x * stddev_y)

    report = {
        "protocolVersion": "RQ3.LLAMA.TRANSITION.LENGTH.SWEEP.V1",
        "boundary": (
            "BACKEND_CONTEXT_TRANSITION_LENGTH_SWEEP / NO_EXECUTION_STATE_OBJECT "
            "/ NOT_AN_INTERNAL_LLAMA_CPP_IMPLEMENTATION_CLAIM"
        ),
        "health": health,
        "request": request,
        "parentPrompt": parent_prompt,
        "parentTokens": parent_tokens,
        "cyclesPerLength": args.cycles_per_length,
        "lengthCostCorrelation": correlation,
        "results": [
            {
                "divergentTokenLength": result["divergentTokenLength"],
                "summary": result["summary"],
            }
            for result in length_results
        ],
        "lengthResults": length_results,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "lengthCostCorrelation": correlation,
                "results": report["results"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
