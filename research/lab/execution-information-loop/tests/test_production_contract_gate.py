"""Production-path tests for the declarative result gate.

These exercise the REAL functions the production bridge calls:
``production_runtime_bridge._validate_model_value`` (which is a thin delegation
to ``declarative_result_contract.validate_declared_result``), the contract
builders the H/I/J graphs use to declare their items, and the bridge source text
itself as the static proof that result semantics no longer key on task item ids.
"""
from __future__ import annotations

import ast
import importlib.util
import re
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
LOOP_ROOT = HERE.parent
sys.path.insert(0, str(LOOP_ROOT))

import declarative_result_contract as engine  # noqa: E402
import production_runtime_bridge as bridge  # noqa: E402

BRIDGE_SOURCE = (LOOP_ROOT / "production_runtime_bridge.py").read_text(
    encoding="utf-8")

TEXT_GOOD = ("ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5\n")


def route_world(origin_id: str, dest_id: str, u1_id: str) -> dict:
    """An item declaration whose dependency ids are the caller's, verbatim."""
    return {
        "input_bindings": [
            {"placeholder": "origin", "item_id": origin_id,
             "result_field": "origin_code"},
            {"placeholder": "origin_priority", "item_id": origin_id,
             "result_field": "priority"},
            {"placeholder": "destination", "item_id": dest_id,
             "result_field": "destination_code"},
            {"placeholder": "destination_priority", "item_id": dest_id,
             "result_field": "priority"},
        ],
        "semantic_contract": bridge.route_synthesis_contract(
            origin_binding="origin", destination_binding="destination",
            destination_priority_binding="destination_priority"),
    }


def route_pair(origin_id: str, dest_id: str, u1_id: str,
               origin_priority: str = "3",
               destination_priority: str = "5") -> tuple:
    """An item declaration plus the admitted closure it must be validated in."""
    payload = route_world(origin_id, dest_id, u1_id)
    dependencies = {
        origin_id: {"origin_code": "NORTH", "priority": origin_priority},
        dest_id: {"destination_code": "EAST", "priority": destination_priority},
    }
    return payload, dependencies


def producer_value(text: str) -> dict:
    return {"raw_generated_text": text,
            "generated_token_ids": [1, 2, 3],
            "model_snapshot_revision": "snapshot-under-test"}


class IdIndependentValidation(unittest.TestCase):
    def test_same_contract_same_result_for_two_runtime_ids(self):
        first = bridge._validate_model_value(
            route_world("J-a7f3-ORIGIN", "J-a7f3-DEST", "J-a7f3-U1"),
            producer_value(TEXT_GOOD),
            {"J-a7f3-ORIGIN": {"origin_code": "NORTH", "priority": "3"},
             "J-a7f3-DEST": {"destination_code": "EAST", "priority": "5"}})
        second = bridge._validate_model_value(
            route_world("J-b18c-ORIGIN", "J-b18c-DEST", "J-b18c-U1"),
            producer_value(TEXT_GOOD),
            {"J-b18c-ORIGIN": {"origin_code": "NORTH", "priority": "3"},
             "J-b18c-DEST": {"destination_code": "EAST", "priority": "5"}})
        self.assertEqual(first["values"], second["values"])
        self.assertEqual(first["constraint_checks"],
                         second["constraint_checks"])
        self.assertEqual(first["validation_status"], "VALID")

    def test_missing_required_field_rejects(self):
        payload, deps = route_pair("o", "d", "u1")
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(
                payload,
                producer_value("ORIGIN=NORTH\nDEST=EAST\nPRIORITY=5\n"),
                deps)
        self.assertEqual(caught.exception.code, "PRODUCER_RESULT_FIELD_MISSING")

    def test_binding_mismatch_rejects(self):
        payload, deps = route_pair("o", "d", "u1")
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(
                payload,
                producer_value(
                    "ORIGIN=SOUTH\nDEST=EAST\nROUTE=SOUTH>EAST\nPRIORITY=5\n"),
                deps)
        self.assertEqual(caught.exception.code,
                         "PRODUCER_RESULT_BINDING_MISMATCH")

    def test_derived_field_mismatch_rejects(self):
        payload, deps = route_pair("o", "d", "u1")
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(
                payload,
                producer_value(
                    "ORIGIN=NORTH\nDEST=EAST\nROUTE=EAST>NORTH\nPRIORITY=5\n"),
                deps)
        self.assertEqual(caught.exception.code,
                         "PRODUCER_RESULT_DERIVATION_MISMATCH")

    def test_priority_must_come_from_the_destination_binding(self):
        payload, deps = route_pair("o", "d", "u1")
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(
                payload,
                producer_value(TEXT_GOOD.replace("PRIORITY=5", "PRIORITY=3")),
                deps)
        self.assertEqual(caught.exception.code,
                         "PRODUCER_RESULT_BINDING_MISMATCH")


class FailClosedContractHandling(unittest.TestCase):
    def test_undeclared_contract_is_refused_not_guessed(self):
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(
                {"input_bindings": []}, producer_value(TEXT_GOOD), {})
        self.assertEqual(caught.exception.code,
                         "PRODUCER_RESULT_CONTRACT_UNDECLARED")

    def test_unknown_schema_version_fails_closed(self):
        payload, deps = route_pair("o", "d", "u1")
        payload["semantic_contract"]["schema_version"] = "simigo.result-contract/v9"
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(payload, producer_value(TEXT_GOOD), deps)
        self.assertEqual(caught.exception.code,
                         "CONTRACT_UNKNOWN_SCHEMA_VERSION")

    def test_producer_value_disagreeing_with_its_own_text_rejects(self):
        payload, deps = route_pair("o", "d", "u1")
        value = producer_value(TEXT_GOOD)
        value["route_key"] = "NORTH>WEST"
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(payload, value, deps)
        self.assertEqual(caught.exception.code,
                         "PRODUCER_RESULT_VALUE_TEXT_DISAGREEMENT")

    def test_ambiguous_binding_source_fails_closed(self):
        payload = {
            "input_bindings": [],
            "semantic_contract": {
                "schema_version": engine.CONTRACT_VERSION,
                "fields": {"route_key": {"pattern": "ROUTE=([A-Z>]+)"}},
                "bindings": [{"name": "priority", "source": "dependency_field",
                              "field": "priority"}],
                "constraints": [],
            },
        }
        with self.assertRaises(engine.ContractError) as caught:
            bridge._validate_model_value(
                payload, producer_value("ROUTE=NORTH>EAST\n"),
                {"a": {"priority": "3"}, "b": {"priority": "5"}})
        self.assertEqual(caught.exception.code,
                         "CONTRACT_AMBIGUOUS_BINDING_SOURCE")


class LegacyHContractsStillHold(unittest.TestCase):
    """The migrated H-round declarations keep the old item-id semantics."""

    def test_u1_secret_must_commit_to_the_settled_digest(self):
        from carrier_loop import digest
        secret = "0123456789abcdef"
        payload = {
            "input_bindings": [],
            "semantic_contract": {
                "schema_version": engine.CONTRACT_VERSION,
                "fields": {"secret": {
                    "pattern": "SECRET=([0-9a-f]{16})", "capture_group": 1}},
                "bindings": [{"name": "secret_commitment",
                              "source": "dependency_field",
                              "field": "secret_sha256"}],
                "constraints": [{"kind": "digest_equals_binding",
                                 "field": "secret",
                                 "binding": "secret_commitment"}],
            },
        }
        good = bridge._validate_model_value(
            payload, producer_value("SECRET=%s\n" % secret),
            {"SRC": {"secret_sha256": digest(secret)}})
        self.assertEqual(good["validation_status"], "VALID")
        with self.assertRaises(engine.ContractError):
            bridge._validate_model_value(
                payload, producer_value("SECRET=%s\n" % secret),
                {"SRC": {"secret_sha256": digest("fedcba9876543210")}})

    def test_u3_stamp_must_be_the_answer_prefix(self):
        payload = {
            "input_bindings": [],
            "semantic_contract": {
                "schema_version": engine.CONTRACT_VERSION,
                "fields": {"stamp": {"pattern": "STAMP=([0-9a-f]+)"}},
                "bindings": [{"name": "answer", "source": "dependency_field",
                              "field": "answer"}],
                "constraints": [{"kind": "equals_binding_segment",
                                 "field": "stamp", "binding": "answer",
                                 "separator": "-", "segment": 0}],
            },
        }
        good = bridge._validate_model_value(
            payload, producer_value("STAMP=0123456789abcdef\n"),
            {"U2": {"answer": "0123456789abcdef-abcd"}})
        self.assertEqual(good["validation_status"], "VALID")
        with self.assertRaises(engine.ContractError):
            bridge._validate_model_value(
                payload, producer_value("STAMP=abcd\n"),
                {"U2": {"answer": "0123456789abcdef-abcd"}})


class NoItemIdentityDispatch(unittest.TestCase):
    """Static proof: the production validation path takes no item id as input."""

    def _function(self, name: str) -> ast.FunctionDef:
        tree = ast.parse(BRIDGE_SOURCE)
        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and node.name == name:
                return node
        raise AssertionError("function %s not found in the bridge" % name)

    def test_gate_is_not_given_an_item_id(self):
        gate = self._function("_validate_model_value")
        names = [arg.arg for arg in gate.args.args]
        self.assertNotIn("item_id", names)
        self.assertEqual(names, ["source_payload", "value", "dependency_values"])

    def test_bridge_has_no_item_id_equality_branches(self):
        self.assertIsNone(
            re.search(r"item_id\s*==\s*[\"']TASK", BRIDGE_SOURCE),
            "result validation must not branch on literal task item ids")

    def test_reference_contract_validates_against_the_engine(self):
        import json
        contract = json.loads(
            (LOOP_ROOT / "example_result_contract.json").read_text())
        report = engine.validate_result_text(
            TEXT_GOOD, contract,
            {"origin_code": "NORTH", "destination_code": "EAST",
             "priority": 5})
        self.assertEqual(report["validation_status"], "VALID")

    def test_runtime_j_ids_are_not_known_to_the_source(self):
        seen = re.findall(r"\"J-[0-9a-zA-Z]+-(?:U1|U2|U3)\"", BRIDGE_SOURCE)
        self.assertEqual(seen, [], "unseen ids must not be hardcoded")


if __name__ == "__main__":
    unittest.main()
