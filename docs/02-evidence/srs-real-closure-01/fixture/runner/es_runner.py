#!/usr/bin/env python3
"""SRS-REAL-CLOSURE-01 ES process runner (fixture instrument).

Deterministic single-purpose runner for the minimal ES1 -> IS(SRS) ->
independent ES2 lawful-reuse experiment (Design v0.2). One process per
invocation; every mode appends events to its own process-local event log.

Subcommands (each = one process lifetime):
  materialize   write the D object + initial current-dependency resolution
                mapping into IS            (IS_MUTATION, execution stage only)
  es1           read tau1; run expensive unit U once (write-before-return
                ledger entry); settle SRS; persist into IS; exit
  es2           read tau2; resolve SRS from IS; hash-verify; schema-validate;
                read current dependency; compare pinned vs current; build
                closed SRS-VAL invocation graph; invoke T-IMPL-01 via the
                compiled adapter; on REUSE compute the delta continuation;
                write continuation record into IS; exit
  esn           same as es2 with tau2-N1 (same srs_identity, negative control)
  mutate-n1     add D' as a NEW immutable object and update ONLY the
                current-dependency resolution mapping  (IS_MUTATION, exec only)
  driver        orchestrates es1 -> es2 -> mutate-n1 -> esn with recorded
                spawn/exit ordering, then invokes the observer separately

Nothing in this file executes unless invoked; fixture preparation only
syntax-checks it (py_compile). Execution itself is a later authorized stage.
"""

import hashlib
import json
import os
import subprocess
import sys

IS_OBJECTS = "objects"
IS_INDEX = "index.jsonl"
IS_CURRENT = os.path.join("current", "dependencies.jsonl")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json(record) -> str:
    return json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class EventLog:
    """Per-process append-only event log with write-before-return semantics.
    Every line carries a monotonic `ordinal` (0-based per process) so the
    observer can mechanically verify temporal ordering (C4)."""

    def __init__(self, path: str, run_id: str, mode: str, pid: int):
        self.path = path
        self._ordinal = 0
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self._fh = open(path, "a", encoding="utf-8")
        self._emit({"event": "process_start", "run_id": run_id, "mode": mode, "pid": pid})

    def _emit(self, record) -> None:
        record["ordinal"] = self._ordinal
        self._ordinal += 1
        self._fh.write(canonical_json(record) + "\n")
        self._fh.flush()
        os.fsync(self._fh.fileno())

    def event(self, event: str, **fields) -> None:
        self._emit({"event": event, **fields})

    def ledger_u_entry(self, run_id: str, ordinal: int, input_digest: str, output_digest: str) -> None:
        """The expensive-unit invocation ledger entry. Flushed BEFORE the
        result value is returned to the caller (write-before-return)."""
        self._emit({"event": "U_INVOCATION_LEDGER", "run_id": run_id,
                    "ordinal": ordinal, "input_digest": input_digest,
                    "output_digest": output_digest, "ledger_type": "U"})

    def close(self, event: str, **fields) -> None:
        self._emit({"event": event, **fields})
        self._fh.close()


def is_write_object(is_dir: str, content: bytes) -> str:
    """Write-once content-addressed object. Refuses to overwrite."""
    addr = sha256_hex(content)
    path = os.path.join(is_dir, IS_OBJECTS, addr)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() != content:
                raise RuntimeError("content-address collision")
        return addr
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(content)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)
    return addr


def is_append_index(is_dir: str, line: dict) -> None:
    with open(os.path.join(is_dir, IS_INDEX), "a", encoding="utf-8") as fh:
        fh.write(canonical_json(line) + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def is_read_index(is_dir: str, srs_identity: str):
    path = os.path.join(is_dir, IS_INDEX)
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            if entry.get("srs_identity") == srs_identity:
                return entry
    return None


def is_read_object(is_dir: str, address: str) -> bytes:
    with open(os.path.join(is_dir, IS_OBJECTS, address), "rb") as fh:
        return fh.read()


def mapping_read(is_dir: str, dependency_id: str):
    path = os.path.join(is_dir, IS_CURRENT)
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            if entry.get("dependency_id") == dependency_id:
                return entry
    return None


def mapping_update(is_dir: str, dependency_id: str, content_address: str, revision: int, reason: str) -> None:
    """Append a new current-resolution entry (the ONLY mutable fixture state)."""
    path = os.path.join(is_dir, IS_CURRENT)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(canonical_json({"dependency_id": dependency_id,
                                 "content_address": content_address,
                                 "revision": revision,
                                 "reason": reason}) + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def expensive_unit_u(dependency_content: bytes, procedure: dict, log: EventLog, run_id: str) -> str:
    """U = iterated hash chain sha256^N(digest(D) || identity(P)).

    Exactly one ledger entry is written and flushed BEFORE the result is
    returned (Design v0.2 section 1, write-before-return)."""
    n = int(procedure["iterations"])
    proc_id = procedure["identity"] + "@" + procedure["version"]
    digest_d = sha256_hex(dependency_content)
    h = sha256_hex((digest_d + proc_id).encode("utf-8"))
    for _ in range(n):
        h = sha256_hex(h.encode("utf-8"))
    ordinal = int(os.environ.get("SRSVAL_U_ORDINAL", "0")) + 1
    os.environ["SRSVAL_U_ORDINAL"] = str(ordinal)
    log.ledger_u_entry(run_id, ordinal, digest_d + "|" + proc_id, h)
    return h


def mode_materialize(is_dir: str, tau: dict, log: EventLog, run_id: str) -> int:
    deps = tau["dependencies"]
    for dep in deps:
        with open(dep["seed_path"], "rb") as fh:
            content = fh.read()
        addr = is_write_object(is_dir, content)
        mapping_update(is_dir, dep["dependency_id"], addr, 1, "initial materialization")
        log.event("OBJECT_MATERIALIZED", dependency_id=dep["dependency_id"],
                  content_address=addr, revision=1)
    return 0


def build_srs_record(tau: dict, dependency_addr: str, revision: int,
                     result: str, run_id: str, u_ref: str) -> dict:
    d = tau["dependencies"][0]
    return {
        "schema_version": "SRS-1",
        "settlement_status": "DECLARED_SETTLED",
        "result": {"identity": result,
                   "derivation_procedure": {"identity": tau["procedure"]["identity"],
                                            "version": tau["procedure"]["version"]}},
        "source_relation": {"relation_id": tau["relation_id"],
                            "semantics_binding": tau["semantics_binding"]},
        "dependencies": [{"dependency_id": d["dependency_id"],
                          "content_address": dependency_addr,
                          "revision": revision}],
        "provenance": {"formation_es_id": "ES1-" + run_id,
                       "formation_run_id": run_id,
                       "u_invocation_record_ref": u_ref},
        "freshness": [{"requirement_id": "dep-current",
                       "condition": "dependency-content-current",
                       "initial_evidence_ref": dependency_addr}],
        "request_class": tau["request_class"],
        "identity_rule": {"identity": "SRS-CANONICAL-ID-V1", "version": "1.0.0"},
    }


def mode_es1(is_dir: str, tau: dict, log: EventLog, run_id: str) -> int:
    dep = tau["dependencies"][0]
    current = mapping_read(is_dir, dep["dependency_id"])
    if current is None:
        log.close("ABORT", reason="dependency not materialized")
        return 2
    dependency_content = is_read_object(is_dir, current["content_address"])
    result = expensive_unit_u(dependency_content, tau["procedure"], log, run_id)
    srs = build_srs_record(tau, current["content_address"], current["revision"],
                           result, run_id, "U:" + run_id + ":1")
    srs["srs_identity"] = sha256_hex(canonical_json(srs).encode("utf-8"))
    record_bytes = canonical_json(srs).encode("utf-8")
    record_addr = is_write_object(is_dir, record_bytes)
    is_append_index(is_dir, {"srs_identity": srs["srs_identity"],
                             "record_object": record_addr})
    log.event("SRS_SETTLED_AND_PERSISTED", srs_identity=srs["srs_identity"],
              record_object=record_addr, result_identity=result,
              pinned_dependency_address=current["content_address"])
    log.close("PROCESS_EXIT", exit_code=0)
    return 0


def exact_binding_json(identity: str, version: str, content_address: str) -> dict:
    return {"state": "exact", "identity": identity, "version": version,
            "contentAddress": "sha256obj:" + content_address,
            "integrityBinding": "sha256:" + content_address}


def mode_es2(is_dir: str, tau: dict, log: EventLog, run_id: str, negative: bool) -> int:
    import validate_srs  # noqa: E402  (sys.path includes fixture/schema)

    srs_identity = tau["srs_identity"]
    entry = is_read_index(is_dir, srs_identity)
    if entry is None:
        log.close("ABORT", reason="srs_identity not found in IS index")
        return 2
    record_bytes = is_read_object(is_dir, entry["record_object"])
    if sha256_hex(record_bytes) != entry["record_object"]:
        log.close("ABORT", reason="resolved bytes do not hash to object address")
        return 2
    srs = json.loads(record_bytes.decode("utf-8"))
    ok, reason = validate_srs.validate(srs)
    log.event("SRS_RESOLVED", srs_identity=srs_identity,
              record_object=entry["record_object"],
              byte_hash_match=sha256_hex(record_bytes) == entry["record_object"],
              schema_valid=ok, schema_reason=reason)
    if not ok:
        log.close("ABORT", reason="schema invalid: " + str(reason))
        return 2

    # E3 instrument: compare pinned dependency binding vs current state.
    pinned = srs["dependencies"][0]
    current = mapping_read(is_dir, pinned["dependency_id"])
    resolved = current is not None and current["content_address"] == pinned["content_address"]
    log.event("DEPENDENCY_COMPARISON", dependency_id=pinned["dependency_id"],
              pinned_address=pinned["content_address"],
              current_address=(current or {}).get("content_address"),
              resolved=resolved)

    invocation = build_invocation_graph(tau, srs, current, resolved, negative)
    inv_name = "invocation_graph-esn.json" if negative else "invocation_graph-es2.json"
    inv_path = os.path.normpath(os.path.join(log.path, "..", inv_name))
    with open(inv_path, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(invocation))
        fh.flush()
        os.fsync(fh.fileno())
    log.event("INVOCATION_GRAPH_WRITTEN", path=os.path.abspath(inv_path))

    decision = invoke_adapter(inv_path)
    log.event("SRSVAL_DECISION", **decision)
    expected = "BLOCK" if negative else "REUSE"
    match = decision.get("primaryDecision") == expected
    log.event("EXPECTED_VS_ACTUAL", expected=expected,
              actual=decision.get("primaryDecision"), match=match)

    if not negative and decision.get("primaryDecision") == "REUSE":
        # E5/E6.3: the continuation output is a direct data function of the
        # SRS result content (delta consumes the result digest).
        delta_input = srs["result"]["identity"] + "|" + tau["delta"]["task_nonce"]
        continuation_output = sha256_hex(delta_input.encode("utf-8"))
        cont_record = {"continuation_record": "CR-ES2-" + run_id,
                       "consumed_srs_identity": srs_identity,
                       "delta_procedure": tau["delta"]["procedure"],
                       "continuation_output": continuation_output}
        cont_addr = is_write_object(is_dir, canonical_json(cont_record).encode("utf-8"))
        is_append_index(is_dir, {"srs_identity": "CR:" + cont_record["continuation_record"],
                                 "record_object": cont_addr})
        log.event("CONTINUATION_COMPLETED", consumed_srs_identity=srs_identity,
                  continuation_output=continuation_output, record_object=cont_addr)
    log.close("PROCESS_EXIT", exit_code=0)
    return 0


def build_invocation_graph(tau: dict, srs: dict, current, resolved: bool, negative: bool) -> dict:
    pinned = srs["dependencies"][0]
    dep = {
        "boundaryIdentity": tau["boundary_id"],
        "dependencyIdentity": pinned["dependency_id"],
        "revisionBinding": exact_binding_json(pinned["dependency_id"],
                                              "rev-" + str(pinned["revision"]),
                                              pinned["content_address"]),
        "resolved": resolved,
        "integrityReference": "sha256:" + pinned["content_address"],
        "role": "input",
        "necessity": "required",
        "blockingSupersession": False,
        "blockingInvalidation": (not resolved),
    }
    return {
        "boundary": {"boundaryIdentity": tau["boundary_id"],
                     "closeBoundary": tau["boundary_id"] + "-close",
                     "orderingEvidenceReference": "monotonic:" + tau["run_order"],
                     "orderingEvidenceIntegrity": "recorded-by-harness",
                     "consistencyDeclaration": "consistent"},
        "srs": {"boundaryIdentity": tau["boundary_id"],
                "settlementIdentity": srs["srs_identity"],
                "birthStatus": "declaredSettled",
                "sourceRelationBinding": srs["source_relation"]["relation_id"],
                "canonicalIdentityRuleApplicable": True,
                "canonicalIdentityRule": exact_binding_json(
                    srs["identity_rule"]["identity"], srs["identity_rule"]["version"],
                    srs["srs_identity"]),
                "resultIdentity": srs["result"]["identity"],
                "provenanceBindings": [srs["provenance"]["formation_es_id"],
                                       srs["provenance"]["u_invocation_record_ref"]]},
        "sourceRelation": {"boundaryIdentity": tau["boundary_id"],
                           "sourceIdentity": exact_binding_json(
                               srs["source_relation"]["relation_id"], "1.0.0",
                               srs["result"]["identity"]),
                           "semanticsIdentity": exact_binding_json(
                               srs["source_relation"]["semantics_binding"], "1.0.0",
                               srs["result"]["identity"]),
                           "applicabilityCoverage": tau["request_class"],
                           "invalidationRecords": []},
        "dependencies": [dep],
        "result": {"boundaryIdentity": tau["boundary_id"],
                   "resultIdentity": srs["result"]["identity"],
                   "resultRevision": "1",
                   "resolvedWithoutRecomputation": True,
                   "integrityReference": "sha256:" + srs["result"]["identity"],
                   "interpretable": True, "superseded": False, "invalidated": False},
        "resolution": {"boundaryIdentity": tau["boundary_id"],
                       "ruleBinding": exact_binding_json("res-rule", "1.0.0",
                                                         srs["result"]["identity"])},
        "policy": {"boundaryIdentity": tau["boundary_id"],
                   "applicablePolicyVersions": [exact_binding_json("policy-1", "1.0.0",
                                                                   srs["srs_identity"])]},
        "provenance": {"boundaryIdentity": tau["boundary_id"],
                       "productionEvidence": srs["provenance"]["formation_es_id"],
                       "declarationEvidence": srs["provenance"]["u_invocation_record_ref"],
                       "dependencyEvidence": "sha256:" + pinned["content_address"],
                       "resultEvidence": "sha256:" + srs["result"]["identity"],
                       "orderingEvidence": "monotonic:" + tau["run_order"]},
        "lifecycle": {"boundaryIdentity": tau["boundary_id"], "state": "determinate"},
        "freshnessRequirements": [{"requirementId": fr["requirement_id"],
                                   "boundaryIdentity": tau["boundary_id"],
                                   "state": {"state": "cleared",
                                             "evidenceReference": fr["initial_evidence_ref"]}}
                                  for fr in srs["freshness"]],
        "reuseRequest": {"state": "exact",
                         "requestIdentity": tau["request_id"],
                         "exactBinding": exact_binding_json(tau["request_id"], "1.0.0",
                                                            tau["tau_content_ref"]),
                         "requestedSettlementIdentity": srs["srs_identity"],
                         "requestClass": srs["request_class"],
                         "applicability": "applicable"},
        "governingAuthorization": {"kind": "notUsedNoRecomputePath"},
        "predicateRule": {"kind": "notUsed"},
        "declaredSurvivingFailures": [],
    }


def invoke_adapter(invocation_path: str) -> dict:
    adapter = os.environ["SRSVAL_ADAPTER_BIN"]
    out = subprocess.run([adapter, invocation_path], capture_output=True, text=True)
    if out.returncode != 0:
        return {"error": "adapter failed", "stderr": out.stderr[-500:]}
    return json.loads(out.stdout)


def mode_mutate_n1(is_dir: str, tau: dict, log: EventLog, run_id: str) -> int:
    with open(tau["d_prime_seed_path"], "rb") as fh:
        d_prime = fh.read()
    addr = is_write_object(is_dir, d_prime)
    mapping_update(is_dir, tau["dependencies"][0]["dependency_id"], addr, 2,
                   "N1 negative-control state advance")
    log.event("N1_MUTATION_APPLIED", new_object=addr, revision=2,
              original_objects_untouched=True, srs_index_untouched=True)
    log.close("PROCESS_EXIT", exit_code=0)
    return 0


def run_step(args, log: EventLog, label: str) -> int:
    log.event("SPAWN", target=label, argv=args[0:2])
    proc = subprocess.run(args, capture_output=True, text=True)
    log.event("EXIT", target=label, exit_code=proc.returncode)
    if proc.returncode != 0:
        log.event("STEP_STDERR", target=label, tail=proc.stderr[-800:])
    return proc.returncode


def mode_driver(tau_dir: str, run_dir: str, is_dir: str, adapter_bin: str) -> int:
    """Sequential orchestration with campaign-level ordering evidence in ONE
    log (driver-events.jsonl). Temporal separation (Design v0.2 §4) is proven
    by event order IN THIS FILE: es1 EXIT precedes es2 SPAWN, etc."""
    log = EventLog(os.path.join(run_dir, "driver-events.jsonl"),
                   "driver", "driver", os.getpid())
    here = os.path.dirname(os.path.abspath(__file__))
    env = dict(os.environ, SRSVAL_ADAPTER_BIN=adapter_bin,
               PYTHONPATH=os.path.abspath(os.path.join(here, "..", "schema")))
    runner = os.path.abspath(__file__)
    steps = [
        ("materialize", [sys.executable, runner, "materialize", "r1",
                         os.path.join(run_dir, "materialize-events.jsonl"),
                         os.path.join(tau_dir, "tau1.json"), is_dir]),
        ("es1", [sys.executable, runner, "es1", "r1",
                 os.path.join(run_dir, "es1-events.jsonl"),
                 os.path.join(tau_dir, "tau1.json"), is_dir]),
        ("es2", [sys.executable, runner, "es2", "r2",
                 os.path.join(run_dir, "es2-events.jsonl"),
                 os.path.join(tau_dir, "tau2.json"), is_dir]),
        ("mutate-n1", [sys.executable, runner, "mutate-n1", "r3",
                       os.path.join(run_dir, "mutate-n1-events.jsonl"),
                       os.path.join(tau_dir, "tauN1.json"), is_dir]),
        ("esn", [sys.executable, runner, "esn", "r4",
                 os.path.join(run_dir, "esn-events.jsonl"),
                 os.path.join(tau_dir, "tauN1.json"), is_dir]),
    ]
    failed = []
    for label, args in steps:
        if run_step(args, log, label) != 0:
            failed.append(label)
            if label in ("materialize", "es1"):
                break
    log.event("OBSERVER_NEXT", note="observer runs as a separate process after driver exit")
    log.close("DRIVER_EXIT", failed_steps=failed)
    return 0 if not failed else 1


def main() -> int:
    if len(sys.argv) >= 6 and sys.argv[1] == "driver":
        # driver RUN_DIR TAU_DIR IS_DIR ADAPTER_BIN
        return mode_driver(sys.argv[3], sys.argv[2], sys.argv[4], sys.argv[5])
    if len(sys.argv) < 4:
        print("usage: es_runner.py MODE RUN_ID EVENT_LOG_PATH TAU_JSON [IS_DIR]\n"
              "       es_runner.py driver RUN_DIR TAU_DIR IS_DIR ADAPTER_BIN", file=sys.stderr)
        return 64
    mode, run_id, log_path, tau_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    is_dir = sys.argv[5] if len(sys.argv) > 5 else "."
    with open(tau_path, "r", encoding="utf-8") as fh:
        tau = json.load(fh)
    log = EventLog(log_path, run_id, mode, os.getpid())
    handlers = {"materialize": lambda: mode_materialize(is_dir, tau, log, run_id),
                "es1": lambda: mode_es1(is_dir, tau, log, run_id),
                "es2": lambda: mode_es2(is_dir, tau, log, run_id, negative=False),
                "esn": lambda: mode_es2(is_dir, tau, log, run_id, negative=True),
                "mutate-n1": lambda: mode_mutate_n1(is_dir, tau, log, run_id)}
    if mode not in handlers:
        log.close("ABORT", reason="unknown mode " + mode)
        return 64
    return handlers[mode]()


if __name__ == "__main__":
    sys.exit(main())
