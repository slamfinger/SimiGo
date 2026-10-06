# CCVS-01 P8 — Crash / Recovery Controlled Validation Record (Baseline A)

Date: 2026-10-06
Status: `P8 COMPLETE / G2 PASS (R6 SCOPE)` 
Frozen protocol: `CCVS-01-PB v1.2`
Crash model: process-level SIGKILL only (R6). Raw artifacts:
`/Users/mr.simi/Documents/CCVS01-Bench/P8/crash-report.json`
Runner: `trackD-memory/Sources/CarrierSQLiteCrash` (modes: prep-inject / verify / suite)

## G2 verdict

```text
G2 = PASS
Counts: PASS 5, REPAIR 1, DETACHED 2, N/A 1, FAIL 0
Scope: "Baseline A process-crash recovery contract passes within the tested
F1–F9 range." No power-loss durability, universal filesystem crash
consistency, or universal crash-safety claim is made (R6).
```

F4 is an explicit protocol N/A, excluded from failure counting:

```text
F4 status = N/A
reason = no independent archival boundary exists in Baseline A; MOVE is one
SQLite transaction covering locator retirement and new locator assignment.
N/A ≠ PASS; N/A ≠ FAIL.
```

## Per-point verdicts

### F1 — PASS

```text
pre_crash_expected : A1 create order: revision row committed first, then entity durable, then representation row; F1 crash leaves revision visible + representation row absent + orphan entity file explicitly visible
post_restart_observed : revisionRow=true representationRows=0 orphans=1
integrity : ISSUES | orphanRepresentation: entity file d754ab9e3fab2f5adeaa140eaf7d861c7c54ffa6d4965d515ec0de5b2f7cf1e2 is not referenced by the registry
repair_action : null (none performed / none applicable)
orphan_evidence : entity file d754ab9e3fab2f5adeaa140eaf7d861c7c54ffa6d4965d515ec0de5b2f7cf1e2 is not referenced by the registry
killed_by_sigkill : True
final_integrity : ISSUES
```
### F2 — PASS

```text
pre_crash_expected : registry complete; derived index missing the new document
post_restart_observed : crashDocIndexed=false baseDocsIndexed=20
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : none
killed_by_sigkill : True
final_integrity : CLEAN
```
### F3 — PASS

```text
pre_crash_expected : open locator transaction rolls back; move invisible
post_restart_observed : movedVisible=false historyCount=1
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : none
killed_by_sigkill : True
final_integrity : CLEAN
```
### F4 — N/A

```text
pre_crash_expected : N/A: no independent archival boundary exists in Baseline A; MOVE is one SQLite transaction covering locator retirement and new locator assignment
post_restart_observed : boundary does not exist in this topology
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : none
killed_by_sigkill : False
final_integrity : CLEAN
```
### F5 — PASS

```text
pre_crash_expected : committed prefix (5 or 6 of 10) visible; batch remainder absent
post_restart_observed : committedRelations=4
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : none
killed_by_sigkill : True
final_integrity : CLEAN
```
### F6 — PASS

```text
pre_crash_expected : committed ordered prefix with no gaps
post_restart_observed : sequences=[0, 1]
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : none
killed_by_sigkill : True
final_integrity : CLEAN
```
### F7 — REPAIR

```text
pre_crash_expected : authority intact; partial derived index discarded/rebuilt from registry authority
post_restart_observed : authorityDocs=20 postRepairHits=20
integrity : CLEAN
repair_action : re-run index rebuild from registry authority; identity coverage re-verified (diagnostic: FTS full-text content is not reconstructable from authority; searchable text provenance lives only in the derived index)
orphan_evidence : none
killed_by_sigkill : True
final_integrity : CLEAN
```
### F8 — DETACHED

```text
pre_crash_expected : partial backup exists, explicitly not adoptable (no completion marker)
post_restart_observed : completionMarker=false
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : partial backup dir without BACKUP_COMPLETE
killed_by_sigkill : True
final_integrity : CLEAN
```
### F9 — DETACHED

```text
pre_crash_expected : incomplete restore stays explicitly unavailable; completed restore must be integrity-clean
post_restart_observed : completionMarker=false restoredIntegrityClean=false
integrity : CLEAN
repair_action : null (none performed / none applicable)
orphan_evidence : none
killed_by_sigkill : True
final_integrity : CLEAN
```

## Findings beyond the verdicts

```text
F1 exposes A1's real create order: revision row commits BEFORE the entity and
representation rows — a crash there leaves a revision visible without its
representation, explicitly flagged by the integrity reporter (orphan scan).
This boundary is now measured, not assumed.
F7 honest limitation: FTS full-text content lives only in the derived index;
rebuild-from-authority restores identity coverage (registry rows → index), not
the original searchable text. Searchable-text provenance beyond authority is a
recorded A1 architectural property, to be weighed in candidate comparison
under the same correctness contract.
F8/F9 completion markers prevent partial backup/restore adoption (DETACHED);
the same infrastructure provides the G8 smoke evidence, with G2/G8 judgment
semantics kept separate.
```

## Instrumentation defects found and fixed during P8 (pre-evidence)

```text
I-1 CrashGate originally read ProcessInfo.environment (cached at process
    start); injection env set post-launch was invisible. Fixed to getenv().
I-2 VACUUM INTO ran inside the managed transaction (SQLite rejects); added an
    outside-transaction execution path.
I-3 Trap-arm ordering: the gate was armed before deterministic seeding, so
    early points crashed during fixture setup. Arm moved after seeding.
I-4 F5/F6 batch traps use sequence-qualified names (F5-5 / F6-3) matched
    against armed env values.
All four are test-instrumentation corrections, not protocol changes.
