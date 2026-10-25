#!/usr/bin/env python3
"""Static audit: every production task entry reaches a settlement admission.

This audit answers the coverage question separately from the E round runner:
which entries in `simigo2-experimental/Sources` actually execute task items,
which admission each one reaches, and which direct-generation entries are
excluded as non-task surfaces. It is read-only and derives everything from the
current sources, so it does not depend on the model run.

The legacy Swift API `continueWithRealInformation` is treated as a task entry,
not as a non-task inference surface: it advances the carrier through
`runBridge("execute")`, which opens the loop with `require_provenance=True`
and therefore reaches `_settlement_reuse_decision` before any generation.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

LAB = Path("/Users/mr.simi/Documents/SimiGo-Lab")
RUN_ROOT = Path(__file__).resolve().parents[1]
SOURCES = LAB / "simigo2-experimental/Sources"
INTEGRATION = (SOURCES / "SimiGo2Experimental" /
               "ProductionRuntimeInformationIntegration.swift")
BRIDGE = LAB / "execution-information-loop/production_runtime_bridge.py"
LOOP = LAB / "execution-information-loop/carrier_loop.py"
PROVENANCE = LAB / "execution-information-loop/settlement_provenance.py"


def line_of(text: str, index: int) -> int:
    return text[:max(index, 0)].count("\n") + 1


def func_body(text: str, signature: str) -> tuple[str, int]:
    """Return (body, definition_line) for a Swift member function."""
    start = text.find(signature)
    if start < 0:
        return "", 0
    ends = [
        index for index in (
            text.find("\n  public func ", start + len(signature)),
            text.find("\n  private func ", start + len(signature)),
            text.find("\n  @discardableResult\n  public func ",
                      start + len(signature)),
        ) if index > start
    ]
    end = min(ends) if ends else len(text)
    return text[start:end], line_of(text, start)


def call_sites(text: str, name: str) -> list[dict]:
    """Find call expressions (not definitions) and their balanced text."""
    sites = []
    needle = name + "("
    index = text.find(needle)
    while index >= 0:
        prefix = text[max(0, index - 12):index]
        if not prefix.rstrip().endswith("func"):
            depth = 0
            position = index + len(name)
            in_string = False
            escaped = False
            while position < len(text):
                character = text[position]
                if in_string:
                    if escaped:
                        escaped = False
                    elif character == "\\":
                        escaped = True
                    elif character == '"':
                        in_string = False
                elif character == '"':
                    in_string = True
                elif character == "(":
                    depth += 1
                elif character == ")":
                    depth -= 1
                    if depth == 0:
                        position += 1
                        break
                position += 1
            sites.append({
                "line": line_of(text, index),
                "text": " ".join(text[index:position].split()),
            })
        index = text.find(needle, index + len(needle))
    return sites


def main() -> int:
    integration_text = INTEGRATION.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")
    loop_text = LOOP.read_text(encoding="utf-8")
    provenance_text = PROVENANCE.read_text(encoding="utf-8")
    texts = {path: path.read_text(encoding="utf-8")
             for path in sorted(SOURCES.rglob("*.swift"))}
    integration_entries = sorted(
        path.relative_to(LAB).as_posix()
        for path, text in texts.items()
        if "ProductionRuntimeInformationIntegration(" in text
    )
    expected_entries = [
        "simigo2-experimental/Sources/ActualMLXSmokeChild/main.swift",
        "simigo2-experimental/Sources/RealModelHandoff/main.swift",
        "simigo2-experimental/Sources/SimiGoTaskRun/main.swift",
    ]

    continue_task_sites = []
    for path, text in texts.items():
        for site in call_sites(text, "continueTask"):
            site["path"] = path.relative_to(LAB).as_posix()
            continue_task_sites.append(site)
    continue_real_sites = []
    for path, text in texts.items():
        for site in call_sites(text, "continueWithRealInformation"):
            site["path"] = path.relative_to(LAB).as_posix()
            continue_real_sites.append(site)

    legacy_body, legacy_line = func_body(
        integration_text, "public func continueWithRealInformation(")
    continue_body, continue_line = func_body(
        integration_text, "public func continueTask(")
    legacy_execute = legacy_body.find('runBridge("execute"')
    legacy_tokenize = legacy_body.find("tokenizeText(")
    legacy_seed = legacy_body.find("tokenizeSeedText(")
    swift_execute_total = sum(
        text.count('runBridge("execute"') for text in texts.values())

    execute_start = bridge_text.find("\ndef execute(")
    execute_body = bridge_text[execute_start:] if execute_start >= 0 else ""
    execute_open = execute_body.find(
        "open_loop(args.database, require_provenance=True)")
    reuse_start = loop_text.find("def execute_demand(")
    reuse_body = loop_text[reuse_start:] if reuse_start >= 0 else ""
    decision_call = reuse_body.find("_settlement_reuse_decision(")
    decision_start = loop_text.find("def _settlement_reuse_decision(")
    decision_body = loop_text[decision_start:] if decision_start >= 0 else ""
    verify_start = loop_text.find("def _verify_signed_settlement(")
    verify_body = loop_text[verify_start:] if verify_start >= 0 else ""

    non_task_specs = [
        {
            "entry": "SimiGo2App.send / sendSmallScale / self-test",
            "path": SOURCES / "SimiGo2App/SimiGo2App.swift",
            "reason": "interactive chat/benchmark surface: direct engine.generate "
                      "with user text, no task item and no IS settlement",
        },
        {
            "entry": "MLXGroupResidencyBenchmark / MLXGroupInferenceGate",
            "path": SOURCES / "SimiGo2Experimental/MLXGroupResidencyBenchmark.swift",
            "reason": "measurement/residency probe: direct generation, no task "
                      "identity and no settlement consumption",
        },
        {
            "entry": "GroupExecutionTraceProbe",
            "path": SOURCES / "SimiGo2Experimental/Instrumentation/GroupExecutionTraceProbe.swift",
            "reason": "instrumentation-only trace generation, no IS admission",
        },
        {
            "entry": "MeasuredExecutionTracePilot",
            "path": SOURCES / "SimiGo2Experimental/Instrumentation/MeasuredExecutionTracePilot.swift",
            "reason": "instrumentation-only measured trace, no IS admission",
        },
        {
            "entry": "G3SwiftIsolationEntry",
            "path": SOURCES / "G3SwiftIsolationEntry/main.swift",
            "reason": "isolation/cancellation harness with an injected generate "
                      "closure; it does not advance a task",
            "marker": "generate:",
        },
    ]
    forbidden = ("ProductionRuntimeInformationIntegration", "continueTask(",
                 "continueWithRealInformation(")
    non_task_entries = []
    for spec in non_task_specs:
        path = spec["path"]
        text = path.read_text(encoding="utf-8") if path.exists() else ""
        present = [name for name in forbidden if name in text]
        generate_lines = {site["line"] for site in call_sites(text, "generate")}
        marker = spec.get("marker")
        if marker and marker in text:
            generate_lines.add(line_of(text, text.find(marker)))
        non_task_entries.append({
            "entry": spec["entry"],
            "path": path.relative_to(LAB).as_posix(),
            "exists": path.exists(),
            "reason": spec["reason"],
            "excluded": path.exists() and not present,
            "task_capability_found": present,
            "direct_generation_evidence": marker or "generate(",
            "generate_call_lines": sorted(generate_lines),
        })

    checks = {
        "integration_defines_continueTask": bool(continue_body),
        "integration_defines_continueWithRealInformation": bool(legacy_body),
        "production_integration_entries_are_the_three_known_ones":
            integration_entries == expected_entries,
        "every_continueTask_call_site_passes_provenance":
            bool(continue_task_sites)
            and all("provenance:" in site["text"]
                    for site in continue_task_sites),
        "legacy_entry_calls_continueWithRealInformation":
            any(site["path"].endswith("ActualMLXSmokeChild/main.swift")
                for site in continue_real_sites),
        "sole_swift_execute_site_is_inside_continueWithRealInformation":
            swift_execute_total == 1 and legacy_execute >= 0,
        "continueWithRealInformation_executes_bridge_before_tokenize":
            0 <= legacy_execute < legacy_tokenize
            and 0 <= legacy_execute < legacy_seed,
        "bridge_execute_opens_required_provenance": execute_open >= 0,
        "bridge_open_loop_selects_required_not_env_default":
            '"required" if require_provenance else "off"' in bridge_text,
        "producer_policy_cannot_silently_fall_back_to_off":
            'selected = (policy or os.environ.get(POLICY_ENV) or "off")'
            in provenance_text,
        "execute_demand_uses_reuse_decision": decision_call >= 0,
        "reuse_decision_verifies_signature":
            "_verify_signed_settlement(" in decision_body,
        "missing_or_invalid_signature_is_a_refusal":
            "SETTLEMENT_SIGNATURE_MISSING" in verify_body
            and "SETTLEMENT_SIGNATURE_INVALID" in verify_body,
        "non_task_entries_have_no_task_capability":
            all(entry["excluded"] for entry in non_task_entries),
        "non_task_entries_have_direct_generation_evidence":
            all(entry["generate_call_lines"] for entry in non_task_entries),
    }
    task_entries = [
        {
            "entry": "SimiGoTaskRun",
            "path": "simigo2-experimental/Sources/SimiGoTaskRun/main.swift",
            "admission": "continueTask -> resolveTaskInput -> bridge "
                         "resolve-model-input (verify) -> Swift Ed25519 verify",
            "dynamic_in_e_round": "MODEL_RUNS_AND_TAMPER_MATRIX",
        },
        {
            "entry": "RealModelHandoff",
            "path": "simigo2-experimental/Sources/RealModelHandoff/main.swift",
            "admission": "same continueTask admission; handoff only chooses "
                         "the item",
            "dynamic_in_e_round": "NOT_RUN_STATIC_ONLY",
        },
        {
            "entry": "ActualMLXSmokeChild (legacy advancement)",
            "path": "simigo2-experimental/Sources/ActualMLXSmokeChild/main.swift",
            "admission": "continueWithRealInformation -> runBridge(execute) -> "
                         "open_loop(require_provenance=True) -> execute_demand "
                         "-> _settlement_reuse_decision -> "
                         "_verify_signed_settlement",
            "dynamic_in_e_round": "BRIDGE_EXECUTE_DYNAMIC; "
                                  "SWIFT_WRAPPER_STATIC_ONLY",
        },
    ]
    execute_open_abs = (execute_start + 1 + execute_open
                        if execute_open >= 0 else -1)
    decision_abs = (reuse_start + decision_call
                    if decision_call >= 0 else -1)
    report = {
        "schema_id": "SIMIGO-E-ROUND-ENTRY-COVERAGE-AUDIT-V1",
        "sources": {
            INTEGRATION.relative_to(LAB).as_posix(): hashlib.sha256(
                INTEGRATION.read_bytes()).hexdigest(),
            BRIDGE.relative_to(LAB).as_posix(): hashlib.sha256(
                BRIDGE.read_bytes()).hexdigest(),
            LOOP.relative_to(LAB).as_posix(): hashlib.sha256(
                LOOP.read_bytes()).hexdigest(),
            PROVENANCE.relative_to(LAB).as_posix(): hashlib.sha256(
                PROVENANCE.read_bytes()).hexdigest(),
        },
        "checks": checks,
        "production_task_entries": task_entries,
        "non_task_entries": non_task_entries,
        "source_evidence": {
            "continueTask_definition_line": continue_line,
            "continueWithRealInformation_definition_line": legacy_line,
            "continueWithRealInformation_bridge_execute_line":
                line_of(legacy_body, legacy_execute) + legacy_line - 1
                if legacy_execute >= 0 else None,
            "continueWithRealInformation_first_tokenize_line":
                line_of(legacy_body, legacy_tokenize) + legacy_line - 1
                if legacy_tokenize >= 0 else None,
            "bridge_execute_open_loop_line":
                line_of(bridge_text, execute_open_abs)
                if execute_open_abs >= 0 else None,
            "execute_demand_reuse_decision_line":
                line_of(loop_text, decision_abs) if decision_abs >= 0 else None,
            "continueTask_call_sites": continue_task_sites,
            "continueWithRealInformation_call_sites": continue_real_sites,
            "production_integration_entries": integration_entries,
        },
        "not_claimed": [
            "that every inference call in the repository is admission-covered",
            "that the RealModelHandoff entry was dynamically exercised in E",
            "that the Swift ActualMLXSmokeChild wrapper was executed in E; the "
            "bridge execute path it invokes was",
            "semantic correctness of a signed answer",
        ],
        "verdict": "PASS" if all(checks.values()) else "FAIL",
    }
    output = RUN_ROOT / "logs" / "entry-coverage-audit.json"
    output.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n",
                      encoding="utf-8")
    print(json.dumps({
        "verdict": report["verdict"],
        "false_checks": [key for key, value in checks.items() if not value],
        "source_evidence": report["source_evidence"],
        "report": str(output),
    }, ensure_ascii=False, indent=1))
    return 0 if report["verdict"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
