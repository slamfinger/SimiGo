#!/usr/bin/env python3
"""Resume only the three remaining Round-1 RD9 conditions at 180s intervals."""

import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
TRACE = pathlib.Path.home() / ".simigo/logs/native_mlx_trace.log"
RUN_ROOT = ROOT.parents[1] / "runs/20261004-210000-round1"
CONDITIONS = (
    "RD9-TOOL-PRESENT",
    "RD9-TOOL-ABSENT",
    "RD9-TOOL-SUMMARY",
)
INTERVAL_SECONDS = 180


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: pathlib.Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def post_prompt(condition: str, prompt: str):
    payload = {
        "agent_id": "simigo-tc-a-" + condition.lower().replace("-", ""),
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}],
        "model": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX",
        "stream": False,
        "temperature": 0,
    }
    request = urllib.request.Request(
        "http://127.0.0.1:8000/v1/chat/completions",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            status = response.status
            raw = response.read()
    except urllib.error.HTTPError as exc:
        status = exc.code
        raw = exc.read()
    elapsed = round(time.time() - started, 6)
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = {"_raw": raw.decode("utf-8", errors="replace")}
    return status, parsed, elapsed


def main():
    if TRACE.stat().st_size == 0:
        raise RuntimeError("Runtime trace is empty")
    # Refuse to run if another RD9 resume already created output.
    for condition in CONDITIONS:
        if (RUN_ROOT / condition).exists():
            raise RuntimeError(f"condition output already exists: {condition}")

    records = []
    baseline_size = TRACE.stat().st_size
    baseline_tail = TRACE.read_bytes()[-1024:].decode("utf-8", errors="replace")

    for index, condition in enumerate(CONDITIONS):
        prompt_path = ROOT / f"{condition}.prompt.txt"
        condition_root = RUN_ROOT / condition
        condition_root.mkdir(parents=True)
        prompt = prompt_path.read_text(encoding="utf-8")
        trace_start = TRACE.stat().st_size
        status, response_json, elapsed = post_prompt(condition, prompt)
        write_json(condition_root / "request.json", {
            "agent_id": "simigo-tc-a-" + condition.lower().replace("-", ""),
            "max_tokens": 1024,
            "messages": [{"role": "user", "content": prompt}],
            "model": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX",
            "stream": False,
            "temperature": 0,
        })
        write_json(condition_root / "response.json", response_json)
        choices = response_json.get("choices") if isinstance(response_json, dict) else None
        content = choices[0].get("message", {}).get("content") if choices else None
        (condition_root / "final-answer.txt").write_text(
            content if isinstance(content, str) else "", encoding="utf-8"
        )
        if status != 200:
            raise RuntimeError(f"{condition}: HTTP {status}")

        # For every condition except the last, wait exactly the newly authorized interval.
        if index + 1 < len(CONDITIONS):
            time.sleep(INTERVAL_SECONDS)

        trace_end = TRACE.stat().st_size
        excerpt = TRACE.read_bytes()[trace_start:trace_end].decode("utf-8", errors="replace")
        isolation_lines = [
            line for line in excerpt.splitlines()
            if any(key in line for key in ("STATE_TRANSITION", "mode=", "poolBind", "poolHit", "RELEASED"))
        ]
        cold = any(
            "mode=cold" in line and "cacheHitTokens=0" in line and "reuse=false" in line
            for line in isolation_lines
        )
        reused = any(("poolHit" in line or "poolBind" in line) for line in isolation_lines)
        if not cold or reused:
            raise RuntimeError(f"{condition}: cold-path assertion failed; reused={reused}")

        records.append({
            "condition": condition,
            "prompt_path": prompt_path.as_posix(),
            "prompt_sha256": sha256(prompt_path),
            "http_status": status,
            "elapsed_seconds": elapsed,
            "isolation": {
                "method": "180s_inter_condition_interval_with_cold_path_assertion",
                "interval_before_next_seconds": INTERVAL_SECONDS if index + 1 < len(CONDITIONS) else 0,
                "trace_byte_start": trace_start,
                "trace_byte_end": trace_end,
                "cold_path_observed": cold,
                "cache_reuse_observed": reused,
                "isolation_lines": isolation_lines,
            },
        })
        print(json.dumps({
            "condition": condition,
            "status": status,
            "cold_path": cold,
            "cache_reuse": reused,
        }, ensure_ascii=False), flush=True)

    write_json(RUN_ROOT / "resume-record.json", {
        "phase": "ROUND1_RD9_RESUME_COMPLETE",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S+08:00"),
        "authorization": "RESUME REMAINING 3 RD9 CONDITIONS / 180S INTERVAL",
        "baseline_trace_size": baseline_size,
        "baseline_trace_tail": baseline_tail,
        "observer": "NOT RUN",
        "store": "NOT RUN",
        "interpretation": "NOT PERFORMED",
        "conditions": records,
    })


if __name__ == "__main__":
    main()
