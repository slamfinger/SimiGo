# R-C1 Attempt #4 — Evidence / Result Audit

Date: 2026-10-03  
Status: `AUDIT PASS / RESEARCH OBSERVATIONS TRACEABLE`  
Run root:
`docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375`  
Machine audit artifact:
`evidence-result-audit.json`

## 1. Identity / authorization / baseline

```text
Run ID = RC1-A4-20261003T040749Z-57375
Implementation baseline = 569fe540d1ff
Authorization = Attempt #4 explicit human authorization
Implementation change during run = NONE
Protocol change during run = NONE
```

## 2. Lifecycle / process audit

```text
All old commands = old
All fresh commands = continue
All old/fresh PIDs distinct
All old termination markers present
All fresh start markers present
Old/fresh evidence files preserved separately
```

## 3. Physical-change audit

```text
All arms recorded external overwrite.
Before SHA-256 = 3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44
After  SHA-256 = cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a
Per-arm overwrite references = RC1-A4-C-A/B/C-EXTERNAL-001
```

## 4. Carrier audit

```text
C-A: information.sqlite absent; relation.json absent
C-B: information.sqlite present; relation.json absent
C-C: information.sqlite present; relation.json present
C-C relation direction:
  subject  = I-S1
  predicate = observed-change-of
  object   = I-S0
```

## 5. Protocol / evaluator audit

```text
C-A = X-1 PASS; X-2…X-5 FAIL; PARTIAL SUCCESS
C-B = X-1…X-5 PASS; FULL SUCCESS
C-C = X-1…X-5 PASS; FULL SUCCESS
Runtime forbidden-channel checks = ALL PASSED
Source legality = TRUE for all arms
```

Machine audit checks = all true.

## 6. Nonblocking observation

`invocation-evidence.jsonl` contains one pretty-printed JSON object despite the
`.jsonl` suffix. It parses successfully, remains preserved, and does not affect
the conclusion. This is recorded only as an evidence-format note; no runtime
repair was made.

## 7. Audit conclusion

Every sentence in the research interpretation record maps to preserved run
evidence. O1 is supported only as task-domain-bounded. O2 is recorded as
`NOT OBSERVED`, not as Relation being unnecessary.

```text
R-C1 #4 = CLOSED / VALID / EVIDENCE PRESERVED / OBSERVATIONS SEALED
```
