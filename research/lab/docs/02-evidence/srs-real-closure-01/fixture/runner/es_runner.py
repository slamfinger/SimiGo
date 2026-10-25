#!/usr/bin/env python3
"""SRS-REAL-CLOSURE-01 ES process runner (fixture instrument, revision 3).

RF-4.5/RF-4.6 cycle under SARS ..._REVISION_002:
  complete binding-kind-specific IMMUTABLE_REVISION §9 payload and make the
  mapping snapshot seal boundary explicit; keep all accepted F-1..F-4
  mechanics unchanged.

Deterministic single-purpose runner. One process per invocation; every mode
appends events to its own process-local event log with monotonic ordinals.

Subcommands (each = one process lifetime):
  materialize   write the D object + initial current-dependency resolution
                mapping entry                            (IS_MUTATION, exec)
  es1           read tau1; sealed-read D; run expensive unit U once
                (write-before-return ledger); settle SRS; persist; exit
  es2           read tau2; resolve SRS from IS; hash-verify; schema-validate;
                sealed mapping read; dependency comparison; build closed
                SRS-VAL invocation graph; invoke T-IMPL-01 via the compiled
                adapter; on REUSE compute the delta continuation; write
                continuation record into IS; exit
  esn           same as es2 with tauN1 (negative control; expected BLOCK)
  mutate-n1     add D' as a NEW immutable object and update ONLY the
                current-dependency resolution mapping   (IS_MUTATION, exec)
  driver        orchestrates materialize → es1 → [tau substitution] → es2 →
                mutate-n1 → esn with campaign-level ordering evidence, then
                invokes the observer separately

Nothing in this file executes unless invoked; fixture self-validation
(SV-1..SV-6) exercises the units in isolation in a temporary directory.
"""

import hashlib
import json
import os
import subprocess
import sys

IS_OBJECTS = "objects"
IS_INDEX = "index.jsonl"
IS_CURRENT = os.path.join("current", "dependencies.jsonl")

OBSERVER_AUTHORIZATION_IDENTITY = "SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_001"
CHANNEL_UNIVERSE_IDENTITY = "SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1"

# §9 failure vocabulary
READ_INSTANCE_NOT_IMMUTABLE = "READ_INSTANCE_NOT_IMMUTABLE"
READ_TIME_CONTENT_MISMATCH = "READ_TIME_CONTENT_MISMATCH"
REVISION_TO_DIGEST_BINDING_INVALID = "REVISION_TO_DIGEST_BINDING_INVALID"


class MappingNotImmutable(Exception):
    """READ_INSTANCE_NOT_IMMUTABLE — mapping snapshot boundary violation
    (identity replaced, prefix not exactly obtainable, append-only
    invariant violated)."""


class RevisionBindingInvalid(Exception):
    """REVISION_TO_DIGEST_BINDING_INVALID — malformed or digest-invalid
    revision→content-digest resolution from the sealed mapping entry."""


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json(record) -> str:
    return json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


class EventLog:
    """Per-process append-only event log with write-before-return semantics.
    Every line carries a monotonic `ordinal` (0-based per process)."""

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
        """Expensive-unit invocation ledger entry. Flushed BEFORE the result
        value is returned to the caller (write-before-return)."""
        self._emit({"event": "U_INVOCATION_LEDGER", "run_id": run_id,
                    "ordinal_in_ledger": ordinal, "input_digest": input_digest,
                    "output_digest": output_digest, "ledger_type": "U"})

    def close(self, event: str, **fields) -> None:
        self._emit({"event": event, **fields})
        self._fh.close()


# ---------------------------------------------------------------------------
# F-4.3b: mapping read-instance sealing (IMMUTABLE_SNAPSHOT_PRESEALED)
# ---------------------------------------------------------------------------

def seal_mapping_snapshot(is_dir: str) -> tuple:
    """Seal the mapping state at read-instance start.

    Procedure (Auth Package §9; Revision Request v0.6 F-4.3b):
      1. open the mapping file, obtain an FD;
      2. capture file identity (st_dev/st_ino) and start_size = fstat size;
      3. capture EXACTLY bytes [0, start_size) from that FD — a short read
         is a failure (file shrank below start_size = non-append mutation),
         not a smaller snapshot;
      4. seal: mapping_snapshot_digest = sha256(prefix bytes);
      5. parse the LAST entry per dependency_id FROM THE SEALED PREFIX
         ONLY — the mapping path is never re-read inside this read
         instance;
      post-snapshot checks are METADATA-ONLY (fstat same identity;
      current_size >= start_size) — the mapping CONTENT is never re-read.
      With the frozen append-only semantics, same inode + size >=
      start_size + the sole lawful writer appending place later appends
      outside this read instance.

    Raises MappingNotImmutable (READ_INSTANCE_NOT_IMMUTABLE) on: identity
    replacement, short read (non-append mutation), or post-snapshot
    metadata-check failure.
    """
    path = os.path.join(is_dir, IS_CURRENT)
    fd = os.open(path, os.O_RDONLY)
    try:
        st = os.fstat(fd)
        file_identity = {"st_dev": st.st_dev, "st_ino": st.st_ino}
        start_size = st.st_size
        chunks = []
        remaining = start_size
        while remaining > 0:
            chunk = os.read(fd, remaining)
            if not chunk:
                raise MappingNotImmutable(READ_INSTANCE_NOT_IMMUTABLE +
                                          ": short read — file shrank below start_size")
            chunks.append(chunk)
            remaining -= len(chunk)
        prefix = b"".join(chunks)
        st_after_capture = os.fstat(fd)
        post_fd = {
            "same_identity": (st_after_capture.st_dev,
                              st_after_capture.st_ino) ==
                             (st.st_dev, st.st_ino),
            "current_size_ge_start_size":
                st_after_capture.st_size >= start_size,
        }
    finally:
        os.close(fd)
    snapshot_digest = sha256_hex(prefix)
    # parse LAST entry per dependency_id from the sealed prefix ONLY
    last_entries = {}
    for line in prefix.decode("utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        e = json.loads(line)
        last_entries[e["dependency_id"]] = e
    # Post-close path identity is separate from the required FD-level check.
    st_path = os.stat(path)
    post = {
        "fd_level": post_fd,
        "path_identity_same": (st_path.st_dev,
                               st_path.st_ino) == (st.st_dev, st.st_ino),
    }
    if not (post_fd["same_identity"] and
            post_fd["current_size_ge_start_size"] and post["path_identity_same"]):
        raise MappingNotImmutable(READ_INSTANCE_NOT_IMMUTABLE +
                                  ": post-snapshot metadata check failed")
    seal = {
        "mapping_snapshot_identity": "MAPPING-SNAPSHOT-" + snapshot_digest[:16],
        "mapping_snapshot_file_identity": file_identity,
        "mapping_snapshot_start_size": start_size,
        "mapping_snapshot_digest": snapshot_digest,
        "mapping_snapshot_seal_boundary": {
            "boundary_type": "BYTE_PREFIX_CLOSED",
            "start_offset": 0,
            "end_offset_exclusive": start_size,
            "acquisition_order": [
                "OPEN_FD", "FSTAT_IDENTITY_AND_START_SIZE",
                "EXACT_PREFIX_CAPTURE", "SHA256_SEAL",
            ],
            "content_re_read_after_boundary": False,
        },
    }
    return seal, last_entries, post


def read_instance_record(log: EventLog, ri_id: str, declared_input_identity: str,
                         binding_kind: str, declared_digest: str,
                         read_time_digest: str, begin_ordinal: int,
                         mapping_seal=None, extra=None,
                         sealed_mapping_entry=None) -> dict:
    """Auth Package §9 record: ALL ELEVEN fields, plus SUPPLEMENTARY
    instrumentation fields (additive, never substituting)."""
    consumed = declared_digest == read_time_digest
    if binding_kind == "IMMUTABLE_REVISION":
        if (not isinstance(sealed_mapping_entry, dict) or
                not isinstance(sealed_mapping_entry.get("revision"), int) or
                sealed_mapping_entry.get("revision") < 0 or
                not isinstance(sealed_mapping_entry.get("content_address"), str)):
            raise RevisionBindingInvalid(REVISION_TO_DIGEST_BINDING_INVALID +
                                         ": malformed sealed revision binding")
        resolved = sealed_mapping_entry["content_address"]
        if len(resolved) != 64 or any(c not in "0123456789abcdef" for c in resolved):
            raise RevisionBindingInvalid(REVISION_TO_DIGEST_BINDING_INVALID +
                                         ": digest-invalid revision binding")
        if declared_digest != resolved or read_time_digest != resolved:
            raise RevisionBindingInvalid(REVISION_TO_DIGEST_BINDING_INVALID +
                                         ": revision binding mismatch")
    rec = {
        "event": "READ_INSTANCE",
        "read_instance_identity": ri_id,
        "declared_input_identity": declared_input_identity,
        "declared_input_binding_kind": binding_kind,
        "declared_content_digest": declared_digest,
        "declared_digest_algorithm": "sha256",
        "read_time_content_digest": read_time_digest,
        "read_instance_snapshot_or_atomicity_proof": "IMMUTABLE_SNAPSHOT_PRESEALED",
        "observer_authorization_identity": OBSERVER_AUTHORIZATION_IDENTITY,
        "channel_universe_identity": CHANNEL_UNIVERSE_IDENTITY,
        "read_begin_boundary": begin_ordinal,
        "read_end_boundary": None,  # filled below with this record's ordinal
        "consumed_content_matches_declaration": consumed,
    }
    if mapping_seal is not None:
        rec["mapping_snapshot_seal"] = mapping_seal
    if binding_kind == "IMMUTABLE_REVISION":
        resolved = sealed_mapping_entry["content_address"]
        revision = sealed_mapping_entry["revision"]
        rec["declared_immutable_revision"] = revision
        rec["revision_to_content_digest_binding"] = {
            "revision": revision,
            "content_digest": resolved,
            "binding_source": "MAPPING_SNAPSHOT_LAST_ENTRY",
        }
        rec["resolved_declared_content_digest"] = resolved
    if extra:
        rec.update(extra)
    rec["read_end_boundary"] = log._ordinal  # the ordinal this record will take
    log._emit(rec)
    return rec


# ---------------------------------------------------------------------------
# IS primitives
# ---------------------------------------------------------------------------

def is_write_object(is_dir: str, content: bytes) -> str:
    """Write-once content-addressed object. The seal operation: tmp+fsync+
    rename; an existing address REFUSES divergent content."""
    addr = sha256_hex(content)
    path = os.path.join(is_dir, IS_OBJECTS, addr)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() != content:
                raise RuntimeError("READ_INSTANCE_NOT_IMMUTABLE: content-address collision")
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


def is_read_object_verified(is_dir: str, address: str, declared_digest: str,
                            binding_kind: str, ri_id: str,
                            declared_input_identity: str,
                            log: EventLog, mapping_seal=None) -> bytes:
    """Content-addressed object read with §9 digest verification.
    IMMUTABLE_SNAPSHOT_PRESEALED: the seal is the write-once content
    addressing; the read verifies read_time digest == declared digest."""
    begin = log._ordinal
    log.event("READ_INSTANCE_BEGIN", read_instance_identity=ri_id)
    path = os.path.join(is_dir, IS_OBJECTS, address)
    with open(path, "rb") as fh:
        content = fh.read()
    read_time_digest = sha256_hex(content)
    rec = read_instance_record(
        log, ri_id, declared_input_identity, binding_kind,
        declared_digest, read_time_digest, begin, mapping_seal=mapping_seal,
        extra={"object_address": address})
    if read_time_digest != declared_digest:
        raise RuntimeError(READ_TIME_CONTENT_MISMATCH + ": " + ri_id)
    if not rec["consumed_content_matches_declaration"]:
        raise RuntimeError(READ_INSTANCE_NOT_IMMUTABLE + ": " + ri_id)
    return content


def mapping_update(is_dir: str, dependency_id: str, content_address: str,
                   revision: int, reason: str) -> None:
    """The ONLY mapping write path: append-mode open/write/fsync.
    Append-only writer invariant (closed-world, audited by SV-4c-1b):
    no truncate, no pwrite, no seek-and-overwrite, no in-place rewrite."""
    path = os.path.join(is_dir, IS_CURRENT)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(canonical_json({"dependency_id": dependency_id,
                                 "content_address": content_address,
                                 "revision": revision,
                                 "reason": reason}) + "\n")
        fh.flush()
        os.fsync(fh.fileno())


# ---------------------------------------------------------------------------
# Expensive unit U
# ---------------------------------------------------------------------------

def expensive_unit_u(dependency_content: bytes, procedure: dict,
                     log: EventLog, run_id: str) -> str:
    """U = iterated hash chain sha256^N(digest(D) || identity(P)).
    Exactly one ledger entry, flushed BEFORE the result is returned."""
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


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

def mode_materialize(is_dir: str, tau: dict, log: EventLog, run_id: str) -> int:
    for dep in tau["dependencies"]:
        with open(dep["seed_path"], "rb") as fh:
            content = fh.read()
        addr = is_write_object(is_dir, content)
        mapping_update(is_dir, dep["dependency_id"], addr, 1, "initial materialization")
        log.event("OBJECT_MATERIALIZED", dependency_id=dep["dependency_id"],
                  content_address=addr, revision=1)
    log.close("PROCESS_EXIT", exit_code=0)
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
    # F-4.3b: sealed mapping read (new read instance)
    begin = log._ordinal
    log.event("READ_INSTANCE_BEGIN", read_instance_identity="RI-ES1-MAPPING")
    seal, entries, post = seal_mapping_snapshot(is_dir)
    current = entries.get(dep["dependency_id"])
    log.event("MAPPING_SNAPSHOT_SEALED", **seal, post_metadata_checks=post)
    if current is None:
        log.close("ABORT", reason="dependency not materialized")
        return 2
    read_instance_record(
        log, "RI-ES1-MAPPING", dep["dependency_id"], "IMMUTABLE_REVISION",
        current["content_address"], current["content_address"], begin,
        mapping_seal=seal, sealed_mapping_entry=current)
    # read the D object with §9 digest verification
    dependency_content = is_read_object_verified(
        is_dir, current["content_address"], current["content_address"],
        "CONTENT_ADDRESS", "RI-ES1-DOBJECT", dep["dependency_id"], log,
        mapping_seal=seal)
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
              pinned_dependency_address=current["content_address"],
              pinned_dependency_revision=current["revision"])
    log.close("PROCESS_EXIT", exit_code=0)
    return 0


def exact_binding_json(identity: str, version: str, content_address: str) -> dict:
    return {"state": "exact", "identity": identity, "version": version,
            "contentAddress": "sha256obj:" + content_address,
            "integrityBinding": "sha256:" + content_address}


def mode_es2(is_dir: str, tau: dict, log: EventLog, run_id: str,
             negative: bool) -> int:
    import validate_srs  # via PYTHONPATH (fixture/schema), env-propagated

    srs_identity = tau["srs_identity"]
    entry = is_read_index(is_dir, srs_identity)
    if entry is None:
        log.close("ABORT", reason="srs_identity not found in IS index")
        return 2
    begin = log._ordinal
    log.event("READ_INSTANCE_BEGIN", read_instance_identity="RI-ES-SRS")
    record_bytes = is_read_object_verified(
        is_dir, entry["record_object"], entry["record_object"],
        "CONTENT_ADDRESS", "RI-ES-SRS", srs_identity, log)
    srs = json.loads(record_bytes.decode("utf-8"))
    ok, reason = validate_srs.validate(srs)
    log.event("SRS_RESOLVED", srs_identity=srs_identity,
              record_object=entry["record_object"],
              byte_hash_match=sha256_hex(record_bytes) == entry["record_object"],
              schema_valid=ok, schema_reason=reason)
    if not ok:
        log.close("ABORT", reason="schema invalid: " + str(reason))
        return 2

    # F-4.3b: sealed mapping read (new read instance) + F-1 LAST-entry
    begin_m = log._ordinal
    log.event("READ_INSTANCE_BEGIN", read_instance_identity="RI-ES-MAPPING")
    seal, entries, post = seal_mapping_snapshot(is_dir)
    pinned = srs["dependencies"][0]
    current = entries.get(pinned["dependency_id"])
    log.event("MAPPING_SNAPSHOT_SEALED", **seal, post_metadata_checks=post)
    # F-4.4: a revision number is never compared as if it were a digest —
    # the IMMUTABLE_REVISION binding resolves revision → content digest via
    # the sealed snapshot entry; the digest is what is compared.
    if current is not None:
        read_instance_record(
            log, "RI-ES-MAPPING", pinned["dependency_id"],
            "IMMUTABLE_REVISION", current["content_address"],
            current["content_address"], begin_m, mapping_seal=seal,
            sealed_mapping_entry=current)
    resolved = (current is not None
                and current["content_address"] == pinned["content_address"])
    log.event("DEPENDENCY_COMPARISON", dependency_id=pinned["dependency_id"],
              pinned_address=pinned["content_address"],
              pinned_revision=pinned["revision"],
              current_address=(current or {}).get("content_address"),
              current_revision=(current or {}).get("revision"),
              resolved=resolved)

    # read the current dependency object with §9 digest verification
    if current is not None:
        dep_obj_addr = current["content_address"]
        dep_obj = is_read_object_verified(
            is_dir, dep_obj_addr, dep_obj_addr, "CONTENT_ADDRESS",
            "RI-ES-DEPOBJ", pinned["dependency_id"], log, mapping_seal=seal)
        del dep_obj  # content consumed only through its verified digest

    invocation = build_invocation_graph(tau, srs, current, resolved)
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


def build_invocation_graph(tau: dict, srs: dict, current, resolved: bool) -> dict:
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


# ---------------------------------------------------------------------------
# F-3: tau runtime-copy substitution (driver)
# ---------------------------------------------------------------------------

def substitute_tau(tau_path: str, srs_identity: str, out_path: str) -> dict:
    """Read a fixture τ original (read-only), substitute the actual
    srs_identity for the placeholder, and write the runtime τ copy to the
    run directory. Fixture originals are never modified."""
    with open(tau_path, "r", encoding="utf-8") as fh:
        tau = json.load(fh)
    tau["srs_identity"] = srs_identity
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(tau))
        fh.flush()
        os.fsync(fh.fileno())
    return {"runtime_tau_path": os.path.abspath(out_path),
            "substituted_srs_identity": srs_identity,
            "source_tau": os.path.abspath(tau_path)}


def extract_srs_identity_from_es1_log(log_path: str) -> str:
    with open(log_path, "r", encoding="utf-8") as fh:
        for line in fh:
            rec = json.loads(line.strip() or "{}")
            if rec.get("event") == "SRS_SETTLED_AND_PERSISTED":
                return rec["srs_identity"]
    raise RuntimeError("no SRS_SETTLED_AND_PERSISTED event in es1 log")


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def run_step(args, log: EventLog, label: str, env: dict) -> int:
    log.event("SPAWN", target=label, argv=args[0:2])
    proc = subprocess.run(args, capture_output=True, text=True, env=env)
    log.event("EXIT", target=label, exit_code=proc.returncode)
    if proc.returncode != 0:
        log.event("STEP_STDERR", target=label, tail=proc.stderr[-800:])
    return proc.returncode


def mode_driver(tau_dir: str, run_dir: str, is_dir: str, adapter_bin: str) -> int:
    """Sequential orchestration with campaign-level ordering evidence in ONE
    log. Temporal separation is proven by event order IN THIS FILE."""
    log = EventLog(os.path.join(run_dir, "driver-events.jsonl"),
                   "driver", "driver", os.getpid())
    here = os.path.dirname(os.path.abspath(__file__))
    env = dict(os.environ, SRSVAL_ADAPTER_BIN=adapter_bin,
               PYTHONPATH=os.path.abspath(os.path.join(here, "..", "schema")),
               PYTHONDONTWRITEBYTECODE="1")
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
        if label == "es1":
            # F-3: after es1, substitute the actual srs_identity into
            # runtime τ copies (fixture τ originals untouched).
            if run_step(args, log, label, env) != 0:
                failed.append(label)
                break
            srs_id = extract_srs_identity_from_es1_log(
                os.path.join(run_dir, "es1-events.jsonl"))
            runtime_taus = {}
            for name, src in (("tau2", os.path.join(tau_dir, "tau2.json")),
                              ("tauN1", os.path.join(tau_dir, "tauN1.json"))):
                out = os.path.join(run_dir, name + "-runtime.json")
                info = substitute_tau(src, srs_id, out)
                runtime_taus[name] = info["runtime_tau_path"]
            log.event("TAU_RUNTIME_COPIES_SUBSTITUTED", srs_identity=srs_id,
                      tau2_runtime=runtime_taus["tau2"],
                      tauN1_runtime=runtime_taus["tauN1"],
                      fixture_tau_originals_untouched=True)
            # point es2/esn at the runtime copies
            steps[2][1][5] = runtime_taus["tau2"]
            steps[4][1][5] = runtime_taus["tauN1"]
            continue
        if run_step(args, log, label, env) != 0:
            failed.append(label)
            if label == "materialize":
                break
    log.event("OBSERVER_NEXT", note="observer runs as a separate process after driver exit")
    log.close("DRIVER_EXIT", failed_steps=failed)
    return 0 if not failed else 1


def main() -> int:
    if len(sys.argv) >= 6 and sys.argv[1] == "driver":
        return mode_driver(sys.argv[3], sys.argv[2], sys.argv[4], sys.argv[5])
    if len(sys.argv) < 4:
        print("usage: es_runner.py MODE RUN_ID EVENT_LOG_PATH TAU_JSON [IS_DIR]\n"
              "       es_runner.py driver RUN_DIR TAU_DIR IS_DIR ADAPTER_BIN",
              file=sys.stderr)
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
