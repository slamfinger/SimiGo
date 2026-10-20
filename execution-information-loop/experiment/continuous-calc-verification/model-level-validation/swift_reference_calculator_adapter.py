#!/usr/bin/env python3
"""Fail-closed adapter between the Python Carrier and the Swift reference calculator.

G1.1/G1.2 boundary:
  - one Swift process per calculator call; the request goes in on stdin;
  - a non-zero exit is raised, never retried, never satisfied by a Python oracle;
  - every call must leave exactly one `started` and exactly one terminal event in
    the event log, and every event must carry the pinned executable hash;
  - stdout must be the canonical JSON of the result, not merely parseable JSON.

This module never computes the frozen formulas itself. The only arithmetic in this
file is digest verification.
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import uuid
from pathlib import Path
from typing import Any


class SwiftCalculatorFailure(Exception):
    """Raised when the Swift side fails or violates the wire contract."""

    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        self.detail = detail
        super().__init__(code if not detail else f"{code}: {detail}")


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class SwiftReferenceCalculatorAdapter:
    """`calculator(item_id, source_payload, dependency_values) -> dict` over subprocess."""

    def __init__(
        self,
        executable: str | os.PathLike[str],
        events_path: str | os.PathLike[str],
        *,
        error_class: type[Exception] = SwiftCalculatorFailure,
        timeout: float = 60.0,
    ) -> None:
        self.executable = str(Path(executable).resolve())
        self.events_path = str(Path(events_path).resolve())
        self.error_class = error_class
        self.timeout = timeout
        self.calls: list[str] = []
        self.last_events: list[dict] = []
        if not os.path.isfile(self.executable):
            raise self.error_class(
                "SWIFT_EXECUTABLE_MISSING",
                f"{self.executable} does not exist; build it first (see the gate script)",
            )
        self.pinned_sha256 = sha256_hex(Path(self.executable).read_bytes())

    def __call__(self, item_id: str, source_payload: dict, dependency_values: dict) -> dict:
        # Recorded before the call: an attempted invocation that fails still counts.
        self.calls.append(item_id)
        request = {
            "mode": "compute",
            "invocation_id": f"g1-{uuid.uuid4().hex}",
            "item_id": item_id,
            "source_payload": source_payload,
            "dependency_values": dependency_values,
        }
        response = self._invoke(request)
        if not isinstance(response, dict) or set(response) != {"swift_value"}:
            raise self.error_class("PROTOCOL_VIOLATION", f"unexpected result object: {response!r}")
        value = response["swift_value"]
        if not isinstance(value, str):
            raise self.error_class("PROTOCOL_VIOLATION", f"swift_value is not a string: {value!r}")
        return response

    def canonicalize(self, value: Any) -> tuple[str, str]:
        response = self._invoke({
            "mode": "canonicalize",
            "invocation_id": f"g1-{uuid.uuid4().hex}",
            "value": value,
        })
        if not isinstance(response, dict) or set(response) != {
            "canonical_sha256", "canonical_utf8_text"
        }:
            raise self.error_class("PROTOCOL_VIOLATION", f"unexpected canonicalize response: {response!r}")
        return response["canonical_utf8_text"], response["canonical_sha256"]

    # -- internals ---------------------------------------------------------

    def _invoke(self, request: dict) -> dict:
        request_bytes = canonical_bytes(request)
        offset = os.path.getsize(self.events_path) if os.path.exists(self.events_path) else 0
        try:
            completed = subprocess.run(
                [self.executable, "--events", self.events_path],
                input=request_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise self.error_class("SWIFT_TIMEOUT", f"{self.timeout}s") from error

        events = self._read_new_events(offset)
        self.last_events = events
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")

        if completed.returncode != 0:
            code = self._error_code(completed.returncode, stderr, stdout)
            self._require_failed_events(events, code)
            raise self.error_class(code, stderr.strip())

        if emitted := self._sole_failure(events):
            raise self.error_class("EVENT_LOG_VIOLATION", f"success exit but event log says {emitted}")
        self._require_success_events(events, stdout, request.get("mode"))

        try:
            parsed = json.loads(stdout)
        except json.JSONDecodeError as error:
            raise self.error_class("PROTOCOL_VIOLATION", f"stdout is not JSON: {stdout!r}") from error
        if stdout.strip() != canonical_bytes(parsed).decode("utf-8"):
            raise self.error_class("PROTOCOL_VIOLATION", f"stdout is not canonical JSON: {stdout!r}")
        return parsed

    def _read_new_events(self, offset: int) -> list[dict]:
        if not os.path.exists(self.events_path):
            return []
        with open(self.events_path, "rb") as stream:
            stream.seek(offset)
            payload = stream.read().decode("utf-8")
        events = []
        for line in payload.splitlines():
            if not line.strip():
                continue
            events.append(json.loads(line))
        return events

    def _error_code(self, returncode: int, stderr: str, stdout: str) -> str:
        if stdout.strip():
            raise self.error_class(
                "PROTOCOL_VIOLATION", f"nonzero exit {returncode} but stdout was not empty"
            )
        try:
            return json.loads(stderr)["error_code"]
        except (json.JSONDecodeError, KeyError, TypeError):
            return "SWIFT_INTERNAL_ERROR"

    def _require_success_events(self, events: list[dict], stdout: str, mode: str | None) -> None:
        self._require_pair(events)
        started, terminal = events
        if terminal.get("event") != "completed":
            raise self.error_class("EVENT_LOG_VIOLATION", f"terminal event is {terminal.get('event')!r}")
        if mode != "compute":
            # canonicalize responses carry canonical_sha256; the caller compares it
            # against the frozen vector rather than against the wire envelope.
            return
        result = json.loads(stdout)
        expected = sha256_hex(canonical_bytes(result))
        if terminal.get("result_sha256") != expected:
            raise self.error_class(
                "EVENT_LOG_VIOLATION",
                f"result_sha256 {terminal.get('result_sha256')!r} != stdout digest {expected}",
            )

    def _require_failed_events(self, events: list[dict], code: str) -> None:
        self._require_pair(events)
        started, terminal = events
        if terminal.get("event") != "failed":
            raise self.error_class("EVENT_LOG_VIOLATION", f"terminal event is {terminal.get('event')!r}")
        if terminal.get("error_code") != code:
            raise self.error_class(
                "EVENT_LOG_VIOLATION",
                f"stderr code {code!r} != event code {terminal.get('error_code')!r}",
            )

    def _require_pair(self, events: list[dict]) -> None:
        if len(events) != 2:
            raise self.error_class("EVENT_LOG_VIOLATION", f"expected 2 events, got {len(events)}")
        started, terminal = events
        if started.get("event") != "started" or started.get("seq") != 1:
            raise self.error_class("EVENT_LOG_VIOLATION", f"bad started event: {started!r}")
        if terminal.get("seq") != 2:
            raise self.error_class("EVENT_LOG_VIOLATION", f"bad terminal seq: {terminal!r}")
        for event in events:
            if event.get("executable_sha256") != self.pinned_sha256:
                raise self.error_class(
                    "EVENT_LOG_VIOLATION",
                    f"executable hash {event.get('executable_sha256')!r} != pinned {self.pinned_sha256}",
                )
            if event.get("invocation_id") != started.get("invocation_id"):
                raise self.error_class("EVENT_LOG_VIOLATION", "invocation_id changed between events")

    @staticmethod
    def _sole_failure(events: list[dict]) -> str | None:
        for event in events:
            if event.get("event") == "failed":
                return str(event.get("error_code"))
        return None
