#!/usr/bin/env python3
"""Expand the shared parity fixture into one canonical case file.

`tests/fixtures/native_python_contract_parity.json` may reuse a contract with
`"@<case>.contract"` shorthand. Both engines must be handed the SAME bytes, so
this tool resolves every reference once and writes a flat, self-contained
canonical file (`..._expanded.json`) that the Python gate and the native Swift
harness each read verbatim. Neither engine implements reference resolution, so
neither can drift in how a shared case is built.

Usage:
  python3 expand_native_parity_fixture.py [fixture.json] [expanded.json]
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_IN = HERE / "native_python_contract_parity.json"
REJECT_CODES = {
    "PRODUCER_RESULT_FIELD_MISSING", "PRODUCER_RESULT_BINDING_MISMATCH",
    "PRODUCER_RESULT_DERIVATION_MISMATCH", "PRODUCER_RESULT_FIELD_MISMATCH",
    "PRODUCER_RESULT_LITERAL_MISMATCH", "CONTRACT_UNKNOWN_SCHEMA_VERSION",
    "CONTRACT_UNKNOWN_KEY", "CONTRACT_UNKNOWN_CONSTRAINT",
    "CONTRACT_UNKNOWN_FIELD_TYPE", "CONTRACT_INVALID_FIELD_SPEC",
    "CONTRACT_INVALID_PATTERN", "CONTRACT_AMBIGUOUS_FIELD",
    "CONTRACT_BINDING_MISSING", "CONTRACT_RANGE_VIOLATION",
    "CONTRACT_TYPE_MISMATCH", "CONTRACT_ENUM_VIOLATION",
    "CONTRACT_EMPTY_FIELD", "CONTRACT_INVALID_CONSTRAINT",
    "CONTRACT_CONSTRAINT_FIELD_MISSING",
}


def build_cases(document: dict) -> list:
    named = {case["name"]: case for case in document["cases"]}
    if len(named) != len(document["cases"]):
        raise SystemExit("duplicate case name in fixture")

    def resolve(reference: str):
        # Only "<case>.contract" references are supported, and only for the
        # contract body; text/bindings/expectation are always explicit per case.
        if not reference.startswith("@") or not reference.endswith(".contract"):
            raise SystemExit("unsupported fixture reference %r" % reference)
        target = named.get(reference[1:-len(".contract")])
        if target is None:
            raise SystemExit("fixture reference names no case: %r" % reference)
        return json.loads(json.dumps(target["contract"]))

    cases = []
    for case in document["cases"]:
        contract = case["contract"]
        if isinstance(contract, str):
            contract = resolve(contract)
        expect = case.get("expect")
        if expect not in ("VALID", "REJECT"):
            raise SystemExit("case %s has no valid expect" % case["name"])
        if expect == "REJECT":
            code = case.get("error_code")
            if code not in REJECT_CODES:
                raise SystemExit(
                    "case %s rejects with %r, outside the agreed code family"
                    % (case["name"], code))
        if expect == "VALID" and "values" not in case:
            raise SystemExit("case %s is VALID but records no expected values"
                             % case["name"])
        cases.append({
            "name": case["name"],
            "class": case.get("class", "family"),
            "contract": contract,
            "bindings": case.get("bindings", {}),
            "text": case["text"],
            "expect": expect,
            "expected_error_code": case.get("error_code", ""),
            "expected_values": case.get("values", {}),
        })
    return cases


def main() -> int:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_IN
    destination = (Path(sys.argv[2]) if len(sys.argv) > 2 else
                   HERE / "native_python_contract_parity_expanded.json")
    document = json.loads(source.read_text(encoding="utf-8"))
    cases = build_cases(document)
    payload = {
        "schema_id": "SIMIGO-NATIVE-PYTHON-CONTRACT-PARITY-CASES-V1",
        "source_fixture": source.name,
        "case_count": len(cases),
        "cases": cases,
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    destination.write_text(text, encoding="utf-8")
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    print(json.dumps({
        "expanded": str(destination),
        "case_count": len(cases),
        "sha256": digest,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
