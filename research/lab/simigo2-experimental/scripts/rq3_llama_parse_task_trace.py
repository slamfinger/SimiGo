#!/usr/bin/env python3
"""Parse a llama-server control log into task and context-transition costs."""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path
from typing import Any


LAUNCH = re.compile(
    r"^([0-9.]+) I slot launch_slot_: id  0 \| task (\d+) "
)
RELEASE = re.compile(
    r"^([0-9.]+) I slot\s+release: id  0 \| task (\d+) "
)
PROMPT = re.compile(
    r"^([0-9.]+) I slot print_timing: id  0 \| task (\d+) \| "
    r"prompt eval time =\s+([0-9.]+) ms /\s+(\d+) tokens"
)


def parse_timestamp(value: str) -> float:
    minutes, rest = value.split(".", 1)
    seconds, milliseconds, microseconds = rest.split(".")
    return (
        int(minutes) * 60
        + int(seconds)
        + int(milliseconds) / 1000
        + int(microseconds) / 1_000_000
    )


def summarize(values: list[float]) -> dict[str, float]:
    return {
        "n": float(len(values)),
        "meanMs": statistics.fmean(values),
        "medianMs": statistics.median(values),
        "minMs": min(values),
        "maxMs": max(values),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--control", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    launch: dict[int, float] = {}
    release: dict[int, float] = {}
    prompt: dict[int, dict[str, float]] = {}
    for line in Path(args.log).read_text().splitlines():
        match = LAUNCH.match(line)
        if match:
            launch[int(match.group(2))] = parse_timestamp(match.group(1))
            continue
        match = RELEASE.match(line)
        if match:
            release[int(match.group(2))] = parse_timestamp(match.group(1))
            continue
        match = PROMPT.match(line)
        if match:
            prompt[int(match.group(2))] = {
                "serverPromptMs": float(match.group(3)),
                "promptTokens": int(match.group(4)),
            }

    task_ids = sorted(set(launch) & set(release) & set(prompt))
    tasks: list[dict[str, Any]] = []
    for task_id in task_ids:
        tasks.append(
            {
                "taskID": task_id,
                "launchAtSec": launch[task_id],
                "releaseAtSec": release[task_id],
                "serverTaskMs": (release[task_id] - launch[task_id]) * 1000,
                **prompt[task_id],
            }
        )

    transitions: list[dict[str, Any]] = []
    by_tokens: dict[str, list[float]] = {}
    for previous, current in zip(tasks, tasks[1:]):
        delay_ms = (
            launch[current["taskID"]] - release[previous["taskID"]]
        ) * 1000
        row = {
            "previousTaskID": previous["taskID"],
            "currentTaskID": current["taskID"],
            "previousPromptTokens": previous["promptTokens"],
            "currentPromptTokens": current["promptTokens"],
            "transition": (
                f"{previous['promptTokens']}->{current['promptTokens']}"
            ),
            "releaseToLaunchMs": delay_ms,
        }
        transitions.append(row)
        by_tokens.setdefault(row["transition"], []).append(delay_ms)

    control = json.loads(Path(args.control).read_text())
    request_count = 1 + control["cyclesRequested"] * 6
    if len(tasks) != request_count:
        raise RuntimeError(f"expected {request_count} tasks, found {len(tasks)}")

    expected_orders: list[str] = []
    for index in range(control["cyclesRequested"]):
        order = ("same", "diverge") if index % 2 == 0 else ("diverge", "same")
        expected_orders.extend([order[0]] * 3 + [order[1]] * 3)
    observed_token_counts = [task["promptTokens"] for task in tasks[1:]]
    sequence_match = True
    offset = 0
    for index in range(control["cyclesRequested"]):
        order = ("same", "diverge") if index % 2 == 0 else ("diverge", "same")
        for name in order:
            lengths = (
                [6, 6, 6]
                if name == "same"
                else [6, len(control["prompts"]["divergentTokens"]), 6]
            )
            if observed_token_counts[offset : offset + 3] != lengths:
                sequence_match = False
            offset += 3

    report = {
        "protocolVersion": "RQ3.LLAMA.SERVER.TRACE.PARSE.V1",
        "boundary": (
            "SERVER_LOG_TASK_AND_TRANSITION_TIMING / CORRELATION_ONLY "
            "/ NOT_AN_INTERNAL_LLAMA_CPP_IMPLEMENTATION_CLAIM"
        ),
        "control": args.control,
        "log": args.log,
        "expectedRequestCount": request_count,
        "observedRequestCount": len(tasks),
        "sequenceMatch": sequence_match,
        "transitionSummaryMs": {
            name: summarize(values) for name, values in sorted(by_tokens.items())
        },
        "tasks": tasks,
        "transitions": transitions,
        "expectedOrders": expected_orders,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "sequenceMatch": sequence_match,
                "transitionSummaryMs": report["transitionSummaryMs"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
