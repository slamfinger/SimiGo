#!/usr/bin/env python3
"""Validate SIMIGO-REFERENCE-CALCULATOR-V1 against the Carrier loop.

This is a Python reference-oracle / Carrier integration test only. It does not
claim Swift execution, model continuation, or KV-cache release evidence.

Expected placement in the Lab repository:
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/

The frozen JSONL contract is an input artifact and is never modified. Supply it
with --contract, or put calculator-contract-freeze.jsonl beside this script or
at the repository root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable

CONTRACT_ID = "SIMIGO-REFERENCE-CALCULATOR-V1"
CONTRACT_VERSION = "1.0.0"
MIN_I64 = -(2**63)
MAX_I64 = 2**63 - 1
DECIMAL_RE = re.compile(r"(?:0|-?[1-9][0-9]*)\Z")
VALID_UNTIL_UTC = "2030-12-31T23:59:59Z"
EVALUATED_AT_UTC = "2026-10-20T00:00:00Z"


class CalculatorContractError(ValueError):
    """Stable, machine-readable reference-calculator failure."""

    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        self.detail = detail
        message = code if not detail else f"{code}: {detail}"
        super().__init__(message)


def canonical_bytes(value: Any) -> bytes:
    """Contract canonicalization: compact, sorted-key UTF-8 JSON, no Unicode rewrite."""
    try:
        text = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    except (TypeError, ValueError) as error:
        raise ValueError(f"value is outside canonical JSON domain: {error}") from error
    return text.encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def load_jsonl_contract(path: Path) -> tuple[dict, list[dict]]:
    if not path.is_file():
        raise FileNotFoundError(f"frozen calculator contract not found: {path}")
    records: list[dict] = []
    with path.open("r", encoding="utf-8") as stream:
        for line_no, raw in enumerate(stream, 1):
            if not raw.strip():
                continue
            try:
                record = json.loads(raw)
            except json.JSONDecodeError as error:
                raise ValueError(f"invalid JSONL at {path}:{line_no}: {error}") from error
            if not isinstance(record, dict):
                raise ValueError(f"JSONL record at {path}:{line_no} is not an object")
            records.append(record)
    headers = [r for r in records if r.get("record_type") == "contract_header"]
    if len(headers) != 1:
        raise ValueError(f"expected one contract_header, found {len(headers)}")
    header = headers[0]
    if header.get("contract_id") != CONTRACT_ID or header.get("version") != CONTRACT_VERSION:
        raise ValueError(
            "frozen contract identity/version mismatch: "
            f"{header.get('contract_id')} v{header.get('version')}"
        )
    if header.get("status") != "FROZEN_FOR_STEP_3_IMPLEMENTATION":
        raise ValueError(f"contract is not frozen for implementation: {header.get('status')}")
    for record in records:
        if record.get("record_type") != "contract_header" and record.get("contract_id") != CONTRACT_ID:
            raise ValueError(f"record refers to unexpected contract id: {record.get('record_type')}")
    return header, records


def _i64(value: Any, *, code: str, field: str) -> int:
    # bool is a subclass of int in Python, but is explicitly excluded by contract.
    if type(value) is not int or not MIN_I64 <= value <= MAX_I64:
        raise CalculatorContractError(code, f"{field} must be a signed int64 integer")
    return value


def _checked_i64(value: int, *, operation: str) -> int:
    if not MIN_I64 <= value <= MAX_I64:
        raise CalculatorContractError("ARITHMETIC_OVERFLOW", operation)
    return value


def _dependency_integer(value: Any, *, dependency_id: str) -> int:
    if type(value) is not dict or set(value) != {"swift_value"}:
        raise CalculatorContractError(
            "INVALID_DEPENDENCY_VALUE",
            f"{dependency_id} must be exactly {{'swift_value': <canonical decimal string>}}",
        )
    decimal = value["swift_value"]
    if not isinstance(decimal, str) or DECIMAL_RE.fullmatch(decimal) is None:
        raise CalculatorContractError(
            "INVALID_DEPENDENCY_VALUE", f"{dependency_id}.swift_value is not canonical decimal"
        )
    parsed = int(decimal, 10)
    if not MIN_I64 <= parsed <= MAX_I64:
        raise CalculatorContractError(
            "INVALID_DEPENDENCY_VALUE", f"{dependency_id}.swift_value is outside int64 range"
        )
    return parsed


# This table is deliberately explicit: it mirrors the frozen v1 contract and is
# checked against its calculation_rules record before any test is run.
IMPLEMENTED_RULES = {
    "A": {
        "keys": ["input"],
        "deps": [],
        "formula": "value = input * 2",
    },
    "B": {
        "keys": ["input"],
        "deps": ["A"],
        "formula": "value = dependency_values['A'].swift_value + input",
    },
    "C": {
        "keys": ["factor"],
        "deps": ["A"],
        "formula": "value = dependency_values['A'].swift_value * factor",
    },
    "D": {
        "keys": ["input"],
        "deps": ["B", "C"],
        "formula": (
            "value = input + dependency_values['B'].swift_value + "
            "dependency_values['C'].swift_value; additions are evaluated left-to-right "
            "with checked int64 arithmetic"
        ),
    },
    "E": {
        "keys": ["input"],
        "deps": [],
        "formula": "value = input * 2",
    },
}


def validate_implementation_matches_contract(records: list[dict]) -> dict:
    candidates = [r for r in records if r.get("record_type") == "calculation_rules"]
    if len(candidates) != 1:
        raise ValueError(f"expected one calculation_rules record, found {len(candidates)}")
    rule_record = candidates[0]
    raw_units = rule_record.get("per_unit_rules")
    if not isinstance(raw_units, list):
        raise ValueError("calculation_rules.per_unit_rules is missing")
    frozen_units = {r.get("item_id"): r for r in raw_units}
    if set(frozen_units) != set(IMPLEMENTED_RULES):
        raise ValueError(f"unit set mismatch: frozen={sorted(frozen_units)} implementation={sorted(IMPLEMENTED_RULES)}")
    for unit_id, impl in IMPLEMENTED_RULES.items():
        frozen = frozen_units[unit_id]
        payload_schema = frozen.get("payload_schema")
        frozen_keys = payload_schema.get("exact_keys") if isinstance(payload_schema, dict) else None
        if frozen_keys != impl["keys"]:
            raise ValueError(f"{unit_id}: frozen payload keys disagree with implementation")
        if frozen.get("required_dependency_ids") != impl["deps"]:
            raise ValueError(f"{unit_id}: frozen dependency set disagrees with implementation")
        if frozen.get("formula") != impl["formula"]:
            raise ValueError(f"{unit_id}: frozen formula text disagrees with implementation")
    graph_records = [r for r in records if r.get("record_type") == "p3_arm4_acceptance_contract"]
    if len(graph_records) != 1:
        raise ValueError(f"expected one p3_arm4_acceptance_contract, found {len(graph_records)}")
    graph = graph_records[0].get("dependency_graph")
    expected_graph = {key: rule["deps"] for key, rule in IMPLEMENTED_RULES.items()}
    if graph != expected_graph:
        raise ValueError(f"P3 graph mismatch: frozen={graph} implementation={expected_graph}")
    return graph_records[0]


def reference_calculator(item_id: str, source_payload: dict, dependency_values: dict) -> dict:
    """Deterministic Python oracle implementing the frozen reference formulas."""
    if item_id not in IMPLEMENTED_RULES:
        raise CalculatorContractError("UNSUPPORTED_UNIT_ID", repr(item_id))
    if type(source_payload) is not dict or set(source_payload) != set(IMPLEMENTED_RULES[item_id]["keys"]):
        raise CalculatorContractError("INVALID_PAYLOAD", f"{item_id} payload keys must be {IMPLEMENTED_RULES[item_id]['keys']}")
    payload_values = {
        key: _i64(value, code="INVALID_PAYLOAD", field=f"{item_id}.{key}")
        for key, value in source_payload.items()
    }
    required_dependencies = IMPLEMENTED_RULES[item_id]["deps"]
    if type(dependency_values) is not dict or set(dependency_values) != set(required_dependencies):
        raise CalculatorContractError(
            "DEPENDENCY_SET_MISMATCH",
            f"{item_id} expected dependencies {required_dependencies}, got "
            f"{sorted(dependency_values) if isinstance(dependency_values, dict) else type(dependency_values).__name__}",
        )
    dep_values = {
        dependency_id: _dependency_integer(dependency_values[dependency_id], dependency_id=dependency_id)
        for dependency_id in required_dependencies
    }

    if item_id == "A" or item_id == "E":
        result = _checked_i64(payload_values["input"] * 2, operation=f"{item_id}: multiply input by 2")
    elif item_id == "B":
        result = _checked_i64(dep_values["A"] + payload_values["input"], operation="B: dependency A + input")
    elif item_id == "C":
        result = _checked_i64(dep_values["A"] * payload_values["factor"], operation="C: dependency A * factor")
    else:  # D: each addition is checked left-to-right per the frozen contract.
        partial = _checked_i64(payload_values["input"] + dep_values["B"], operation="D: input + dependency B")
        result = _checked_i64(partial + dep_values["C"], operation="D: partial + dependency C")
    return {"swift_value": str(result)}


def run_oracle_vectors(records: list[dict]) -> dict:
    vectors = [r for r in records if r.get("record_type") == "test_vector"]
    success_vectors = [r for r in vectors if r.get("expected_status") == "SUCCESS"]
    error_vectors = [r for r in vectors if r.get("expected_status") == "ERROR"]
    if len(success_vectors) != 9 or len(error_vectors) != 6:
        raise AssertionError(
            f"v1 vector inventory drifted: expected 9 success + 6 error; got {len(success_vectors)} + {len(error_vectors)}"
        )
    passed_success: list[str] = []
    passed_errors: list[str] = []
    for vector in success_vectors:
        basis = vector["canonical_input_basis"]
        if digest(basis) != vector["input_sha256"]:
            raise AssertionError(f"{vector['vector_id']}: frozen input_sha256 mismatch")
        if digest(basis["dependencies"]) != vector["dependencies_sha256"]:
            raise AssertionError(f"{vector['vector_id']}: frozen dependencies_sha256 mismatch")
        if digest(vector["expected_result"]) != vector["expected_result_sha256"]:
            raise AssertionError(f"{vector['vector_id']}: frozen expected_result_sha256 mismatch")
        inp = vector["input"]
        result = reference_calculator(inp["item_id"], inp["source_payload"], inp["dependency_values"])
        if result != vector["expected_result"]:
            raise AssertionError(
                f"{vector['vector_id']}: result mismatch; expected={vector['expected_result']}, actual={result}"
            )
        passed_success.append(vector["vector_id"])
    for vector in error_vectors:
        try:
            reference_calculator(vector["item_id"], vector["source_payload"], vector["dependency_values"])
        except CalculatorContractError as error:
            if error.code != vector.get("expected_error_code"):
                raise AssertionError(
                    f"{vector['vector_id']}: expected error {vector.get('expected_error_code')}, got {error.code}"
                ) from error
        else:
            raise AssertionError(f"{vector['vector_id']}: expected {vector.get('expected_error_code')} but succeeded")
        passed_errors.append(vector["vector_id"])

    canon_vectors = [r for r in records if r.get("record_type") == "canonicalization_test_vector"]
    if len(canon_vectors) != 1:
        raise AssertionError(f"expected one canonicalization vector, found {len(canon_vectors)}")
    canon = canon_vectors[0]
    encoded = canonical_bytes(canon["input_value"])
    actual_text = encoded.decode("utf-8")
    if actual_text != canon["expected_canonical_utf8_text"]:
        raise AssertionError(f"canonical text mismatch: {actual_text!r}")
    if hashlib.sha256(encoded).hexdigest() != canon["expected_sha256"]:
        raise AssertionError("canonicalization SHA-256 mismatch")

    unique_error_codes = sorted({v["expected_error_code"] for v in error_vectors})
    return {
        "success_vectors_passed": passed_success,
        "error_vectors_passed": passed_errors,
        "error_vector_count": len(passed_errors),
        "unique_error_code_count": len(unique_error_codes),
        "unique_error_codes": unique_error_codes,
        "canonicalization_vector_passed": canon["vector_id"],
    }


def find_repo_root(start: Path) -> Path | None:
    for candidate in (start, *start.parents):
        if (
            (candidate / "execution-information-loop" / "carrier_loop.py").is_file()
            and (candidate / "database-carrier-replication" / "implementation" / "db_is.py").is_file()
        ):
            return candidate
    return None


def find_contract_default(script_path: Path, repo_root: Path | None) -> Path | None:
    candidates: list[Path] = [script_path.parent / "calculator-contract-freeze.jsonl"]
    if repo_root is not None:
        candidates.extend([
            repo_root / "calculator-contract-freeze.jsonl",
            repo_root / "contract-assertions" / "calculator-contract-freeze.jsonl",
        ])
    env_path = os.environ.get("SIMIGO_REFERENCE_CALCULATOR_CONTRACT")
    if env_path:
        candidates.insert(0, Path(env_path).expanduser())
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return None


def sealed_policy(digest_fn: Callable[[Any], str]) -> dict:
    body = {
        "policy_version": "reference-calculator-test-v1",
        "policy_source": "FROZEN_JSONL_CONTRACT",
    }
    return {**body, "policy_sha256": digest_fn(body)}


def carrier_table_snapshot(carrier) -> dict[str, list[tuple]]:
    """Snapshot all three real append-only Carrier tables; there is no settlements table."""
    connection = carrier.connection
    queries = {
        "is_objects": "SELECT object_id, byte_size, content, created_order FROM is_objects ORDER BY created_order",
        "is_index_entries": "SELECT append_order, srs_identity, record_object FROM is_index_entries ORDER BY append_order",
        "dependency_entries": "SELECT append_order, dependency_id, content_address, revision, reason FROM dependency_entries ORDER BY append_order",
    }
    snapshot: dict[str, list[tuple]] = {}
    for table, query in queries.items():
        rows = connection.execute(query).fetchall()
        normalized = []
        for row in rows:
            normalized.append(tuple(bytes(value) if isinstance(value, memoryview) else value for value in tuple(row)))
        snapshot[table] = normalized
    return snapshot


def run_carrier_acceptance(records: list[dict], acceptance: dict, repo_root: Path) -> dict:
    sys.path.insert(0, str(repo_root / "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop, digest as carrier_digest  # noqa: E402

    initial_sources = acceptance["initial_source_payloads"]
    graph = acceptance["dependency_graph"]
    item_ids = list(initial_sources)
    if set(item_ids) != set(graph):
        raise AssertionError("initial_source_payloads and dependency_graph unit sets differ")
    policy = sealed_policy(carrier_digest)
    expected_initial = acceptance["initial_expected_results"]
    expected_after = acceptance["expected_results_after_mutation"]
    mutation = acceptance["mutation"]
    changed_unit = mutation["item_id"]
    expected_compute = set(acceptance["expected_swift_compute_unit_set"])
    expected_reuse = set(acceptance["expected_reuse_unit_set"])
    expected_new_ids = {k for k in item_ids if k not in expected_reuse}

    def bind_source(loop, item_id: str, payload: dict, version: str) -> None:
        loop.put_source(
            "demand-refcalculator-v1",
            item_id,
            "reference_calculator_fixture",
            version,
            payload,
            graph[item_id],
            valid_until_utc=VALID_UNTIL_UTC,
            validity_policy=policy,
        )

    def settlement_values(loop, expected: dict, label: str) -> dict[str, str]:
        observed: dict[str, str] = {}
        for item_id in item_ids:
            settlement = loop.current_settlement(item_id)
            if settlement is None or settlement.get("state") != "SETTLED":
                raise AssertionError(f"{label}: {item_id} has no current SETTLED record")
            stored = settlement["result"]["value"]
            if stored != expected[item_id] or set(stored) != {"swift_value"}:
                raise AssertionError(f"{label}: {item_id} settlement value mismatch: {stored!r}")
            observed[item_id] = settlement["_object_id"]
        return observed

    with tempfile.TemporaryDirectory(prefix="simigo-refcalculator-arm4-") as temporary:
        database = str(Path(temporary) / "carrier.sqlite")
        loop = CarrierInformationLoop.create(database)
        loop.define_demand(
            "demand-refcalculator-v1",
            continuation_point="reference-calculator-arm4",
            pending_obligations=["validate frozen reference calculator semantics"],
            continuation_conditions=["all required oracle results are current"],
            required_item_ids=item_ids,
        )
        for item_id in item_ids:
            bind_source(loop, item_id, initial_sources[item_id], "v1")
        loop.commit()

        initial_calls: list[str] = []
        def tracked_initial(item_id: str, payload: dict, dependencies: dict) -> dict:
            initial_calls.append(item_id)
            return reference_calculator(item_id, payload, dependencies)

        first = loop.execute_demand(
            "demand-refcalculator-v1",
            "advance-refcalculator-initial",
            tracked_initial,
            evaluated_at_utc=EVALUATED_AT_UTC,
        )
        if first.get("advanced") is not True or first.get("state") != "ADVANCED":
            raise AssertionError(f"initial demand did not advance: {first}")
        initial_actions = {item["item_id"]: item["action"] for item in first["actions"]}
        if set(initial_actions) != set(item_ids) or set(first["computed_item_ids"]) != set(item_ids):
            raise AssertionError(f"cold start did not compute all units: {initial_actions}")
        if first.get("reused_item_ids"):
            raise AssertionError(f"cold start unexpectedly reused settlements: {first['reused_item_ids']}")
        resolved_initial = first["result"]["resolved_items"]
        if resolved_initial != expected_initial:
            raise AssertionError(f"cold-start values differ: expected={expected_initial}, actual={resolved_initial}")
        if set(initial_calls) != set(item_ids):
            raise AssertionError(f"cold-start calculator invocation set mismatch: {initial_calls}")
        initial_ids = settlement_values(loop, expected_initial, "initial")
        loop.confirm_runtime_application("advance-refcalculator-initial")

        before_payload = mutation["source_payload_before"]
        after_payload = mutation["source_payload_after"]
        current = loop.current_item(changed_unit)
        if current is None or current["source_payload"] != before_payload:
            raise AssertionError("frozen mutation precondition does not match current source")
        loop.update_source(
            changed_unit,
            "v2",
            after_payload,
            "frozen P3 Arm-4 source-sensitivity mutation",
        )
        loop.commit()

        mutation_calls: list[str] = []
        def tracked_mutation(item_id: str, payload: dict, dependencies: dict) -> dict:
            mutation_calls.append(item_id)
            return reference_calculator(item_id, payload, dependencies)

        second = loop.execute_demand(
            "demand-refcalculator-v1",
            "advance-refcalculator-mutation",
            tracked_mutation,
            evaluated_at_utc=EVALUATED_AT_UTC,
        )
        if second.get("advanced") is not True or second.get("state") != "ADVANCED":
            raise AssertionError(f"mutation demand did not advance: {second}")
        actions_after = {item["item_id"]: item["action"] for item in second["actions"]}
        computed_after = set(second["computed_item_ids"])
        reused_after = set(second["reused_item_ids"])
        if computed_after != expected_compute:
            raise AssertionError(f"computed set mismatch: expected={sorted(expected_compute)}, actual={sorted(computed_after)}")
        if reused_after != expected_reuse:
            raise AssertionError(f"reused set mismatch: expected={sorted(expected_reuse)}, actual={sorted(reused_after)}")
        if {k for k, action in actions_after.items() if action == "COMPUTE"} != expected_compute:
            raise AssertionError(f"action map contradicts computed set: {actions_after}")
        if {k for k, action in actions_after.items() if action == "REUSE"} != expected_reuse:
            raise AssertionError(f"action map contradicts reused set: {actions_after}")
        if set(mutation_calls) != expected_compute:
            raise AssertionError(f"calculator call set mismatch: expected={sorted(expected_compute)}, actual={sorted(mutation_calls)}")
        resolved_after = second["result"]["resolved_items"]
        if resolved_after != expected_after:
            raise AssertionError(f"post-mutation values differ: expected={expected_after}, actual={resolved_after}")
        updated_ids = settlement_values(loop, expected_after, "after mutation")
        for item_id in item_ids:
            if item_id in expected_new_ids and updated_ids[item_id] == initial_ids[item_id]:
                raise AssertionError(f"{item_id}: recomputed settlement object_id did not change")
            if item_id in expected_reuse and updated_ids[item_id] != initial_ids[item_id]:
                raise AssertionError(f"{item_id}: reused settlement object_id unexpectedly changed")
        loop.commit()
        loop.close()

    return {
        "cold_start_values": expected_initial,
        "cold_start_calls": sorted(set(initial_calls)),
        "post_mutation_values": expected_after,
        "mutated_unit": changed_unit,
        "post_mutation_compute_set": sorted(computed_after),
        "post_mutation_reuse_set": sorted(reused_after),
        "post_mutation_calls": sorted(set(mutation_calls)),
        "settlement_identity_check": "PASS",
    }


def run_rollback_acceptance(repo_root: Path) -> dict:
    sys.path.insert(0, str(repo_root / "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop, digest as carrier_digest  # noqa: E402

    policy = sealed_policy(carrier_digest)
    calls: list[str] = []
    # A=6; B=(INT64_MAX-4)+6 overflows. A is settled first inside the
    # demand transaction, then B raises, forcing a real rollback of A's writes.
    payloads = {"A": {"input": 3}, "B": {"input": MAX_I64 - 4}}
    dependencies = {"A": [], "B": ["A"]}

    with tempfile.TemporaryDirectory(prefix="simigo-refcalculator-rollback-") as temporary:
        database = str(Path(temporary) / "rollback.sqlite")
        loop = CarrierInformationLoop.create(database)
        loop.define_demand(
            "demand-refcalculator-rollback",
            continuation_point="reference-calculator-rollback",
            pending_obligations=["prove all-or-nothing settlement transaction"],
            continuation_conditions=["A writes, then B overflows"],
            required_item_ids=["B"],
        )
        for item_id in ("A", "B"):
            loop.put_source(
                "demand-refcalculator-rollback",
                item_id,
                "reference_calculator_rollback_fixture",
                "v1",
                payloads[item_id],
                dependencies[item_id],
                valid_until_utc=VALID_UNTIL_UTC,
                validity_policy=policy,
            )
        loop.commit()
        before = carrier_table_snapshot(loop.carrier)

        def tracked(item_id: str, payload: dict, dependency_values: dict) -> dict:
            calls.append(item_id)
            return reference_calculator(item_id, payload, dependency_values)

        error_code: str | None = None
        try:
            loop.execute_demand(
                "demand-refcalculator-rollback",
                "advance-refcalculator-rollback",
                tracked,
                evaluated_at_utc=EVALUATED_AT_UTC,
            )
        except CalculatorContractError as error:
            error_code = error.code
        after = carrier_table_snapshot(loop.carrier)
        settlement_a = loop.current_settlement("A")
        settlement_b = loop.current_settlement("B")
        if error_code != "ARITHMETIC_OVERFLOW":
            raise AssertionError(f"rollback expected ARITHMETIC_OVERFLOW, observed {error_code!r}")
        if calls != ["A", "B"]:
            raise AssertionError(f"rollback did not prove a partial-write path: calculator calls={calls}")
        if before != after:
            raise AssertionError("Carrier table snapshot changed across failed demand; rollback was not atomic")
        if settlement_a is not None or settlement_b is not None:
            raise AssertionError("a settlement survived the failed transaction")
        loop.commit()
        loop.close()

    return {
        "injected_error_code": error_code,
        "calculator_calls_before_failure": calls,
        "exact_snapshot_unchanged": True,
        "no_current_settlements_survived": True,
        "tables_snapshotted": ["is_objects", "is_index_entries", "dependency_entries"],
    }


def main() -> int:
    script_path = Path(__file__).resolve()
    preliminary_root = find_repo_root(script_path.parent)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, help="path to frozen calculator-contract-freeze.jsonl")
    parser.add_argument("--oracle-only", action="store_true", help="run frozen vectors only; do not import or execute Carrier")
    args = parser.parse_args()

    contract_path = args.contract.expanduser().resolve() if args.contract else find_contract_default(script_path, preliminary_root)
    if contract_path is None:
        parser.error(
            "cannot locate calculator-contract-freeze.jsonl; pass --contract PATH or set "
            "SIMIGO_REFERENCE_CALCULATOR_CONTRACT"
        )
    header, records = load_jsonl_contract(contract_path)
    acceptance = validate_implementation_matches_contract(records)
    oracle_report = run_oracle_vectors(records)
    report: dict[str, Any] = {
        "schema_id": "SIMIGO-REFERENCE-CALCULATOR-ENTRY-TEST-REPORT-V1",
        "contract_id": header["contract_id"],
        "contract_version": header["version"],
        "contract_path": str(contract_path),
        "scope": "Python reference oracle + Carrier transaction/reuse integration; not Swift/model/KV proof",
        "oracle_vectors": oracle_report,
    }
    if not args.oracle_only:
        repo_root = find_repo_root(script_path.parent)
        if repo_root is None:
            parser.error(
                "Carrier repository root not found from this script location; place it at the planned Lab path "
                "or use --oracle-only for contract-vector validation"
            )
        report["carrier_acceptance"] = run_carrier_acceptance(records, acceptance, repo_root)
        report["rollback_acceptance"] = run_rollback_acceptance(repo_root)
    report["result"] = "PASS"
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
