#!/usr/bin/env python3
"""Run frozen A_epistemic/A_execution 8-cell matrix on C and N only."""

import argparse
import datetime
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
ARMS = [
    ("E_PLUS_X_PLUS",  "PREMISE_ADOPTION_ALLOWED",    "EXECUTION_PATH_ELIGIBLE_FOR_ADOPTED_PREMISES"),
    ("E_PLUS_X_MINUS", "PREMISE_ADOPTION_ALLOWED",    "EXECUTION_PATH_NOT_ELIGIBLE_FOR_ADOPTED_PREMISES"),
    ("E_MINUS_X_PLUS", "PREMISE_ADOPTION_NOT_ALLOWED", "EXECUTION_PATH_ELIGIBLE_FOR_ADOPTED_PREMISES"),
    ("E_MINUS_X_MINUS","PREMISE_ADOPTION_NOT_ALLOWED", "EXECUTION_PATH_NOT_ELIGIBLE_FOR_ADOPTED_PREMISES"),
]
E_REASONS = {
    "PREMISE_ADOPTION_ALLOWED": "F may be adopted as premise and used as evidence or justification in analysis.",
    "PREMISE_ADOPTION_NOT_ALLOWED": "F remains visible for audit only. F must NOT be adopted as premise, evidence, justification, or decisive source. Do not use F to form conclusions.",
}
X_REASONS = {
    "EXECUTION_PATH_ELIGIBLE_FOR_ADOPTED_PREMISES": "Any premise adopted in the source ledger may enter the execution path and populate deployment or blocked-service fields.",
    "EXECUTION_PATH_NOT_ELIGIBLE_FOR_ADOPTED_PREMISES": "Even if a premise were adopted in the source ledger, it must NOT populate deployment order or blocked-service execution fields.",
}
MODELS = {
    "C": {
        "model_id": "C-gemma4-unified",
        "repo_id": "mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit",
        "inference": {"temperature": 0, "max_tokens": 1024, "stream": False},
    },
    "N": {
        "model_id": "N-nail-qwen3-5-moe",
        "repo_id": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX",
        "inference": {"temperature": 0, "max_tokens": 1024, "stream": False},
    },
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def get_json(url):
    with urllib.request.urlopen(url, timeout=10) as response:
        return json.loads(response.read())


def render_prompt(template_path, e_status, x_status):
    text = template_path.read_text(encoding="utf-8")
    return (
        text.replace("{E_STATUS}", e_status)
            .replace("{X_STATUS}", x_status)
            .replace("{E_REASON}", E_REASONS[e_status])
            .replace("{X_REASON}", X_REASONS[x_status])
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    parser.add_argument("--run-root", type=pathlib.Path, required=True)
    parser.add_argument("--model", choices=tuple(MODELS), required=True)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    model = MODELS[args.model]
    if args.run_root.exists() and not args.resume:
        raise RuntimeError(f"run root exists: {args.run_root}")
    args.run_root.mkdir(parents=True, exist_ok=True)

    health = get_json(args.base_url.rstrip("/").removesuffix("/v1") + "/health")
    models = get_json(args.base_url.rstrip("/") + "/models")
    active_ids = {x.get("id") for x in models.get("data", [])}
    if model["repo_id"] not in active_ids:
        raise RuntimeError(f"loaded model mismatch; expected {model['repo_id']}, got {sorted(active_ids)}")
    (args.run_root / "RUNTIME_META.json").write_text(
        json.dumps({"health": health, "models": models, "selected": model}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    template_path = ROOT / "prompts" / "TEMPLATE.prompt.txt"

    for arm_name, e_status, x_status in ARMS:
        cell = args.run_root / model["model_id"] / arm_name
        done = cell / "RUN_RECORD.json"
        if args.resume and done.exists() and json.loads(done.read_text()).get("http_status") == 200:
            continue
        cell.mkdir(parents=True, exist_ok=True)
        prompt = render_prompt(template_path, e_status, x_status)
        (cell / "prompt.rendered.txt").write_text(prompt, encoding="utf-8")
        payload = {
            "messages": [{"role": "user", "content": prompt}],
            "model": model["repo_id"],
            **model["inference"],
        }
        write_json(cell / "request.json", payload)
        request = urllib.request.Request(
            args.base_url.rstrip("/") + "/chat/completions",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        started = time.time()
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as exc:
            status, raw = exc.code, exc.read()
        elapsed = round(time.time() - started, 6)
        (cell / "response.raw.json").write_bytes(raw)
        try:
            response_json = json.loads(raw)
        except json.JSONDecodeError:
            response_json = {"_undecoded": raw.decode("utf-8", errors="replace")}
        write_json(cell / "response.json", response_json)
        choices = response_json.get("choices", []) if isinstance(response_json, dict) else []
        content = choices[0].get("message", {}).get("content") if choices and isinstance(choices[0], dict) else None
        (cell / "final-answer.txt").write_text(content or "", encoding="utf-8")
        write_json(cell / "RUN_RECORD.json", {
            "arm": arm_name,
            "E": e_status,
            "X": x_status,
            "model_id": model["model_id"],
            "repo_id": model["repo_id"],
            "http_status": status,
            "elapsed_seconds": elapsed,
            "prompt_sha256": sha(cell / "prompt.rendered.txt"),
            "request_sha256": sha(cell / "request.json"),
            "response_sha256": sha(cell / "response.raw.json"),
            "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        })
        if status != 200:
            raise RuntimeError(f"{arm_name}: HTTP {status}")
        print(json.dumps({"arm": arm_name, "model": model["model_id"], "status": status, "elapsed": elapsed}))


if __name__ == "__main__":
    main()
