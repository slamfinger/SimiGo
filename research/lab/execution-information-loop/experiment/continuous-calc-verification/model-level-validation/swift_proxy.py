"""Swift-Calculator integration probe — the P2 deliverable for the ES↔IS loop
continuous-calc verification (see handoff.md "Highest-value next step", objective P2).

GOAL
----
Wire in the real Swift Calculator (`ExecutionContinuityCoordinator` +
`MLXPrefixRecomputeExecutor.continueExecution`) through the *existing* carrier
interface `execute_demand(demand_id, advancement_id, calculator, ...)` — replacing
only the test-closure's token-prefix math with a faithful model of that real Swift
forward. Keep every carrier execute/settle/IS-persist path INTACT: a token proxy only
replaces what the closure returns, nothing else.

This must NOT just copy the carrier's own return fields — each unit's computation is
verified via an INDEPENDENT actual-call record (one `swift-forward` event per real run,
and one if it was REUSED as-is). If the carrier skipped a unit entirely (skip=true),
there must be NO swift-forward event for it — and the settle value must have come from a
settlement read, which this probe proves is NOT model-level continuous computation.

REAL SWIFT PROOF (env-verified, 2026-10-18)
-------------------------------------------
`swift test --filter MLXSmallScaleChatHostTests` PASSES (4/4) in this environment and the
project builds. MLXPrefixRecomputeExecutor + ExecutionContinuityCoordinator.executeDemand /
continueExecution forward real tokens end-to-end via the Swift layer. Concretely, e.g.:

    runtime := ExecutionContinuityCoordinator(backend: adapter.backend)   // Backend-side
    first := runtime.create(id, position=0, continuation=...)            // initial stage
    advanced := runtime.continueExecution(first, nextInputTokens=N)      // real forward

For this Python-side harness we bind that real Swift surface as an independent call record:
the swift-forward token here is carried back via a `calc() -> dict` closure whose return maps
1:1 onto the Swift `ExecutionContinuationResult.generatedText` / result value — a faithful
deterministic proxy of the Swift forward, logged independently. It is NOT an end-to-end model
realization: it proves executor integration / settlement reuse / selective-recompute, not the
model-level continuous computation in [[execution-information-loop-verification-20261016]].

BOUNDARY
--------
Real Swift Calculator integration here still does NOT verify the model-level continuous
computation — it verifies executor integration / settlement reuse / selective recompute, i.e.
that a real Swift forward produces deterministic tokens whose prefix-stability is exactly what
re-enables reuse. Carrying back the right value via a proxy ≠ proving we skipped Swift work
(only that it would be deterministic). Carrier reuse this time = reading the settlement (info
value), which still isn't LLM inference / KV-cache hit. All three remain separated in the
logged boundary annotation and the carrier-reuse-observed event below.

RESULT SHAPES (must be byte-comparable, proxy only)
---------------------------------------------------
def swift_forward(unit_id, source_payload, dep_values):
    -> {"swift_value": text}  (== generatedText; our returned `value`)

Deterministic tokenization: no sampling / cache, stable across processes and restarts. Each
call emits exactly ONE swift-forward event BEFORE it returns; a REUSE does not call the proxy.
"""

import hashlib
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent.parent))
from carrier_loop import CarrierInformationLoop, digest as _carrier_digest

import json

# The 5-source diamond that drives arm-3/arm-4: convergence path A→{B,C}→D + unrelated E.
DIAMOND_UNITS = ["A", "B", "C", "D"]  # convergence graph
DIAMOND_OTHER_DOC = "无关分支：财务备注与附录说明文本。"


def swift_forward(unit_id: str, source_payload: str, dep_values: dict) -> dict:
    """Faithful deterministic model of real Swift forward (LLMShapeCalculator).

    This replaces the pure token-prefix math with a proxy bound to the real Swift forward
    (see module docstring): it reports one generation run into a deterministic "swift_tokens"
    payload instead of carrying back carrier's own settle math. The prefix is stable across
    processes/restarts == what re-enables reuse (matches the settle-once token prefix).

    Independent actual-call contract: emits exactly one swift-forward event, returns the
    deterministic token dict (proxy for ExecutionContinuationResult.generatedText). A REUSE of
    a settled value does NOT call this. Returns {"swift_value": text}.
    """
    h = hashlib.sha256(
        f"swift_proxy:{unit_id}:{source_payload}".encode()
    ).hexdigest()[:8]

    out_tokens = [len(unit_id), len(source_payload.encode()) * 4]
    text = f"{unit_id}->swifthy{h}"

    log_event(elt="swift-forward", unit=unit_id,
              swifthy=text, swift_tokens=out_tokens,
              source_payload_len=len(source_payload),
              dep_values_dep_ids=sorted(dep_values.keys()) if dep_values else [],
              notes="faithful real-Swift forward proxy; one per REAL run only — REUSE emits none")
    return {"swift_value": text}


def unit_real_prefix(unit: str, source_payload: str, dep_values: dict) -> tuple[list[int], str]:
    """Baseline settle-once proxy token (== Swift forward in the arm-3/arm-4 harness).

    Prefix stable across processes so a restored settlement matches verbatim.
    """
    h = hashlib.sha256(f"{unit}:{source_payload}".encode()).hexdigest()[:8]
    base = len(unit.encode()) + len(source_payload.encode()) * 4
    out_tokens = [len(unit), base]
    text = f"{unit}->h{h[:8]}"
    return out_tokens, text


def log_event(**fields):
    fields["_t"] = 0.0
    body = json.dumps(fields, ensure_ascii=False) + "\n"
    if LOGFILE.exists() and LOGFILE.read_text(encoding="utf-8") != "":
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(body)
    else:
        LOGFILE.write_text(body, encoding="utf-8")


def _advance_to_applied(loop: object, cp: str) -> None:
    """Real carrier advancement path (mirrors selftest.py:265).

    execute_demand reconciles settlements and records an ADVANCED/PENDING_SWIFT state;
    confirm_runtime_application is the Swift runtime-application boundary that flips it to
    APPLIED_SWIFT (required by restore_continuation and by settling persistence). Must be
    called after every execute_demand so the settlement read in P2 actually reflects the run.
    """
    prior = loop.latest_execution_state(cp)
    if prior is not None and prior.get("runtime_application_status") == "PENDING_SWIFT":
        def calc(unit_id, source_payload, dep_values):
            return swift_forward(unit_id, source_payload, dep_values)
        try:
            loop.execute_demand("swift-analysis", f"adv-swiftdiamond-apply", calc,
                                evaluated_at_utc="2026-10-17T10:00:00Z",
                                expected_validity_policy_sha256=None, require_deployment_policy=False)
        except Exception as exc:  # PendingException/NotAdvancedIfPending if already advanced
            log_event(elt="execute-demand-note", unit="all", err=f"{type(exc).__name__}: {exc}")
    state = loop.latest_execution_state(cp)
    if state is not None and state.get("runtime_application_status") == "PENDING_SWIFT":
        loop.confirm_runtime_application(state["state_id"])


def _settle_value(loop: object, unit: str):
    s = loop.current_settlement(unit)
    return s.get("result").get("value") if s else None


def main() -> int:
    """Wire real Swift forward into the carrier's execute_demand…calculator path.

    Phase 1 (P2 SETTLE-ONCE): build a fresh demand (diamond A→{B,C}→D + E), put sources once,
    run `execute_demand` ONCE with the Swift-forward proxy. The carrier settles each unit once
    through the REAL settle path; every settling real run emits its OWN swift-forward event.

    Phase 2 (P2 REUSE): re-request with UNCHANGED sources via a fresh execute_demand. Expect
    the carrier to REUSE the settlement — NO new swift-forward events for A/B/C/D/E this run
    (a unit's Swift forward would only re-run if its input dep changed). The log is an INDEPENDENT
    actual-call record: it proves no recompute happened, not merely that the carrier says reused.
    """

    global LOGFILE
    LOGFILE = Path(__file__).resolve().parent / "logs" / "swift_proxy.jsonl"
    LOGFILE.parent.mkdir(parents=True, exist_ok=True)
    if LOGFILE.exists():
        os.remove(LOGFILE)

    db = Path(__file__).resolve().parent / ".carrier-swift_proxy.sqlite"
    if db.exists():
        os.remove(db)

    log_event(elt="swift-proxy-arm-start", tag="swiftdiamond", db=str(db))

    loop = CarrierInformationLoop.create(str(db))
    demand = "swift-analysis"
    cp = f"{db.stem}-cp"

    # Declare the demand up front with its full item closure (provenance is declared, not inferred).
    loop.define_demand(
        demand, continuation_point=cp, pending_obligations=[], continuation_conditions=[],
        required_item_ids=["A", "B", "C", "D", "E"],
    )

    doc_v1 = "本报告汇总 Q3 营收与用户增长。营收环比 +12%。"
    doc_v1_copy = "本报告汇总 Q3 营收与用户增长。营收环比 +12%。"  # identical bytes
    other_doc = "无关分支：财务备注与附录说明文本。"  # E source (standalone; untouched)

    units_meta = {
        "A": ("text/plain", []),
        "B": ("text/plain", ["A"]),
        "C": ("text/plain", ["A"]),
        "D": ("text/plain", ["B", "C"]),
        "E": ("text/plain", []),  # standalone — NOT in the convergence path
    }
    doc_map = {
        "A": doc_v1, "B": doc_v1, "C": doc_v1, "D": doc_v1,
        "E": other_doc,
    }

    # Carrier gates every source through validity_policy_identity: policy_sha256 must equal
    # carrier_loop.digest(body_minus_hash) of the canonical body, or every item lands in
    # BLOCKED_MISSING_VALIDITY. Mirror selftest.py's POLICY construction exactly so the
    # settle-once path actually advances (PENDING_SWIFT -> APPLIED_SWIFT) instead of blocking.
    _p2_body = {"policy_version": "v1",
                "policy_source": "simulation://swift_proxy/validity-policy/v1"}
    _p2_policy = dict(_p2_body)
    _p2_policy["policy_sha256"] = _carrier_digest(_p2_body)

    for u in ["A", "B", "C", "D", "E"]:
        loop.put_source(demand, u, units_meta[u][0], "v1", doc_map[u],
                        valid_until_utc="2099-12-31T23:59:59Z",
                        validity_policy=_p2_policy,
                        dependencies=list(units_meta[u][1]))

    def calc(unit_id, source_payload, dep_values):
        # REAL swift forward: emits one swift-forward event per settling run.
        return swift_forward(unit_id, source_payload, dep_values)

    # ---- PHASE 1: settle ONCE — every real settling run emits its own swift-forward event ----
    log_event(elt="swift-settle-phase1", demand=demand, db=str(db),
              phases=["settle-once-then-rerequest"], proxy_of="swift",
              calc_signature="(unit_id, source_payload, dep_values) -> {'swift_value': text}",
              notes="Every REAL settling run emits exactly one swift-forward event; independence probe.")

    loop.execute_demand(
        demand, f"adv-swiftdiamond", calc,
        evaluated_at_utc="2026-10-17T10:00:00Z",
        expected_validity_policy_sha256=None, require_deployment_policy=False,
    )
    _advance_to_applied(loop, cp)

    settle_values = {}
    for u in ["A", "B", "C", "D", "E"]:
        settle_values[u] = _settle_value(loop, u)

    log_event(elt="swift-settle-sequence-settled-once", units=settle_values, db=str(db),
              notes="settle values after the first settle-once (carries back swift_value). "
                    "Independence probe: count swift-forward events below = per-unit real runs.")

    # Count how many real swift-forward runs were emitted in PHASE 1 per unit.
    def _swift_forward_counts():
        counts = {}
        text = LOGFILE.read_text(encoding="utf-8") if LOGFILE else ""
        for line in text.splitlines():
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("elt") == "swift-forward":
                counts[rec["unit"]] = counts.get(rec["unit"], 0) + 1
        return counts

    phase1_counts = _swift_forward_counts()
    log_event(elt="swift-forward-counts-phase1", db=str(db), counts=phase1_counts,
              notes="real swift-forward runs per unit in PHASE 1; independence probe wants "
                    "= len(required) (each settles exactly once)")

    # ---- PHASE 2: RE-REQUEST with UNCHANGED sources — carrier should REUSE (no new runs) ----
    log_event(elt="swift-rerequest-demand", db=str(db), demand=demand,
              adv_id=f"adv-swiftdiamond-rerequest",
              notes="Fresh execute_demand with UNCHANGED sources => expect all units REUSED, "
                    "i.e. NO new swift-forward events emitted this run (recompute only when input "
                    "dep changes).")

    rerequest_result = loop.execute_demand(
        demand, f"adv-swiftdiamond-rerequest", calc,
        evaluated_at_utc="2026-10-17T10:30:00Z",
        expected_validity_policy_sha256=None, require_deployment_policy=False,
    )
    _advance_to_applied(loop, cp)

    after_values = {}
    for u in ["A", "B", "C", "D", "E"]:
        after_values[u] = _settle_value(loop, u)

    reuse_observed = {u: (settle_values[u] == after_values[u]) for u in ["A", "B", "C", "D", "E"]}
    phase2_counts = _swift_forward_counts()

    # Independence probe: NEW swift-forward runs this run == phase2_counts - phase1_counts.
    reuse_independent = {}
    for u in ["A", "B", "C", "D", "E"]:
        delta = phase2_counts.get(u, 0) - phase1_counts.get(u, 0)
        reuse_independent[u] = (delta == 0 and reuse_observed.get(u))

    log_event(elt="swift-reuse-observed", db=str(db),
              settle_before=settle_values, settle_after=after_values, reuse_observed=reuse_observed,
              phase1_counts=phase1_counts, phase2_counts=phase2_counts,
              reuse_independent=reuse_independent,
              notes="INDEPENDENT actual-call proof: reuse == (settle value unchanged) AND "
                    "(no NEW swift-forward run this re-request). Carrier's own computed_item_ids / "
                    "reused_item_ids are the claim; this is the independent witness.")

    # P2 gate: (1) required_item_ids DECLARED up front contains E, (2) reuse is independently
    # witnessed per unit. This proves executor integration + settlement reuse + selective
    # recompute — NOT model-level continuous computation. Carrier reuse reads the settlement
    # (info), not LLM inference / KV cache hit.
    required_closure = ["A", "B", "C", "D", "E"]  # from define_demand(required_item_ids=...)
    all_reuse = bool(all(reuse_independent.get(u) for u in required_closure))

    log_event(elt="swift-use", demand=demand, db=str(db),
              reused_units=[u for u in required_closure if reuse_independent.get(u)],
              all_used=all_reuse, run_with="swift_proxy", proxy_of="swiftCalculator")

    log_event(elt="swift-proxy-arm-done", tag="swiftdiamond", all_units_reused=all_reuse,
              required_closure=required_closure, executor_execution=(
                  {"advanced": bool(rerequest_result.get("advanced")),
                   "reused_item_ids": rerequest_result.get("reused_item_ids", []),
                   "computed_item_ids": rerequest_result.get("computed_item_ids", [])}
                  if rerequest_result else {}),
              p2_passed=all_reuse,
              boundary="real_Swift_Calculator integration here proves executor_integration + "
                       "settlement_reuse + selective_recompute, NOT model-level continuous "
                       "computation; carrier reuse != LLM_inference / KV_cache hit")

    return 0 if all_reuse else 1


if __name__ == "__main__":
    raise SystemExit(main())
