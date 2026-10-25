# P5-2-ER Reviewer-3: Research Integrity Review

日期：2026-10-01  
Role：Research Integrity Reviewer  
审查对象：P5-2 Draft + Reviewer-1 + Reviewer-2  
职责：overclaim / carrier-definition confusion / evidence level / constructibility vs existence

---

## Check 1: Absence of evidence ≠ evidence of absence

```yaml
check: PASS
application: >
  Draft correctly marks Semantic Anchor minimum form as OPEN (OP-P5-3).
  Does NOT claim "history text is unnecessary" from absence of
  counter-example. P5-1 shows full text is sufficient, not that
  shorter forms are insufficient. Correctly defers to P5-3 ablation.
```

## Check 2: Constructible ≠ pre-existing

```yaml
check: PASS (with one flag)
assessment: >
  Draft constructs the closure from observed dependencies. Does NOT
  claim pre-existing natural kinds. However, "Execution State = 
  保证未来计算连续性的最小关系闭包" could be read as discovery
  rather than proposal.
FLAG R3-1: >
  Add to §0: "This ontology is CONSTRUCTED from observed dependency
  relations, not claimed as a pre-existing natural category. Its
  value is measured by predictive and engineering utility."
```

## Check 3: Carrier behavior ≠ Execution State definition

```yaml
check: PASS
assessment: >
  MLX rebuild behavior (P5-1) is correctly used as carrier-level
  evidence ("KV alone insufficient"), not definition-level claim
  ("closure must include X"). Draft says "the current backend
  implementation requires alignment; the minimum anchor form is
  an open empirical question" — correct scoping.
minor_concern: >
  §1.3 Identity components are derived from MLX code. A different
  backend might have different identity requirements. Draft should
  clarify: IDENTITY RELATION (closure member) is backend-independent,
  but its INSTANTIATION (which credentials) is backend-specific.
```

## Check 4: Backend limitation ≠ architecture impossibility

```yaml
check: PASS
assessment: >
  Draft correctly scopes "MLX ChatSession rejects KV-only continuation"
  as current-implementation finding, not architecture impossibility.
  P5-1 INCONCLUSIVE (not FAIL) reflects this. Dependency map correctly
  labeled as MLX-specific. Ontology claims backend-independence —
  this is asserted but not yet proven. Acceptable for draft;
  P5-3/P6 should test.
```

## Check 5: Evidence level audit

```yaml
code-fact:
  items: MLX ledgerBootstrapPending, performLoad guards, reuse conditions
  appropriate: YES — directly verifiable in source

trace-observation:
  items: P5-1 mode=rebuild, cacheEff=0.00, promptTokens=212
  appropriate: YES for root-cause analysis
  CAVEAT R3-4: >
    These are from the OLD (pre-revision) execution. Correct for
    identifying the rebuild root cause, but should be marked as
    "from old execution, not for new result validity."

architecture-inference:
  items: Closure derivation, remove-one-relation argument
  appropriate: YES for draft — must be distinguished from empirical proof

speculative:
  items: Security B1-B4, Palace connection
  appropriate: YES — clearly marked as exploratory

overall: ADEQUATE for draft status
```

## Check 6: Overclaim scan

```yaml
overclaims:
  - location: "§0.1"
    text: "最小关系闭包"
    issue: "最小 asserted without empirical proof"
    fix: "→ 候选最小关系闭包 until P5-3"
    severity: LOW

  - location: "§6"
    text: "闭包检查清单（五问）"
    issue: "Implies exhaustiveness without argument"
    fix: "→ 已识别的五个关系维度"
    severity: LOW

  - location: "Reviewer-1"
    text: "minimal_closure_confirmed: YES"
    issue: "Stronger than conceptual argument warrants"
    fix: "→ PROVISIONALLY YES"
    severity: LOW

significant_overclaims: NONE
```

## Check 7: Carrier-definition confusion scan

```yaml
scanned: P5-2 Draft + Reviewer-1 + Reviewer-2 + RESEARCH_STATE
findings: >
  §1-§5 correctly distinguish relations from MLX implementation.
  Each § bridges to architecture level via Contract 对照.
  P5-1 evidence correctly scoped as backend behavior.
  Dependency map correctly labeled MLX-specific.
confusion_detected: NONE
```

## Reviewer-3 verdict

```yaml
verdict: PASS-WITH-RECOMMENDATIONS

recommendations:
  R3-1: Add "This ontology is CONSTRUCTED, not discovered" to §0
  R3-2: "最小关系闭包" → "候选最小关系闭包" until P5-3
  R3-3: "五问" → "已识别的五个关系维度" (avoid implying exhaustiveness)
  R3-4: Mark P5-1 trace numbers as "from old execution, root-cause only"
  R3-5: Reviewer-1 minimal_closure "YES" → "PROVISIONALLY YES"

integrity_issues: NONE
constructibility_vs_existence: ADEQUATE (flagged R3-1)
evidence_level: ADEQUATE
carrier_definition_separation: MAINTAINED
```
