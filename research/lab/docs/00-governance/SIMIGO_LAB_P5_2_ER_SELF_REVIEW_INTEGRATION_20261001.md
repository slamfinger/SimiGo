# P5-2-ER Self-Review: Final Integration

日期：2026-10-01  
Role：Self-review (integration only, after external-style reviews)  
Input：Reviewer-1 + Reviewer-2 + Reviewer-3

---

## Consolidated verdict

```yaml
P5-2-ER_Result:

  Definition:
    accepted: YES (with revisions R3-1, R3-2)
    revision_notes: >
      Ontology is CONSTRUCTED (not discovered). "最小" → "候选最小"
      until P5-3 provides empirical minimality evidence.

  Minimal_Closure:
    Identity: necessary (code-fact + architecture argument)
    Position: necessary (code-fact + P5-1 trace)
    Anchor: necessary (code-fact + P5-1 trace; minimum form OPEN)
    Continuation: in-state (Contract SC-2; acceptance rule = R-level)
    minimality: PROVISIONALLY YES (conceptual argument; P5-3 required)
    carrier_status: NOT a closure member (confirmed by all reviewers)

  Security:
    capability_level: EXECUTION-LEVEL
    risk_boundary: >
      Complete closure (State + identity + anchor + continuation)
      on compatible backend = computation resumption capability.
      meta.json is highest-value security target (plaintext
      conversation + identity credentials).
    revocation_feasible: NO (requires cryptographic binding design)
    delegation_semantics: context YES / authority NO / assumptions PARTIAL
    open_questions:
      - KV tensor inversion attacks (can content be reconstructed?)
      - Minimum identity binding for unauthorized-continuation prevention
      - Context sanitization feasibility for cross-user delegation
      - Cryptographic revocation design for checkpoint format

  Verdict: PASS-WITH-REVISIONS
```

## Required revisions (before registration)

```text
R3-1  §0 add: "This ontology is CONSTRUCTED, not discovered."
R3-2  §0.1 "最小关系闭包" → "候选最小关系闭包"
R3-3  §6 "五问" → "已识别的五个关系维度"
R3-4  P5-1 trace numbers → mark "from old execution, root-cause only"
R3-5  Reviewer-1 minimal_closure → "PROVISIONALLY YES"
R1-Q1 §1.3 clarify: Identity relation backend-independent, 
      instantiation backend-specific
R1-Q2 §3.5 mark OP-P5-3 as P5-3 axis A input
R2-C1 Add "meta.json is sensitive" to security conditions
```

## Open points (updated ledger)

| # | 问题 | 来源 | 状态 | 归属 |
|---|---|---|---|---|
| OP-P5-1 | checkpointGeneration identity地位 | §1.5 | OPEN | P6 synthesis |
| OP-P5-2 | cachedTokens D/R分类 | §2.5 | OPEN（倾向R） | P5-3 ablation |
| OP-P5-3 | Semantic Anchor最小形式 | §3.5 | OPEN | P5-3 axis A |
| OP-P5-4 | acceptance rule层归属 | §4.5 | OPEN | P6 synthesis |
| OP-P5-5 | backward anchor D地位 | §3.4 | OPEN | P6 synthesis |
| OP-P5-6 | KV inversion attack risk | Reviewer-2 B2 | NEW | Security design |
| OP-P5-7 | revocation mechanism design | Reviewer-2 B4 | NEW | P6 / production |
| OP-P5-8 | cross-user delegation protocol | Reviewer-2 B3 | NEW | P6 / production |

## Integration self-check

```yaml
carrier_definition_confusion: NONE (confirmed across all three reviewers)
overclaim_significance: NONE (5 LOW-severity items, all addressed by revisions)
evidence_integrity: ADEQUATE (old-execution caveat added via R3-4)
backend_vs_architecture_separation: MAINTAINED
constructibility_distinction: FLAGGED and addressed (R3-1)
security_boundary_adequacy: >
  ADEQUATE for research context. Four open security questions
  registered for production design (OP-P5-6..8 + identity binding).
palace_mapping_readiness: >
  CONDITIONAL — Palace mapping may proceed after revisions are applied,
  using "候选最小闭包" language. Palace must not assume the closure
  is proven minimal.
```

## Final integration verdict

```text
P5-2-ER = PASS-WITH-REVISIONS

8 revisions required (R3-1..R3-5, R1-Q1..Q2, R2-C1)
All revisions are language/hedging changes, no structural rework.
Upon applying revisions → P5-2 Dependency Closure = REGISTERED (provisional)

Palace Mapping may proceed in parallel with P5-3 ablation design,
using provisional closure language and without assuming minimality.

Security boundary conditions carried forward:
  - meta.json = sensitive
  - revocation = required design (pre-production)
  - delegation consent = required protocol (pre-production)
  - KV inversion = open research question
```
