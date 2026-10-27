#!/usr/bin/env python3
"""Stage 3 / K2: real generation -> idle suspend with both KV carriers blocked ->
process terminate & restart -> recover the settled result through ES/IS.

  --phase a   running process: settle a real turn, declare its reuse contract,
              block both KV carriers, watch the idle-suspend path. Leaves the
              block in place.
  --phase b   after the user quits and relaunches the app: re-verify the block,
              then read the settled value back through the product IS surface,
              consume it with zero model work, and continue the same session
              (must cold-start from the logical anchor, not from persisted KV).
  --unblock   restore the moved cache directory (never by deletion).
"""
import argparse, json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stage3_common as C

TAG = "K2"
STATE = "state-K2.json"


def ensure_block(tag, res):
    """The block must be verifiably enforced for every reading window."""
    ok, probes = C.block_enforced()
    res["block_check"] = {"enforced_before_repair": ok, "probe": probes,
                          "cache": C.cache_root_state()}
    if ok:
        return res["block_check"]
    C.log(tag, "block NOT enforced; repairing (product recreated the cache root?)")
    if os.path.isdir(C.CACHE):
        dest = os.path.join(C.R, "isolation-cache",
                            "repair-" + time.strftime("%H%M%S"))
        os.makedirs(dest)
        moved = os.path.join(dest, "cache")
        shutil_move(C.CACHE, moved)
        with open(C.CACHE, "w") as f:
            f.write(C.BLOCK_MARKER)
    else:
        raise SystemExit("CANNOT_REPAIR_BLOCK: cache kind=%s" % C.kind_of(C.CACHE))
    ok, probes = C.block_enforced()
    res["block_check"]["enforced_after_repair"] = ok
    res["block_check"]["repair_probe"] = probes
    if not ok:
        raise SystemExit("BLOCK_STILL_NOT_ENFORCED: %r" % probes)
    with open(C.BLOCK_STATE) as f:
        state = json.load(f)
    state["repaired_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    state["repaired_marker_sha256"] = C.cache_root_state()["sha256"]
    with open(C.BLOCK_STATE, "w") as f:
        json.dump(state, f, indent=1)
    return res["block_check"]


def shutil_move(src, dst):
    import shutil
    if os.path.exists(dst):
        raise SystemExit("MOVE_DEST_EXISTS: %s" % dst)
    shutil.move(src, dst)


def phase_a():
    nonce = time.strftime("%Y%m%d-%H%M%S")
    res = C.new_results("K2a", nonce)
    app = C.app_state()
    res["app_state_before"] = app
    model_id = C.wait_ready()
    res["model_id"] = model_id
    res["counters_before"] = C.db_counters()
    res["cache_before"] = C.cache_root_state()
    res["real_home_before"] = C.real_home_state()
    C.log(TAG, "phase a pid=%s model=%s cache=%s"
          % (app["pids"], model_id, res["cache_before"]["kind"]))

    source = C.settle_source(res, TAG, model_id, nonce, "k2")
    res["source"] = source
    res["contract"] = C.declare_contract(TAG, source["settlement_id"],
                                         "k2 exact repeat %s" % nonce)
    C.save(res)

    res["block"] = C.block_kv(TAG)
    off = C.trace_offset()
    samples, suspend = [], None
    for i in range(48):
        time.sleep(10)
        trace = C.trace_since(off)
        ok, probes = C.block_enforced()
        life = [ln for ln in C.kv_lines(trace)
                if "[LIFECYCLE]" in ln or "[MEM]" in ln or "cacheSave" in ln
                or "checkpoint" in ln]
        st = C.cache_root_state()
        samples.append({"t": time.strftime("%H:%M:%S"), "block_enforced": ok,
                        "prefix_pool_present":
                            st["children"]["prefix-pool"]["present"],
                        "branch_checkpoints_present":
                            st["children"]["branch-checkpoints"]["present"],
                        "lifecycle_lines": life[-8:]})
        if any("suspend_done" in ln for ln in life):
            suspend = samples[-1]
            C.log(TAG, "idle suspend observed at %s" % samples[-1]["t"])
            break
        if not ok:
            suspend = {"block_lost": samples[-1]}
            C.log(TAG, "block lost at %s" % samples[-1]["t"])
            break
        if i % 6 == 0:
            C.log(TAG, "waiting for idle suspend: %ds enforced=%s"
                  % ((i + 1) * 10, ok))
    res["suspend_samples"] = samples
    res["suspend_seen"] = suspend
    res["trace_since_block"] = C.trace_since(off)
    res["counters_after_watch"] = C.db_counters()
    res["cache_after_phase_a"] = C.cache_root_state()
    C.save(res)
    with open(os.path.join(C.R, "k2a-trace-%s.txt" % nonce), "w") as f:
        f.write(res["trace_since_block"])
    C.write_state(STATE, {"nonce": nonce, "source": source,
                          "contract": res["contract"], "block": res["block"],
                          "phase_a_pids": app["pids"],
                          "suspend_seen": bool(suspend),
                          "phase_a_results": "results-K2a-%s.json" % nonce})
    C.log(TAG, "phase a done suspend_seen=%s block left in place" % bool(suspend))


def phase_b():
    state = C.read_state(STATE)
    nonce, source = state["nonce"], state["source"]
    res = C.new_results("K2b", nonce)
    res["carried"] = state
    app = C.app_state()
    res["app_state_after_restart"] = app
    model_id = C.wait_ready()
    res["model_id"] = model_id
    res["block_check"] = ensure_block(TAG, res)
    res["counters_before"] = C.db_counters()
    res["settlements_before"] = C.settlement_rows()
    res["real_home_before"] = C.real_home_state()
    res["cache_before"] = C.cache_root_state()
    C.save(res)
    C.log(TAG, "phase b pid=%s (phase a pid=%s) block enforced=%s"
          % (app["pids"], state.get("phase_a_pids"),
             res["block_check"].get("enforced_after_repair", True)))

    # 1. product IS surface: settled value read back from the store
    off = C.trace_offset()
    st, receipt = C.get("/v1/simigo/is/settlement?id=%s" % source["settlement_id"])
    trace = C.trace_since(off)
    res["is_settlement_read"] = {"status": st, "body": receipt,
                                 "generation_lines": C.generation_lines(trace),
                                 "kv_lines": C.kv_lines(trace), "trace_raw": trace}
    C.log(TAG, "is/settlement -> %s" % st)
    C.save(res)

    # 2. typed consumption: settled value with zero model work
    consumed = C.window(res, TAG, "consume-after-restart",
                        C.consumption_body(model_id, source["settlement_id"],
                                           state["contract"]["query"],
                                           [state["contract"]["root_id"]]))

    # 3. continuation of the same session (no in-memory session, no persisted KV)
    follow = ("在上一次输出的那一行之后，再输出这一行，不要解释："
              "K2-CONTINUED-%s" % nonce)
    cont = C.window(res, TAG, "continuation-after-restart",
                    {"model": model_id, "session_id": source["session_id"],
                     "max_tokens": 96,
                     "messages": [{"role": "system",
                                   "content": "你是精确的标记输出器，只输出用户要求的那一行。"},
                                  {"role": "user", "content": follow}]},
                    path="/v1/chat/completions")
    time.sleep(2.0)
    before_ids = {r["settlement_id"] for r in res["settlements_before"]}
    new_rows = [r for r in C.settlement_rows()
                if r["settlement_id"] not in before_ids]
    res["new_settlement_rows"] = new_rows
    res["consumption_ledger_rows"] = C.db_rows(
        "SELECT consumption_id, source_settlement_id, consumer_settlement_id, "
        "model_calls, created_at FROM settlement_consumptions ORDER BY created_at;")
    res["kv_probe_at_end"] = C.block_enforced()[1]
    res["cache_at_end"] = C.cache_root_state()
    res["counters_after"] = C.db_counters()
    res["counter_delta"] = {k: res["counters_after"][k] - res["counters_before"][k]
                            for k in res["counters_after"]}
    res["sweep_for_redirected_kv"] = C.sweep_kv_paths()
    res["real_home_after"] = C.real_home_state()

    restore_lines = [ln for ln in cont["trace_raw"].splitlines()
                     if "cacheLoad" in ln or "poolBind" in ln
                     or "estored" in ln or "checkpoint" in ln]
    consumed_body = consumed["body"].get("settlement_consumption") or {}
    is_content = receipt.get("content") or receipt.get("text")
    checks = {
        "process_restarted": app["pids"] != state.get("phase_a_pids"),
        "block_enforced_at_start": "enforced_after_repair" in res["block_check"]
            or res["block_check"].get("enforced_before_repair"),
        "block_enforced_at_end": res["kv_probe_at_end"] and all(
            p["listdir_error"] and p["makedirs_error"] != "WRITE_SUCCEEDED"
            for p in res["kv_probe_at_end"].values()),
        "no_kv_files_created": not res["cache_at_end"]["children"]["prefix-pool"]["present"]
            and not res["cache_at_end"]["children"]["branch-checkpoints"]["present"],
        "no_kv_redirection": not [f for f in res["sweep_for_redirected_kv"]
                                  if f["where"] == "run-tree"],
        "real_home_untouched": res["real_home_before"] == res["real_home_after"],
        "is_read_200": st == 200,
        "is_read_returns_settled_value": is_content is not None and str(
            is_content).strip() == source["settled_value"].strip(),
        "is_read_no_generation": not res["is_settlement_read"]["generation_lines"],
        "consume_200": consumed["status"] == 200,
        "consume_model_calls_zero": consumed_body.get("model_calls") == 0,
        "consume_text_matches": C.output_text(consumed["body"]).strip()
            == source["settled_value"].strip(),
        "consume_no_generation_lines": not consumed["generation_lines"],
        "continuation_200": cont["status"] == 200,
        "continuation_marker_returned": ("K2-CONTINUED-%s" % nonce)
            in C.output_text(cont["body"]),
        "continuation_settled": bool([r for r in new_rows
                                      if r["validation_status"] == "VALID"]),
        "continuation_no_kv_restore_lines": not restore_lines,
        "continuation_probe_saw_generation": bool(cont["generation_lines"]),
    }
    res["restore_lines"] = restore_lines
    res["checks"] = checks
    res["summary"] = {"passed": sum(1 for v in checks.values() if v),
                      "total": len(checks),
                      "failures": [k for k, v in checks.items() if not v]}
    C.save(res)
    C.log(TAG, "phase b checks %d/%d failures=%s"
          % (res["summary"]["passed"], res["summary"]["total"],
             res["summary"]["failures"]))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["a", "b"])
    ap.add_argument("--unblock", action="store_true")
    a = ap.parse_args()
    if a.unblock:
        print(json.dumps(C.unblock_kv(TAG), indent=1)[:1200])
    elif a.phase == "a":
        phase_a()
    elif a.phase == "b":
        phase_b()
    else:
        raise SystemExit("use --phase a|b or --unblock")
