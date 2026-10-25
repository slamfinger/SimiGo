#!/usr/bin/env python3
"""Run frozen S-B prompts and preserve raw outputs only."""

import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parent
TRACE = pathlib.Path.home() / ".simigo/logs/native_mlx_trace.log"
CONDITIONS = ("S-B0", "S-B1", "S-B2")


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: pathlib.Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def wait_for_new_suspend(start: int, timeout: int = 900) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if TRACE.stat().st_size > start:
            data = TRACE.read_bytes()[start:]
            if b"[LIFECYCLE] suspend_done" in data:
                return
        time.sleep(10)
    raise RuntimeError(f"NativeMLX suspend not observed within {timeout}s")


def main(run_root: pathlib.Path, conditions: tuple[str, ...]) -> int:
    if run_root.exists():
        raise RuntimeError(f"run root already exists: {run_root}")
    if TRACE.read_bytes().rstrip().rsplit(b"\n", 1)[-1].find(b"[LIFECYCLE] suspend_done") < 0:
        raise RuntimeError("NativeMLX must begin suspended")

    run_root.mkdir(parents=True)
    records = []
    baseline_size = TRACE.stat().st_size
    baseline_tail = TRACE.read_bytes()[-512:].decode("utf-8", errors="replace")

    for condition in conditions:
        prompt_path = ROOT / f"{condition}.prompt.txt"
        condition_root = run_root / condition
        condition_root.mkdir()
        prompt = prompt_path.read_text(encoding="utf-8")
        trace_start = TRACE.stat().st_size
        payload = {
            "agent_id": f"simigo-tc-a-{condition.lower().replace('-', '')}",
            "max_tokens": 1024,
            "messages": [{"role": "user", "content": prompt}],
            "model": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX",
            "stream": False,
            "temperature": 0,
        }
        write_json(condition_root / "request.json", payload)
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
            response_json = json.loads(raw)
        except json.JSONDecodeError:
            response_json = {"_raw": raw.decode("utf-8", errors="replace")}
        write_json(condition_root / "response.json", response_json)
        choices = response_json.get("choices") if isinstance(response_json, dict) else None
        content = choices[0].get("message", {}).get("content") if choices else None
        (condition_root / "final-answer.txt").write_text(
            content if isinstance(content, str) else "", encoding="utf-8"
        )
        if status != 200:
            raise RuntimeError(f"{condition}: HTTP {status}")

        pre_suspend_size = TRACE.stat().st_size
        wait_for_new_suspend(pre_suspend_size)
        trace_end = TRACE.stat().st_size
        trace_excerpt = TRACE.read_bytes()[trace_start:trace_end].decode("utf-8", errors="replace")
        isolation_lines = [
            line for line in trace_excerpt.splitlines()
            if any(key in line for key in ("resume_done", "mode=", "poolBind", "poolHit", "suspend_done"))
        ]
        cold = any("mode=cold" in line and "cacheHitTokens=0" in line for line in isolation_lines)
        if not cold:
            raise RuntimeError(f"{condition}: cold-path evidence missing")

        record = {
            "condition": condition,
            "prompt_path": prompt_path.as_posix(),
            "prompt_sha256": sha256(prompt_path),
            "request_path": (condition_root / "request.json").as_posix(),
            "response_path": (condition_root / "response.json").as_posix(),
            "final_answer_path": (condition_root / "final-answer.txt").as_posix(),
            "http_status": status,
            "elapsed_seconds": elapsed,
            "runtime_isolation": {
                "method": "idle_suspend_with_memory_cache_clear",
                "trace_path": TRACE.as_posix(),
                "trace_byte_start": trace_start,
                "trace_byte_end": trace_end,
                "cold_path_observed": cold,
                "isolation_lines": isolation_lines,
            },
        }
        records.append(record)
        print(json.dumps({"condition": condition, "status": status, "cold_path": cold}, ensure_ascii=False))

    write_json(
        run_root / "RUN_RECORD.json",
        {
            "phase": "S_B_RAW_OUTPUTS_ONLY",
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S+08:00"),
            "authorization": "AUTHORIZED CONDITION EXECUTION / RAW OUTPUTS ONLY",
            "observer": "NOT RUN",
            "store": "NOT RUN",
            "interpretation": "NOT PERFORMED",
            "baseline_isolation": {
                "initial_trace_tail": baseline_tail,
                "initial_trace_size": baseline_size,
            },
            "conditions": records,
        },
    )
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("run_root", type=pathlib.Path)
    parser.add_argument(
        "--conditions",
        default=",".join(CONDITIONS),
        help="Comma-separated frozen condition names.",
    )
    args = parser.parse_args()
    main(args.run_root, tuple(args.conditions.split(",")))
