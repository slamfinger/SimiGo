#!/usr/bin/env python3
"""Cross-engine contract parity gate (Python side).

Runs the shared canonical case file through the PRODUCTION Python gate
(`declarative_result_contract.validate_result_text`) and compares, case by case,
against the native Swift engine's verdicts produced by
`NativeContractParityHarness`. It also checks BOTH engines against the case's
declared expectation, so the gate fails if either engine drifts from the agreed
behaviour OR from each other.

Neither engine grades its own homework: the native harness emits raw verdicts
with no expectations, and this script holds the expectations and the comparison.
Any divergence is a hard failure (issue_count > 0).

Usage:
  python3 compare_native_python_parity.py \
      --cases <expanded.json> --native <native_parity_out.json>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))  # execution-information-loop/

import declarative_result_contract as drc  # noqa: E402


def python_verdict(text, contract, bindings):
    try:
        report = drc.validate_result_text(text, contract, bindings)
        return {"verdict": "VALID", "error_code": "",
                "values": report["values"]}
    except drc.ContractError as err:
        return {"verdict": "REJECT", "error_code": err.code, "values": {}}
    except Exception as err:  # unexpected engine fault
        return {"verdict": "ERROR", "error_code": "PYTHON_UNCLASSIFIED:%s" % err,
                "values": {}}


def norm_values(v):
    # Coerce ints/bools/None/str to a comparable canonical form; treat -0/0 and
    # numeric-string equality strictly (both engines typed them, so shapes must
    # already agree).
    return json.dumps(v, sort_keys=True, default=str)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--native", required=True)
    args = ap.parse_args()

    cases_path = Path(args.cases)
    cases_doc = json.loads(cases_path.read_text(encoding="utf-8"))
    cases = cases_doc["cases"]
    cases_sha = hashlib.sha256(cases_path.read_bytes()).hexdigest()

    native_doc = json.loads(Path(args.native).read_text(encoding="utf-8"))
    native_by_name = {}
    for rec in native_doc["case_results"]:
        native_by_name[rec["name"]] = rec

    issues = []
    rows = []

    if native_doc.get("cases_sha256") != cases_sha:
        issues.append("native harness read a DIFFERENT case file "
                      "(cases_sha256 mismatch: %s != %s)"
                      % (native_doc.get("cases_sha256"), cases_sha))

    if len(native_by_name) != len(cases):
        issues.append("case count mismatch: python %d native %d"
                      % (len(cases), len(native_by_name)))

    for case in cases:
        name = case["name"]
        native = native_by_name.get(name)
        if native is None:
            issues.append("%s: native harness produced no verdict" % name)
            continue
        py = python_verdict(case["text"], case["contract"], case["bindings"])
        nv = {"verdict": native["native_verdict"],
              "error_code": native["native_error_code"],
              "values": native["native_values"]}
        klass = case.get("class", "family")
        exp = case["expect"]

        # Safety invariant that holds for EVERY case, in both classes: the
        # native gate is never MORE permissive than the Python gate. If Python
        # refuses a result, native must not settle it. (Native refusing while
        # Python accepts is the documented, safe strictness direction.)
        if py["verdict"] == "REJECT" and nv["verdict"] == "VALID":
            issues.append("%s: UNSAFE divergence native=VALID but python=REJECT "
                          "(native settled something the production gate refuses)"
                          % name)

        if klass == "family":
            # Within the shared implemented construct family the two engines
            # must be byte-for-byte indistinguishable.
            if py["verdict"] != nv["verdict"]:
                issues.append("%s: VERDICT divergence python=%s native=%s"
                              % (name, py["verdict"], nv["verdict"]))
            if py["error_code"] != nv["error_code"]:
                issues.append("%s: ERROR_CODE divergence python=%r native=%r"
                              % (name, py["error_code"], nv["error_code"]))
            if py["verdict"] == "VALID" and norm_values(py["values"]) != norm_values(nv["values"]):
                issues.append("%s: VALUES divergence python=%s native=%s"
                              % (name, py["values"], nv["values"]))
            if py["verdict"] != exp:
                issues.append("%s: python verdict %s != expected %s"
                              % (name, py["verdict"], exp))
            if nv["verdict"] != exp:
                issues.append("%s: native verdict %s != expected %s"
                              % (name, nv["verdict"], exp))
            if exp == "REJECT":
                if py["error_code"] != case["expected_error_code"]:
                    issues.append("%s: python code %r != expected %r"
                                  % (name, py["error_code"], case["expected_error_code"]))
                if nv["error_code"] != case["expected_error_code"]:
                    issues.append("%s: native code %r != expected %r"
                                  % (name, nv["error_code"], case["expected_error_code"]))
            if exp == "VALID":
                if norm_values(py["values"]) != norm_values(case["expected_values"]):
                    issues.append("%s: python values %s != expected %s"
                                  % (name, py["values"], case["expected_values"]))
                if norm_values(nv["values"]) != norm_values(case["expected_values"]):
                    issues.append("%s: native values %s != expected %s"
                                  % (name, nv["values"], case["expected_values"]))
        elif klass == "native-stricter":
            # A construct outside the native engine's implemented family: the
            # native gate must refuse fail-closed with the documented code, and
            # the safety invariant above already forbids native being laxer.
            if nv["verdict"] != "REJECT":
                issues.append("%s: native-stricter case not refused (native=%s)"
                              % (name, nv["verdict"]))
            if nv["error_code"] != case["expected_error_code"]:
                issues.append("%s: native code %r != documented %r"
                              % (name, nv["error_code"], case["expected_error_code"]))
        else:
            issues.append("%s: unknown case class %r" % (name, klass))

        rows.append({
            "name": name, "class": klass, "expect": exp,
            "python": "%s/%s" % (py["verdict"], py["error_code"] or "-"),
            "native": "%s/%s" % (nv["verdict"], nv["error_code"] or "-"),
        })

    result = {
        "schema_id": "SIMIGO-NATIVE-PYTHON-CONTRACT-PARITY-VERIFY-V1",
        "cases_sha256": cases_sha,
        "case_count": len(cases),
        "agree": len(cases) - len({i.split(":")[0] for i in issues}),
        "issue_count": len(issues),
        "issues": issues,
        "per_case": rows,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if not issues else 1


if __name__ == "__main__":
    raise SystemExit(main())
