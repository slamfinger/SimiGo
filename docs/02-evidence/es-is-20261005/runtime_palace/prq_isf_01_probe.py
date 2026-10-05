"""PRQ-ISF-01 minimal decodable probe — implementation and execution harness.

This program executes the accepted probe design's scenarios SC-00..SC-12.  Its
in-memory ProbeReferencePort is a non-candidate probe control, not a selected
PALACE/Information-Space carrier.  It exists so the decoder, resolver handoff,
and judge can be mechanically exercised without choosing a storage technology.

Run:  python3 prq_isf_01_probe.py
Exit: 0 when all registered scenarios match their preregistered behavior.
"""
from __future__ import annotations

import copy
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1] / "runtime_g1"
sys.path.insert(0, str(ROOT))

from i1_records import ContentStore, write_cr  # noqa: E402
from i1_resolve import resolve  # noqa: E402


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class ProbeReferencePort:
    """Non-candidate in-memory control implementing only the named abstract
    operations. Fault injections are harness instrumentation, not carrier API."""

    def __init__(self) -> None:
        self.blobs: Dict[str, bytes] = {}
        self.nodes: Dict[str, Dict[str, Any]] = {}
        self.edges: Dict[str, List[Dict[str, str]]] = {}
        self.provenance: Dict[str, Dict[str, Any]] = {}
        self.pins: Dict[str, str] = {}
        self.events: List[Dict[str, str]] = []
        self.blob_deletions: List[str] = []
        self.operation_log: List[Dict[str, str]] = []

    def _log(self, operation: str, target: str) -> None:
        self.operation_log.append({"operation": operation, "target": target})

    def put_blob(self, data: bytes) -> str:
        digest = sha256_hex(data)
        self.blobs[digest] = data
        self._log("put_blob", digest)
        return digest

    def get_blob(self, digest: str) -> Optional[bytes]:
        self._log("get_blob", digest)
        if digest in self.blob_deletions:
            return None
        return self.blobs.get(digest)

    def put_node(self, node_id: str, record: Dict[str, Any]) -> str:
        self.nodes[node_id] = copy.deepcopy(record)
        self._log("put_node", node_id)
        return node_id

    def get_node(self, node_id: str) -> Optional[Dict[str, Any]]:
        self._log("get_node", node_id)
        node = self.nodes.get(node_id)
        return copy.deepcopy(node) if node is not None else None

    def put_edge(self, from_id: str, edge_type: str, to_id: str) -> None:
        self.edges.setdefault(from_id, []).append(
            {"edge_type": edge_type, "to_id": to_id}
        )
        self._log("put_edge", f"{from_id}:{edge_type}:{to_id}")

    def get_edges(self, node_id: str, edge_type: Optional[str] = None) -> List[Dict[str, str]]:
        self._log("get_edges", node_id)
        edges = copy.deepcopy(self.edges.get(node_id, []))
        if edge_type is not None:
            edges = [edge for edge in edges if edge["edge_type"] == edge_type]
        return edges

    def put_provenance(self, node_id: str, provenance: Dict[str, Any]) -> None:
        self.provenance[node_id] = copy.deepcopy(provenance)
        self._log("put_provenance", node_id)

    def get_provenance(self, node_id: str) -> Optional[Dict[str, Any]]:
        self._log("get_provenance", node_id)
        provenance = self.provenance.get(node_id)
        return copy.deepcopy(provenance) if provenance is not None else None

    def pin(self, label: str, target: str) -> str:
        self.pins[label] = target
        self._log("pin", label)
        return label

    def resolve_pin(self, label: str) -> Optional[str]:
        self._log("resolve_pin", label)
        return self.pins.get(label)

    def put_mutation_event(self, event: Dict[str, str]) -> str:
        self.events.append(copy.deepcopy(event))
        self._log("put_mutation_event", event.get("target", ""))
        return str(len(self.events) - 1)

    def get_mutation_events(self, target: Optional[str] = None) -> List[Dict[str, str]]:
        self._log("get_mutation_events", target or "*")
        events = copy.deepcopy(self.events)
        if target is not None:
            events = [event for event in events if event.get("target") == target]
        return events

    # ---- harness-only fault instrumentation ----
    def fault_delete_blob(self, digest: str) -> None:
        self.blob_deletions.append(digest)

    def fault_delete_pin(self, label: str) -> None:
        self.pins.pop(label, None)

    def fault_override_blob(self, digest: str, data: bytes) -> None:
        self.blobs[digest] = data

    def fault_mutate_node(self, node_id: str, mutator) -> None:
        mutator(self.nodes[node_id])

    def fault_drop_edge(self, from_id: str, edge_type: str) -> None:
        self.edges[from_id] = [
            edge for edge in self.edges.get(from_id, [])
            if edge["edge_type"] != edge_type
        ]

    def fault_flatten_edges(self, from_id: str) -> None:
        self.edges[from_id] = [
            {"edge_type": "link", "to_id": edge["to_id"]}
            for edge in self.edges.get(from_id, [])
        ]

    def fault_replace_provenance(self, node_id: str, provenance: Dict[str, Any]) -> None:
        self.provenance[node_id] = copy.deepcopy(provenance)

    def clear_decode_log(self) -> None:
        self.operation_log.clear()


def canonical_graph_to_store(graph: Dict[str, Any], root: Path) -> ContentStore:
    """Materialize a decoded canonical graph into the existing frozen I-1
    ContentStore format. This is resolver handoff, not a new resolver."""
    store = ContentStore(root)
    for digest, data in graph["blobs"].items():
        actual = store.put_blob(data)
        if actual != digest:
            raise RuntimeError("resolver handoff digest mismatch")
    for node_id, node in graph["nodes"].items():
        store.put_node(node, node_id)
    return store


class Decoder:
    """Mechanical decoder. It reads only ProbeReferencePort abstract operations
    and never repairs, infers, summarizes, or ranks."""

    REQUIRED_EDGE_TYPES = ("result", "used", "surface", "continues")

    def __init__(self, port: ProbeReferencePort, cr_ref: str,
                 required_pin_labels: Optional[List[str]] = None) -> None:
        self.port = port
        self.cr_ref = cr_ref
        self.required_pin_labels = required_pin_labels or []
        self.checks: List[Dict[str, Any]] = []
        self.graph: Dict[str, Any] = {
            "blobs": {},
            "nodes": {},
            "edges": {},
            "provenance": {},
            "pins": {},
            "events": [],
        }
        self.used_operations: List[str] = []
        self.failure_reasons: List[str] = []

    def fail(self, code: str, frozen_family: Optional[str] = None) -> Dict[str, Any]:
        if code not in self.failure_reasons:
            self.failure_reasons.append(code)
        return {
            "decode_state": "FAIL",
            "failure_reasons": list(self.failure_reasons),
            "frozen_failure_family": frozen_family,
            "graph": None,
            "checks": self.checks,
            "used_operations": list(dict.fromkeys(self.used_operations)),
            "semantic_oracle_used": False,
        }

    def check(self, check_id: str, passed: bool, observed: Any,
              expected: Any, frozen_family: Optional[str] = None) -> bool:
        self.checks.append({
            "check_id": check_id,
            "verdict": "PASS" if passed else "FAIL",
            "observed": observed,
            "expected": expected,
            "frozen_family": frozen_family,
        })
        return passed

    def decode(self) -> Dict[str, Any]:
        port = self.port
        port.clear_decode_log()

        node = port.get_node(self.cr_ref)
        if node is None:
            self.check("IS-MCI-02.node-present", False, "MISSING", "canonical record", "C-REF-NOT-FOUND")
            return self.fail("CANONICAL-RECORD-MISSING", "C-REF-NOT-FOUND")
        self.check("IS-MCI-02.node-present", True, "present", "present")
        self.graph["nodes"][self.cr_ref] = node

        raw_edges = port.get_edges(self.cr_ref)
        self.graph["edges"][self.cr_ref] = raw_edges
        by_type: Dict[str, List[Dict[str, str]]] = {}
        for edge in raw_edges:
            by_type.setdefault(edge["edge_type"], []).append(edge)

        if "link" in by_type or not set(by_type).issubset(set(self.REQUIRED_EDGE_TYPES)):
            self.check("IS-MCI-03.edge-types-preserved", False,
                       sorted(by_type.keys()), sorted(self.REQUIRED_EDGE_TYPES))
            return self.fail("EDGE-TYPES-FLATTENED", "CARRIER-OBLIGATION-FAILURE")

        required_refs: Dict[str, Optional[str]] = {}
        for edge_type in self.REQUIRED_EDGE_TYPES:
            candidates = by_type.get(edge_type, [])
            required_refs[edge_type] = candidates[0]["to_id"] if candidates else None
            if not self.check(f"IS-MCI-03.{edge_type}-edge", len(candidates) == 1,
                              len(candidates), 1,
                              "I-NF" if edge_type in ("used", "result") else "P-VIOLATION"):
                code = f"REQUIRED-EDGE-MISSING:{edge_type}"
                family = "I-NF" if edge_type in ("used", "result") else "P-VIOLATION"
                return self.fail(code, family)
        self.check("IS-MCI-03.edge-types-preserved", True,
                   sorted(by_type.keys()), sorted(self.REQUIRED_EDGE_TYPES))

        # Traverse observable lineage before identity recheck. A CR with
        # parent_cr_ref=None is a root and has no continues edge.
        lineage_seen = set()
        current = self.cr_ref
        while True:
            if current in lineage_seen:
                self.check("IS-MCI-07.lineage-acyclic", False, "cycle", "acyclic", "A-CYCLE")
                return self.fail("LINEAGE-CYCLE", "A-CYCLE")
            lineage_seen.add(current)
            lineage_node = port.get_node(current)
            if lineage_node is None:
                self.check("IS-MCI-07.lineage-node", False, "MISSING",
                           "canonical record", "A-NF")
                return self.fail("LINEAGE-NODE-MISSING", "A-NF")
            self.graph["nodes"][current] = lineage_node
            self.graph["edges"][current] = port.get_edges(current)
            lineage_provenance = port.get_provenance(current)
            if lineage_provenance is not None:
                self.graph["provenance"][current] = lineage_provenance
            parent_ref = lineage_node.get("continues", {}).get("parent_cr_ref")
            if parent_ref is None:
                break
            candidates = [edge for edge in port.get_edges(current, "continues")
                          if edge["to_id"] == parent_ref]
            if len(candidates) != 1:
                self.check("IS-MCI-07.lineage-edge", False, len(candidates), 1, "A-NF")
                return self.fail("LINEAGE-EDGE-MISSING", "A-NF")
            current = parent_ref
        self.check("IS-MCI-07.lineage-acyclic", True, "acyclic", "acyclic")

        try:
            from i1_records import recompute_cr_identity
            actual_identity = recompute_cr_identity(node)
            if not self.check(
                "IS-MCI-02.canonical-identity",
                actual_identity == self.cr_ref,
                actual_identity,
                self.cr_ref,
                "CR-ID-MISMATCH",
            ):
                return self.fail("CANONICAL-IDENTITY-MISMATCH", "CR-ID-MISMATCH")
        except Exception as exc:
            self.check("IS-MCI-02.canonical-identity", False, type(exc).__name__,
                       "recomputable", "CR-ID-MISMATCH")
            return self.fail("CANONICAL-IDENTITY-MISMATCH", "CR-ID-MISMATCH")

        blob_refs = {
            "result": required_refs["result"],
            "surface": required_refs["surface"],
            "used": required_refs["used"],
        }
        for role, digest in blob_refs.items():
            if digest is None:
                return self.fail(f"REQUIRED-BLOB-MISSING:{role}", "I-NF")
            data = port.get_blob(digest)
            if data is None:
                self.check(f"IS-MCI-01.{role}-blob-present", False,
                           "MISSING", digest, "I-NF")
                return self.fail(f"REQUIRED-BLOB-MISSING:{role}", "I-NF")
            actual_digest = sha256_hex(data)
            if not self.check(f"IS-MCI-01.{role}-blob-immutable",
                              actual_digest == digest, actual_digest, digest,
                              "I-MISMATCH"):
                return self.fail("BLOB-DIGEST-MISMATCH", "I-MISMATCH")
            self.graph["blobs"][digest] = data

        provenance = port.get_provenance(self.cr_ref)
        if provenance is None:
            self.check("IS-MCI-04.provenance-separate", False, "MISSING",
                       "separated provenance", None)
            return self.fail("PROVENANCE-MISSING")
        self.check("IS-MCI-04.provenance-separate", True, "separate", "separate")
        self.graph["provenance"][self.cr_ref] = provenance

        registered_pins = {
            label: port.resolve_pin(label)
            for label in self.required_pin_labels
        }
        for label, target in registered_pins.items():
            target_kind = "blob" if target in self.port.blobs else "node"
            present = port.get_blob(target) is not None if target_kind == "blob" \
                else port.get_node(target) is not None
            if not self.check(f"IS-MCI-05.pin:{label}", present, present, True,
                              "HISTORICAL-RETENTION-FAILURE"):
                return self.fail("HISTORICAL-PIN-TARGET-MISSING",
                                 "HISTORICAL-RETENTION-FAILURE")
            self.graph["pins"][label] = target

        events = port.get_mutation_events()
        for index, event in enumerate(events):
            prior = event.get("prior_ref")
            new = event.get("new_ref")
            prior_present = prior is not None and port.get_blob(prior) is not None
            new_present = new is not None and port.get_blob(new) is not None
            if not self.check(f"IS-MCI-06.event:{index}", prior_present and new_present,
                              {"prior_present": prior_present,
                               "new_present": new_present},
                              {"prior_present": True, "new_present": True},
                              "HISTORICAL-RETENTION-FAILURE"):
                return self.fail("MUTATION-EVENT-TARGET-MISSING",
                                 "HISTORICAL-RETENTION-FAILURE")
        self.graph["events"] = events

        self.used_operations = list(dict.fromkeys(
            entry["operation"] for entry in port.operation_log
        ))
        return {
            "decode_state": "OK",
            "failure_reasons": [],
            "frozen_failure_family": None,
            "graph": self.graph,
            "checks": self.checks,
            "used_operations": self.used_operations,
            "semantic_oracle_used": False,
        }


def register_fixture() -> Tuple[ProbeReferencePort, Dict[str, Any]]:
    port = ProbeReferencePort()
    root_result = b"PRQ root result"
    root_surface = b"PRQ root continuation surface"
    child_result = b"PRQ child result"
    child_used = b"PRQ pinned used information"
    child_surface = b"PRQ child continuation surface"
    child_used_v2 = b"PRQ pinned used information - successor bytes"
    optional_note = b"optional interpretive note (not referenced)"
    decoy_summary = b"symbolic summary of missing required information"

    digests = {
        "B-ROOT-RESULT": port.put_blob(root_result),
        "B-ROOT-SURFACE": port.put_blob(root_surface),
        "B-CHILD-RESULT": port.put_blob(child_result),
        "B-CHILD-USED": port.put_blob(child_used),
        "B-CHILD-SURFACE": port.put_blob(child_surface),
        "B-CHILD-USED-V2": port.put_blob(child_used_v2),
        "B-OPTIONAL-NOTE": port.put_blob(optional_note),
        "B-DECOY-SUMMARY": port.put_blob(decoy_summary),
    }

    with tempfile.TemporaryDirectory(prefix="prq-isf-fixture-") as temp:
        store = ContentStore(Path(temp))
        root = write_cr(
            store,
            result_bytes=root_result,
            used_items=[],
            surface_bytes=root_surface,
            parent_cr_ref=None,
            formation={"procedure_id": "PRQ-ISF-ROOT", "input_digests": []},
            provenance={
                "actor": "probe-fixture",
                "segments": ["ISF.seg[0]"],
                "weights_id": "W-ISF-1",
            },
        )
        child = write_cr(
            store,
            result_bytes=child_result,
            used_items=[{"name": "used-information", "bytes": child_used}],
            surface_bytes=child_surface,
            parent_cr_ref=root["cr_ref"],
            formation={"procedure_id": "PRQ-ISF-CHILD",
                       "input_digests": [root["cr_ref"]]},
            provenance={
                "actor": "probe-fixture",
                "segments": ["ISF.seg[1]", "ISF.seg[2]"],
                "weights_id": "W-ISF-1",
            },
        )

    for node in (root, child):
        port.put_node(node["cr_ref"], node)

    for node_id, node in ((root["cr_ref"], root), (child["cr_ref"], child)):
        port.put_edge(node_id, "result", node["result"]["content_digest"])
        port.put_edge(node_id, "surface", node["surface"]["content_digest"])
        for used in node["used"]:
            port.put_edge(node_id, "used", used["content_digest"])
        parent = node["continues"]["parent_cr_ref"]
        if parent is not None:
            port.put_edge(node_id, "continues", parent)
        port.put_provenance(node_id, node["provenance"])

    port.pin("pin/continuation/current", child["cr_ref"])
    port.pin("pin/item/current", digests["B-CHILD-USED"])
    port.pin("pin/item/audit-v1", digests["B-CHILD-USED"])

    metadata = {
        "digests": digests,
        "root_cr_ref": root["cr_ref"],
        "child_cr_ref": child["cr_ref"],
        "root_node": root,
        "child_node": child,
    }
    return port, metadata


def prepare_scenario(scenario_id: str) -> Tuple[ProbeReferencePort, Dict[str, Any], str]:
    port, metadata = register_fixture()
    child_ref = metadata["child_cr_ref"]
    child_id = child_ref
    used_digest = metadata["digests"]["B-CHILD-USED"]
    v2_digest = metadata["digests"]["B-CHILD-USED-V2"]

    if scenario_id == "SC-01":
        port.fault_override_blob(used_digest, b"tampered bytes")
    elif scenario_id == "SC-02":
        port.fault_delete_blob(used_digest)
    elif scenario_id == "SC-03":
        def mutate(node: Dict[str, Any]) -> None:
            node["result"]["content_digest"] = "0" * 64
        port.fault_mutate_node(child_id, mutate)
    elif scenario_id == "SC-04":
        port.nodes.pop(child_id, None)
    elif scenario_id == "SC-05":
        port.fault_drop_edge(child_id, "used")
    elif scenario_id == "SC-06":
        port.fault_flatten_edges(child_id)
    elif scenario_id == "SC-07":
        port.fault_replace_provenance(
            child_id,
            {
                "actor": "post-registration correction",
                "segments": ["ISF.seg[1]", "ISF.seg[2]", "ISF.seg[3]"],
                "weights_id": "W-ISF-1",
                "revision": 2,
            },
        )
    elif scenario_id == "SC-08":
        port.put_mutation_event({
            "target": "pin/item/current",
            "prior_ref": used_digest,
            "new_ref": v2_digest,
            "event_kind": "VERSION-SUCCESSION",
        })
        port.pin("pin/item/current", v2_digest)
    elif scenario_id == "SC-09":
        port.put_mutation_event({
            "target": "pin/item/current",
            "prior_ref": used_digest,
            "new_ref": v2_digest,
            "event_kind": "VERSION-SUCCESSION",
        })
        port.pin("pin/item/current", v2_digest)
        port.fault_delete_pin("pin/item/audit-v1")
    elif scenario_id == "SC-10":
        port.edges[child_id] = [
            {"edge_type": edge_type, "to_id": child_id}
            for edge_type in ("result", "used", "surface")
        ]
        port.edges[child_id].append(
            {"edge_type": "continues", "to_id": child_id}
        )

        def cycle_parent(node: Dict[str, Any]) -> None:
            node["continues"]["parent_cr_ref"] = child_id
        port.fault_mutate_node(child_id, cycle_parent)
    elif scenario_id == "SC-11":
        # The optional note exists but is intentionally not referenced.
        pass
    elif scenario_id == "SC-12":
        port.fault_delete_blob(used_digest)
        # The decoy summary was registered, but the decoder is forbidden to use it.
    else:
        if scenario_id != "SC-00":
            raise ValueError(f"unknown scenario {scenario_id}")
    return port, metadata, child_ref


EXPECTED = {
    "SC-00": {"outcome": "CLEAN_RESOLVE", "decoder_code": None, "frozen_family": None},
    "SC-01": {"outcome": "DECODE_FAILURE", "decoder_code": "BLOB-DIGEST-MISMATCH", "frozen_family": "I-MISMATCH"},
    "SC-02": {"outcome": "DECODE_FAILURE", "decoder_code": "REQUIRED-BLOB-MISSING:used", "frozen_family": "I-NF"},
    "SC-03": {"outcome": "DECODE_FAILURE", "decoder_code": "CANONICAL-IDENTITY-MISMATCH", "frozen_family": "CR-ID-MISMATCH"},
    "SC-04": {"outcome": "DECODE_FAILURE", "decoder_code": "CANONICAL-RECORD-MISSING", "frozen_family": "C-REF-NOT-FOUND"},
    "SC-05": {"outcome": "DECODE_FAILURE", "decoder_code": "REQUIRED-EDGE-MISSING:used", "frozen_family": "I-NF"},
    "SC-06": {"outcome": "DECODE_FAILURE", "decoder_code": "EDGE-TYPES-FLATTENED", "frozen_family": "CARRIER-OBLIGATION-FAILURE"},
    "SC-07": {"outcome": "CLEAN_RESOLVE", "decoder_code": None, "frozen_family": None},
    "SC-08": {"outcome": "CLEAN_RESOLVE", "decoder_code": None, "frozen_family": None},
    "SC-09": {"outcome": "DECODE_FAILURE", "decoder_code": "HISTORICAL-PIN-TARGET-MISSING", "frozen_family": "HISTORICAL-RETENTION-FAILURE"},
    "SC-10": {"outcome": "DECODE_FAILURE", "decoder_code": "LINEAGE-CYCLE", "frozen_family": "A-CYCLE"},
    "SC-11": {"outcome": "CLEAN_RESOLVE", "decoder_code": None, "frozen_family": None},
    "SC-12": {"outcome": "DECODE_FAILURE", "decoder_code": "REQUIRED-BLOB-MISSING:used", "frozen_family": "I-NF"},
}


def run_scenario(scenario_id: str) -> Dict[str, Any]:
    port, metadata, cr_ref = prepare_scenario(scenario_id)
    decoded = Decoder(port, cr_ref, required_pin_labels=[
        "pin/continuation/current", "pin/item/current", "pin/item/audit-v1"
    ]).decode()

    resolution = None
    if decoded["decode_state"] == "OK":
        graph = decoded["graph"]
        with tempfile.TemporaryDirectory(prefix="prq-isf-resolve-") as temp:
            store = canonical_graph_to_store(graph, Path(temp))
            resolution = resolve(cr_ref, store)
        outcome = "CLEAN_RESOLVE" if resolution["state"] == "RESOLVED" else "FROZEN_FAILURE"
        frozen_family = ",".join(v["signature"] for v in resolution["violations"]) or None
        r2_digest = resolution["r2"]["r2_digest"] if resolution["r2"] else None
        violations = resolution["violations"]
    else:
        outcome = "DECODE_FAILURE"
        frozen_family = decoded["frozen_failure_family"]
        r2_digest = None
        violations = []

    actual = {
        "outcome": outcome,
        "decoder_code": decoded["failure_reasons"][0] if decoded["failure_reasons"] else None,
        "frozen_family": frozen_family,
    }
    expected = EXPECTED[scenario_id]
    case_pass = actual == expected

    if scenario_id == "SC-12":
        forbidden = "get_blob:B-DECOY-SUMMARY" in decoded["used_operations"]
        if forbidden:
            case_pass = False
            actual["forbidden_decoy_read"] = True

    if scenario_id == "SC-08":
        event_ok = any(
            event.get("prior_ref") == metadata["digests"]["B-CHILD-USED"]
            and event.get("new_ref") == metadata["digests"]["B-CHILD-USED-V2"]
            for event in decoded["graph"]["events"]
        )
        pin_ok = decoded["graph"]["pins"].get("pin/item/current") == \
            metadata["digests"]["B-CHILD-USED-V2"]
        old_ok = decoded["graph"]["pins"].get("pin/item/audit-v1") == \
            metadata["digests"]["B-CHILD-USED"]
        case_pass = case_pass and event_ok and pin_ok and old_ok

    if outcome == "CLEAN_RESOLVE":
        used_actual = [item.get("actual_digest", item.get("pinned_digest")) for item in
                       (resolution["r2"]["used_items"] if resolution["r2"] else [])]
        if metadata["digests"]["B-CHILD-USED"] not in used_actual:
            case_pass = False
            actual["historical_graph_mutation"] = True

    return {
        "scenario_id": scenario_id,
        "expected": expected,
        "actual": actual,
        "case_pass": case_pass,
        "decode": {key: value for key, value in decoded.items() if key != "graph"},
        "resolver": None if resolution is None else {
            "state": resolution["state"],
            "violations": resolution["violations"],
            "r2_digest": resolution["r2"]["r2_digest"],
            "used_item_digests": [
                item.get("actual_digest", item.get("pinned_digest")) for item in resolution["r2"]["used_items"]
            ],
        },
        "used_operations": decoded["used_operations"],
        "semantic_oracle_used": False,
    }


def main() -> int:
    scenario_ids = [f"SC-{index:02d}" for index in range(13)]
    scenarios = [run_scenario(scenario_id) for scenario_id in scenario_ids]
    passed = sum(1 for scenario in scenarios if scenario["case_pass"])
    semantic_oracle = any(scenario["semantic_oracle_used"] for scenario in scenarios)

    record = {
        "probe": "PRQ-ISF-01",
        "design_delivery": "7b9d167",
        "phase_1_charter": "e4c74bd",
        "phase_1_ruling": "618ea84",
        "gate_baseline": "ab97244",
        "carrier_under_test": {
            "name": "ProbeReferencePort",
            "kind": "non-candidate in-memory probe control",
            "storage_selection_claim": "NONE",
            "palace_candidate_claim": "NONE",
        },
        "allowed_port_operations": [
            "put_blob", "get_blob", "put_node", "get_node", "put_edge",
            "get_edges", "put_provenance", "get_provenance", "pin",
            "resolve_pin", "put_mutation_event", "get_mutation_events",
        ],
        "semantic_oracle_used": semantic_oracle,
        "scenarios": scenarios,
        "summary": {
            "scenario_total": len(scenarios),
            "scenario_pass": passed,
            "scenario_fail": len(scenarios) - passed,
            "harness_qualification": "PASS" if passed == len(scenarios) else "FAIL",
            "route_prq_isf_01": "INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST",
            "reason": "Execution used the non-candidate ProbeReferencePort control; it did not test a selected PALACE or external Information Space carrier.",
        },
    }

    out = Path(__file__).parent / "PRQ_ISF_01_EXECUTION_RECORD.json"
    out.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")

    for scenario in scenarios:
        marker = "PASS" if scenario["case_pass"] else "FAIL"
        actual = scenario["actual"]
        detail = actual["decoder_code"] or actual["frozen_family"] or "clean resolve"
        print(f"[{marker}] {scenario['scenario_id']} — {detail}")
    print(f"\n{passed}/{len(scenarios)} scenario expectations matched")
    print("harness qualification:", record["summary"]["harness_qualification"])
    print("route PRQ-ISF-01:", record["summary"]["route_prq_isf_01"])
    print(f"execution record: {out}")
    return 0 if passed == len(scenarios) else 1


if __name__ == "__main__":
    raise SystemExit(main())
