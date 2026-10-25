#!/usr/bin/env python3
"""Isolate the fork/restore client delta as a backend context-sequence effect.

No Execution State object participates. Each cycle compares two three-request
backend sequences:

  same     C,C,C
  diverge  C,D,C

Alternating cycle order controls slow drift. If the divergent sequence has a
positive third-minus-first delta while the same-prefix sequence does not, the
effect belongs to backend context switching rather than local fork/restore
bookkeeping.
"""

from __future__ import annotations

import argparse
import http.client
import json
import statistics
import time
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
    parser.add_argument("--cycles", type=int, default=20)
    parser.add_argument("--tokens", type=int, default=8)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--divergent-prompt",
        default="Ignore the old request. Return exactly: alpha beta",
    )
    parser.add_argument("--cache-prompt", action="store_true")
    parser.add_argument(
        "--server-cache-disabled",
        action="store_true",
        help="record that llama-server was launched with --no-cache-prompt",
    )
    parser.add_argument(
        "--slot-similarity-disabled",
        action="store_true",
        help="record that llama-server was launched with --slot-prompt-similarity=0",
    )
    parser.add_argument(
        "--reuse-connection",
        action="store_true",
        help="send /completion requests on one HTTP keep-alive connection",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}"
    with urllib.request.urlopen(f"{base_url}/health", timeout=10) as response:
        health = json.loads(response.read())
    if health.get("status") != "ok":
        raise RuntimeError(f"llama-server not healthy: {health}")

    parent_prompt = "Return exactly one word: ping"
    divergent_prompt = args.divergent_prompt
    parent_tokens = post_json(
        f"{base_url}/tokenize", {"content": parent_prompt}
    )[0]["tokens"]
    divergent_tokens = post_json(
        f"{base_url}/tokenize", {"content": divergent_prompt}
    )[0]["tokens"]
    request = {
        "n_predict": args.tokens,
        "temperature": 0.0,
        "seed": args.seed,
        "cache_prompt": args.cache_prompt,
        "return_tokens": True,
    }

    keep_alive_connection = (
        http.client.HTTPConnection(args.host, args.port, timeout=120)
        if args.reuse_connection
        else None
    )

    def post_completion(payload: dict[str, Any]) -> tuple[dict[str, Any], float]:
        if keep_alive_connection is None:
            return post_json(f"{base_url}/completion", payload)
        body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
        started = time.perf_counter_ns()
        keep_alive_connection.request(
            "POST",
            "/completion",
            body=body,
            headers={"Content-Type": "application/json"},
        )
        response = keep_alive_connection.getresponse()
        decoded = json.loads(response.read())
        return decoded, time.perf_counter_ns() - started

    def generate(prompt_tokens: list[int]) -> dict[str, Any]:
        response, client_ns = post_completion(
            {**request, "prompt": prompt_tokens}
        )
        timings = response["timings"]
        return {
            "content": response.get("content", ""),
            "tokens": response.get("tokens", []),
            "clientWallMs": client_ns / 1e6,
            "promptN": timings["prompt_n"],
            "cachedN": timings["cache_n"],
            "promptMs": timings["prompt_ms"],
            "predictedMs": timings["predicted_ms"],
        }

    # Warm model and graph compilation; the warm request is not recorded.
    generate(parent_tokens)
    cycles: list[dict[str, Any]] = []
    for index in range(args.cycles):
        order = ("same", "diverge") if index % 2 == 0 else ("diverge", "same")
        row: dict[str, Any] = {
            "cycle": index,
            "order": "+".join(order),
            "sequences": {},
        }
        for name in order:
            prompts = {
                "same": [parent_tokens] * 3,
                "diverge": [parent_tokens, divergent_tokens, parent_tokens],
            }[name]
            phases = [generate(prompt) for prompt in prompts]
            row["sequences"][name] = {
                "phases": phases,
                "thirdMinusFirstClientMs": phases[2]["clientWallMs"]
                - phases[0]["clientWallMs"],
                "thirdMinusFirstPredictedMs": phases[2]["predictedMs"]
                - phases[0]["predictedMs"],
                "thirdMinusFirstPromptMs": phases[2]["promptMs"]
                - phases[0]["promptMs"],
                "thirdTokensIdenticalFirst": phases[2]["tokens"]
                == phases[0]["tokens"],
            }
        cycles.append(row)

    def deltas(sequence: str, field: str) -> list[float]:
        return [
            cycle["sequences"][sequence][field]
            for cycle in cycles
        ]

    summary: dict[str, Any] = {
        "sameClientThirdMinusFirst": summarize(
            deltas("same", "thirdMinusFirstClientMs")
        ),
        "divergeClientThirdMinusFirst": summarize(
            deltas("diverge", "thirdMinusFirstClientMs")
        ),
        "samePredictedThirdMinusFirst": summarize(
            deltas("same", "thirdMinusFirstPredictedMs")
        ),
        "divergePredictedThirdMinusFirst": summarize(
            deltas("diverge", "thirdMinusFirstPredictedMs")
        ),
        "samePromptThirdMinusFirst": summarize(
            deltas("same", "thirdMinusFirstPromptMs")
        ),
        "divergePromptThirdMinusFirst": summarize(
            deltas("diverge", "thirdMinusFirstPromptMs")
        ),
    }
    summary["divergeMinusSameClientDeltaMeanMs"] = summary[
        "divergeClientThirdMinusFirst"
    ]["meanMs"] - summary["sameClientThirdMinusFirst"]["meanMs"]
    summary["sameThirdTokensIdenticalFirst"] = sum(
        cycle["sequences"]["same"]["thirdTokensIdenticalFirst"]
        for cycle in cycles
    )
    summary["divergeThirdTokensIdenticalFirst"] = sum(
        cycle["sequences"]["diverge"]["thirdTokensIdenticalFirst"]
        for cycle in cycles
    )

    report = {
        "protocolVersion": "RQ3.LLAMA.CONTEXT.CONTROLS.V1",
        "boundary": (
            "BACKEND_CONTEXT_SEQUENCE_CONTROL / NO_EXECUTION_STATE_OBJECT "
            "/ NOT_A_UNIVERSAL_PERFORMANCE_CLAIM"
        ),
        "health": health,
        "request": request,
        "transport": "http-keep-alive" if args.reuse_connection else "new-connection-per-request",
        "serverCacheDisabled": args.server_cache_disabled,
        "slotSimilarityDisabled": args.slot_similarity_disabled,
        "prompts": {
            "parent": parent_prompt,
            "divergent": divergent_prompt,
            "parentTokens": parent_tokens,
            "divergentTokens": divergent_tokens,
        },
        "cyclesRequested": args.cycles,
        "sequenceDefinitions": {
            "same": "C,C,C",
            "diverge": "C,D,C",
        },
        "summary": summary,
        "cycles": cycles,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
