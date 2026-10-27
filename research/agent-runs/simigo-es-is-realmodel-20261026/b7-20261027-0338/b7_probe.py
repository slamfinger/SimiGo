#!/usr/bin/env python3
"""B-7 real-model replay of Stage B settlement consumption.

Runs against the INSTALLED Release build's plaintext loopback API
(127.0.0.1:8000) with a real model. It:

  1. stages a source settlement with a real chat generation;
  2. declares its reuse contract through the product's native
     `declareSettlementReuseContract` (scratch tool, no hand-written SQL);
  3. moves prefix-pool + branch-checkpoints aside and proves explicit
     consumption returns the settled value with ZERO model work and no KV files;
  4. exercises the refusal matrix, the ordinary (absent-field) path, the
     explicit recompute path and chainability of the derived settlement;
  5. audits the DB ledger and restores the moved directories.

Every request window is bracketed by a trace offset so "zero model work" is
read from the runtime trace, not inferred from the HTTP body alone.
"""
import hashlib, json, os, shutil, sqlite3, subprocess, sys, time
import urllib.error, urllib.request

REPO = "/Users/mr.simi/Documents/SimiGo"
HOME = os.path.expanduser("~")
SIMIGO = os.path.join(HOME, ".simigo")
DB = os.path.join(SIMIGO, "simigo.sqlite3")
TRACE = os.path.join(SIMIGO, "logs/native_mlx_trace.log")
OUT = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(REPO, "build/b7/tools/declare-contract/declare-contract")
PORT = 8000
BASE = "http://127.0.0.1:%d" % PORT
ROOT_ID = "work-000000008a721251"  # dep-root: 2 stable files
STARTED = time.time()
NONCE = time.strftime("%Y%m%d-%H%M%S")

results = {
    "nonce": NONCE,
    "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "base_url": BASE,
    "root_id": ROOT_ID,
    "steps": {},
}


def log(msg):
    print("[B7 %s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def save():
    path = os.path.join(OUT, "results-%s.json" % NONCE)
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    return path


def sha_json(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True).encode()).hexdigest()


# ---------------- HTTP ----------------

def post(path, payload, timeout=900):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        BASE + path, data=data, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            status = int(r.status)
    except urllib.error.HTTPError as e:
        raw = e.read()
        status = int(e.code)
    except Exception as e:
        return -1, {"error": repr(e)}, round(time.time() - t0, 3)
    try:
        body = json.loads(raw.decode())
    except Exception:
        body = {"raw": raw.decode(errors="replace")}
    return status, body, round(time.time() - t0, 3)


def get(path, timeout=60):
    try:
        with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return int(e.code), json.loads(e.read().decode())
        except Exception:
            return int(e.code), {}
    except Exception as e:
        return -1, {"error": repr(e)}


def wait_ready(limit=900):
    deadline = time.time() + limit
    last = None
    while time.time() < deadline:
        status, body = get("/v1/models", timeout=10)
        if status == 200 and body.get("data"):
            return body["data"][0].get("id")
        last = (status, body)
        time.sleep(5)
    raise SystemExit(
        "SERVICE_NOT_READY: /v1/models never returned 200 within %ss (last=%r). "
        "Start the service from the menu bar first." % (limit, last))


def output_text(body):
    parts = []
    for item in body.get("output") or []:
        for piece in item.get("content") or []:
            if isinstance(piece, dict) and piece.get("type") == "output_text":
                parts.append(piece.get("text") or "")
    return "\n".join(parts)


# ---------------- trace ----------------

def trace_offset():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(offset):
    if not os.path.exists(TRACE):
        return ""
    with open(TRACE, "rb") as f:
        f.seek(offset)
        return f.read().decode(errors="replace")


GEN_KEYS = ("[MLX] prefill", "mode=", "ttft=", "poolBind", "cacheHitTokens")


def generation_lines(text):
    return [ln.strip() for ln in text.splitlines()
            if any(k in ln for k in GEN_KEYS)]


def trace_digest(text):
    return [ln.strip() for ln in text.splitlines()
            if any(k in ln for k in
                   GEN_KEYS + ("[PROTOCOL] arrive", "NativeMLX ready",
                               "continuation_branch", "continuation_admitted"))]


# ---------------- DB (read-only) ----------------

def db_rows(sql, args=()):
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(sql, args).fetchall()]
    finally:
        con.close()


def db_one(sql, args=()):
    rows = db_rows(sql, args)
    return rows[0] if rows else None


def tool(*args, retries=6):
    for attempt in range(retries):
        r = subprocess.run([TOOL, DB] + list(args),
                           capture_output=True, text=True)
        if r.returncode == 0:
            return json.loads(r.stdout)
        if "database is locked" in (r.stderr or "") and attempt + 1 < retries:
            time.sleep(2)
            continue
        raise SystemExit("TOOL_FAILED %r: %s" % (args, r.stderr.strip()))
    raise SystemExit("TOOL_BUSY %r" % (args,))


# ---------------- directories ----------------

def dir_tree(root):
    if not os.path.isdir(root):
        return {"present": False, "file_count": 0, "total_bytes": 0,
                "listing_sha256": None, "files": []}
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            files.append({
                "rel": os.path.relpath(p, root),
                "size": st.st_size,
                "mtime_ns": st.st_mtime_ns,
                "inode": st.st_ino,
            })
    listing = "\n".join(
        "%s|%d|%d|%d" % (f["rel"], f["size"], f["mtime_ns"], f["inode"])
        for f in files)
    return {
        "present": True,
        "file_count": len(files),
        "total_bytes": sum(f["size"] for f in files),
        "listing_sha256": hashlib.sha256(listing.encode()).hexdigest(),
        "files": files,
    }


def two_dirs():
    return {
        "prefix_pool": dir_tree(os.path.join(SIMIGO, "prefix-pool")),
        "branch_checkpoints": dir_tree(os.path.join(SIMIGO, "branch-checkpoints")),
    }


def move_aside():
    dest = os.path.join(OUT, "isolation")
    os.makedirs(dest, exist_ok=True)
    moved = {}
    for name in ("prefix-pool", "branch-checkpoints"):
        src = os.path.join(SIMIGO, name)
        if os.path.isdir(src):
            target = os.path.join(dest, name)
            if os.path.exists(target):
                shutil.rmtree(target)
            shutil.move(src, target)
            moved[name] = target
    return moved


def restore(moved):
    """Never delete data: if the app recreated a directory during the window,
    keep the recreated copy under recreated-<name>/ and put the original back."""
    conflicts = {}
    for name, src in moved.items():
        if not os.path.isdir(src):
            continue
        dst = os.path.join(SIMIGO, name)
        if not os.path.exists(dst):
            shutil.move(src, dst)
            continue
        conflict = os.path.join(OUT, "recreated-" + name)
        if os.path.exists(conflict):
            shutil.rmtree(conflict)
        os.makedirs(conflict)
        shutil.move(dst, os.path.join(conflict, name))
        shutil.move(src, dst)
        conflicts[name] = conflict
    return conflicts


# ---------------- request bodies ----------------

CONTRACT = {
    "id": "simigo.settlement-consumption",
    "demand_class": "exact-repeat",
    "version": "v1",
    "extract": "content",
}


def consumption_body(model_id, source, query, roots, allow_recompute=False,
                     identity=None, include=True, contract=None, stream=False):
    body = {"model": model_id, "input": "consume", "max_output_tokens": 64}
    if stream:
        body["stream"] = True
    if include:
        entry = {
            "source_settlement_id": source,
            "contract": dict(contract or CONTRACT),
            "query": query,
            "root_ids": list(roots),
        }
        if allow_recompute:
            entry["allow_recompute"] = True
        if identity:
            entry["identity"] = identity
        body["settlement_consumption"] = entry
    return body


def window(label, payload, path="/v1/responses", timeout=900):
    off = trace_offset()
    status, body, secs = post(path, payload, timeout=timeout)
    time.sleep(0.4)
    trace = trace_since(off)
    record = {
        "label": label,
        "path": path,
        "request": payload,
        "status": status,
        "seconds": secs,
        "body": body,
        "generation_lines": generation_lines(trace),
        "trace": trace_digest(trace),
    }
    results["steps"][label] = record
    save()
    gen = len(record["generation_lines"])
    log("%s -> %s %.3fs generation_lines=%d" % (label, status, secs, gen))
    return record


# ---------------- main ----------------

def main():
    if not os.path.exists(TOOL):
        raise SystemExit("tool missing: %s" % TOOL)

    model_id = wait_ready()
    log("service ready model=%s" % model_id)

    exe = "/Applications/SimiGo.app/Contents/MacOS/SimiGo"
    results["identity"] = {
        "model_id": model_id,
        "installed_exe_sha256": subprocess.run(
            ["shasum", "-a", "256", exe], capture_output=True, text=True
        ).stdout.split()[0],
        "installed_exe_mtime": time.strftime(
            "%Y-%m-%d %H:%M:%S", time.localtime(os.stat(exe).st_mtime)),
        "app_pid": subprocess.run(
            ["pgrep", "-f", exe], capture_output=True, text=True
        ).stdout.split(),
        "head": subprocess.run(
            ["git", "-C", REPO, "rev-parse", "HEAD"],
            capture_output=True, text=True).stdout.strip(),
        "diff_sha256": subprocess.run(
            ["bash", "-lc", "git -C %s diff | shasum -a 256" % REPO],
            capture_output=True, text=True).stdout.strip(),
        "trace_size": trace_offset(),
    }
    is_status, is_body = get("/v1/simigo/is/status")
    results["identity"]["is_status_http"] = is_status
    results["identity"]["is_status"] = is_body
    save()

    # ---- 1. real-model source settlement ----
    start_stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(STARTED - 5))
    source_prompt = "只输出这一行，不要解释：B7-SETTLED-%s" % NONCE
    source = window(
        "source-chat-generation",
        {
            "model": model_id,
            "session_id": "b7-source-%s" % NONCE,
            "max_tokens": 96,
            "messages": [
                {"role": "system",
                 "content": "你是精确的标记输出器，只输出用户要求的那一行。"},
                {"role": "user", "content": source_prompt},
            ],
        },
        path="/v1/chat/completions")
    if source["status"] != 200:
        raise SystemExit("SOURCE_GENERATION_FAILED: %r" % source["body"])
    choices = source["body"].get("choices") or []
    source_text = ((choices[0].get("message") or {}).get("content") or "") \
        if choices else ""
    time.sleep(2.0)
    row = db_one(
        "SELECT settlement_id, state_id, settled_at FROM settlements "
        "WHERE state_id IN (SELECT state_id FROM execution_states "
        "  WHERE state_id LIKE 'chat-%' AND substr(created_at,1,19) >= ?) "
        "ORDER BY settled_at DESC LIMIT 1;", (start_stamp,))
    if not row:
        raise SystemExit("NO_SOURCE_SETTLEMENT after chat generation")
    source_id = row["settlement_id"]
    source_state = row["state_id"]
    inspected = tool("status", source_id)
    value = inspected["content"]
    results["source"] = {
        "settlement_id": source_id,
        "state_id": source_state,
        "settled_at": row["settled_at"],
        "generated_text": source_text,
        "settled_value": value,
        "payload_digest_ok": inspected["payload_digest_ok"],
        "payload_digest": inspected["payload_digest"],
        "bindings": inspected["bindings"],
        "usage": source["body"].get("usage"),
        "marker_matched": value.strip() == ("B7-SETTLED-%s" % NONCE),
    }
    if not value.strip() or not inspected["payload_digest_ok"]:
        raise SystemExit("SOURCE_SETTLEMENT_UNUSABLE: %r" % results["source"])
    log("source settlement %s value=%r" % (source_id, value))
    save()

    # ---- 2. declare the reuse contract (native API) ----
    query = "b7 exact repeat %s" % NONCE
    demand = tool("demand", query, ROOT_ID)
    declaration = tool("declare", source_id, query, ROOT_ID)
    stored = tool("contract", source_id)
    if declaration["canonical_digest"] != demand["digest"]:
        raise SystemExit("DECLARATION_DIGEST_MISMATCH: %r vs %r"
                         % (declaration, demand))
    results["contract"] = {
        "query": query,
        "root_id": ROOT_ID,
        "canonical_entries": demand["entries"],
        "canonical": demand["canonical"],
        "canonical_digest": demand["digest"],
        "declaration": declaration,
        "stored": stored,
    }
    log("contract declared digest=%s" % demand["digest"][:16])
    save()

    # ---- 3. isolated consumption window ----
    before = two_dirs()
    results["directories"] = {"before": before}
    moved = move_aside()
    results["directories"]["moved_aside"] = moved
    absent = two_dirs()
    results["directories"]["during"] = absent
    if moved and (absent["prefix_pool"]["present"]
                  or absent["branch_checkpoints"]["present"]):
        raise SystemExit("ISOLATION_FAILED: directories reappeared before requests")
    save()

    stats_before = tool("stats")
    first = window(
        "consume-positive",
        consumption_body(model_id, source_id, query, [ROOT_ID]))
    second = window(
        "consume-second-request",
        consumption_body(model_id, source_id, query, [ROOT_ID]))
    during_after = two_dirs()
    results["directories"]["after_consumption"] = during_after
    stats_after = tool("stats")
    results["statistics"] = {"before": stats_before, "after": stats_after}

    positive = first["body"].get("settlement_consumption") or {}
    checks = {
        "status_200": first["status"] == 200,
        "model_calls_zero": positive.get("model_calls") == 0,
        "store_false": first["body"].get("store") is False,
        "text_is_settled_value": output_text(first["body"]).strip()
            == value.strip(),
        "no_generation_lines": len(first["generation_lines"]) == 0,
        "no_kv_files_created": (not during_after["prefix_pool"]["present"]
                                and not during_after["branch_checkpoints"]["present"]),
        "second_request_200": second["status"] == 200,
        "second_request_zero_calls":
            (second["body"].get("settlement_consumption") or {}).get("model_calls") == 0,
        "second_request_no_generation":
            len(second["generation_lines"]) == 0,
        "model_output_stats_unchanged":
            stats_before.get("valid_model_output_settlements")
            == stats_after.get("valid_model_output_settlements"),
    }
    results["consumption_checks"] = checks
    log("consumption checks: %s" % json.dumps(checks))
    if not all(checks.values()):
        save()
        raise SystemExit("CONSUMPTION_CHECKS_FAILED")

    consumer_state = positive.get("consumer_es_state_id")
    consumer_settlement = positive.get("consumer_settlement_id")
    results["consumers"] = {"first": positive, "second":
                            second["body"].get("settlement_consumption")}
    save()

    # ---- 4. restore directories, prove unchanged ----
    conflicts = restore(moved)
    results["directories"]["restore_conflicts"] = conflicts
    after_restore = two_dirs()
    results["directories"]["after_restore"] = after_restore
    results["directories"]["restore_identical"] = {
        "prefix_pool": before["prefix_pool"]["listing_sha256"]
            == after_restore["prefix_pool"]["listing_sha256"],
        "branch_checkpoints": before["branch_checkpoints"]["listing_sha256"]
            == after_restore["branch_checkpoints"]["listing_sha256"],
    }
    save()
    log("restored directories identical=%s"
        % results["directories"]["restore_identical"])
    if conflicts:
        save()
        raise SystemExit("ISOLATION_DIRECTORY_RECREATED: %r" % conflicts)

    # ---- 5. refusal matrix (dirs restored; refusals must not generate) ----
    refusal_cases = {
        "refuse-malformed-missing-contract": consumption_body(
            model_id, source_id, query, [ROOT_ID], include=False),
    }
    malformed = {"model": model_id, "input": "consume",
                 "settlement_consumption": {"source_settlement_id": source_id}}
    refusal_cases["refuse-malformed-bad-contract"] = {
        "model": model_id, "input": "consume", "settlement_consumption": {
            "source_settlement_id": source_id, "query": query,
            "contract": dict(CONTRACT, bogus="x")}}
    refusal_cases["refuse-unknown-source"] = consumption_body(
        model_id, "no-such-settlement", query, [ROOT_ID])
    refusal_cases["refuse-identity-mismatch"] = consumption_body(
        model_id, source_id, query, [ROOT_ID],
        identity={"model_identity": "b7-bogus-model",
                  "tokenizer_identity": "b7-bogus-tokenizer"})
    refusal_cases["refuse-changed-query"] = consumption_body(
        model_id, source_id, query + " (changed)", [ROOT_ID])
    refusal_cases["refuse-streaming"] = consumption_body(
        model_id, source_id, query, [ROOT_ID], stream=True)
    del refusal_cases["refuse-malformed-missing-contract"]
    refusal_cases["refuse-malformed-missing-contract"] = malformed

    refusal_checks = {}
    for label, payload in refusal_cases.items():
        rec = window(label, payload)
        expected = 501 if label == "refuse-streaming" else 422
        reason = ((rec["body"].get("error") or {}).get("reason_code")
                  or (rec["body"].get("error") or {}).get("error_kind"))
        refusal_checks[label] = {
            "status": rec["status"],
            "expected_status": expected,
            "reason": reason,
            "no_generation": len(rec["generation_lines"]) == 0,
            "ok": rec["status"] == expected
                and len(rec["generation_lines"]) == 0,
        }
    results["refusal_checks"] = refusal_checks
    save()
    log("refusals: %s" % json.dumps({k: v["ok"] for k, v in refusal_checks.items()}))
    if not all(v["ok"] for v in refusal_checks.values()):
        raise SystemExit("REFUSAL_MATRIX_FAILED")

    # ---- 6. absent field keeps ordinary generation ----
    control = window(
        "absent-field-ordinary-generation",
        {"model": model_id,
         "input": "只输出：B7-CONTROL-%s" % NONCE,
         "max_output_tokens": 64})
    results["absent_field_check"] = {
        "status": control["status"],
        "output": output_text(control["body"]),
        "generation_lines": len(control["generation_lines"]),
        "ok": control["status"] == 200
            and len(control["generation_lines"]) > 0,
    }
    if not results["absent_field_check"]["ok"]:
        raise SystemExit("ABSENT_FIELD_PATH_FAILED")

    # ---- 7. explicit recompute is the only way to change the demand ----
    consumptions_before = db_rows(
        "SELECT COUNT(*) AS n FROM settlement_consumptions;")[0]["n"]
    recompute = window(
        "allow-recompute-changed-query",
        consumption_body(model_id, source_id, query + " (changed)",
                         [ROOT_ID], allow_recompute=True))
    note = recompute["body"].get("settlement_consumption") or {}
    consumptions_after = db_rows(
        "SELECT COUNT(*) AS n FROM settlement_consumptions;")[0]["n"]
    results["recompute_check"] = {
        "status": recompute["status"],
        "outcome": note.get("outcome"),
        "reason": note.get("reason"),
        "generation_lines": len(recompute["generation_lines"]),
        "consumptions_before": consumptions_before,
        "consumptions_after": consumptions_after,
        "ok": recompute["status"] == 200
            and note.get("outcome") == "recompute"
            and bool(note.get("reason"))
            and len(recompute["generation_lines"]) > 0
            and consumptions_before == consumptions_after,
    }
    if not results["recompute_check"]["ok"]:
        raise SystemExit("RECOMPUTE_PATH_FAILED")

    # ---- 8. derived settlement remains a continuation anchor ----
    chain = window(
        "derived-anchor-continuation",
        {"model": model_id,
         "input": "复述上一轮已结算的标记。",
         "max_output_tokens": 64,
         "previous_es_state_id": consumer_state,
         "continuation_settle": True})
    chain_payload = chain["body"].get("continuation_settlement") or {}
    results["chain_check"] = {
        "status": chain["status"],
        "settlement": chain_payload,
        "generation_lines": len(chain["generation_lines"]),
        "ok": chain["status"] == 200
            and bool(chain_payload.get("settlement_id"))
            and len(chain["generation_lines"]) > 0,
    }
    if not results["chain_check"]["ok"]:
        log("chain check failed (recorded): %r" % chain["body"])

    # ---- 9. DB ledger audit ----
    consumptions = db_rows(
        "SELECT consumption_id, source_settlement_id, consumer_state_id, "
        "consumer_settlement_id, demand_id, contract_id, demand_class, "
        "contract_version, canonical_digest, model_calls, created_at "
        "FROM settlement_consumptions WHERE source_settlement_id=? "
        "ORDER BY created_at;", (source_id,))
    derived = db_rows(
        "SELECT settlement_id, state_id, validation_status, validity, "
        "payload_digest FROM settlements WHERE settlement_id=?;",
        (consumer_settlement,))
    derived_bindings = db_rows(
        "SELECT name, value_digest FROM settlement_bindings "
        "WHERE settlement_id=? ORDER BY name;", (consumer_settlement,))
    source_row = db_rows(
        "SELECT settlement_id, validity, validation_status FROM settlements "
        "WHERE settlement_id=?;", (source_id,))
    edges = db_rows(
        "SELECT from_settlement, to_settlement, kind FROM dependency_edges "
        "WHERE from_settlement=?;", (consumer_settlement,))
    demands = db_rows(
        "SELECT demand_id, state_id, session_id, retrieval_settlement_id, "
        "state, query, input_digest FROM information_demands WHERE demand_id=?;",
        (positive.get("demand_id"),))
    advancements = db_rows(
        "SELECT advancement_id, demand_id, state_id, settlement_id, "
        "retrieval_settlement_id, actions_json FROM information_advancements "
        "WHERE demand_id=?;", (positive.get("demand_id"),))
    summaries = db_rows(
        "SELECT * FROM settlement_summaries WHERE settlement_id=?;",
        (consumer_settlement,))
    consumer_state_row = db_rows(
        "SELECT state_id, parent_id, model_identity, position, lifecycle, "
        "anchor, next_input FROM execution_states WHERE state_id=?;",
        (consumer_state,))
    binding_names = [b["name"] for b in derived_bindings]
    results["db_audit"] = {
        "consumptions": consumptions,
        "derived_settlement": derived,
        "derived_bindings": derived_bindings,
        "source": source_row,
        "dependency_edges": edges,
        "information_demands": demands,
        "information_advancements": advancements,
        "summaries": summaries,
        "consumer_state": consumer_state_row,
        "checks": {
            "all_consumptions_zero_calls":
                all(c["model_calls"] == 0 for c in consumptions),
            "derived_row_present": any(
                d["validation_status"] == "DERIVED_CONSUMPTION"
                and d["validity"] == "valid" for d in derived),
            "consumer_bindings_present": (
                "consumer.model_identity" in binding_names
                and "consumer.tokenizer_identity" in binding_names),
            "no_producer_bindings": not any(
                n.startswith("producer.") for n in binding_names),
            "no_kv_bindings": not any(n.startswith("kv.") for n in binding_names),
            "source_still_valid": any(
                s["validity"] == "valid" for s in source_row),
            "dependency_edge_written": any(
                e["kind"] == "settlement-consumption" for e in edges),
            "summary_marks_derivation": any(
                s.get("derivation_type") == "DERIVED_CONSUMPTION"
                or s.get("provenance_settlement_id") == source_id
                for s in summaries),
            "consumer_state_active": any(
                s["lifecycle"] == "active" for s in consumer_state_row),
        },
    }

    # ---- 10. final directory state after the generating steps ----
    after_all = two_dirs()
    results["directories"]["after_all"] = after_all
    results["directories"]["delta_vs_before"] = {
        "prefix_pool": after_all["prefix_pool"]["file_count"]
            - before["prefix_pool"]["file_count"],
        "branch_checkpoints": after_all["branch_checkpoints"]["file_count"]
            - before["branch_checkpoints"]["file_count"],
    }
    results["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    results["ok"] = (
        all(checks.values())
        and all(v["ok"] for v in refusal_checks.values())
        and results["absent_field_check"]["ok"]
        and results["recompute_check"]["ok"]
        and all(results["db_audit"]["checks"].values()))
    path = save()
    log("done ok=%s -> %s" % (results["ok"], path))
    print(json.dumps({
        "ok": results["ok"],
        "source_settlement_id": source_id,
        "settled_value": value,
        "consumer_state": consumer_state,
        "consumer_settlement": consumer_settlement,
        "consumption_checks": checks,
        "refusal_checks": {k: v["ok"] for k, v in refusal_checks.items()},
        "absent_field": results["absent_field_check"]["ok"],
        "recompute": results["recompute_check"]["ok"],
        "chain": results["chain_check"]["ok"],
        "db_audit": results["db_audit"]["checks"],
        "directory_delta": results["directories"]["delta_vs_before"],
        "results_file": path,
    }, ensure_ascii=False, indent=1))
    if not results["ok"]:
        raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 - record unexpected faults
        results["fatal"] = repr(exc)
        save()
        raise
