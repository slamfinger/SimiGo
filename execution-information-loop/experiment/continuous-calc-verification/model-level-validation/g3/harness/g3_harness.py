#!/usr/bin/env python3
"""G3 harness: one task graph, two arms, one variable. Stub calculator only.

Both arms start from the *same* IS bytes (one prefix carrier, copied twice and
hash-compared before either arm runs), use the same frozen checker
(`g2/batch/checker.py`), the same declared task graph, the same validity policy
and the same validity window. The only difference is where the arm is allowed to
learn its continuation position from:

  ES+IS    restore_continuation() -> persisted execution state, then read IS
  IS-only  no execution state at all; derive the position from items and
           settlements

`ISOnlyView` is a whitelist proxy: any attribute outside the IS surface raises
`AssertionError`, so "the IS-only arm never read an execution state" is enforced
rather than promised. `denied` records every refused touch and must stay empty.

The calculator is a deterministic stub that reproduces the frozen unit rule and
verifies its own answer with the frozen checker. What this harness therefore
measures is the number of *calculator invocation slots* the design consumes and
the number of gate *processes* the negative controls need. It does not start a
model: `actual_model_starts: 0` and `is_execution_evidence: false` for the whole
run, while `measured_calculator_invocations: 20` counts calls into the stub.
The two numbers are named apart on purpose; a stub call is a slot in the design,
not an execution. The default (no flag) path below stays stub-only. A separate
`--real-runner` branch exists ONLY to make fail-closed control flow observable:
it calls the runtime isolation gate before any model generation and refuses,
because no trusted attestation provider is source-registered. It does not load
or start a model, does not implement the Swift/MLX emitter, and cannot report
success. Its result is control-flow behaviour, not a G3 execution outcome.

The frozen budget comes from the approved plan (§7.4):

  2 fixtures x 2 arms x 5 compute slots = 20 invocation slots
  4 gate processes, process cap 24, 0 retries

Usage:
  python3 g3_harness.py [--fixtures fixture-1 fixture-2] [--out RECORD.json]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

HERE = pathlib.Path(__file__).resolve().parent
G3_ROOT = HERE.parent
REPO_ROOT = HERE.parents[5]
EIL = REPO_ROOT / "execution-information-loop"
G2_BATCH = (EIL / "experiment" / "continuous-calc-verification"
            / "model-level-validation" / "g2" / "batch")
PREREGISTRATION = G3_ROOT / "preregistration" / "G3_PREREGISTRATION.json"
sys.path.insert(0, str(EIL))
sys.path.insert(0, str(G2_BATCH))

from carrier_loop import (  # noqa: E402
    CarrierInformationLoop, canonical, digest, parse_utc,
)
from checker import check_u2, checksum_for_site  # noqa: E402

SCHEMA_ID = "SIMIGO-G3-DRY-RUN-V1"
REAL_RUNNER_SCHEMA_ID = "SIMIGO-G3-REAL-RUNNER-PREFLIGHT-V1"
REAL_RUNNER_GATE_ID = "G3_RUNTIME_ISOLATION_PRECHECK_V1"
WINDOW = "2030-12-31T23:59:59Z"
EXPIRED_WINDOW = "2026-01-01T00:00:00Z"
EVALUATED_AT = "2026-10-22T00:00:00Z"
TERMINAL_ITEM = "U3"
FREE_ITEM = "U_free"
PROBE_ITEM = "U_isolation_probe"
SOURCE_CHANGE_AFTER_STEP = "d2"

# Frozen task graph. `obligations` is the set left open *after* the step is
# applied, which is the moment both arms are sampled at.
#
# `expected_recomputed` / `expected_reused` / `expected_unsettled` are the
# three sets the reviewer of this pre-registration asked for, expressed on a
# basis that does not depend on which arm is running: an item is *recomputed*
# when its current settlement object id differs after the step, *reused* when
# the id is unchanged and non-empty, and *unsettled* when there is no
# settlement on either side. The third bucket exists because "no settlement
# before, no settlement after" is not reuse, and counting it as reuse would let
# a plan satisfy an expectation with absence.
#
# `expected_blocked` is empty for every formal step: the formal arms must never
# block. Blocking is carried by the negative controls, each on its own copy.
ITEM_UNIVERSE = ["U1", "U2", "U3", FREE_ITEM]
STEPS = [
    {"step_id": "d1", "required": [FREE_ITEM, "U1"],
     "obligations": ["settle u2 transfer", "settle u3 terminal artifact",
                     "report the terminal artifact"],
     "expected_recomputed": ["U1"], "expected_reused": [FREE_ITEM],
     "expected_unsettled": ["U2", "U3"], "expected_blocked": []},
    {"step_id": "d2", "required": ["U2"],
     "obligations": ["settle u3 terminal artifact", "report the terminal artifact"],
     "expected_recomputed": ["U2"], "expected_reused": ["U1", FREE_ITEM],
     "expected_unsettled": ["U3"], "expected_blocked": []},
    {"step_id": "d3", "required": ["U1", "U2"],
     "obligations": ["settle u3 terminal artifact", "report the terminal artifact"],
     "expected_recomputed": ["U1", "U2"], "expected_reused": [FREE_ITEM],
     "expected_unsettled": ["U3"], "expected_blocked": []},
    {"step_id": "d4", "required": [TERMINAL_ITEM, FREE_ITEM],
     "obligations": ["report the terminal artifact"],
     "expected_recomputed": ["U3"], "expected_reused": ["U1", "U2", FREE_ITEM],
     "expected_unsettled": [], "expected_blocked": []},
]
EXPECTED_COMPUTES = [len(step["expected_recomputed"]) for step in STEPS]
CONDITIONS = ["required items are current and inside their declared window"]

UNIT_INPUTS = {
    "U1": {"dependencies": [], "source": "u1_source"},
    "U2": {"dependencies": ["U1"], "source": "unit_declared_sources:U2"},
    "U3": {"dependencies": ["U2"], "source": "unit_declared_sources:U3"},
}


def sealed_policy() -> dict:
    body = {"policy_version": "g3-preregistered-v1",
            "policy_source": "SIMIGO_G3_PREREGISTRATION"}
    return {**body, "policy_sha256": digest(body)}


POLICY = sealed_policy()


def unit_result(unit_id: str, upstream: dict) -> dict:
    """The frozen unit rule: carry the upstream triple, label the unit."""
    return {
        "unit": unit_id,
        "secret": upstream["secret"],
        "site": upstream["site"],
        "checksum": checksum_for_site(upstream["site"]),
    }


def answer_line(upstream: dict) -> str:
    return "ANSWER=%s-%s" % (upstream["secret"],
                             checksum_for_site(upstream["site"]))


def accepted_sources(fixture: dict, unit_id: str) -> list:
    """Every source payload a unit is allowed to be computed from.

    U1 has two declared versions because the task graph replaces its source
    between `d2` and `d3`; both are legitimate inputs, one per phase.
    """
    key = UNIT_INPUTS[unit_id]["source"]
    if key == "u1_source":
        return [fixture["u1_source"]["payload"],
                fixture["u1_source_changed"]["payload"]]
    if key.startswith("unit_declared_sources:"):
        name = key.split(":", 1)[1]
        return [fixture["unit_declared_sources"][name]["payload"]]
    return [fixture[key]["payload"]]


class StubCalculator:
    """Offline stand-in for the model runner; logs every would-be model start.

    It refuses to answer from anything except its declared inputs, so a missing
    or stale upstream fails here instead of being papered over.
    """

    def __init__(self, fixture: dict):
        self.fixture = fixture
        self.calls: list[str] = []

    def __call__(self, item_id: str, payload: dict, dependencies: dict) -> dict:
        declared = UNIT_INPUTS.get(item_id)
        if declared is None:
            raise AssertionError("%s is not a declared unit" % item_id)
        if sorted(dependencies) != sorted(declared["dependencies"]):
            raise AssertionError("%s got dependencies %s, expected %s"
                                 % (item_id, sorted(dependencies),
                                    sorted(declared["dependencies"])))
        if payload not in accepted_sources(self.fixture, item_id):
            raise AssertionError("%s got an unexpected source payload" % item_id)
        upstream = (payload if not declared["dependencies"]
                    else dependencies[declared["dependencies"][0]])
        view = {**upstream, "checksum": checksum_for_site(upstream["site"])}
        check = check_u2(answer_line(upstream), view, self.fixture)
        if not check["pass"]:
            raise AssertionError("%s failed the frozen checker: %s"
                                 % (item_id, check))
        self.calls.append(item_id)
        return unit_result(item_id, upstream)


class ISOnlyView:
    """Everything the IS-only arm may see. Every ES entry point is refused.

    The check runs in `__getattribute__`, not `__getattr__`. `__getattr__` fires
    only after normal lookup fails, so an instance attribute was handed out
    unguarded: `view._loop` returned the wrapped loop itself, from which
    `restore_continuation` and every other ES entry point are reachable, and the
    `denied` log stayed empty. The isolation assertion would have passed while
    the arm was in fact unrestricted.
    """

    ALLOWED = (
        "current_item",
        "current_settlement",
        "settle",
        "update_source",
        "commit",
        "close",
        "_settlement_reuse_decision",
    )
    # The proxy's own log, readable by the harness that built it.
    OWN_ATTRS = ("denied",)

    def __init__(self, loop):
        object.__setattr__(self, "_loop", loop)
        object.__setattr__(self, "denied", [])

    def __getattribute__(self, name):
        if name in object.__getattribute__(self, "OWN_ATTRS"):
            return object.__getattribute__(self, name)
        if name in object.__getattribute__(self, "ALLOWED"):
            return getattr(object.__getattribute__(self, "_loop"), name)
        object.__getattribute__(self, "denied").append(name)
        raise AssertionError("IS-only arm touched %r" % name)

    def __setattr__(self, name, value):
        object.__getattribute__(self, "denied").append(name)
        raise AssertionError("IS-only arm may not set %r" % name)

    def __delattr__(self, name):
        object.__getattribute__(self, "denied").append(name)
        raise AssertionError("IS-only arm may not delete %r" % name)


def sha256_path(path) -> str:
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def settle_external(loop, item_id: str, payload: dict, version: str) -> str:
    """Settle externally supplied information: no model, no execution state."""
    value = {"unit": item_id, "secret": payload["secret"],
             "site": payload["site"],
             "checksum": checksum_for_site(payload["site"])}
    shared = {
        "source_payload_sha256": digest(payload),
        "result_value_sha256": digest(value),
        "source_version": version,
        "dependency_object_ids": {},
        "evaluated_at_utc": EVALUATED_AT,
        "valid_until_utc": WINDOW,
        "validity_policy": POLICY,
    }
    return loop.settle("g3-external-%s" % item_id, item_id,
                       {"value": value, **shared}, dict(shared))["object_id"]


def build_prefix(path, fixture: dict) -> None:
    """The shared IS prefix: identical bytes for both arms, zero model starts."""
    loop = CarrierInformationLoop.create(str(path))
    label = "%s-declared" % fixture["fixture_id"]
    u1 = fixture["u1_source"]
    loop.put_source(label, "U1", "model-extraction-u1", u1["version"],
                    u1["payload"], dependencies=[],
                    valid_until_utc=WINDOW, validity_policy=POLICY)
    for unit_id in ("U2", "U3"):
        declared = fixture["unit_declared_sources"][unit_id]
        loop.put_source(label, unit_id, "model-unit-%s" % unit_id.lower(),
                        declared["version"], declared["payload"],
                        dependencies=list(UNIT_INPUTS[unit_id]["dependencies"]),
                        valid_until_utc=WINDOW, validity_policy=POLICY)
    free = fixture["u_free_source"]
    loop.put_source(label, FREE_ITEM, "external-record", free["version"],
                    free["payload"], dependencies=[],
                    valid_until_utc=WINDOW, validity_policy=POLICY)
    settle_external(loop, FREE_ITEM, free["payload"], free["version"])
    loop.commit()
    loop.close()


def demand_id(fixture: dict, step: dict) -> str:
    return "%s-%s" % (fixture["fixture_id"], step["step_id"])


# ---------------------------------------------------------------- ES+IS arm

def es_execute(loop, fixture, step, calculator, continuation_point) -> dict:
    identifier = demand_id(fixture, step)
    outcome = loop.execute_demand(identifier, "%s-advance" % identifier,
                                  calculator, evaluated_at_utc=EVALUATED_AT)
    if outcome["state"] != "ADVANCED":
        return {"state": outcome["state"],
                "failure_reason": outcome.get("failure_reason"),
                "computed": list(outcome.get("computed_item_ids") or []),
                "reused": list(outcome.get("reused_item_ids") or [])}
    loop.confirm_runtime_application("%s-advance" % identifier)
    restored = loop.restore_continuation(continuation_point)
    return {
        "state": "ADVANCED",
        "computed": list(outcome["computed_item_ids"]),
        "reused": list(outcome["reused_item_ids"]),
        "restored_state_id": restored["state"]["state_id"],
        "restored_demand_id": restored["demand"]["demand_id"],
        "es_required_item_ids": restored["required_item_ids"],
        "es_open_obligations": sorted(restored["demand"]["pending_obligations"]),
    }


def es_next_step(restored_demand_id: str, fixture: dict) -> str:
    """Pure ES-derived position: the step after the last executed demand."""
    for index, step in enumerate(STEPS):
        if demand_id(fixture, step) == restored_demand_id:
            return (STEPS[index + 1]["step_id"]
                    if index + 1 < len(STEPS) else "complete")
    return "unknown"


def terminal_value(loop) -> dict:
    settlement = loop.current_settlement(TERMINAL_ITEM)
    if settlement is None:
        return {"state": "UNSETTLED"}
    value = dict(settlement["result"]["value"])
    return {"state": settlement.get("state"), "value": value}


# ------------------------------------------------------------------ IS arm

def dependency_object_ids(loop, item: dict) -> tuple:
    values, object_ids = {}, {}
    for dependency_id in item["dependencies"]:
        settlement = loop.current_settlement(dependency_id)
        if settlement is None or settlement.get("state") != "SETTLED":
            return None, None
        values[dependency_id] = settlement["result"]["value"]
        object_ids[dependency_id] = settlement["_object_id"]
    return values, object_ids


def is_settled_usable(loop, item_id: str) -> bool:
    item = loop.current_item(item_id)
    if item is None:
        return False
    values, object_ids = dependency_object_ids(loop, item)
    if object_ids is None:
        return False
    reusable, _ = loop._settlement_reuse_decision(
        loop.current_settlement(item_id), item, object_ids,
        parse_utc(EVALUATED_AT))
    return reusable


def is_next_step(loop) -> str:
    """Pure IS-derived position: the first step whose items are not usable."""
    for step in STEPS:
        if not all(is_settled_usable(loop, item_id) for item_id in step["required"]):
            return step["step_id"]
    return "complete"


def is_open_obligations(loop, fixture: dict) -> list:
    open_obligations = []
    for entry in fixture["obligations"]:
        discharged_by = entry["discharged_by"]
        if discharged_by is None or not is_settled_usable(loop, discharged_by):
            open_obligations.append(entry["obligation"])
    return sorted(open_obligations)


def is_execute(view, fixture, step, calculator) -> dict:
    computed, reused = [], []
    for item_id in step["required"]:
        item = view.current_item(item_id)
        if item is None:
            return {"state": "BLOCKED_MISSING_ITEM", "item_id": item_id,
                    "computed": computed, "reused": reused}
        window = item.get("valid_until_utc")
        if window is not None and parse_utc(EVALUATED_AT) > parse_utc(window):
            return {"state": "BLOCKED_STALE_VALIDITY", "item_id": item_id,
                    "computed": computed, "reused": reused}
        values, object_ids = dependency_object_ids(view, item)
        if object_ids is None:
            return {"state": "BLOCKED_MISSING_DEPENDENCY", "item_id": item_id,
                    "computed": computed, "reused": reused}
        reusable, _ = view._settlement_reuse_decision(
            view.current_settlement(item_id), item, object_ids,
            parse_utc(EVALUATED_AT))
        if reusable:
            reused.append(item_id)
            continue
        value = calculator(item_id, item["source_payload"], values)
        shared = {
            "source_payload_sha256": digest(item["source_payload"]),
            "result_value_sha256": digest(value),
            "source_version": item["source_version"],
            "dependency_object_ids": dict(object_ids),
            "evaluated_at_utc": EVALUATED_AT,
            "valid_until_utc": window,
            "validity_policy": item.get("validity_policy"),
        }
        view.settle("g3-is-%s-%s" % (fixture["fixture_id"], step["step_id"]),
                    item_id, {"value": value, **shared}, dict(shared))
        computed.append(item_id)
    return {"state": "ADVANCED", "computed": computed, "reused": reused}


# ---------------------------------------------------------------- comparison

def projection(final: dict, obligations: list, next_step: str) -> dict:
    return {"final_result": final, "open_obligations": obligations,
            "next_step": next_step}


def settlement_object_ids(loop) -> dict:
    """Current settlement object id per item of the frozen universe.

    `None` means the item is unsettled. Comparing the map before and after a
    step is the arm-independent definition of "this item was recomputed":
    recomputation appends a new settlement object, reuse returns the recorded
    one, so the id changes exactly when work happened.
    """
    identifiers = {}
    for item_id in ITEM_UNIVERSE:
        settlement = loop.current_settlement(item_id)
        identifiers[item_id] = (settlement or {}).get("_object_id")
    return identifiers


def work_since(before: dict, after: dict) -> tuple:
    """Split the frozen item universe into recomputed / reused / unsettled.

    `None == None` does not mean reuse: an item that was never settled cannot
    have been reused. Keeping that case in its own bucket is what stops the
    reuse expectation from being satisfied by nothing happening.
    """
    recomputed, reused, unsettled = [], [], []
    for item_id in ITEM_UNIVERSE:
        old = before.get(item_id)
        new = after.get(item_id)
        if old != new:
            recomputed.append(item_id)
        elif new is None:
            unsettled.append(item_id)
        else:
            reused.append(item_id)
    return sorted(recomputed), sorted(reused), sorted(unsettled)


def count_execution_states(loop) -> int:
    return loop.carrier.connection.execute(
        "SELECT COUNT(*) n FROM is_index_entries "
        "WHERE srs_identity LIKE 'execution_state:%'").fetchone()["n"]


def run_pair(prefix_bytes: bytes, fixture: dict, directory: pathlib.Path) -> dict:
    fixture_id = fixture["fixture_id"]
    continuation_point = "%s-downstream" % fixture_id
    es_database = directory / "es.sqlite"
    is_database = directory / "is.sqlite"
    es_database.write_bytes(prefix_bytes)
    is_database.write_bytes(prefix_bytes)
    checks = {
        "initial_is_bytes_identical": (sha256_path(es_database)
                                       == sha256_path(is_database)),
    }
    # The fixture is the one object both arms legitimately share, and only as
    # read-only input. Its fingerprint is taken before either arm runs so that
    # "shared input" cannot quietly become "shared state".
    fixture_fingerprint = canonical(fixture)

    es_loop = CarrierInformationLoop.open(str(es_database))
    is_loop = CarrierInformationLoop.open(str(is_database))
    view = ISOnlyView(is_loop)
    es_calculator = StubCalculator(fixture)
    is_calculator = StubCalculator(fixture)

    for step in STEPS:
        identifier = demand_id(fixture, step)
        es_loop.define_demand(identifier,
                              continuation_point=continuation_point,
                              pending_obligations=list(step["obligations"]),
                              continuation_conditions=list(CONDITIONS),
                              required_item_ids=list(step["required"]))

    probes = []
    snapshot_after_d1 = None
    for step in STEPS:
        es_before = settlement_object_ids(es_loop)
        is_before = settlement_object_ids(is_loop)
        es_result = es_execute(es_loop, fixture, step, es_calculator,
                               continuation_point)
        is_result = is_execute(view, fixture, step, is_calculator)
        es_recomputed, es_reused, es_unsettled = work_since(
            es_before, settlement_object_ids(es_loop))
        is_recomputed, is_reused, is_unsettled = work_since(
            is_before, settlement_object_ids(is_loop))
        es_view = projection(
            terminal_value(es_loop), es_result.get("es_open_obligations", []),
            es_next_step(es_result.get("restored_demand_id", ""), fixture))
        is_view = projection(
            terminal_value(is_loop), is_open_obligations(is_loop, fixture),
            is_next_step(is_loop))
        probes.append({
            "step_id": step["step_id"],
            "es_state": es_result["state"],
            "is_state": is_result["state"],
            "es_computed": es_result["computed"],
            "is_computed": is_result["computed"],
            "es_reused": es_result["reused"],
            "is_reused": is_result["reused"],
            "es_recomputed": es_recomputed,
            "es_unchanged": es_reused,
            "es_unsettled": es_unsettled,
            "is_recomputed": is_recomputed,
            "is_unchanged": is_reused,
            "is_unsettled": is_unsettled,
            "expected_recomputed": sorted(step["expected_recomputed"]),
            "expected_unchanged": sorted(step["expected_reused"]),
            "expected_unsettled": sorted(step["expected_unsettled"]),
            "es_projection": es_view,
            "is_projection": is_view,
            "agree": es_view == is_view,
        })
        if step["step_id"] == "d1":
            snapshot_after_d1 = directory / "after-d1.sqlite"
            shutil.copyfile(es_database, snapshot_after_d1)
        if step["step_id"] == SOURCE_CHANGE_AFTER_STEP:
            change = fixture["u1_source_changed"]
            es_loop.update_source("U1", change["version"], change["payload"],
                                  reason="declared source change")
            view.update_source("U1", change["version"], change["payload"],
                               reason="declared source change")
            es_loop.commit()
            view.commit()

    checks["expected_computes_per_arm"] = (
        [len(probe["es_recomputed"]) for probe in probes] == EXPECTED_COMPUTES
        and [len(probe["is_recomputed"]) for probe in probes] == EXPECTED_COMPUTES)
    # The three frozen sets are checked per step and per arm. They are declared
    # on the settlement-object-id basis, so a mismatch means the design's
    # selective-propagation claim is wrong, not that bookkeeping differed.
    checks["recomputed_set_matches_frozen_plan"] = all(
        probe["es_recomputed"] == probe["expected_recomputed"]
        and probe["is_recomputed"] == probe["expected_recomputed"]
        for probe in probes)
    checks["reused_set_matches_frozen_plan"] = all(
        probe["es_unchanged"] == probe["expected_unchanged"]
        and probe["is_unchanged"] == probe["expected_unchanged"]
        for probe in probes)
    # The third bucket is the one that keeps the other two honest: an item with
    # no settlement on either side must never be counted as reuse.
    checks["unsettled_set_matches_frozen_plan"] = all(
        probe["es_unsettled"] == probe["expected_unsettled"]
        and probe["is_unsettled"] == probe["expected_unsettled"]
        for probe in probes)
    checks["three_sets_partition_the_universe"] = all(
        sorted(probe["es_recomputed"] + probe["es_unchanged"]
               + probe["es_unsettled"]) == sorted(ITEM_UNIVERSE)
        for probe in probes)
    checks["blocked_set_is_empty_on_the_formal_arms"] = all(
        not step["expected_blocked"]
        and probe["es_state"] == "ADVANCED"
        and probe["is_state"] == "ADVANCED"
        for step, probe in zip(STEPS, probes))
    checks["arm_work_sets_agree_on_a_common_basis"] = all(
        probe["es_recomputed"] == probe["is_recomputed"]
        and probe["es_unchanged"] == probe["is_unchanged"]
        for probe in probes)
    checks["es_calculator_calls_are_one_per_compute"] = (
        len(es_calculator.calls) == sum(EXPECTED_COMPUTES))
    checks["is_calculator_calls_are_one_per_compute"] = (
        len(is_calculator.calls) == sum(EXPECTED_COMPUTES))
    checks["is_arm_touched_no_es_entry_point"] = view.denied == []
    checks["free_item_reused_after_source_change"] = (
        FREE_ITEM in probes[-1]["es_reused"]
        and FREE_ITEM in probes[-1]["is_reused"]
        and sorted(probes[-1]["es_reused"]) == sorted([FREE_ITEM, "U1", "U2"]))
    checks["u1_u2_recomputed_after_source_change"] = (
        probes[2]["es_computed"] == ["U1", "U2"]
        and probes[2]["is_computed"] == ["U1", "U2"])
    checks["unrelated_settlement_survives_source_change"] = (
        len(is_loop.carrier.get_dependency_history("settlement:%s" % FREE_ITEM)) == 1
        and len(es_loop.carrier.get_dependency_history("settlement:%s" % FREE_ITEM)) == 1)

    # Arm isolation. Two assertions, both cheap and both structural: the arms
    # must write to different carriers, and every execution-state record must
    # land in the ES carrier only. The second one is what rules out the ES arm
    # lending the IS-only arm an execution-state identity it did not earn.
    es_state_count = count_execution_states(es_loop)
    is_state_count = count_execution_states(is_loop)
    checks["arms_use_distinct_carriers"] = (
        es_database.resolve() != is_database.resolve()
        and es_database.exists() and is_database.exists())
    checks["arms_use_distinct_calculator_instances"] = (
        es_calculator is not is_calculator
        and es_calculator.calls is not is_calculator.calls)
    checks["es_records_land_only_in_the_es_carrier"] = (
        es_state_count > 0 and is_state_count == 0)

    # Three further measurements, each aimed at a leak the assertions above
    # would not see. "The arms are isolated" is only a claim until something
    # would fail if they were not.
    #
    # 1. The proxy's own escape routes. A whitelist is only as strong as the
    #    hook it runs in, and `__getattr__`-based hooks miss instance
    #    attributes: `_loop` used to hand out the wrapped carrier, from which
    #    every ES entry point is reachable while `denied` stays empty.
    baseline_denied = len(view.denied)
    escape_names = ("_loop", "carrier", "restore_continuation", "define_demand")
    refused = []
    for name in escape_names:
        try:
            getattr(view, name)
        except AssertionError:
            refused.append(name)
    checks["proxy_refuses_inner_loop_and_es_entries"] = (
        refused == list(escape_names))
    try:
        view.current_item = None
        checks["proxy_refuses_attribute_write"] = False
    except AssertionError:
        checks["proxy_refuses_attribute_write"] = True
    # Those probes are the harness testing its own object, not the arm reading a
    # state, so the log is rolled back to what the arm actually did.
    del view.denied[baseline_denied:]

    # 2. A write in one arm must not be visible in the other. Separate files is
    #    the argument; this is the measurement.
    probe_payload = {"secret": "isolation-probe", "site": "probe.invalid"}
    es_loop.put_source("g3-isolation-probe", PROBE_ITEM, "model-unit-probe",
                       "v1", probe_payload, dependencies=[],
                       valid_until_utc=WINDOW, validity_policy=POLICY)
    settle_external(es_loop, PROBE_ITEM, probe_payload, "v1")
    es_loop.commit()
    checks["arm_writes_do_not_cross_to_the_other_arm"] = (
        es_loop.current_item(PROBE_ITEM) is not None
        and es_loop.current_settlement(PROBE_ITEM) is not None
        and is_loop.current_item(PROBE_ITEM) is None
        and is_loop.current_settlement(PROBE_ITEM) is None)

    # 3. The shared input stayed input.
    checks["shared_fixture_inputs_not_mutated_by_either_arm"] = (
        canonical(fixture) == fixture_fingerprint)

    agreements = {
        "final_result": all(probe["es_projection"]["final_result"]
                            == probe["is_projection"]["final_result"]
                            for probe in probes),
        "open_obligations": all(probe["es_projection"]["open_obligations"]
                                == probe["is_projection"]["open_obligations"]
                                for probe in probes),
        "next_step": all(probe["es_projection"]["next_step"]
                         == probe["is_projection"]["next_step"]
                         for probe in probes),
    }
    es_loop.close()
    view.close()
    return {
        "checks": checks,
        "probes": probes,
        "agreements": agreements,
        "es_calculator_invocations": len(es_calculator.calls),
        "is_calculator_invocations": len(is_calculator.calls),
        "es_compute_log": es_calculator.calls,
        "is_compute_log": is_calculator.calls,
        "is_denied_touches": view.denied,
        "es_execution_state_count": es_state_count,
        "is_execution_state_count": is_state_count,
        "verdict": ("ES_INDEPENDENT_CONTRIBUTION_NOT_PROVEN"
                    if all(agreements.values())
                    else "ES_INDEPENDENT_CONTRIBUTION_DIVERGENCE_OBSERVED"),
        "snapshot_after_d1": snapshot_after_d1,
    }


# ---------------------------------------------------------- negative controls

def gate_process(database, item_id: str, evaluated_at: str, expect: str,
                 require_validity: bool, directory: pathlib.Path,
                 label: str) -> dict:
    out = directory / ("gate-%s.json" % label)
    command = [sys.executable, str(G2_BATCH / "carrier_gate_v2.py"),
               "--db", str(database), "--item", item_id,
               "--evaluated-at", evaluated_at, "--out", str(out),
               "--expect", expect]
    if require_validity:
        command.append("--require-validity")
    completed = subprocess.run(command, capture_output=True, text=True)
    body = json.loads(out.read_text(encoding="utf-8"))
    return {"label": label, "exit": completed.returncode,
            "decision": body["decision"], "code": body.get("code"),
            "database_unchanged": body["database_unchanged"],
            "pid": body["pid"]}


def tamper_settlement(database, item_id: str) -> str:
    connection = sqlite3.connect(str(database))
    object_id = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1",
        ("settlement:%s" % item_id,)).fetchone()[0]
    content = bytes(connection.execute(
        "SELECT content FROM is_objects WHERE object_id=?",
        (object_id,)).fetchone()[0])
    connection.execute(
        "UPDATE is_objects SET content=? WHERE object_id=?",
        (content.replace(b'"secret":"', b'"secret":"f'), object_id))
    connection.commit()
    connection.close()
    return object_id


def run_controls(snapshot: pathlib.Path, prefix_bytes: bytes, fixture: dict,
                 directory: pathlib.Path) -> dict:
    """Four controls, each on its own copy: two gate processes, two in-process."""
    checks = {}
    processes = []

    expired = directory / "control-expired.sqlite"
    shutil.copyfile(snapshot, expired)
    loop = CarrierInformationLoop.open(str(expired))
    loop.update_source("U1", fixture["u1_source"]["version"],
                       fixture["u1_source"]["payload"],
                       reason="control: declared window moved into the past",
                       valid_until_utc=EXPIRED_WINDOW)
    loop.commit()
    loop.close()
    processes.append(gate_process(expired, "U1", EVALUATED_AT, "refused", True,
                                  directory, "expired-settlement"))
    checks["expired_settlement_refused_by_gate"] = (
        processes[-1]["code"] == "OBJECT_DIGEST_MISMATCH"
        or processes[-1]["code"] == "VALIDITY_EXPIRED")

    tampered = directory / "control-tampered.sqlite"
    shutil.copyfile(snapshot, tampered)
    tamper_settlement(tampered, "U1")
    processes.append(gate_process(tampered, "U1", EVALUATED_AT, "refused", True,
                                  directory, "tampered-settlement"))
    checks["tampered_settlement_refused_by_gate"] = (
        processes[-1]["code"] == "OBJECT_DIGEST_MISMATCH")

    # Missing settlement: the reuse predicate must refuse, never treat absent
    # work as done. Decided in-process so the control costs no model start.
    missing = directory / "control-missing.sqlite"
    missing.write_bytes(prefix_bytes)
    loop = CarrierInformationLoop.open(str(missing))
    item = loop.current_item("U2")
    reusable, reason = loop._settlement_reuse_decision(
        None, item, {}, parse_utc(EVALUATED_AT))
    checks["missing_settlement_is_not_reused"] = (
        reusable is False and reason == "MISSING_OR_SUPERSEDED_SETTLEMENT")
    loop.close()

    # Blocked state: a blocked continuation may not be resumed.
    blocked = directory / "control-blocked.sqlite"
    blocked.write_bytes(prefix_bytes)
    loop = CarrierInformationLoop.open(str(blocked))
    loop.update_source("U1", fixture["u1_source"]["version"],
                       fixture["u1_source"]["payload"],
                       reason="control: blocked by an expired window",
                       valid_until_utc=EXPIRED_WINDOW)
    loop.define_demand("%s-blocked" % fixture["fixture_id"],
                       continuation_point="%s-control" % fixture["fixture_id"],
                       pending_obligations=["observe the block"],
                       continuation_conditions=["window is current"],
                       required_item_ids=["U1"])
    outcome = loop.execute_demand("%s-blocked" % fixture["fixture_id"],
                                 "blocked-advance",
                                 lambda *_: {"should": "never run"},
                                 evaluated_at_utc=EVALUATED_AT)
    checks["blocked_state_is_reported"] = outcome["state"] == "BLOCKED_STALE_VALIDITY"
    try:
        loop.restore_continuation("%s-control" % fixture["fixture_id"])
    except ValueError as error:
        checks["blocked_state_blocks_restore"] = "blocked" in str(error)
    else:
        checks["blocked_state_blocks_restore"] = False
    loop.close()

    return {"checks": checks, "processes": processes,
            "process_count": len(processes)}


# --------------------------------------------------------------------- main

def frozen_dependency_graph() -> dict:
    """Read the frozen edge set and compare it with this harness's own inputs.

    The edges decide which items must recompute after the source change, so a
    harness that quietly used different edges would be measuring a different
    plan than the one that was frozen. Reading the file is what makes the
    pre-registration, rather than this code, the authority on the graph.
    """
    plan = json.loads(PREREGISTRATION.read_text(encoding="utf-8"))
    declared = (plan.get("task_graph") or {}).get("dependency_edges")
    if declared is None:
        return {"checks": {"dependency_edges_declared": False},
                "edges": None, "mismatched_units": []}
    harness = {unit: list(entry["dependencies"])
               for unit, entry in UNIT_INPUTS.items()}
    harness[FREE_ITEM] = []
    agrees = {unit: sorted(harness.get(unit, [])) == sorted(edges)
              for unit, edges in declared.items()}
    return {
        "checks": {
            "dependency_edges_declared": len(declared) == len(ITEM_UNIVERSE),
            "dependency_graph_matches_harness": (
                sorted(declared) == sorted(ITEM_UNIVERSE)
                and all(agrees.values())),
            "independent_sibling_has_no_edges": declared.get(FREE_ITEM) == [],
        },
        "edges": declared,
        "mismatched_units": sorted(u for u, ok in agrees.items() if not ok),
    }


def load_fixture(fixture_id: str) -> dict:
    return json.loads((G3_ROOT / "fixtures" / ("%s.json" % fixture_id))
                      .read_text(encoding="utf-8"))


# --- --real-runner: gated runtime-isolation preflight (control flow only) ----
#
# This branch exists to make the fail-closed ORDER observable and testable. It
# never loads a model and never reaches generation before the isolation gate
# clears. Because no trusted attestation provider is source-registered
# (TRUSTED_LIVE_PROVIDER_TYPES is intentionally empty), the honest result of a
# real-runner invocation is an explicit refusal, not a green run.

G3_GATE_DIR = REPO_ROOT / "g3" / "gate"

# Native Swift execution boundary. The authoritative isolation gate now lives in
# the Swift runtime-contract layer; the Python harness only starts it and
# collects the gate record it returns. These anchors are derived from REPO_ROOT
# (Path(__file__).resolve()) so invocation is cwd-independent.
SWIFT_PKG_DIR = REPO_ROOT / "simigo2-experimental"
SWIFT_ENTRY_NAME = "g3-swift-isolation-entry"
SWIFT_ENTRY_BINARY = SWIFT_PKG_DIR / ".build" / "debug" / SWIFT_ENTRY_NAME
SWIFT_ENTRY_SOURCES = [
    SWIFT_PKG_DIR / "Sources/SimiGoRuntimeContract/G3IsolatedExecutionEntry.swift",
    SWIFT_PKG_DIR / "Sources/SimiGoRuntimeContract/G3ExecutionDispatch.swift",
    SWIFT_PKG_DIR / "Sources/SimiGoRuntimeContract/RuntimeIsolationGate.swift",
    SWIFT_PKG_DIR / "Sources/G3SwiftIsolationEntry/main.swift",
]


def _load_runtime_isolation():
    """Import the landed gate package via a file-anchored, cwd-independent path.

    REPO_ROOT comes from ``Path(__file__).resolve()`` and the fixed repo layout,
    never from the working directory, so the import resolves identically whether
    the harness is launched from the repo root or from an unrelated cwd.
    """
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))
    from g3.gate.g3_runtime_isolation_gate import require_runtime_isolation
    from g3.gate.runtime_attestation_provider import TRUSTED_LIVE_PROVIDER_TYPES
    return require_runtime_isolation, TRUSTED_LIVE_PROVIDER_TYPES


def _obtain_runtime_provider():
    """Return the live attestation provider for this run, or None.

    The Python live-worker and Swift/MLX emitters are neither implemented nor
    authorized in this round, so there is no source-registered provider to hand
    the gate. Returning None (never a fixture dict or a synthetic observation)
    forces the gate to fail closed instead of accepting fabricated evidence.
    """
    return None


def _real_generate():
    """First model generation entry, reachable only after the gate clears.

    Reaching this proves the preflight order held (gate before generation).
    Actual generation is deliberately unimplemented (no emitter, no model load),
    so even a hypothetically passing gate stops here rather than silently
    'succeeding'.
    """
    raise NotImplementedError(
        "real model generation is not implemented; gated behind "
        "require_runtime_isolation and unauthorized for G3")


def preflight_runtime_isolation(provider, *, run_id, challenge_nonce,
                                expected_arms=("ES+IS", "IS-only")):
    """Run the isolation gate BEFORE any generation; never fabricate evidence.

    Returns an audit record dict. On any refusal (no trusted provider, a fixture
    or raw observation, or a failed check) the record carries the gate's own
    reason and marks ``eligible_for_runtime_evidence`` false; a passing gate
    report is recorded in full.
    """
    require_runtime_isolation, trusted_registry = _load_runtime_isolation()
    attempt = {
        "gate": REAL_RUNNER_GATE_ID,
        "run_id": run_id,
        "challenge_nonce": challenge_nonce,
        "expected_arms": list(expected_arms),
        "trusted_provider_count": len(trusted_registry),
        "provider_present": provider is not None,
    }
    try:
        report = require_runtime_isolation(
            provider, run_id=run_id, challenge_nonce=challenge_nonce,
            expected_arms=expected_arms)
    except Exception as error:  # gate is fail-closed; record the refusal reason
        return {**attempt,
                "passed": False,
                "refused": True,
                "reason": "%s: %s" % (type(error).__name__, error),
                "eligible_for_runtime_evidence": False}
    return {**attempt,
            "passed": bool(report.get("passed")),
            "refused": False,
            "failed_checks": report.get("failed_checks", []),
            "check_count": report.get("check_count"),
            "gate_report": report,
            "eligible_for_runtime_evidence":
                report.get("eligible_for_runtime_evidence")}


def invoke_swift_gate(run_id, challenge_nonce, *, binary=None, timeout=60):
    """Call the native Swift G3 execution entry and return its gate record.

    The authoritative isolation gate lives in native Swift; the Python harness
    does NOT construct an official attestation. It runs the Swift binary (which
    owns requireIsolation and the generation it guards) and returns whatever the
    Swift entry emitted. There is NO fallback: a missing binary, a crash, or
    unparsable output yields a fail-closed descriptor with an explicit reason --
    never a reused fixture or a Python-side 'pass'.

    Returns ``(swift_record | None, returncode | None, failure_reason | None)``.
    """
    entry = pathlib.Path(binary) if binary else SWIFT_ENTRY_BINARY
    if not entry.exists():
        return None, None, "swift_entry_missing: %s" % entry
    try:
        completed = subprocess.run(
            [str(entry), "--run-id", run_id, "--challenge-nonce", challenge_nonce],
            capture_output=True, text=True, timeout=timeout)
    except Exception as error:  # never fall back on an invocation failure
        return None, None, "swift_entry_invocation_failed: %s: %s" % (
            type(error).__name__, error)
    stdout = (completed.stdout or "").strip()
    if not stdout:
        return None, completed.returncode, "swift_entry_no_record: rc=%s stderr=%s" % (
            completed.returncode, (completed.stderr or "").strip())
    try:
        record = json.loads(stdout)
    except json.JSONDecodeError as error:
        return None, completed.returncode, "swift_entry_bad_json: %s" % error
    return record, completed.returncode, None


def run_real_runner(*, run_id, challenge_nonce, swift_invoker=None,
                    swift_binary=None,
                    expected_arms=("ES+IS", "IS-only")) -> dict:
    """Drive the native Swift gate before any generation and collect its record.

    Gate-before-generation order is enforced inside the Swift entry: it runs
    requireIsolation and only reaches generation if the gate clears. Because the
    trusted live-provider registry is empty, the entry refuses and its record
    reports ``generationCallCount == 0``. Python records that verdict verbatim
    and adds no runtime-isolation evidence of its own. On any Swift-side failure
    the run stays fail-closed -- there is no fixture or old-runner fallback.
    """
    invoker = swift_invoker or invoke_swift_gate
    swift_record, returncode, failure = invoker(
        run_id, challenge_nonce, binary=swift_binary)

    gate_passed = bool(
        swift_record
        and swift_record.get("passed") is True
        and swift_record.get("eligibleForRuntimeEvidence") is True)
    swift_gen_count = (swift_record.get("generationCallCount")
                       if swift_record else None)

    if failure is not None or swift_record is None:
        result = "SWIFT_ENTRY_UNAVAILABLE_FAIL_CLOSED"
    elif not gate_passed:
        result = "REFUSED_BY_NATIVE_GATE_BEFORE_GENERATION"
    else:
        # The Swift entry cleared the gate and its guarded generation ran inside
        # Swift; Python still started nothing and holds no execution evidence.
        result = "NATIVE_GATE_CLEARED"
    return {
        "schema_id": REAL_RUNNER_SCHEMA_ID,
        "mode": "real-runner",
        "dry_run": False,
        "gate_authority": "native_swift_execution_entry",
        "expected_arms": list(expected_arms),
        "swift_entry_binary": str(SWIFT_ENTRY_BINARY),
        "swift_entry_returncode": returncode,
        "swift_entry_failure": failure,
        "swift_gate_record": swift_record,          # collected verbatim
        "native_gate_passed": gate_passed,
        "native_generation_call_count": swift_gen_count,
        "generation_reached_in_python": False,
        "model_generation_started": False,
        "actual_model_starts": 0,
        "is_execution_evidence": False,
        "result": result,
        "provenance": {
            "harness_sha256": sha256_path(pathlib.Path(__file__)),
            "swift_entry_source_sha256": {
                str(p.relative_to(REPO_ROOT)): sha256_path(p)
                for p in SWIFT_ENTRY_SOURCES if p.exists()},
            "contrast_python_gate_sha256": sha256_path(
                G3_GATE_DIR / "g3_runtime_isolation_gate.py"),
        },
        "non_claims": [
            "the authoritative gate ran in native Swift, not in Python",
            "Python started no model; actual_model_starts stays 0",
            "a Swift refusal is recorded verbatim and is not isolation evidence",
            "no fixture or prior runner is used when the Swift entry fails",
            "the trusted live-provider registry is empty until a reviewed real "
            "emitter is registered",
            "this is control-flow wiring, not a G3 execution result",
        ],
    }


def _main_real_runner(args) -> int:
    run_id = args.run_id or ("g3-real-" + uuid.uuid4().hex[:12])
    challenge_nonce = args.challenge_nonce or uuid.uuid4().hex
    record = run_real_runner(run_id=run_id, challenge_nonce=challenge_nonce)
    text = json.dumps(record, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")) + "\n"
    print(text, end="")
    if args.out:
        pathlib.Path(args.out).write_text(text, encoding="utf-8")
    return 0 if record["result"] == "NATIVE_GATE_CLEARED" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", nargs="*",
                        default=["g3-fixture-1", "g3-fixture-2"])
    parser.add_argument("--out")
    parser.add_argument("--real-runner", action="store_true",
                        help="gated runtime-isolation preflight; refuses before "
                             "generation because no trusted provider is registered")
    parser.add_argument("--run-id")
    parser.add_argument("--challenge-nonce")
    args = parser.parse_args()

    if args.real_runner:
        return _main_real_runner(args)

    report = {
        "schema_id": SCHEMA_ID,
        "dry_run": True,
        "model_starts": 0,
        "is_execution_evidence": False,
        "calculator": "stub",
        "evaluated_at_utc": EVALUATED_AT,
        "validity_policy_sha256": POLICY["policy_sha256"],
        "preregistered_expected_computes": EXPECTED_COMPUTES,
        "fixtures": {},
        "result": "PASS",
    }

    total_invocations = 0
    total_processes = 0
    # The record names the frozen plan and the harness it measured itself
    # against, so a reader can tell a current run from a stale artefact without
    # recomputing anything outside this file. The harness hash is of the harness
    # as it stands before this record is written, which is why it lands in the
    # record and not in the harness.
    report["provenance"] = {
        "preregistration_sha256": sha256_path(PREREGISTRATION),
        "harness_sha256": sha256_path(pathlib.Path(__file__)),
        "preregistration_revision": json.loads(
            PREREGISTRATION.read_text(encoding="utf-8")).get("revision"),
    }
    graph = frozen_dependency_graph()
    report["dependency_graph"] = graph
    if not all(graph["checks"].values()):
        report["result"] = "FAIL"
    for fixture_id in args.fixtures:
        fixture = load_fixture(fixture_id)
        with tempfile.TemporaryDirectory(prefix="g3-%s-" % fixture_id) as temporary:
            directory = pathlib.Path(temporary)
            prefix = directory / "prefix.sqlite"
            build_prefix(prefix, fixture)
            prefix_bytes = prefix.read_bytes()
            pair = run_pair(prefix_bytes, fixture, directory)
            controls = run_controls(pair["snapshot_after_d1"], prefix_bytes,
                                    fixture, directory)
            pair.pop("snapshot_after_d1")
        fixture_checks = {**pair["checks"], **controls["checks"]}
        report["fixtures"][fixture_id] = {
            "checks": fixture_checks,
            "probes": pair["probes"],
            "agreements": pair["agreements"],
            "es_calculator_invocations": pair["es_calculator_invocations"],
            "is_calculator_invocations": pair["is_calculator_invocations"],
            "es_compute_log": pair["es_compute_log"],
            "is_compute_log": pair["is_compute_log"],
            "is_denied_touches": pair["is_denied_touches"],
            "es_execution_state_count": pair["es_execution_state_count"],
            "is_execution_state_count": pair["is_execution_state_count"],
            "verdict": pair["verdict"],
            "gate_processes": controls["processes"],
            "gate_process_count": controls["process_count"],
            "decision": "PASS" if all(fixture_checks.values()) else "FAIL",
        }
        total_invocations += (pair["es_calculator_invocations"]
                              + pair["is_calculator_invocations"])
        total_processes += controls["process_count"]
        if not all(fixture_checks.values()):
            report["result"] = "FAIL"

    report["budget"] = {
        # `calculator_invocations` counts calls into the injected calculator.
        # With the stub that is a *slot* in the design, not a model process:
        # `actual_model_starts` stays 0 for the whole dry run. The two numbers
        # are deliberately named apart so neither can be read as the other.
        "predicted_calculator_invocations": 2 * 2 * sum(EXPECTED_COMPUTES),
        "measured_calculator_invocations": total_invocations,
        "predicted_gate_processes": 2 * 2,
        "measured_gate_processes": total_processes,
        "actual_model_starts": 0,
        "retries": 0,
        "measured_matches_prediction": (
            total_invocations == 2 * 2 * sum(EXPECTED_COMPUTES)
            and total_processes == 4),
    }
    if not report["budget"]["measured_matches_prediction"]:
        report["result"] = "FAIL"
    if report["result"] == "PASS":
        verdicts = {entry["verdict"] for entry in report["fixtures"].values()}
        # A divergence is an observation, not a proof: the harness records what
        # the two arms answered, and leaves the interpretation to the reviewer.
        report["es_independent_contribution"] = (
            "NOT_PROVEN" if verdicts == {"ES_INDEPENDENT_CONTRIBUTION_NOT_PROVEN"}
            else "DIVERGENCE_OBSERVED")
    report["non_claims"] = [
        "no model was started; the calculator is a stub",
        "this harness produces no execution evidence",
        "a formal G3 batch requires separate authorization",
    ]

    text = json.dumps(report, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")) + "\n"
    print(text, end="")
    if args.out:
        pathlib.Path(args.out).write_text(text, encoding="utf-8")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
