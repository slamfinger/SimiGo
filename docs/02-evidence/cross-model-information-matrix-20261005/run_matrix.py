#!/usr/bin/env python3
"""Run the frozen cross-model sample matrix; no 846 mapping and no R-D battery."""

import argparse
import datetime
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def endpoint_models(base_url):
    request = urllib.request.Request(base_url.rstrip("/") + "/models", method="GET")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read())


def render_prompt(sample, contract, repo_root):
    blocks = [
        "You must use only the supplied material. Do not use outside knowledge, tools, or prior reports.",
        sample["task"],
        "Return exactly one strict JSON object with these keys: "
        "task_id, decision, findings, missing_or_uncertain, confidence. "
        "No markdown fence and no prose.",
        "The findings array must contain no more than "
        f"{contract['max_findings']} items; each item has id, statement, evidence, function.",
        "Allowed function values: constraint, decision, evidence, relation, uncertainty, task_rule.",
    ]
    for item in sample["input_files"]:
        path = repo_root / item["path"]
        actual = sha(path)
        if actual != item["sha256"]:
            raise RuntimeError(f"sample freeze mismatch: {item['path']}")
        text = path.read_text(encoding="utf-8", errors="replace")
        blocks.append(f"=== INPUT {item['path']} ===\n{text}")
    return "\n\n".join(blocks) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path,
                       default=pathlib.Path("/Users/mr.simi/Documents/SimiGo-Lab"))
    parser.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    parser.add_argument("--run-root", type=pathlib.Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--render-only", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--models", nargs="*", help="model_id filters")
    parser.add_argument("--samples", nargs="*", help="sample_id filters")
    args = parser.parse_args()

    samples = load(ROOT / "freeze/samples.json")
    models = load(ROOT / "freeze/models.json")
    selected_samples = [s for s in samples["samples"] if not args.samples or s["sample_id"] in args.samples]
    selected_models = [m for m in models["models"] if not args.models or m["model_id"] in args.models]
    if args.check_only:
        for s in selected_samples:
            for item in s["input_files"]:
                path = args.repo_root / item["path"]
                assert path.stat().st_size == item["bytes"], item["path"]
                assert sha(path) == item["sha256"], item["path"]
        assert len(selected_samples) * len(selected_models) == 16 or args.samples or args.models
        print(f"OK {len(selected_samples)} samples x {len(selected_models)} models")
        return

    if args.render_only:
        for sample in selected_samples:
            prompt = render_prompt(sample, samples["common_output_contract"], args.repo_root)
            path = ROOT / "prompts" / f"{sample['sample_id']}.prompt.txt"
            path.write_text(prompt, encoding="utf-8")
            print(f"{sample['sample_id']} {len(prompt.encode('utf-8'))} bytes {path}")
        return

    if not args.run_root:
        raise RuntimeError("--run-root is required for execution")
    if args.run_root.exists() and not args.resume:
        raise RuntimeError(f"run root already exists: {args.run_root}; use --resume only after human review")
    args.run_root.mkdir(parents=True, exist_ok=True)
    records = []
    for sample in selected_samples:
        prompt = render_prompt(sample, samples["common_output_contract"], args.repo_root)
        for model in selected_models:
            active = endpoint_models(args.base_url)
            (args.run_root / f"models-endpoint-{model['model_id']}.json").write_text(
                json.dumps(active, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            active_ids = {item.get("id") for item in active.get("data", [])}
            if model["repo_id"] not in active_ids:
                raise RuntimeError(f"loaded model mismatch; expected {model['repo_id']}, got {sorted(active_ids)}")
            cell = args.run_root / sample["sample_id"] / model["model_id"]
            done = cell / "RUN_RECORD.json"
            if args.resume and done.exists():
                prior = load(done)
                if prior.get("http_status") == 200:
                    records.append(prior)
                    continue
            cell.mkdir(parents=True, exist_ok=True)
            prompt_path = cell / "prompt.txt"
            prompt_path.write_text(prompt, encoding="utf-8")
            payload = {
                "model": model["repo_id"],
                "messages": [{"role": "user", "content": prompt}],
                **model["inference_config"],
            }
            write(cell / "request.json", payload)
            request = urllib.request.Request(
                args.base_url.rstrip("/") + "/chat/completions",
                data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            started = time.time()
            try:
                with urllib.request.urlopen(request, timeout=900) as response:
                    status, raw = response.status, response.read()
            except urllib.error.HTTPError as exc:
                status, raw = exc.code, exc.read()
            elapsed = round(time.time() - started, 6)
            (cell / "response.raw.json").write_bytes(raw)
            try:
                response_json = json.loads(raw)
            except json.JSONDecodeError:
                response_json = {"_undecoded": raw.decode("utf-8", errors="replace")}
            write(cell / "response.json", response_json)
            choices = response_json.get("choices", []) if isinstance(response_json, dict) else []
            content = None
            if choices and isinstance(choices[0], dict):
                content = choices[0].get("message", {}).get("content")
            (cell / "final-answer.txt").write_text(content or "", encoding="utf-8")
            record = {
                "sample_id": sample["sample_id"],
                "model_id": model["model_id"],
                "repo_id": model["repo_id"],
                "architecture": model["architecture"],
                "http_status": status,
                "elapsed_seconds": elapsed,
                "prompt_sha256": sha(prompt_path),
                "request_sha256": sha(cell / "request.json"),
                "response_sha256": sha(cell / "response.raw.json"),
                "runtime_backend": model["runtime_backend"],
                "active_endpoint_models": sorted(active_ids),
                "runtime_isolation": "NOT ENFORCED BY THIS RUNNER",
                "created_at": datetime.datetime.now().astimezone().isoformat(),
            }
            write(cell / "RUN_RECORD.json", record)
            records.append(record)
            if status != 200:
                raise RuntimeError(f"{sample['sample_id']} x {model['model_id']}: HTTP {status}")
    write(args.run_root / "RUN_RECORD.json", {
        "phase": "CROSS_MODEL_RAW_OUTPUTS_ONLY",
        "cells": records,
        "normalization": "NOT PERFORMED",
        "stability": "NOT PERFORMED",
        "mapping_to_846": "NOT PERFORMED",
    })


if __name__ == "__main__":
    main()
