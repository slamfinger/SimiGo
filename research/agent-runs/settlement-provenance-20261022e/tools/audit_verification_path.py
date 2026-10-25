#!/usr/bin/env python3
"""Static audit: signature verification sits on the pre-generation path.

`coverage-audit.json` proves that `continueTask` calls `resolveTaskInput`
before the first tokenization. This audit proves the complementary half: the
Ed25519 verification is inside `resolveTaskInput`, and that function performs
no tokenization or model generation at all.
"""
from __future__ import annotations

import json
from pathlib import Path

LAB = Path("/Users/mr.simi/Documents/SimiGo-Lab")
RUN_ROOT = Path(__file__).resolve().parents[1]
SOURCE = (LAB / "simigo2-experimental/Sources/SimiGo2Experimental/"
          "ProductionRuntimeInformationIntegration.swift")


def body_of(text: str, signature: str) -> str:
    start = text.find(signature)
    if start < 0:
        return ""
    end = text.find("\n  public func ", start + len(signature))
    return text[start:end if end > start else len(text)]


def line_of(text: str, index: int) -> int:
    return text[:max(index, 0)].count("\n") + 1


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    continue_body = body_of(text, "public func continueTask(")
    resolve_body = body_of(text, "public func resolveTaskInput(")
    resolve_call = continue_body.find("resolveTaskInput(")
    tokenize = continue_body.find("modelExecutor.tokenizeText(")
    seed = continue_body.find("modelExecutor.tokenizeSeedText(")
    generate = continue_body.find("modelExecutor.generate(")
    verify_in_resolve = resolve_body.find("SettlementProvenanceVerifier.verify(")
    bridge_resolve = resolve_body.find('runBridge("resolve-model-input"')
    checks = {
        "continueTask_body_found": bool(continue_body),
        "resolveTaskInput_body_found": bool(resolve_body),
        "continueTask_calls_resolveTaskInput": resolve_call >= 0,
        "resolveTaskInput_before_tokenizeText":
            0 <= resolve_call < tokenize if tokenize >= 0 else False,
        "resolveTaskInput_before_tokenizeSeedText":
            0 <= resolve_call < seed if seed >= 0 else False,
        "resolveTaskInput_before_generate":
            0 <= resolve_call < generate if generate >= 0 else None,
        # The consumer verification must live inside the admission function,
        # after the bridge has supplied the signed descriptors.
        "verification_inside_resolveTaskInput": verify_in_resolve >= 0,
        "verification_after_bridge_resolve":
            0 <= bridge_resolve < verify_in_resolve,
        # resolveTaskInput is an admission-only function: it must not reach the
        # model executor at all.
        "resolveTaskInput_has_no_tokenize":
            "tokenizeText(" not in resolve_body
            and "tokenizeSeedText(" not in resolve_body,
        "resolveTaskInput_has_no_generation":
            "modelExecutor.generate" not in resolve_body
            and "modelContinuation" not in resolve_body,
    }
    checks = {key: value for key, value in checks.items() if value is not None}
    offset = text[:text.find("public func continueTask(")].count("\n") + 1
    base = text[:text.find("public func resolveTaskInput(")].count("\n") + 1
    report = {
        "schema_id": "SIMIGO-E-ROUND-VERIFICATION-PATH-AUDIT-V1",
        "source": str(SOURCE),
        "source_sha256": __import__("hashlib").sha256(
            SOURCE.read_bytes()).hexdigest(),
        "checks": checks,
        "source_evidence": {
            "continueTask_definition_line": offset,
            "resolveTaskInput_definition_line": base,
            "continueTask_resolve_call_line":
                line_of(continue_body, resolve_call) + offset - 1
                if resolve_call >= 0 else None,
            "continueTask_first_tokenize_line":
                line_of(continue_body, tokenize) + offset - 1
                if tokenize >= 0 else None,
            "continueTask_first_seed_tokenize_line":
                line_of(continue_body, seed) + offset - 1 if seed >= 0 else None,
            "continueTask_first_generate_line":
                line_of(continue_body, generate) + offset - 1
                if generate >= 0 else None,
            "resolveTaskInput_bridge_resolve_line":
                line_of(resolve_body, bridge_resolve) + base - 1
                if bridge_resolve >= 0 else None,
            "resolveTaskInput_verify_line":
                line_of(resolve_body, verify_in_resolve) + base - 1
                if verify_in_resolve >= 0 else None,
        },
        "verdict": "PASS" if all(checks.values()) else "FAIL",
        "not_claimed": [
            "that every inference call in the repository goes through this entry",
            "semantic correctness of a signed answer",
        ],
    }
    output = RUN_ROOT / "logs" / "verification-path-audit.json"
    output.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n",
                      encoding="utf-8")
    print(json.dumps({"verdict": report["verdict"],
                      "false_checks": [k for k, v in checks.items() if not v],
                      "source_evidence": report["source_evidence"],
                      "report": str(output)}, ensure_ascii=False, indent=1))
    return 0 if report["verdict"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
