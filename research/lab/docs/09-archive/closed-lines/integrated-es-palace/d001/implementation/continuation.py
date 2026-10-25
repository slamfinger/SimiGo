"""Typed authority mapping, precedence, REUSE/BLOCK, and identity."""
from __future__ import annotations

from typing import Any

from inventory import Inventory
from reconstruction import reconstruct
from schemas import BOUNDARY_DIGEST, SCHEMAS, digest, require_schema


def _base(inventory: Inventory) -> tuple[Any, Any, Any, list, Any]:
    closure, recovered, provenance, actions, invocation = reconstruct(inventory)
    authority = {
        "schema_id": SCHEMAS["authority"],
        "closure_id": closure["closure_id"],
        "closure_revision": closure["closure_revision"],
        "recovered_context_digest": recovered["context_digest"],
        "authority_objects": [r["object_id"] for r in recovered["recovered_objects"] if r["authority"]],
        "next_action": actions[0] if len(actions) == 1 else None,
        "boundary_digest": BOUNDARY_DIGEST,
    }
    return closure, recovered, authority, actions, provenance


def _input(closure: dict, recovered: dict, action) -> dict:
    return {
        "schema_id": SCHEMAS["input"],
        "closure_id": closure["closure_id"],
        "closure_revision": closure["closure_revision"],
        "recovered_context_digest": recovered["context_digest"],
        "next_action_id": action["action_id"] if action else None,
        "target_digest": action["target_digest"] if action else None,
        "continuation_class": action["continuation_class"] if action else "BLOCKED_DEFECT",
        "authorization_boundary": "D001-PACKAGE-V1.0",
    }


def _output(input_record: dict, decision: str, continuation_class: str, reason: str, secondary: list[str]) -> dict:
    return {
        "schema_id": SCHEMAS["output"],
        "input_digest": digest(input_record),
        "decision": decision,
        "continuation_class": continuation_class,
        "typed_reason": reason,
        "secondary_defects": secondary,
        "continuation_output_digest": "",
    }


def decide(inventory: Inventory) -> dict:
    try:
        closure, recovered, authority, actions, provenance = _base(inventory)
    except Exception as exc:
        case = inventory.manifest["case_id"]
        closure = {"schema_id": SCHEMAS["closure"], "closure_id": f"UNRESOLVED-{case}", "closure_revision": "UNRESOLVED", "members": [], "closure_digest": digest({"case": case, "state": "UNRESOLVED"})}
        recovered = {"schema_id": SCHEMAS["recovered"], "closure_id": closure["closure_id"], "closure_revision": closure["closure_revision"], "recovered_objects": [], "context_digest": digest({"case": case, "state": "UNRECOVERED"})}
        authority = {"schema_id": SCHEMAS["authority"], "closure_id": closure["closure_id"], "closure_revision": closure["closure_revision"], "recovered_context_digest": recovered["context_digest"], "authority_objects": [], "next_action": None, "boundary_digest": BOUNDARY_DIGEST}
        actions, provenance = [], {"records": {}}
        input_record = _input(closure, recovered, None)
        output = _output(input_record, "BLOCK", "BLOCKED_DEFECT", "MISSING_INFORMATION_BLOCK", [type(exc).__name__])
        output["continuation_output_digest"] = digest({key: output[key] for key in output if key != "continuation_output_digest"})
        identity = {"identity_version": "D001-CONTINUATION-IDENTITY-V1", "closure_id": closure["closure_id"], "closure_revision": closure["closure_revision"], "recovered_context_digest": recovered["context_digest"], "next_action_id": None, "target_digest": None, "continuation_class": "BLOCKED_DEFECT", "authorization_boundary": "D001-PACKAGE-V1.0", "continuation_output_digest": output["continuation_output_digest"]}
        return {"closure": closure, "recovered": recovered, "authority": authority, "input": input_record, "output": output, "identity": identity, "identity_digest": digest(identity), "typed_decision": "MISSING_INFORMATION_BLOCK", "precedence_reason": "MANDATORY_OBJECT_UNRESOLVABLE", "carrier_snapshot": None}

    def negative(decision_type: str, reason: str, secondary: list[str]) -> dict:
        selected = actions[0] if len(actions) == 1 else None
        input_record = _input(closure, recovered, selected)
        output = _output(input_record, "BLOCK", "BLOCKED_DEFECT", decision_type, secondary)
        output["continuation_output_digest"] = digest({key: output[key] for key in output if key != "continuation_output_digest"})
        identity = {
            "identity_version": "D001-CONTINUATION-IDENTITY-V1",
            "closure_id": closure["closure_id"], "closure_revision": closure["closure_revision"],
            "recovered_context_digest": recovered["context_digest"],
            "next_action_id": input_record["next_action_id"], "target_digest": input_record["target_digest"],
            "continuation_class": "BLOCKED_DEFECT", "authorization_boundary": "D001-PACKAGE-V1.0",
            "continuation_output_digest": output["continuation_output_digest"],
        }
        return {
            "closure": closure, "recovered": recovered, "authority": authority,
            "input": input_record, "output": output, "identity": identity,
            "identity_digest": digest(identity), "typed_decision": decision_type,
            "precedence_reason": reason, "carrier_snapshot": None,
        }

    mandatory = {"I1", "I4", "I5", "I6", "I8", "I10"}
    for family in mandatory:
        try:
            inventory.read(family)
        except Exception as exc:
            return negative("MISSING_INFORMATION_BLOCK", "MANDATORY_OBJECT_UNRESOLVABLE", [f"{family}:{type(exc).__name__}"])

    statuses = [provenance["records"][member["object_id"]]["status"] for member in closure["members"]]
    stale = [f"{member['object_id']}:{status}" for member, status in zip(closure["members"], statuses) if status != "CURRENT"]
    if stale:
        return negative("STALE_INFORMATION_BLOCK", "MANDATORY_EVIDENCE_SUPERSEDED", stale)

    if len(actions) != 1:
        return negative("AMBIGUOUS_INFORMATION_BLOCK", "CONFLICTING_VALID_POINTERS", [f"action_count={len(actions)}"])
    action = actions[0]
    if action["boundary_digest"] != BOUNDARY_DIGEST:
        return negative("ILLEGAL_CONTINUATION_BLOCK", "REGISTERED_BOUNDARY_VIOLATION_PROVEN", ["boundary_digest_mismatch"])

    input_record = _input(closure, recovered, action)
    if action["continuation_class"] == "BLOCKED_LAWFUL_CONTINUATION":
        if action.get("blocking_condition") != "REGISTERED_BLOCK":
            return negative("AMBIGUOUS_INFORMATION_BLOCK", "INVALID_REGISTERED_BLOCK", ["missing_blocking_condition"])
        output = _output(input_record, "BLOCK", "BLOCKED_LAWFUL_CONTINUATION", "REGISTERED_BLOCKING_CONDITION", [])
    else:
        snapshot = inventory.read("I3")
        require_schema(snapshot, "CARRIER-SNAPSHOT-D001-V1", {"closure_id", "approved_read", "settled_record"}, "carrier-snapshot")
        if not snapshot["approved_read"] or snapshot["closure_id"] != closure["closure_id"]:
            return negative("ILLEGAL_CONTINUATION_BLOCK", "CARRIER_READ_BINDING_INVALID", ["carrier_snapshot"])
        reuse = bool(snapshot["settled_record"])
        output = _output(input_record, "REUSE" if reuse else "CONTINUE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE" if reuse else "LAWFUL_CURRENT_CONTINUATION", [])

    output["continuation_output_digest"] = digest({key: output[key] for key in output if key != "continuation_output_digest"})
    identity = {
        "identity_version": "D001-CONTINUATION-IDENTITY-V1",
        "closure_id": closure["closure_id"], "closure_revision": closure["closure_revision"],
        "recovered_context_digest": recovered["context_digest"],
        "next_action_id": input_record["next_action_id"], "target_digest": input_record["target_digest"],
        "continuation_class": output["continuation_class"], "authorization_boundary": "D001-PACKAGE-V1.0",
        "continuation_output_digest": output["continuation_output_digest"],
    }
    carrier_snapshot = None
    if output["decision"] == "REUSE":
        carrier_snapshot = inventory.read("I3")
        settled = carrier_snapshot["settled_record"]
        if settled.get("continuation_output_digest") != output["continuation_output_digest"] or settled.get("continuation_identity_digest") != digest(identity):
            return negative("AMBIGUOUS_INFORMATION_BLOCK", "REUSE_IDENTITY_MISMATCH", ["settled_record"])
    return {
        "closure": closure, "recovered": recovered, "authority": authority,
        "input": input_record, "output": output, "identity": identity,
        "identity_digest": digest(identity), "typed_decision": output["decision"],
        "precedence_reason": output["typed_reason"], "carrier_snapshot": carrier_snapshot,
    }
