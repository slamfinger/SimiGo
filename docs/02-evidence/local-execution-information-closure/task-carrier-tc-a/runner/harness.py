#!/usr/bin/env python3
"""Offline-controllable runner for the frozen TC-A closure package.

This harness does not modify SimiGo Runtime, InformationCore, RelationCore,
or any schema.  It only prepares artifacts, calls the already-existing SimiGo
Chat Completions endpoint when explicitly requested, executes the two frozen
task tools, and records evidence.

Authorized preparation:
    verify-package
    prepare

Not authorized by this file alone:
    run-a      (starts Local MLX Execution A)
    observer   (selects residue and stores through InformationCore)
    mark-isolated
    run-b      (starts fresh Local MLX Execution B)
    evaluate
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import pathlib
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from typing import Any, Callable

UTC = dt.timezone.utc


def utc_now() -> str:
    return dt.datetime.now(UTC).isoformat()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


@dataclasses.dataclass
class Settings:
    package_root: pathlib.Path
    run_root: pathlib.Path
    endpoint: str
    model: str
    agent_prefix: str
    t4ctl: pathlib.Path
    sealed_information_db: pathlib.Path
    isolation_method: str = ""
    isolation_evidence: str = ""


class HarnessError(RuntimeError):
    pass


def atomic_json(path: pathlib.Path, value: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    write_json(tmp, value)
    tmp.replace(path)


def http_chat(endpoint: str, payload: dict[str, Any], timeout: int = 300) -> tuple[int, dict[str, str], dict[str, Any]]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            headers = {k.lower(): v for k, v in response.headers.items()}
            raw = response.read()
    except urllib.error.HTTPError as exc:
        status = exc.code
        headers = {k.lower(): v for k, v in exc.headers.items()}
        raw = exc.read()
    elapsed = time.time() - started
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = {"_raw": raw.decode("utf-8", errors="replace")}
    parsed.setdefault("_transport", {})
    parsed["_transport"]["status"] = status
    parsed["_transport"]["elapsed_seconds"] = round(elapsed, 6)
    parsed["_transport"]["response_headers"] = headers
    return status, headers, parsed


def read_state(run_root: pathlib.Path) -> dict[str, Any]:
    return load_json(run_root / "state.json")


def save_state(run_root: pathlib.Path, state: dict[str, Any]) -> None:
    atomic_json(run_root / "state.json", state)


def require_phase(state: dict[str, Any], phase: str) -> None:
    if state.get("phase") != phase:
        raise HarnessError(f"state phase must be {phase!r}, got {state.get('phase')!r}")


def require_true(state: dict[str, Any], key: str) -> None:
    if state.get(key) is not True:
        raise HarnessError(f"required state flag is not true: {key}")


def tool_schema(name: str, description: str, properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required,
            },
        },
    }


READ_FILE_SCHEMA = tool_schema(
    "read_file",
    "Read a UTF-8 text file inside the task workspace using a relative path.",
    {"path": {"type": "string"}},
    ["path"],
)

FETCH_SCHEMA = tool_schema(
    "fetch_stored_information",
    "Fetch Stored Information by the exact identity supplied in this instruction.",
    {"identity": {"type": "string"}},
    ["identity"],
)


def execute_read_file(workspace: pathlib.Path, args: dict[str, Any]) -> dict[str, Any]:
    requested = args.get("path")
    if not isinstance(requested, str) or not requested:
        return {"ok": False, "error": "path must be a nonempty relative string"}
    root = workspace.resolve()
    target = (root / requested).resolve()
    try:
        relative = target.relative_to(root)
    except ValueError:
        return {"ok": False, "error": "path is outside the task workspace"}
    if not target.is_file():
        return {"ok": False, "error": "path is not a regular file"}
    return {
        "ok": True,
        "path": relative.as_posix(),
        "content": target.read_text(encoding="utf-8"),
    }


def execute_fetch(
    run_root: pathlib.Path,
    t4ctl: pathlib.Path,
    db_path: pathlib.Path,
    expected_identity: str,
    args: dict[str, Any],
    turn: int,
) -> dict[str, Any]:
    identity = args.get("identity")
    if not isinstance(identity, str) or not identity:
        return {"ok": False, "error": "identity must be a nonempty string"}
    if identity != expected_identity:
        return {"ok": False, "error": "identity does not match the observer-supplied identity"}

    output = run_root / "b" / f"fetched-{turn:02d}.txt"
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    completed = subprocess.run(
        [
            str(t4ctl),
            "fetch",
            "--db",
            str(db_path),
            "--identity",
            identity,
            "--out",
            str(output),
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    evidence = {
        "ok": completed.returncode == 0 and output.is_file(),
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "identity": identity,
        "output_path": output.as_posix(),
    }
    if evidence["ok"]:
        evidence["content"] = output.read_text(encoding="utf-8")
    else:
        evidence["content"] = None
    return evidence


def chat_turn(
    settings: Settings,
    phase: str,
    turn: int,
    messages: list[dict[str, Any]],
    tools: list[dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, Any]]:
    payload = {
        "model": settings.model,
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto",
        "temperature": 0,
        "max_tokens": 1024,
        "stream": False,
    }
    status, headers, parsed = http_chat(settings.endpoint, payload)
    request_id = headers.get("x-request-id") or headers.get("X-Request-Id") or f"{phase}-{turn:02d}"
    artifact = {
        "phase": phase,
        "turn": turn,
        "utc_start": utc_now(),
        "endpoint": settings.endpoint,
        "model": settings.model,
        "request": payload,
        "status": status,
        "response_headers": headers,
        "response": parsed,
    }
    atomic_json(settings.run_root / phase / f"turn-{turn:02d}.json", artifact)
    choice = parsed.get("choices", [{}])[0] if parsed.get("choices") else {}
    message = choice.get("message", {})
    return message, artifact


def extract_final(message: dict[str, Any]) -> str:
    content = message.get("content")
    return content if isinstance(content, str) else ""


def cmd_verify_package(settings: Settings, _args: argparse.Namespace) -> int:
    manifest_path = settings.package_root / "MANIFEST.sha256"
    expected: dict[str, str] = {}
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, relative = line.split(maxsplit=1)
        expected[relative] = digest.lower()
    failures: list[str] = []
    actual_files = set()
    for relative, digest in expected.items():
        path = settings.package_root / relative
        if not path.is_file():
            failures.append(f"missing: {relative}")
            continue
        actual_files.add(path.resolve())
        if sha256_file(path) != digest:
            failures.append(f"hash mismatch: {relative}")
    for path in settings.package_root.rglob("*"):
        if not path.is_file() or path == manifest_path:
            continue
        if path.resolve() not in actual_files:
            failures.append(f"not in manifest: {path.relative_to(settings.package_root)}")
    result = {
        "manifest": manifest_path.as_posix(),
        "expected_entries": len(expected),
        "failures": failures,
        "ok": not failures,
        "checked_at": utc_now(),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 2


def cmd_prepare(settings: Settings, _args: argparse.Namespace) -> int:
    if settings.run_root.exists():
        raise HarnessError(f"run root already exists: {settings.run_root}")
    settings.run_root.mkdir(parents=True)

    instructions = settings.package_root / "instructions"
    a_instruction = (instructions / "execution-a.md").read_text(encoding="utf-8")
    b_template = (instructions / "execution-b-template.md").read_text(encoding="utf-8")

    workspace = settings.run_root / "workspace"
    workspace.mkdir()
    source_dir = settings.package_root / "sources"
    copied_sources: dict[str, str] = {}
    for source in sorted(source_dir.glob("*.json")):
        shutil.copy2(source, workspace / source.name)
        copied_sources[source.name] = sha256_file(source)

    sealed_hash = sha256_file(settings.sealed_information_db)
    info_copy = settings.run_root / "information-copy.sqlite"
    shutil.copy2(settings.sealed_information_db, info_copy)

    state = {
        "phase": "PREPARED",
        "created_at": utc_now(),
        "endpoint": settings.endpoint,
        "model": settings.model,
        "agent_prefix": settings.agent_prefix,
        "t4ctl": str(settings.t4ctl),
        "package_root": settings.package_root.as_posix(),
        "workspace": workspace.as_posix(),
        "information_copy": info_copy.as_posix(),
        "sealed_information_db": settings.sealed_information_db.as_posix(),
        "sealed_information_sha256": sealed_hash,
        "information_copy_sha256": sha256_file(info_copy),
        "source_sha256": copied_sources,
        "a_instruction_sha256": sha256_file(instructions / "execution-a.md"),
        "b_template_sha256": sha256_file(instructions / "execution-b-template.md"),
        "execution_a_started": False,
        "observer_completed": False,
        "runtime_isolated": False,
        "execution_b_started": False,
    }
    (workspace / "execution-a.md").write_text(a_instruction, encoding="utf-8")
    (workspace / "execution-b-template.md").write_text(b_template, encoding="utf-8")
    save_state(settings.run_root, state)
    print(json.dumps({"phase": state["phase"], "run_root": settings.run_root.as_posix()}, ensure_ascii=False, indent=2))
    return 0


def cmd_run_a(settings: Settings, _args: argparse.Namespace) -> int:
    state = read_state(settings.run_root)
    require_phase(state, "PREPARED")
    if state.get("execution_a_started"):
        raise HarnessError("Execution A has already started")

    workspace = pathlib.Path(state["workspace"])
    instruction = (workspace / "execution-a.md").read_text(encoding="utf-8")
    messages = [{"role": "user", "content": instruction}]
    final = ""
    tool_calls_total = 0

    for turn in range(1, 7):
        message, _ = chat_turn(settings, "a", turn, messages, [READ_FILE_SCHEMA])
        messages.append(message)
        calls = message.get("tool_calls") or []
        tool_calls_total += len(calls)
        final = extract_final(message)
        if not calls:
            break
        for call in calls:
            function = call.get("function", {})
            name = function.get("name")
            raw_args = function.get("arguments") or "{}"
            try:
                args = json.loads(raw_args)
            except json.JSONDecodeError:
                args = {}
            if name != "read_file":
                result = {"ok": False, "error": "unknown tool"}
            else:
                result = execute_read_file(workspace, args)
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call.get("id"),
                    "content": json.dumps(result, ensure_ascii=False),
                }
            )
    else:
        raise HarnessError("Execution A did not stop within six turns")

    state.update(
        {
            "phase": "A_COMPLETE",
            "execution_a_started": True,
            "execution_a_tool_calls": tool_calls_total,
            "execution_a_final_answer": final,
        }
    )
    atomic_json(settings.run_root / "a" / "final-answer.txt", final)
    save_state(settings.run_root, state)
    print(json.dumps({"phase": state["phase"], "tool_calls": tool_calls_total}, ensure_ascii=False, indent=2))
    return 0


def cmd_observer(settings: Settings, args: argparse.Namespace) -> int:
    state = read_state(settings.run_root)
    require_phase(state, "A_COMPLETE")
    require_true(state, "execution_a_started")

    final = state.get("execution_a_final_answer")
    if not isinstance(final, str) or not final.strip():
        write_json(settings.run_root / "observer" / "reading.json", {"reading": "R-A0", "reason": "no final answer"})
        raise HarnessError("R-A0: no suitable final answer")

    try:
        parsed = json.loads(final)
    except json.JSONDecodeError as exc:
        write_json(settings.run_root / "observer" / "reading.json", {"reading": "R-A1", "reason": f"invalid JSON: {exc}"})
        raise HarnessError("R-A1: Candidate Information is not valid JSON") from exc

    services = parsed.get("services")
    pairs = parsed.get("pairs")
    if not isinstance(services, list) or not isinstance(pairs, list):
        write_json(settings.run_root / "observer" / "reading.json", {"reading": "R-A1", "reason": "missing services or pairs"})
        raise HarnessError("R-A1: Candidate Information is structurally incomplete")

    service_ids = [item.get("service_id") for item in services if isinstance(item, dict)]
    if service_ids != ["alpha", "beta", "gamma"]:
        write_json(settings.run_root / "observer" / "reading.json", {"reading": "R-A1", "reason": "service records incomplete"})
        raise HarnessError("R-A1: service records incomplete")
    pair_keys = [(item.get("left"), item.get("right")) for item in pairs if isinstance(item, dict)]
    if pair_keys != [("alpha", "beta"), ("alpha", "gamma"), ("beta", "gamma")]:
        write_json(settings.run_root / "observer" / "reading.json", {"reading": "R-A1", "reason": "pair records incomplete"})
        raise HarnessError("R-A1: pair records incomplete")

    candidate_dir = settings.run_root / "observer"
    candidate = candidate_dir / "candidate-information.json"
    candidate.write_text(final, encoding="utf-8")
    candidate_hash = sha256_file(candidate)

    db_path = pathlib.Path(state["information_copy"])
    before_hash = sha256_file(db_path)
    completed = subprocess.run(
        [
            str(settings.t4ctl),
            "store",
            "--db",
            str(db_path),
            "--file",
            str(candidate),
        ],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    stdout = completed.stdout
    identity = ""
    for token in stdout.replace(";", " ").split():
        if token.startswith("identity="):
            identity = token.removeprefix("identity=").strip()
            break
    after_hash = sha256_file(db_path)
    ok = completed.returncode == 0 and bool(identity)
    if not ok:
        write_json(
            candidate_dir / "reading.json",
            {"reading": "R-A2", "reason": "InformationCore.store failed", "stdout": stdout, "stderr": completed.stderr},
        )
        raise HarnessError("R-A2: InformationCore.store failed")

    observer_record = {
        "reading": "STORED",
        "selected_bytes": len(final.encode("utf-8")),
        "selected_sha256": candidate_hash,
        "selection_rule": "exact final answer; no rewrite or repair",
        "identity": identity,
        "db_before_sha256": before_hash,
        "db_after_sha256": after_hash,
        "t4ctl_stdout": stdout,
        "t4ctl_stderr": completed.stderr,
    }
    write_json(candidate_dir / "store-record.json", observer_record)
    state.update(
        {
            "phase": "STORED",
            "observer_completed": True,
            "stored_identity": identity,
            "stored_information_sha256": candidate_hash,
        }
    )
    save_state(settings.run_root, state)
    print(json.dumps(observer_record, ensure_ascii=False, indent=2))
    return 0


def cmd_mark_isolated(settings: Settings, args: argparse.Namespace) -> int:
    state = read_state(settings.run_root)
    require_phase(state, "STORED")
    require_true(state, "observer_completed")
    evidence = args.isolation_evidence
    if args.isolation_method not in {"reload", "fresh-process", "cache-eviction"}:
        raise HarnessError("isolation method must be reload, fresh-process, or cache-eviction")
    if not evidence:
        raise HarnessError("isolation evidence is required")
    record = {
        "method": args.isolation_method,
        "evidence": evidence,
        "recorded_at": utc_now(),
    }
    write_json(settings.run_root / "isolation.json", record)
    state.update({"phase": "ISOLATED", "runtime_isolated": True, "isolation": record})
    save_state(settings.run_root, state)
    print(json.dumps(record, ensure_ascii=False, indent=2))
    return 0


def cmd_run_b(settings: Settings, _args: argparse.Namespace) -> int:
    state = read_state(settings.run_root)
    require_phase(state, "ISOLATED")
    require_true(state, "runtime_isolated")
    if state.get("execution_b_started"):
        raise HarnessError("Execution B has already started")

    identity = state.get("stored_identity")
    if not isinstance(identity, str) or not identity:
        raise HarnessError("missing Stored Information identity")

    template = (settings.run_root / "workspace" / "execution-b-template.md").read_text(encoding="utf-8")
    instruction = template.replace("{{STORED_INFORMATION_IDENTITY}}", identity)
    messages = [{"role": "user", "content": instruction}]
    db_path = pathlib.Path(state["information_copy"])
    final = ""
    fetch_ok_count = 0
    source_read_attempts = 0

    for turn in range(1, 5):
        message, _ = chat_turn(settings, "b", turn, messages, [FETCH_SCHEMA])
        messages.append(message)
        calls = message.get("tool_calls") or []
        final = extract_final(message)
        if not calls:
            break
        for call in calls:
            function = call.get("function", {})
            name = function.get("name")
            raw_args = function.get("arguments") or "{}"
            try:
                args = json.loads(raw_args)
            except json.JSONDecodeError:
                args = {}
            if name == "fetch_stored_information":
                result = execute_fetch(settings.run_root, settings.t4ctl, db_path, identity, args, turn)
                if result.get("ok"):
                    fetch_ok_count += 1
            elif name == "read_file":
                source_read_attempts += 1
                result = {"ok": False, "error": "read_file is forbidden in Execution B"}
            else:
                result = {"ok": False, "error": "unknown tool"}
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call.get("id"),
                    "content": json.dumps(result, ensure_ascii=False),
                }
            )
    else:
        raise HarnessError("Execution B did not stop within four turns")

    state.update(
        {
            "phase": "B_COMPLETE",
            "execution_b_started": True,
            "execution_b_fetch_ok_count": fetch_ok_count,
            "execution_b_source_read_attempts": source_read_attempts,
            "execution_b_final_answer": final,
        }
    )
    atomic_json(settings.run_root / "b" / "final-answer.txt", final)
    save_state(settings.run_root, state)
    print(
        json.dumps(
            {
                "phase": state["phase"],
                "fetch_ok_count": fetch_ok_count,
                "source_read_attempts": source_read_attempts,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def normalize_register(value: dict[str, Any]) -> tuple[dict[str, bool], dict[tuple[str, str], bool]]:
    services = {
        item.get("service_id"): bool(item.get("baseline_compatible"))
        for item in value.get("services", [])
        if isinstance(item, dict) and item.get("service_id")
    }
    pairs = {
        (item.get("left"), item.get("right")): bool(item.get("compatible"))
        for item in value.get("pairs", [])
        if isinstance(item, dict) and item.get("left") and item.get("right")
    }
    return services, pairs


def cmd_evaluate(settings: Settings, _args: argparse.Namespace) -> int:
    state = read_state(settings.run_root)
    require_phase(state, "B_COMPLETE")
    expected = load_json(settings.package_root / "runner" / "expected-register.json")
    try:
        actual_a = json.loads(state.get("execution_a_final_answer", ""))
    except json.JSONDecodeError:
        actual_a = {}
    expected_services, expected_pairs = normalize_register(expected)
    actual_services, actual_pairs = normalize_register(actual_a)
    a_service_ok = actual_services == expected_services
    a_pair_ok = actual_pairs == expected_pairs
    a_semantics = "PASS" if a_service_ok and a_pair_ok else "FAIL"

    b_final_raw = state.get("execution_b_final_answer", "")
    try:
        actual_b = json.loads(b_final_raw)
    except json.JSONDecodeError:
        actual_b = {}

    expected_order = ["alpha", "beta"]
    actual_order = actual_b.get("deployment_order")
    blocked = actual_b.get("blocked_services", [])
    blocked_ids = [item.get("service_id") for item in blocked if isinstance(item, dict)]
    b_release_ok = (
        actual_b.get("release_decision") in {"blocked", "partially released"}
        and actual_order == expected_order
        and "gamma" in blocked_ids
    )

    fetched_ok = state.get("execution_b_fetch_ok_count", 0) > 0
    source_read_attempts = state.get("execution_b_source_read_attempts", 0)
    used_information = fetched_ok and (
        isinstance(actual_b.get("blocked_services"), list)
        or isinstance(actual_b.get("deployment_order"), list)
    )
    gain = "NOT ASSESSED"

    if not fetched_ok:
        b_reading = "R-B0/R-B1"
    elif not used_information:
        b_reading = "R-B2"
    elif not b_release_ok:
        b_reading = "R-B3"
    else:
        b_reading = "R-B4"

    result = {
        "execution_a_semantics": a_semantics,
        "execution_a_service_ok": a_service_ok,
        "execution_a_pair_ok": a_pair_ok,
        "execution_b_fetch_ok_count": fetched_ok,
        "execution_b_source_read_attempts": source_read_attempts,
        "execution_b_release_ok": b_release_ok,
        "execution_b_used_information": used_information,
        "execution_b_reading": b_reading,
        "continuation_gain": gain,
        "continuation_gain_note": "no control run; observational use only",
    }
    write_json(settings.run_root / "evaluation.json", result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Frozen TC-A local closure runner")
    parser.add_argument("--package-root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent)
    parser.add_argument("--run-root", type=pathlib.Path, required=True)
    parser.add_argument("--endpoint", default="http://127.0.0.1:8000/v1/chat/completions")
    parser.add_argument("--model", default="peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX")
    parser.add_argument("--agent-prefix", default="simigo-tc-a")
    parser.add_argument("--t4ctl", type=pathlib.Path, required=True)
    parser.add_argument(
        "--sealed-information-db",
        type=pathlib.Path,
        default=pathlib.Path("docs/02-evidence/real-task-gap-exploration/qinshen/information-space.sqlite"),
    )
    parser.add_argument("--isolation-method", choices=["reload", "fresh-process", "cache-eviction"], default="")
    parser.add_argument("--isolation-evidence", default="")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("verify-package")
    sub.add_parser("prepare")
    sub.add_parser("run-a")
    sub.add_parser("observer")
    sub.add_parser("mark-isolated")
    sub.add_parser("run-b")
    sub.add_parser("evaluate")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if not args.package_root.is_dir():
        raise HarnessError(f"package root not found: {args.package_root}")
    settings = Settings(
        package_root=args.package_root.resolve(),
        run_root=args.run_root.resolve(),
        endpoint=args.endpoint,
        model=args.model,
        agent_prefix=args.agent_prefix,
        t4ctl=args.t4ctl.resolve(),
        sealed_information_db=args.sealed_information_db.resolve(),
        isolation_method=args.isolation_method,
        isolation_evidence=args.isolation_evidence,
    )
    commands: dict[str, Callable[[Settings, argparse.Namespace], int]] = {
        "verify-package": cmd_verify_package,
        "prepare": cmd_prepare,
        "run-a": cmd_run_a,
        "observer": cmd_observer,
        "mark-isolated": cmd_mark_isolated,
        "run-b": cmd_run_b,
        "evaluate": cmd_evaluate,
    }
    return commands[args.command](settings, args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as exc:
        print(f"HARNESS_ERROR: {exc}")
        raise SystemExit(2)
