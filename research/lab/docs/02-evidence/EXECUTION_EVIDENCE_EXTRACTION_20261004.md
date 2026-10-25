# EXECUTION_EVIDENCE_EXTRACTION.md

Extraction date: 2026-10-04 Asia/Shanghai  
Extraction root: `/Users/mr.simi/Documents/SimiGo-Lab`  
Report discipline: raw/observed facts only. Inference, architecture interpretation, success judgment, and schema mapping are excluded except where a quoted artifact itself states them.

## 1. Repository State

```text
branch: codex/execution-state-research-20260929
HEAD:   b9b4b791f333d377f27925674e475fe02a228197
status: clean (git status --short produced no lines)
remote: synced to origin/codex/execution-state-research-20260929 at b9b4b79
```

Last 20 commits were inspected. The four commits named by the request are present:

```text
7acd397 fix: harden information runtime decode and refresh total status
d7f1c43 research: pin T5 third continuation task
b5e9eb4 research: invalidate infeasible T5 attempt and pin rev1
b9b4b79 research: record T5 replication pass reading
```

The repository was not modified and no commit was made during extraction.

## 2. Evidence Inventory

Evidence-type rules used here:

```text
RUNTIME       = agent action log, run JSON/JSONL, process marker, captured stdout/stderr
DATABASE      = SQLite row/table persisted by a run
ARTIFACT      = file produced by a run
INPUT         = pinned instruction/template/input
SOURCE_CODE   = code that can explain a record but does not prove execution
COMMIT        = Git commit/commit metadata
RESEARCH_NOTE = governance/result narrative; lower priority than raw artifacts
INTEGRITY     = hash manifest
SESSION_RECORD = recorded session id; not a process trace
```

Relevant persisted evidence directories are:

```text
docs/02-evidence/t4-execution       11 files
docs/02-evidence/t42-execution      12 files
docs/02-evidence/t5-execution       38 files
docs/02-evidence/rb1-execution      34 files
docs/02-evidence/rc1-attempt2       65 files
docs/02-evidence/rc1-attempt3       66 files
docs/02-evidence/rc1-attempt4       73 files
total files in these directories    299
```

RC1 directories are included because they are the only persisted raw traces found for the `CContinuationStudy` / `ExecutionScope` lifecycle. `rb1-execution` is included because it directly exercised `ExecutionScope`.

### 2.1 T4 inventory

| File | Evidence Type | What it contains |
|---|---|---|
| `docs/02-evidence/t4-execution/a-run/ledger.md` | ARTIFACT | A-run procurement ledger output. |
| `docs/02-evidence/t4-execution/a-run/todo.md` | ARTIFACT | A-run pending second phase and identity. |
| `docs/02-evidence/t4-execution/a-run/动作日志.md` | RUNTIME | A-run actions: create ledger, store, record identity, create todo. |
| `docs/02-evidence/t4-execution/a-run/db-a.sqlite` | DATABASE | One information row `9fd1608770a655473b18cddf`. |
| `docs/02-evidence/t4-execution/b-e-run/9fd1608770a655473b18cddf.md` | ARTIFACT | Fetched ledger copy plus appended status update. |
| `docs/02-evidence/t4-execution/b-e-run/合同摘要.md` | ARTIFACT | B-E contract summary. |
| `docs/02-evidence/t4-execution/b-e-run/待办状态登记.md` | ARTIFACT | B-E status registration. |
| `docs/02-evidence/t4-execution/b-e-run/动作日志.md` | RUNTIME | B-E actions with fetch timestamp and output/store sequence. |
| `docs/02-evidence/t4-execution/b-e-run/db-b-e.sqlite` | DATABASE | Four information rows. |
| `docs/02-evidence/t4-execution/b-n-run/动作日志.md` | RUNTIME | B-N fetch not-found, workspace/tool probes, sentinel check, blocker. |
| `docs/02-evidence/t4-execution/b-n-run/db-b-n.sqlite` | DATABASE | One sentinel information row, not the target. |

### 2.2 T4-2 inventory

| File | Evidence Type | What it contains |
|---|---|---|
| `docs/02-evidence/t42-execution/a-run/Release_Plan_REL-56ff.md` | ARTIFACT | A-run release plan. |
| `docs/02-evidence/t42-execution/a-run/待办.md` | ARTIFACT | A-run pending activation and identity. |
| `docs/02-evidence/t42-execution/a-run/动作日志.md` | RUNTIME | A-run create/store/todo actions and store identity. |
| `docs/02-evidence/t42-execution/a-run/db-a.sqlite` | DATABASE | One release-plan row `c0da14aabd3d4d22b14cbb2a`. |
| `docs/02-evidence/t42-execution/b-e-run/todo-fetch.txt` | ARTIFACT | Fetched release-plan content. |
| `docs/02-evidence/t42-execution/b-e-run/production-activation-record.md` | ARTIFACT | B-E activation record. |
| `docs/02-evidence/t42-execution/b-e-run/todo-c0da14aabd3d4d22b14cbb2a-updated.md` | ARTIFACT | B-E COMPLETE todo. |
| `docs/02-evidence/t42-execution/b-e-run/动作日志.md` | RUNTIME | B-E fetch → create → store → update → store sequence. |
| `docs/02-evidence/t42-execution/b-e-run/db-b-e.sqlite` | DATABASE | Three information rows. |
| `docs/02-evidence/t42-execution/b-n-run/动作日志.md` | RUNTIME | B-N fetch not-found and blocker sequence. |
| `docs/02-evidence/t42-execution/b-n-run/阻塞报告.md` | ARTIFACT | B-N blocker report. |
| `docs/02-evidence/t42-execution/b-n-run/db-b-n.sqlite` | DATABASE | Zero information rows. |

### 2.3 T5 inventory

All files under `docs/02-evidence/t5-execution/` were inventoried. Pinning files are INPUT/PRE-REGISTRATION. `A_INSTRUCTION.txt` / `B_INSTRUCTION.txt` are RUN INPUT. `动作日志.md` are RUNTIME. Generated Markdown files are ARTIFACT. `information.sqlite` are DATABASE. `evidence-sha256.txt` are INTEGRITY. `session-ids.txt` are SESSION_RECORD.

```text
pinning/a-instruction.txt                         original pinned A input
pinning/b-instruction-template.txt                original B template
pinning/sha256.txt                                original input hashes
attempt1/a-run/A_INSTRUCTION.txt                  actual A input copy
attempt1/a-run/Workshop_Dependency_Plan.md        A plan artifact
attempt1/a-run/todo.md                            A pending todo artifact
attempt1/a-run/动作日志.md                          A runtime log
attempt1/a-run/information.sqlite                 1 information row
attempt1/b-e-run/B_INSTRUCTION.txt                actual B-E input
attempt1/b-e-run/dependency-plan-fetch.txt        fetched plan artifact
attempt1/b-e-run/动作日志.md                        B-E runtime log
attempt1/b-e-run/information.sqlite               1 information row
attempt1/b-n-run/B_INSTRUCTION.txt                actual B-N input
attempt1/b-n-run/BLOCKER_REPORT.md                blocker artifact
attempt1/b-n-run/动作日志.md                        B-N runtime log
attempt1/b-n-run/information.sqlite               0 information rows
attempt1/evidence-sha256.txt                      evidence hash list
attempt1/session-ids.txt                          A/B-E/B-N session ids
pinning/a-instruction-rev1.txt                    rev.1 A input
pinning/b-instruction-template-rev1.txt           rev.1 B template
pinning/sha256-rev1.txt                           rev.1 input hashes
rev1/a-run/A_INSTRUCTION.txt                      actual rev.1 A input
rev1/a-run/Workshop_Dependency_Plan.md            rev.1 plan artifact
rev1/a-run/todo.md                                rev.1 pending todo
rev1/a-run/动作日志.md                              rev.1 A runtime log
rev1/a-run/information.sqlite                     1 information row
rev1/b-e-run/B_INSTRUCTION.txt                    actual rev.1 B-E input
rev1/b-e-run/dependency-plan-fetch.txt            fetched plan artifact
rev1/b-e-run/Workshop_Final_Schedule.md           rev.1 schedule artifact
rev1/b-e-run/todo-updated.md                      rev.1 COMPLETE todo
rev1/b-e-run/动作日志.md                            rev.1 B-E runtime log
rev1/b-e-run/information.sqlite                   3 information rows
rev1/b-n-run/B_INSTRUCTION.txt                    actual rev.1 B-N input
rev1/b-n-run/Blocker_Report.md                    blocker artifact
rev1/b-n-run/动作日志.md                            rev.1 B-N runtime log
rev1/b-n-run/information.sqlite                   1 blocker information row
rev1/evidence-sha256.txt                          evidence hash list
rev1/session-ids.txt                              A/B-E/B-N session ids
```

### 2.4 ExecutionCore / ExecutionScope inventories

Raw ExecutionScope evidence is in:

```text
docs/02-evidence/rb1-execution
docs/02-evidence/rc1-attempt2
docs/02-evidence/rc1-attempt3
docs/02-evidence/rc1-attempt4
```

Raw `ExecutionScope` run records include `e-run.json`, `x-run.json`, `v-e-run.json`, `v-n-run.json`, `experimental.sqlite`, `negative.sqlite`, RC1 `arm-summary.json`, `evaluation.json`, `continuation-evidence.json`, `invocation-evidence.jsonl`, lifecycle markers, checkpoint staging JSON, and workspace DB/relation files.

Governance narratives inspected but treated only as RESEARCH_NOTE:

```text
docs/00-governance/SIMIGO_LAB_T4_EXECUTION_RESULTS_20261002.md
docs/00-governance/SIMIGO_LAB_T4_RULING_20261003.md
docs/00-governance/SIMIGO_LAB_T42_EXECUTION_RESULTS_20261003.md
docs/00-governance/SIMIGO_LAB_T42_REPLICATION_DECLARATION_20261003.md
docs/00-governance/SIMIGO_LAB_T5_ATTEMPT1_RESULT_20261003.md
docs/00-governance/SIMIGO_LAB_T5_REV1_EXECUTION_RESULTS_20261003.md
docs/02-evidence/rb1-execution/RESULTS_20261003.md
docs/02-evidence/rb1-execution/AUDIT_20261003.md
docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/attempt4-summary.json
```

## 3. T4 Raw Execution Evidence

### 3.1 T4 A-run

```text
Run:                       T4 A-run
Experiment:                T4 procurement-ledger setup phase
Commit:                    evidence archived by a0d0195
Timestamp:                 DB produced_at = 2026-10-02T16:15:38Z
Input:                     docs/02-evidence/t4-execution/a-run/ledger.md lines 1-9
Information created:       DB row existed at extraction; separate create-event trace NONE FOUND
Information stored:        DB row identity=9fd1608770a655473b18cddf; source=ledger.md; produced_by=t4ctl
Information fetched:       NONE FOUND in A-run raw artifacts
Execution started:         RUNTIME log says ledger was created; explicit process-start marker NONE FOUND
Execution operations:      动作日志.md lines 1-4: create ledger; store; store complete with identity; register todo
Execution output:          ledger.md lines 1-9 and todo.md lines 1-4
Continuation:              A-run itself ended at pending todo; no second-phase action in A-run
Artifacts:                 ledger.md, todo.md, db-a.sqlite, 动作日志.md
Errors:                    NONE FOUND
Not found:                 NONE FOUND
Source evidence:           a-run/动作日志.md:1-4; a-run/ledger.md:1-9; a-run/todo.md:1-4; db-a.sqlite.information row 1
```

Database record:

```text
file:      docs/02-evidence/t4-execution/a-run/db-a.sqlite
table:     information
record:    identity=9fd1608770a655473b18cddf
fields:    produced_at=2026-10-02T16:15:38Z; produced_by=t4ctl; source=ledger.md; content_length=170
content:   three suppliers SUP-9b47/SUP-93dc/SUP-c1fa, total 2195906.84
sha256:    3bf0553f0cd2bd386a83ccc07f8a8f532ddd645cc6a06c69ebeb6cbc8cfc7c83
```

### 3.2 T4 B-E-run

```text
Run:                       T4 B-E-run
Experiment:                T4 information-enabled continuation arm
Commit:                    evidence archived by a0d0195
Timestamp:                 action log fetch = 2026-10-03T00:17:24+0800; DB later rows = 2026-10-02T16:18:15Z and 16:18:44Z
Input:                     fetched artifact `9fd1608770a655473b18cddf.md`; B prompt itself NONE FOUND in this directory
Information created:       separate create-event trace NONE FOUND
Information stored:        rows f4fa3ab1f0aff78b8a2f8afc, 32390793ba4f0098a9bc2e18, 8e4eac7eef6389d32dc3c8e1
Information fetched:       target 9fd1608770a655473b18cddf; action log says fetched; fetched artifact exists
Execution started:         action log line 1 records entering workdir and fetching; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-10: enter/fetch, read fetched file, check tool help, generate summary, create status, register status, update fetched copy, verify
Execution output:          合同摘要.md lines 1-14; 待办状态登记.md lines 1-6; updated ledger copy lines 1-15
Continuation:              OBSERVED SEQUENCE ONLY: fresh B-run fetched A identity then produced second-phase output. Same-process resume: NO EVIDENCE.
Artifacts:                 fetched ledger copy, contract summary, status registration, action log, DB
Errors:                    action log lines 8-10 record a transient verification mismatch, then self-correction
Not found:                 NONE FOUND
Source evidence:           b-e-run/动作日志.md:1-10; 合同摘要.md:1-14; DB rows 1-4
```

### 3.3 T4 B-N-run

```text
Run:                       T4 B-N-run
Experiment:                T4 empty-boundary negative arm
Commit:                    evidence archived by a0d0195
Timestamp:                 first fetch log = 2026-10-03 00:20:48 CST; blocker log = 00:24:09 CST; sentinel DB row = 2026-10-02T16:23:06Z
Input:                     target identity 9fd1608770a655473b18cddf in action log; B prompt itself NONE FOUND in this directory
Information created:       sentinel row existed; no target plan/summary row
Information stored:        sentinel identity=91576421759960b8a6f28fcd; source=sentinel.txt; content_length=12
Information fetched:       target 9fd1608770a655473b18cddf returned not-found; sentinel 91576421759960b8a6f28fcd fetched for tool-path check
Execution started:         action log begins with fetch; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-10: fetch target, not-found, inspect workdir/help/binary/symbols, write/fetch sentinel, blocker
Execution output:          blocker narrative only; no contract summary artifact in directory
Continuation:              NOT OBSERVED as completed continuation; observed blocker/no-equivalent-output sequence
Artifacts:                 动作日志.md, db-b-n.sqlite
Errors:                    no crash/error file; blocker explicitly recorded
Not found:                 target identity 9fd1608770a655473b18cddf
Source evidence:           b-n-run/动作日志.md:1-10; db-b-n.sqlite.information row 1
```

## 4. T4-2 Raw Execution Evidence

### 4.1 T4-2 A-run

```text
Run:                       T4-2 A-run
Experiment:                system release plan setup phase
Commit:                    evidence archived by d9e7020
Timestamp:                 DB produced_at = 2026-10-02T17:04:32Z
Input:                     Release plan input text itself NONE FOUND as actual run input; pinned facts appear in generated plan and RESEARCH_NOTE
Information created:       separate create-event trace NONE FOUND
Information stored:        identity=c0da14aabd3d4d22b14cbb2a; source=Release_Plan_REL-56ff.md; produced_by=t4ctl
Information fetched:       NONE FOUND
Execution started:         action log line 1 says entered workdir/listed contents; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-5: enter/list, create plan, store, capture identity, create todo
Execution output:          Release_Plan_REL-56ff.md lines 1-22; 待办.md lines 1-5
Continuation:              A-run ended at pending activation; no activation action in A-run
Artifacts:                 release plan, todo, action log, DB
Errors:                    NONE FOUND
Not found:                 NONE FOUND
Source evidence:           a-run/Release_Plan_REL-56ff.md:1-22; a-run/动作日志.md:1-5; DB row 1
```

### 4.2 T4-2 B-E-run

```text
Run:                       T4-2 B-E-run
Experiment:                information-enabled production activation arm
Commit:                    evidence archived by d9e7020
Timestamp:                 local action log fetch=01:06:30, record=01:07:02, stores=01:07:10 and 01:07:31; DB produced_at values 2026-10-02T17:07:10Z and 17:07:31Z
Input:                     identity c0da14aabd3d4d22b14cbb2a; actual B prompt text itself NONE FOUND in this directory
Information created:       separate create-event trace NONE FOUND
Information stored:        identities 1cf28bdab8ff7a0921898626 and c37a78761e9de8adef16ae9a
Information fetched:       c0da14aabd3d4d22b14cbb2a; artifact todo-fetch.txt exists
Execution started:         action log line 1 records workspace listing; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-7: list, fetch, generate activation record, store, update todo, store, complete
Execution output:          production-activation-record.md lines 1-28; updated todo lines 1-9
Continuation:              OBSERVED SEQUENCE ONLY: B fetched A identity then completed activation. Same-process resume: NO EVIDENCE.
Artifacts:                 fetched plan, activation record, updated todo, action log, DB
Errors:                    NONE FOUND
Not found:                 NONE FOUND
Source evidence:           b-e-run/动作日志.md:1-7; production-activation-record.md:1-28; DB rows 1-3
```

### 4.3 T4-2 B-N-run

```text
Run:                       T4-2 B-N-run
Experiment:                empty-boundary negative arm
Commit:                    evidence archived by d9e7020
Timestamp:                 exact wall-clock timestamps NONE FOUND in raw B-N action log
Input:                     identity c0da14aabd3d4d22b14cbb2a; actual B prompt text itself NONE FOUND in this directory
Information created:       NONE FOUND
Information stored:        DB rows = 0
Information fetched:       target c0da14aabd3d4d22b14cbb2a returned not-found
Execution started:         action log begins with workspace inspection; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-8: inspect, fetch target, read attempt, tool help, binary probe, read-only probe, blocker/stop
Execution output:          阻塞报告.md lines 1-9
Continuation:              NOT OBSERVED as completed continuation
Artifacts:                 action log, blocker report, empty DB
Errors:                    no crash/error file; blocker explicitly recorded
Not found:                 target identity c0da14aabd3d4d22b14cbb2a; DB row count=0
Source evidence:           b-n-run/动作日志.md:1-8; 阻塞报告.md:1-9; DB row_count=0
```

## 5. T5 Raw Execution Evidence

### 5.0 Attempt/revision relation

```text
T5 Attempt #1 = three runs, pinned by d7f1c43, evidence commit b5e9eb4.
T5 REV.1      = three runs, revision pinned in b5e9eb4, results recorded by b9b4b79.
Attempt #1 and REV.1 are kept separate. No run-level merging is performed here.
```

### 5.1 T5 Attempt #1 A-run

```text
Run:                       T5 Attempt #1 A-run
Experiment:                workshop dependency-plan setup
Commit:                    pin d7f1c43; evidence commit b5e9eb4
Timestamp:                 action log 2026-10-03 23:19-23:21 Asia/Shanghai; DB produced_at=2026-10-03T15:20:08Z
Input:                     A_INSTRUCTION.txt lines 1-42
Information created:       separate create-event trace NONE FOUND
Information stored:        identity=a88ec8e16fbd4243aa5adbd8; source=Workshop_Dependency_Plan.md; content_length=1355
Information fetched:       NONE FOUND
Execution started:         action log line 1 says read workspace/instruction; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-4: read input, create plan, store, create todo
Execution output:          Workshop_Dependency_Plan.md lines 1-65; todo.md lines 1-6
Continuation:              A-run stopped before final schedule
Artifacts:                 plan, todo, action log, DB, input
Errors:                    NONE FOUND
Not found:                 NONE FOUND
Source evidence:           a-run/动作日志.md:1-4; plan lines 1-65; DB row 1; session-ids.txt:1
```

### 5.2 T5 Attempt #1 B-E-run

```text
Run:                       T5 Attempt #1 B-E-run
Experiment:                information-enabled schedule continuation attempt
Commit:                    pin d7f1c43; evidence commit b5e9eb4
Timestamp:                 NONE FOUND in raw B-E action log
Input:                     B_INSTRUCTION.txt lines 1-18; identity a88ec8e16fbd4243aa5adbd8
Information created:       separate create-event trace NONE FOUND
Information stored:        DB row_count=1; no new row after A plan
Information fetched:       plan a88ec8e16fbd4243aa5adbd8; artifact dependency-plan-fetch.txt exists
Execution started:         action log line 1 says read/execute instruction; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-3: enter/list, fetch, detect infeasibility and stop
Execution output:          fetched plan lines 1-65; blocker explanation embedded in action log line 3; no final schedule
Continuation:              NOT OBSERVED as completed continuation; B refused due infeasible pinned constraints
Artifacts:                 fetched plan, action log, DB
Errors:                    feasibility conflict recorded in action log, not a crash
Not found:                 NONE FOUND
Source evidence:           b-e-run/动作日志.md:1-3; dependency-plan-fetch.txt:1-65; DB row_count=1
```

### 5.3 T5 Attempt #1 B-N-run

```text
Run:                       T5 Attempt #1 B-N-run
Experiment:                empty-boundary negative attempt
Commit:                    pin d7f1c43; evidence commit b5e9eb4
Timestamp:                 NONE FOUND in raw B-N action log
Input:                     B_INSTRUCTION.txt; identity a88ec8e16fbd4243aa5adbd8
Information created:       NONE FOUND
Information stored:        DB row_count=0
Information fetched:       target returned not-found
Execution started:         action log line 1 says read instruction; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-8: read input, fetch, tool help, workspace check, missing-output check, DB query, blocker/stop
Execution output:          BLOCKER_REPORT.md lines 1-25
Continuation:              NOT OBSERVED
Artifacts:                 blocker, action log, empty DB
Errors:                    no crash file; blocker recorded
Not found:                 target identity a88ec8e16fbd4243aa5adbd8
Source evidence:           b-n-run/动作日志.md:1-8; BLOCKER_REPORT.md:1-25; DB row_count=0
```

### 5.4 T5 REV.1 A-run

```text
Run:                       T5 REV.1 A-run
Experiment:                revised workshop dependency-plan setup
Commit:                    REV.1 pin/evidence commit b5e9eb4; result commit b9b4b79
Timestamp:                 DB produced_at=2026-10-03T15:27:26Z; local run log has no wall-clock
Input:                     A_INSTRUCTION.txt lines 1-43; added SLOT-0A9332=16:00
Information created:       separate create-event trace NONE FOUND
Information stored:        identity=69c28c24e690d2c294c2b1ad; source=Workshop_Dependency_Plan.md; content_length=1332
Information fetched:       NONE FOUND
Execution started:         action log line 1 says confirmed workspace/read input; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-4: read input, create plan, store, create todo
Execution output:          Workshop_Dependency_Plan.md lines 1-65; todo.md lines 1-5
Continuation:              A-run stopped before final schedule
Artifacts:                 plan, todo, action log, DB, input
Errors:                    NONE FOUND
Not found:                 NONE FOUND
Source evidence:           a-run/动作日志.md:1-4; plan lines 1-65; DB row 1; session-ids.txt:1
```

### 5.5 T5 REV.1 B-E-run

```text
Run:                       T5 REV.1 B-E-run
Experiment:                information-enabled final schedule continuation
Commit:                    REV.1 pin/evidence commit b5e9eb4; result commit b9b4b79
Timestamp:                 DB schedule row produced_at=2026-10-03T15:29:54Z; todo row=15:30:10Z; local action log wall-clock NONE FOUND
Input:                     B_INSTRUCTION.txt lines 1-19; identity 69c28c24e690d2c294c2b1ad
Information created:       separate create-event trace NONE FOUND
Information stored:        identities 618d2991ffe4a8541aecbfa5 and 9ef82b67b54b0a43462673a7
Information fetched:       plan 69c28c24e690d2c294c2b1ad; artifact dependency-plan-fetch.txt exists
Execution started:         action log line 1 says listed workspace; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-8: list, read instruction, fetch, read plan, generate schedule, store, update todo, store
Execution output:          Workshop_Final_Schedule.md lines 1-23; todo-updated.md lines 1-9
Continuation:              OBSERVED SEQUENCE ONLY: separate B-run fetched A identity and produced final schedule. Same-process resume: NO EVIDENCE.
Artifacts:                 fetched plan, schedule, todo, action log, DB
Errors:                    NONE FOUND
Not found:                 NONE FOUND
Source evidence:           b-e-run/动作日志.md:1-8; schedule lines 1-23; DB rows 1-3; session-ids.txt:2
```

### 5.6 T5 REV.1 B-N-run

```text
Run:                       T5 REV.1 B-N-run
Experiment:                empty-boundary negative continuation arm
Commit:                    REV.1 pin/evidence commit b5e9eb4; result commit b9b4b79
Timestamp:                 action log 2026-10-03 23:28:57-23:30:19 Asia/Shanghai
Input:                     B_INSTRUCTION.txt lines 1-19; identity 69c28c24e690d2c294c2b1ad
Information created:       blocker row existed after run; plan row did not exist
Information stored:        blocker identity=275a137276d0e077dc14f477; source=Blocker_Report.md
Information fetched:       target returned not-found
Execution started:         action log line 1 says entered workspace/read instruction; explicit process-start marker NONE FOUND
Execution operations:      action log lines 1-11: read input, fetch, not-found, tool help, DB schema/key check, blocker, store blocker, stop
Execution output:          Blocker_Report.md lines 1-28
Continuation:              NOT OBSERVED as completed continuation
Artifacts:                 blocker, action log, DB
Errors:                    no crash file; not-found and blocker recorded
Not found:                 target identity 69c28c24e690d2c294c2b1ad before blocker row was stored
Source evidence:           b-n-run/动作日志.md:1-11; Blocker_Report.md:1-28; DB row 1; session-ids.txt:3
```

## 6. ExecutionCore / ExecutionScope Evidence

### 6.1 R-B1 four-run ExecutionScope structure

`docs/02-evidence/rb1-execution/artifacts` contains direct run JSON, DB files, captured build stderr, physical-change hashes, and machine checks.

E-run:

```text
file:      docs/02-evidence/rb1-execution/artifacts/e-run.json
line:      1
type:      RUNTIME
exact:     run_id=7D7B132B-64F2-4F86-BD14-F90DDC6CBCA5; pid=34872; timestamp=2026-10-02T18:05:04Z; boundary_operation=InformationStore.store
stored_id: 7973612eca7d5e62f6866f18
content:   alpha=17;mode=quiet
```

X-run:

```text
file:      docs/02-evidence/rb1-execution/artifacts/x-run.json
line:      1
type:      RUNTIME
exact:     run_id=7461693A-DFE2-4616-815F-6A081DF6D4D5; pid=34906; timestamp=2026-10-02T18:05:07Z
exact:     baseline_path=ExecutionScope.ObservationBaseline.reference
exact:     boundary_operation=fetch-before;store-after;store-relation
stored:    after=59d5fe62d9bc85d2045e57bf; relation=869c145eb01dc7fdc4d9ee50
relation:  subject=59d5fe62d9bc85d2045e57bf; predicate=observed-change-of; object=7973612eca7d5e62f6866f18
```

V-E-run:

```text
file:      docs/02-evidence/rb1-execution/artifacts/v-e-run.json
line:      1
type:      RUNTIME
exact:     run_id=FCA8B9F7-0B71-4CED-9CBA-1765163A1CC6; pid=34940; timestamp=2026-10-02T18:05:10Z
fetch:     relation->after->before
answer:    Entity E changed from alpha=17;mode=quiet to alpha=42;mode=active.
```

V-N-run:

```text
file:      docs/02-evidence/rb1-execution/artifacts/v-n-run.json
line:      1
type:      RUNTIME
exact:     run_id=5FE4F7D7-1E14-4336-8FF8-A2613D309384; pid=34960; timestamp=2026-10-02T18:05:13Z
answer:    null
blocker:   relation-not-found
```

Machine checks:

```text
file:      docs/02-evidence/rb1-execution/artifacts/post-run-checks.txt
lines:     1-20
exact:     20 PASS lines including machine_checks = PASS
```

Persisted DB inspection:

```text
experimental.sqlite:
  information rows=2
    7973612eca7d5e62f6866f18 = alpha=17;mode=quiet; extraction_mode=declared-baseline
    59d5fe62d9bc85d2045e57bf = alpha=42;mode=active; extraction_mode=observation
  relation rows=1
    869c145eb01dc7fdc4d9ee50 = observed-change-of; subject=after; object=before
negative.sqlite:
  information rows=0
  relation rows=0
```

Invalid R-B1 pre-runs:

```text
attempt-01-invalid-argument-count/e-run.stderr.txt:3
  HARNESS_ERROR: expected 4 arguments, got 5
attempt-02-invalid-timestamp-roundtrip/e-run.stderr.txt:3
  HARNESS_ERROR: baseline readback mismatch
attempt-02 experimental.sqlite:
  information rows=1; relation rows=0
```

### 6.2 RC1 / CContinuationStudy three-arm lifecycle

Valid completed run:

```text
run_id:              RC1-A4-20261003T040749Z-57375
manifest:            docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/run_manifest.json lines 1-24
implementation:      baseline 569fe540d1ff; release build; evaluator=CContinuationEvaluator; fresh binary=CContinuationStudyContinue
task:                C-T-001
S0:                  alpha=17;mode=quiet
S1:                  alpha=42;mode=active
arms declared:       C-A,C-B,C-C
```

Per-arm process and evaluation facts:

```text
C-A old_pid=57377; fresh_pid=57378; distinct_processes=true
C-A phases=OLD_PROCESS_STARTED,POST_CHANGE_OBSERVED
C-A pointer_keys=[] then []
C-A evaluation: x1=true; x2/x3/x4/x5=false; partial=true; full=false
C-A report blocker=missing_allowed_carrier

C-B old_pid=57396; fresh_pid=57405; distinct_processes=true
C-B phases=OLD_PROCESS_STARTED,S0_OBSERVED,POST_CHANGE_OBSERVED
C-B pointer_keys=[] then [s0,task] then [progress,s0,s1,task]
C-B evaluation: x1..x5=true; full=true
C-B report before=alpha=17;mode=quiet; after=alpha=42;mode=active; nextAction=REQUEST_HEALTH_CHECK

C-C old_pid=57407; fresh_pid=57408; distinct_processes=true
C-C phases=OLD_PROCESS_STARTED,S0_OBSERVED,POST_CHANGE_OBSERVED
C-C pointer_keys=[] then [s0,task] then [progress,relation,s0,s1,task]
C-C evaluation: x1..x5=true; full=true
C-C report before/after/nextAction same as C-B
```

Lifecycle marker examples:

```text
file:      .../runs/C-A/workspace/fresh-process-started.json
fields:    phase=fresh_process_started; pid=57378; timestamp=2026-10-03T04:07:50Z
file:      .../runs/C-A/workspace/old-process-terminated.json
fields:    phase=old_process_terminated; pid=57377; timestamp=2026-10-03T04:07:50Z
file:      .../runs/C-C/workspace/fresh-process-started.json
fields:    phase=fresh_process_started; pid=57408; timestamp=2026-10-03T04:07:51Z
```

Execution-state pointer evidence:

```text
C-B execution-state.json lines 3-8:
  progress=cc86b4b076f4df3cbfeb7220; s0=6c60473b9af41a30eb7ed884; s1=4b58af0f61e1868a7035499a; task=34a4fa241e23a32d273870c4
C-C execution-state.json lines 3-9:
  progress=4dd3879657f77c47a55dcb79; relation=df05e39ce28da168ccba1c70; s0=673e81d9dae07e94d48adf4a; s1=14b71e7168cef99af79227b9; task=c309c7ec00588a5c99d4597c
```

C-C relation artifact:

```text
file:   docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/relation.json
object: df05e39ce28da168ccba1c70
fields: subject=14b71e7168cef99af79227b9; predicate=observed-change-of; object=673e81d9dae07e94d48adf4a
        producedBy=declared-old-process-observation; extractionMode=observation
```

Protocol outcome:

```text
file:      docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/protocol-result.json
lines:     1-23
exact:     execution_integrity=VALID
           C-A=PARTIAL_SUCCESS; C-B=FULL_SUCCESS; C-C=FULL_SUCCESS
           overall=VALID_THREE_ARM_EXECUTION_COMPLETED
```

Audit result:

```text
file:      .../evidence-audit.json
fields:    layer1_evidence_integrity=PRESERVED; lifecycle_reconstructable=true
           old_fresh_pids_distinct=true; physical_change_preserved=true
           forbidden_channel_runtime_checks_failed=[]
```

Invalid prior CContinuationStudy records:

```text
RC1-A2-20261002T204525Z-45479/run-status.txt:
  status=ABORTED_ORCHESTRATION_FIFO_OPEN_BLOCK; arms_executed=NONE
RC1-A2-20261002T204848Z-45707/run-status.txt:
  status=ABORTED_ORCHESTRATION_MISSING_DECLARED_S1; arms_executed=C_A_OLD_ONLY
RC1-A2-20261002T204925Z-45791/run-status.txt:
  status=STOPPED_IMPLEMENTATION_DEFECT; C-B_old=CRASH_NIL_RELATION_STORE_FORCE_UNWRAP
RC1-A2-20261002T204925Z-45791/CContinuationStudy-crash.ips exists
RC1-A3-20261002T211316Z-48817/run-status.txt:
  status=ABORTED_ORCHESTRATION_FIFO_OPEN_BLOCK; arms_executed=NONE
RC1-A3-20261002T211332Z-48860/run-status.txt:
  status=STOPPED_IMPLEMENTATION_DEFECT; C-B=FULL_SUCCESS_X1_X5; C-C_old stopped
RC1-A3-20261002T211332Z-48860/CContinuationStudy-crash.ips exists
```

RC1 Attempt #1 raw artifact directory: `NO EVIDENCE FOUND` under current `docs/02-evidence`; only RESEARCH_NOTE records that it was stopped/invalid.

### 6.3 Source-code explanations, not runtime proof

```text
tools/t4ctl/Sources/t4ctl/main.swift:31-57
  maps `store` to Information formation + SQLiteStore.store and `fetch` to SQLiteStore.fetch/write/not-found.

trackD-memory/Sources/InformationCore/SQLiteStore.swift:106-169
  SQLite INSERT OR IGNORE and SELECT WHERE identity; absence is nil.

trackD-memory/Sources/ExecutionCore/ExecutionCore.swift:48-75
  ExecutionScope delegates observe/form to injected stores.

trackD-memory/Sources/ExecutionCore/ExecutionCore.swift:82-137
  formObservedChange can fetch a reference baseline, store after-state, and store an observed-change relation.

trackD-memory/Tests/ExecutionCoreTests/ExecutionCoreTests.swift:35-129
  Four ExecutionScope tests exist in source.
  Persisted TEST_OUTPUT for these tests: NO EVIDENCE FOUND.
```

## 7. InformationCore Evidence

### 7.1 Create

Direct `create` event logs: `NO EVIDENCE FOUND`.  
Observed DB rows prove persisted Information values existed after runs, but do not by themselves capture a separate creation event. Source `t4ctl/main.swift:40-46` forms an `Information` before store; this is SOURCE_CODE, not runtime proof.

### 7.2 Store

Direct store side-effects observed as SQLite rows:

```text
T4 A-run:           1 row
T4 B-E-run:         4 rows
T4 B-N-run:         1 sentinel row
T4-2 A-run:         1 row
T4-2 B-E-run:       3 rows
T4-2 B-N-run:       0 rows
T5 Attempt1 A-run:  1 row
T5 Attempt1 B-E:    1 row
T5 Attempt1 B-N:    0 rows
T5 REV.1 A-run:     1 row
T5 REV.1 B-E:       3 rows
T5 REV.1 B-N:       1 blocker row
R-B1 experimental:  2 information rows + 1 relation row
R-B1 negative:      0 information rows + 0 relation rows
R-B1 attempt2:      1 information row
RC1 Attempt2 C-B:   0 information rows
RC1 Attempt3 C-B:   4 information rows
RC1 Attempt4 C-B:   4 information rows
RC1 Attempt4 C-C:   4 information rows + 1 relation.json object
```

### 7.3 Fetch

Observed fetch/not-found traces:

```text
T4 B-E: target 9fd1608770a655473b18cddf; action log says fetched; fetched artifact exists.
T4 B-N: target 9fd1608770a655473b18cddf = not-found; sentinel 91576421759960b8a6f28fcd fetched.
T4-2 B-E: target c0da14aabd3d4d22b14cbb2a; action log says fetched; todo-fetch.txt exists.
T4-2 B-N: target c0da14aabd3d4d22b14cbb2a = not-found.
T5 Attempt1 B-E: target a88ec8e16fbd4243aa5adbd8; fetched artifact exists.
T5 Attempt1 B-N: target a88ec8e16fbd4243aa5adbd8 = not-found.
T5 REV.1 B-E: target 69c28c24e690d2c294c2b1ad; fetched artifact exists.
T5 REV.1 B-N: target 69c28c24e690d2c294c2b1ad = not-found.
R-B1 V-E: fetch_sequence=relation->after->before; IDs/content returned.
R-B1 V-N: blocker=relation-not-found.
```

### 7.4 Query

`t4ctl` source declares no query/list capability (`tools/t4ctl/Sources/t4ctl/main.swift:1-16`).  
B-N action logs describe local DB inspection/query attempts in T4/T4-2/T5.  
RC1/R-B1 raw run JSON records boundary fetch operations but no general query API.

## 8. SQLite Evidence

SQLite files and row counts:

| File | Rows / relation rows | Key records |
|---|---:|---|
| `t4-execution/a-run/db-a.sqlite` | 1 / none | `9fd1608770a655473b18cddf` |
| `t4-execution/b-e-run/db-b-e.sqlite` | 4 / none | `9fd...`, `f4f...`, `323...`, `8e4...` |
| `t4-execution/b-n-run/db-b-n.sqlite` | 1 / none | sentinel `91576421759960b8a6f28fcd` |
| `t42-execution/a-run/db-a.sqlite` | 1 / none | `c0da14aabd3d4d22b14cbb2a` |
| `t42-execution/b-e-run/db-b-e.sqlite` | 3 / none | plan, activation record, updated todo |
| `t42-execution/b-n-run/db-b-n.sqlite` | 0 / none | empty |
| `t5-execution/attempt1/a-run/information.sqlite` | 1 / none | `a88ec8e16fbd4243aa5adbd8` |
| `t5-execution/attempt1/b-e-run/information.sqlite` | 1 / none | same plan row, byte-identical DB hash |
| `t5-execution/attempt1/b-n-run/information.sqlite` | 0 / none | empty |
| `t5-execution/rev1/a-run/information.sqlite` | 1 / none | `69c28c24e690d2c294c2b1ad` |
| `t5-execution/rev1/b-e-run/information.sqlite` | 3 / none | plan, schedule, COMPLETE todo |
| `t5-execution/rev1/b-n-run/information.sqlite` | 1 / none | blocker `275a137276d0e077dc14f477` |
| `rb1-execution/artifacts/experimental.sqlite` | 2 information + 1 relation | before, after, observed-change-of |
| `rb1-execution/artifacts/negative.sqlite` | 0 information + 0 relation | empty |
| `rb1-execution/artifacts/attempt-02-invalid-timestamp-roundtrip/experimental.sqlite` | 1 information + 0 relation | before only |
| `rc1-attempt2/.../C-B/workspace/information.sqlite` | 0 / none | empty |
| `rc1-attempt3/.../C-B/workspace/information.sqlite` | 4 / none | task,s0,s1,progress |
| `rc1-attempt4/.../C-B/workspace/information.sqlite` | 4 / none | task,s0,s1,progress |
| `rc1-attempt4/.../C-C/workspace/information.sqlite` | 4 / none | task,s0,s1,progress |

`relation.json` is not SQLite but is a persisted Relation artifact:

```text
file: docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/relation.json
id:   df05e39ce28da168ccba1c70
edge: after -> observed-change-of -> before
```

## 9. Continuation Evidence

```text
Observed:
  T4/T4-2/T5 have persisted evidence of separate A-run and B-run phases.
  B-E runs have fetch-before-output evidence.
  B-N runs have fetch-not-found and blocker evidence.
  R-B1 has four separate fresh run IDs/PIDs, a stored before/after/relation chain, and a fresh V-E fetch sequence.
  RC1 Attempt #4 has distinct old/fresh PIDs, separate lifecycle markers, checkpoint staging, and old/fresh evidence separation.

Partially observed:
  T4/T4-2/T5 continuation is observable only as a run-level A→B sequence plus fetch/output artifacts, not as low-level resume/restore of one process.
  CContinuationStudy Attempt #3 C-B was FULL_SUCCESS_X1_X5, but the run stopped before C-C completed; therefore partial only.

Not observed:
  Same-process resume for T4/T4-2/T5: NO EVIDENCE FOUND.
  A t4ctl-level resume operation: NO EVIDENCE FOUND.
  RC1 Attempt #2 or #3 complete three-arm continuation: NO EVIDENCE FOUND.
```

No fetch+output sequence is labeled here as continuation semantics beyond the observed facts above.

## 10. Cross-Experiment Structural Comparison

| Property | T4 | T4-2 | T5 |
|---|---|---|---|
| Information created | DB rows present; separate create event UNKNOWN | DB rows present; separate create event UNKNOWN | DB rows present; separate create event UNKNOWN |
| Information stored | yes: DB rows in A/B-E/B-N | yes: A/B-E rows; B-N 0 rows | yes: Attempt1 A/B-E; REV.1 A/B-E/B-N blocker |
| Information fetched | B-E target found; B-N target not-found | B-E target found; B-N target not-found | Attempt1 and REV.1 B-E found; B-N not-found |
| Execution observed | action logs only; no process trace | action logs only; no process trace | action logs + session ids; no low-level process trace |
| Multiple execution phases | yes: A and B raw artifacts | yes: A and B raw artifacts | yes: A and B raw artifacts in both attempts |
| Continuation observed | partially: A→B fetch/output sequence; no process resume evidence | partially: A→B fetch/output sequence; no process resume evidence | Attempt1 blocked/infeasible; REV.1 A→B fetch/output sequence; no process resume evidence |
| Persistent artifact | ledger, summary, status, SQLite DBs | release plan, activation record, todo, SQLite DBs | plan/fetched plan/schedule/todo/blocker/SQLite DBs |

## 11. Evidence Gaps

```text
1. T4/T4-2/T5 have no low-level process-start/PID/exit trace files.
2. T4/T4-2 raw evidence does not contain actual agent session IDs; only T5 session-ids.txt records them.
3. T4/T4-2/T5 action logs are agent-authored action records, not instrumentation traces.
4. t4ctl stdout was not captured as a separate runtime file; identities appear in later artifacts/logs.
5. Separate Information create-event traces are absent; DB rows are the direct storage evidence.
6. Actual B prompt files for T4/T4-2 are not present in their raw evidence directories; only T5 preserves actual B_INSTRUCTION files.
7. No persisted Swift Testing output was found for ExecutionCoreTests or CContinuationTests.
8. RC1 Attempt #1 raw artifact directory was not found; only RESEARCH_NOTE status remains.
9. RC1 Attempt #2 and #3 did not produce complete valid three-arm runs.
10. R-B1 physical S0→S1 change evidence is external orchestration/hash evidence, not ExecutionCore change detection.
11. T5 Attempt #1 had only three slots for a four-level graph; no feasible schedule was possible under pinned constraints.
12. Cross-run executor/model/version equality for T4/T4-2/T5 cannot be extracted from raw evidence alone.
13. Some T5 run logs lack wall-clock timestamps; DB produced_at and session ids are the only temporal anchors.
14. No t4ctl query/list API or query result artifact exists.
```

## 12. Extraction Conclusion

```text
1. Extractable execution data:
   T4, T4-2, and T5 have raw action logs, run artifacts, and SQLite rows.
   T5 additionally preserves actual input files, session ids, and evidence hash manifests.
   R-B1 has the strongest ExecutionScope process evidence: four run JSON records with PID/run_id/timestamp, boundary operation fields, DB inspection, machine checks, and persisted Information/Relation rows.
   RC1 Attempt #4 has three-arm old/fresh process markers, checkpoint staging, evaluation JSON, continuation reports, and persisted Information rows.

2. Not extractable:
   Low-level OS traces for T4/T4-2/T5, separate create events, actual t4ctl stdout, T4/T4-2 session ids, persisted Swift test output, RC1 Attempt #1 raw directory, and complete RC1 Attempt #2/#3 three-arm continuation evidence.

3. Directly comparable real run structures:
   T4, T4-2, and T5 REV.1 all have A-run storage, B-E fetch/output, and B-N not-found/blocker artifacts.
   Their comparison is limited to these observed structures; it does not establish identical runtime mechanics.

4. Single-observation structures:
   The R-B1 four-run ExecutionScope consumption chain and RC1 Attempt #4 old/fresh three-arm lifecycle are each represented by one sealed valid campaign in the current repository.

5. Repeated across tasks:
   The A→B sequence with B-E fetch-found and B-N fetch-not-found appears in T4, T4-2, and T5 REV.1.
   This is a repeated observable structure, not a universal continuation claim.
```



## Raw Evidence Index


### T4 files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/t4-execution/a-run/db-a.sqlite` | DATABASE | 12288 | `3bf0553f0cd2bd386a83ccc07f8a8f532ddd645cc6a06c69ebeb6cbc8cfc7c83` |
| `docs/02-evidence/t4-execution/a-run/ledger.md` | ARTIFACT | 212 | `b311025ec40a63462f6ad87f1a35c3c5a2daca128421a623492efdfce009a7e7` |
| `docs/02-evidence/t4-execution/a-run/todo.md` | ARTIFACT | 159 | `c1e1cd9456317f4ae7aeaf9dc27183bf39435f2e760311b9fb4815c23be83da2` |
| `docs/02-evidence/t4-execution/a-run/动作日志.md` | RUNTIME | 218 | `19ad9c87fea4e04b5bca38ea17cfaeb889518d4d93b4d8ef4f53e474fa937bd6` |
| `docs/02-evidence/t4-execution/b-e-run/9fd1608770a655473b18cddf.md` | ARTIFACT | 347 | `f95633ef85699ef2b0a9f4fc6dfd61abf8464cbe00ac446bff13244bf58020b1` |
| `docs/02-evidence/t4-execution/b-e-run/db-b-e.sqlite` | DATABASE | 12288 | `a3953c9e3b3cc9a744b4fb04b5a1601b14dd266626aea3feb9b863e13bb3aad8` |
| `docs/02-evidence/t4-execution/b-e-run/动作日志.md` | RUNTIME | 688 | `0a8a777b9ede112ca8a0ed9bb72de0de495a3c01a9ac9d5c991aedac22ddb4df` |
| `docs/02-evidence/t4-execution/b-e-run/合同摘要.md` | ARTIFACT | 264 | `6f6ab01cb600df8647383b19d7196a1a7aad2d35f8771b4d91a25e24faa83e8e` |
| `docs/02-evidence/t4-execution/b-e-run/待办状态登记.md` | ARTIFACT | 166 | `824d5ec1a14914398c54dd30c6ea0bdced7a71538cb8f91dc26cf502bc731834` |
| `docs/02-evidence/t4-execution/b-n-run/db-b-n.sqlite` | DATABASE | 12288 | `f240d1a2d70ee8e235e95ef01e123933b54a699f4312ca4f6b42867bc8c51edb` |
| `docs/02-evidence/t4-execution/b-n-run/动作日志.md` | RUNTIME | 1235 | `9c67f2ac01a80d167850bd30f83d4ae161321cbfcad7670fc7462265363cd35f` |


### T4-2 files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/t42-execution/a-run/Release_Plan_REL-56ff.md` | RESEARCH_NOTE | 775 | `2e02c9ea84ba77891043750b28d54f63391dedfc8345597373d39b28269d3ec6` |
| `docs/02-evidence/t42-execution/a-run/db-a.sqlite` | DATABASE | 12288 | `b7dbe2c338f17193e7869ab777ea85ec0f9cb1f3195a410b8f2b83fb82247307` |
| `docs/02-evidence/t42-execution/a-run/动作日志.md` | RUNTIME | 342 | `12c067068d04d85eebca0fde3e3669265c23bf4ab69279cbfa3aff8913ac1237` |
| `docs/02-evidence/t42-execution/a-run/待办.md` | ARTIFACT | 121 | `ad72b723924271eb78879e053ef35e18c44badcbed04257fc3a6eba7f26f01a7` |
| `docs/02-evidence/t42-execution/b-e-run/db-b-e.sqlite` | DATABASE | 12288 | `03a42cb94d6ec9425a6a2030e566eee6ec2d8839148277038437da8a235d07ce` |
| `docs/02-evidence/t42-execution/b-e-run/production-activation-record.md` | ARTIFACT | 721 | `cb527c4a5e0cd128b53431e8cbb66a6a68bc96eff31e35b4af5f72aa6656010c` |
| `docs/02-evidence/t42-execution/b-e-run/todo-c0da14aabd3d4d22b14cbb2a-updated.md` | ARTIFACT | 319 | `fb92b014644fc8870169ac6424949e135e081c21badf37482d3e44fed897e7f4` |
| `docs/02-evidence/t42-execution/b-e-run/todo-fetch.txt` | ARTIFACT | 775 | `2e02c9ea84ba77891043750b28d54f63391dedfc8345597373d39b28269d3ec6` |
| `docs/02-evidence/t42-execution/b-e-run/动作日志.md` | RUNTIME | 897 | `a609c2cf3236ad8df2c751613bbbc690f7dfa6ce370a8124099bd223ea5c5b33` |
| `docs/02-evidence/t42-execution/b-n-run/db-b-n.sqlite` | DATABASE | 12288 | `dc719c7254af040ac5e98e577f197d124e26afe667c599d94417397bb13861a4` |
| `docs/02-evidence/t42-execution/b-n-run/动作日志.md` | RUNTIME | 356 | `a8b6f66023f0418b5a5bfffcc4745f51545bceae77613bba99e11fbbf1d78837` |
| `docs/02-evidence/t42-execution/b-n-run/阻塞报告.md` | ARTIFACT | 714 | `ac506da2b7afe408d9e18ee8646816a9ef6cc07809297a1a091160cb1b8c6262` |


### T5 files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/t5-execution/attempt1/a-run/A_INSTRUCTION.txt` | INPUT ARTIFACT | 1582 | `2d0f36f0fadd6b84e31847fd8e2a357e1795302b7717eafa87abe9549d2237cf` |
| `docs/02-evidence/t5-execution/attempt1/a-run/Workshop_Dependency_Plan.md` | RESEARCH_NOTE | 1355 | `bd7aa0bef180bd8605d2624290285ea3fa0ceee2f8b42505995c26c99a5a57b3` |
| `docs/02-evidence/t5-execution/attempt1/a-run/information.sqlite` | DATABASE | 12288 | `31d02e963aa7e087b524262a6a86c76a27012be25d1e087d069b2fd6a78d6dc4` |
| `docs/02-evidence/t5-execution/attempt1/a-run/todo.md` | ARTIFACT | 184 | `7dbab3528c2c74b1fe6e5ee2da836757b8ceb865ee4d05fb7329855e93717981` |
| `docs/02-evidence/t5-execution/attempt1/a-run/动作日志.md` | RUNTIME | 528 | `949651199b2eec3984d497ae96cea2ce522bc083a9af50e0db25fd98e65e670f` |
| `docs/02-evidence/t5-execution/attempt1/b-e-run/B_INSTRUCTION.txt` | INPUT ARTIFACT | 1201 | `4d7d94238e4ef450e1882382f1383067fceb764e44f483fe09fefade37029199` |
| `docs/02-evidence/t5-execution/attempt1/b-e-run/dependency-plan-fetch.txt` | ARTIFACT | 1355 | `bd7aa0bef180bd8605d2624290285ea3fa0ceee2f8b42505995c26c99a5a57b3` |
| `docs/02-evidence/t5-execution/attempt1/b-e-run/information.sqlite` | DATABASE | 12288 | `31d02e963aa7e087b524262a6a86c76a27012be25d1e087d069b2fd6a78d6dc4` |
| `docs/02-evidence/t5-execution/attempt1/b-e-run/动作日志.md` | RUNTIME | 520 | `736fa5d8b1d70c77db831abb4bf9286391a122bc3e245949ea09449b46cc45c4` |
| `docs/02-evidence/t5-execution/attempt1/b-n-run/BLOCKER_REPORT.md` | ARTIFACT | 1060 | `9208743857f11380d765a50f7633f6f42b7d985635290da95a129804b3591686` |
| `docs/02-evidence/t5-execution/attempt1/b-n-run/B_INSTRUCTION.txt` | INPUT ARTIFACT | 1201 | `4d7d94238e4ef450e1882382f1383067fceb764e44f483fe09fefade37029199` |
| `docs/02-evidence/t5-execution/attempt1/b-n-run/information.sqlite` | DATABASE | 12288 | `dc719c7254af040ac5e98e577f197d124e26afe667c599d94417397bb13861a4` |
| `docs/02-evidence/t5-execution/attempt1/b-n-run/动作日志.md` | RUNTIME | 495 | `24e6c006430139ed4fca333f657bb1ed4ae66e80a24b05167df24df9244d5aba` |
| `docs/02-evidence/t5-execution/attempt1/evidence-sha256.txt` | INTEGRITY | 1944 | `790902e2c4bbc57258061b0281debe4b9db0a79206b639faa5f1ec4a0e2876bf` |
| `docs/02-evidence/t5-execution/attempt1/session-ids.txt` | SESSION_RECORD | 236 | `6387bbf8bb5113a716eec30f0bbc865817e07691a9910a398e54bad4c3a95893` |
| `docs/02-evidence/t5-execution/pinning/a-instruction-rev1.txt` | INPUT ARTIFACT | 1604 | `cdb2e4fd681380f7e2f8ec13d8fce86b339020ea29aa2298c5507b7eb45de104` |
| `docs/02-evidence/t5-execution/pinning/a-instruction.txt` | INPUT ARTIFACT | 1582 | `2d0f36f0fadd6b84e31847fd8e2a357e1795302b7717eafa87abe9549d2237cf` |
| `docs/02-evidence/t5-execution/pinning/b-instruction-template-rev1.txt` | INPUT ARTIFACT | 1205 | `e591f265b2d08af98734e28da929f19a72fe29312fa3aaeca00b6d087be6067a` |
| `docs/02-evidence/t5-execution/pinning/b-instruction-template.txt` | INPUT ARTIFACT | 1205 | `e591f265b2d08af98734e28da929f19a72fe29312fa3aaeca00b6d087be6067a` |
| `docs/02-evidence/t5-execution/pinning/sha256-rev1.txt` | INTEGRITY | 263 | `2b8bbec6268d8ce8d5da808516ce646fadfa25b91e21e75a10a2e7bd12100d67` |
| `docs/02-evidence/t5-execution/pinning/sha256.txt` | INTEGRITY | 253 | `7f32dac8ca5f8652ef409b8ad4c77299e1effc64660045d5e20bbc53c968ca2c` |
| `docs/02-evidence/t5-execution/rev1/a-run/A_INSTRUCTION.txt` | INPUT ARTIFACT | 1604 | `cdb2e4fd681380f7e2f8ec13d8fce86b339020ea29aa2298c5507b7eb45de104` |
| `docs/02-evidence/t5-execution/rev1/a-run/Workshop_Dependency_Plan.md` | RESEARCH_NOTE | 1332 | `ea698d8a0c3e61f0fd95bd186c7dd9e9240c15ea5ee6696e5b0e258e17b3be4e` |
| `docs/02-evidence/t5-execution/rev1/a-run/information.sqlite` | DATABASE | 12288 | `f5409892704b81a30ae9d6294dfab84402d6b5d9b2137160c75ab9bacd80b921` |
| `docs/02-evidence/t5-execution/rev1/a-run/todo.md` | ARTIFACT | 131 | `efe499a8e6f3f0682cc3b7f3591aa0ff6572fc74aa063b59d138e76d99f986e4` |
| `docs/02-evidence/t5-execution/rev1/a-run/动作日志.md` | RUNTIME | 631 | `b0a6246061cafb1d7ab25785f9cc08bf4b8df766f1a84eb9fce9646c8b0cbe7f` |
| `docs/02-evidence/t5-execution/rev1/b-e-run/B_INSTRUCTION.txt` | INPUT ARTIFACT | 1201 | `09ab15e7282302806a75374514439da4129e81aa5b04d69509912edb3962db9b` |
| `docs/02-evidence/t5-execution/rev1/b-e-run/Workshop_Final_Schedule.md` | ARTIFACT | 827 | `d60ef1041421153b2e854e3591e36bf75d1332ec6b5b80447ec0fb158325d019` |
| `docs/02-evidence/t5-execution/rev1/b-e-run/dependency-plan-fetch.txt` | ARTIFACT | 1332 | `ea698d8a0c3e61f0fd95bd186c7dd9e9240c15ea5ee6696e5b0e258e17b3be4e` |
| `docs/02-evidence/t5-execution/rev1/b-e-run/information.sqlite` | DATABASE | 12288 | `538fee38fa9852a7d2acfdd7b85fe8c35a88ccb437dd57f975ca2cbef1fe1a1f` |
| `docs/02-evidence/t5-execution/rev1/b-e-run/todo-updated.md` | ARTIFACT | 170 | `f73c2b4b78cd165c19761fddb379396561df0255d96445331632e260ce8c86e0` |
| `docs/02-evidence/t5-execution/rev1/b-e-run/动作日志.md` | RUNTIME | 499 | `a6f88f37f10cfa09688ce956fc007bdce3ce9465acdf69743713a78259ea0a74` |
| `docs/02-evidence/t5-execution/rev1/b-n-run/B_INSTRUCTION.txt` | INPUT ARTIFACT | 1201 | `09ab15e7282302806a75374514439da4129e81aa5b04d69509912edb3962db9b` |
| `docs/02-evidence/t5-execution/rev1/b-n-run/Blocker_Report.md` | ARTIFACT | 1130 | `a9134fa1692fac6fa3443c2219ffe2b0bf8220b2f17da4496feb102df261ceae` |
| `docs/02-evidence/t5-execution/rev1/b-n-run/information.sqlite` | DATABASE | 12288 | `35ad6e1a5cff4fd3336e7363b815227ecf214093f9b0c22875c2ac0a33527652` |
| `docs/02-evidence/t5-execution/rev1/b-n-run/动作日志.md` | RUNTIME | 1278 | `221409757e2043756b41846956e0941b4a755487bd2cb685c9edf6cebb71e7fa` |
| `docs/02-evidence/t5-execution/rev1/evidence-sha256.txt` | INTEGRITY | 2145 | `39dbfc9ffd24f65cd23cb8013fb16b1b3a1bc67f671616a729bcce7beae5ecd6` |
| `docs/02-evidence/t5-execution/rev1/session-ids.txt` | SESSION_RECORD | 241 | `bc1a0ebe552d3b64e799475ee158869025975e7b2ba20ec85def1c7000c3a6bc` |


### R-B1/ExecutionScope files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/rb1-execution/AUDIT_20261003.md` | RESEARCH_NOTE | 2160 | `de7b729ad028bbba19f2ef6b5fe546b0e2f966991663de1df6d4ef0c29f4f3f8` |
| `docs/02-evidence/rb1-execution/EXTERNAL_AUDIT_20261003.md` | RESEARCH_NOTE | 2056 | `320cc82756cff961d096a4d696bfdeb766d8b3b7820d63ae95425a1f8d0f51b9` |
| `docs/02-evidence/rb1-execution/RESULTS_20261003.md` | RESEARCH_NOTE | 3497 | `e0a771a91505c107812b98f53acd4176f196301d6f4a5f83602f8572702c5456` |
| `docs/02-evidence/rb1-execution/RUN_PLAN_20261003.md` | RESEARCH_NOTE | 2448 | `08452a0e2e55159817f18b08025de36b0fe27fb38bc89c3c4114fe7fd0a44e04` |
| `docs/02-evidence/rb1-execution/artifacts/MANIFEST.sha256` | INTEGRITY | 3080 | `e5da935763c2ab9ae9c9fbcaa4ecc3354f9c37a8dc3c5780b6e4ce91d7cc267d` |
| `docs/02-evidence/rb1-execution/artifacts/artifact-hashes.txt` | ARTIFACT | 966 | `ddf30823e0b29a53a3cd510c1b7743137cbee84e687a632c5c5e60df44ed8079` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-01-invalid-argument-count/NOTE.txt` | ARTIFACT | 134 | `a2477220f9c62dc27af096a6629f97b8a28bbc23425c8adcab122d7878c6686e` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-01-invalid-argument-count/e-run.json` | RUNTIME | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-01-invalid-argument-count/e-run.stderr.txt` | ARTIFACT | 95 | `99d022d38deb82d0923ee9023e38a9b3634ddd0117364ca3796f5a4904cc634b` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-01-invalid-argument-count/physical-before.sha256` | INTEGRITY | 88 | `37ba6f4e8fd9c49b0e233683ca9ed6291d1b306c1c1c0a5f2f3f19199b00efdf` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-02-invalid-timestamp-roundtrip/NOTE.txt` | ARTIFACT | 203 | `998b91d4c9e26547a730c98ebbe61bd11c26a5ca7f796ca9ffc13f0ee5c76a03` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-02-invalid-timestamp-roundtrip/e-run.json` | RUNTIME | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-02-invalid-timestamp-roundtrip/e-run.stderr.txt` | ARTIFACT | 94 | `806799137e7095592d1c4e6bb1fc84edbb72cccbfb279efab6facec1cdf532b0` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-02-invalid-timestamp-roundtrip/experimental.sqlite` | DATABASE | 20480 | `d58deec39f9ffe41e00801e7773ccb311c84ddf22c8786c18048088875f6c8e0` |
| `docs/02-evidence/rb1-execution/artifacts/attempt-02-invalid-timestamp-roundtrip/physical-before.sha256` | INTEGRITY | 88 | `37ba6f4e8fd9c49b0e233683ca9ed6291d1b306c1c1c0a5f2f3f19199b00efdf` |
| `docs/02-evidence/rb1-execution/artifacts/before-id.txt` | ARTIFACT | 35 | `252da3f758d5de7a9f0f21896b160578f5e5509e515148a209b51e8543a382de` |
| `docs/02-evidence/rb1-execution/artifacts/database-inspection.txt` | ARTIFACT | 655 | `183b3a51f37aa16267e2afd1e0e7c9c23fc96a01b16570b30f2e711c29671bd5` |
| `docs/02-evidence/rb1-execution/artifacts/e-run.json` | RUNTIME | 480 | `357bdd280fea792646178fbec044616ceb2927dea0408275388a689749348d78` |
| `docs/02-evidence/rb1-execution/artifacts/e-run.stderr.txt` | ARTIFACT | 52 | `268ce3df50afd1db1947b66b01e06fd95e763f0fb1d5e6a3dfffc9e8d3fef288` |
| `docs/02-evidence/rb1-execution/artifacts/experimental.sqlite` | DATABASE | 20480 | `ce78c618ce499581063a9377d7f3b5cb803e056b898f5178de632410a320a33b` |
| `docs/02-evidence/rb1-execution/artifacts/negative.sqlite` | DATABASE | 20480 | `74569c60eab39196ae828f5546015f58f192157349b3c7435ad4cd41867daf90` |
| `docs/02-evidence/rb1-execution/artifacts/physical-after.sha256` | INTEGRITY | 87 | `c8157c13419195531680048d70e36613e9a5b94867ef2e8a466daefd634fb440` |
| `docs/02-evidence/rb1-execution/artifacts/physical-after.txt` | ARTIFACT | 44 | `5af1d55276bdfe79a1fe0075063dbd5e28490264490655cc107737f5a0583289` |
| `docs/02-evidence/rb1-execution/artifacts/physical-before.sha256` | INTEGRITY | 88 | `37ba6f4e8fd9c49b0e233683ca9ed6291d1b306c1c1c0a5f2f3f19199b00efdf` |
| `docs/02-evidence/rb1-execution/artifacts/post-run-checks.txt` | ARTIFACT | 454 | `b1dfa467755d58df1ff26e0717c087f8342f531f087f189d6a61cbd0b7a50188` |
| `docs/02-evidence/rb1-execution/artifacts/relation-id.txt` | ARTIFACT | 37 | `491e64ee4620b7cb9b0c5b6319974f2e78692bcac690f7f51ec0ebb34fbcfd4e` |
| `docs/02-evidence/rb1-execution/artifacts/source-and-db-hashes.txt` | ARTIFACT | 602 | `0305c6b206b46340f05bf0c455434f207b9351f95871f311ca277d195791b886` |
| `docs/02-evidence/rb1-execution/artifacts/v-e-run.json` | RUNTIME | 592 | `08a42ad84b62dd1014d00daee6f6ec363138706d60c5acbc83a07bb7f2369823` |
| `docs/02-evidence/rb1-execution/artifacts/v-e-run.stderr.txt` | ARTIFACT | 52 | `268ce3df50afd1db1947b66b01e06fd95e763f0fb1d5e6a3dfffc9e8d3fef288` |
| `docs/02-evidence/rb1-execution/artifacts/v-n-run.json` | RUNTIME | 362 | `f3916b35a2fe7ceeb2c56af06c0c34e41f770c5dd2ccbfd27ed875bfb6f8c426` |
| `docs/02-evidence/rb1-execution/artifacts/v-n-run.stderr.txt` | ARTIFACT | 52 | `ba7a2cbda7a25d04fb882ecbab9cca8d40320e6b90b6e7ce97862266ea455404` |
| `docs/02-evidence/rb1-execution/artifacts/x-run.json` | RUNTIME | 571 | `468ad340dcb7cd20dd5e4a952db2f29235edab50dab03bf3efded5c5a099b440` |
| `docs/02-evidence/rb1-execution/artifacts/x-run.stderr.txt` | ARTIFACT | 52 | `651ae52a2be609b9939df6b67a026fd42ee46416c3039652a05a837ee5563d84` |
| `docs/02-evidence/rb1-execution/workspace/entity-E.txt` | ARTIFACT | 21 | `ff8083645cf7ce426746a6e636d8e426a6aa392acda672d261b0ad694c12a6f0` |


### RC1 Attempt 2 files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/authorization.json` | ARTIFACT | 589 | `a60c90fe4be828a9f0a41c6cd998e1051c924594e9ddc8dfae538998032f002f` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/orchestration-abort.json` | ARTIFACT | 286 | `ed74976c796c7b4c5b85c0462e853731648456e858df4cc155eaa561f26858cf` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/run-status.txt` | RUNTIME | 167 | `0fd96f008b5cf002c312e4360af1434d50f9ff4bac6b0fd2e91c8ba103eb75c0` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/run_manifest.json` | ARTIFACT | 731 | `06167af2b7026967c378bb4474ffe193d2a8ae9a2dcb700a07f5eba35dd10d72` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204525Z-45479/runs/C-A/physical/entity-E.txt` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204817Z-45666/authorization.json` | ARTIFACT | 589 | `a3095f60ac33f6841954616edab6440a10569422aac93b2dd69c6b5ffb663e5a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204817Z-45666/run_manifest.json` | ARTIFACT | 731 | `218dd699d56426661e0f0738b9825ca264d9e7fb89f802dac8b68d25da9766ff` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204817Z-45666/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204817Z-45666/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204817Z-45666/runs/C-A/physical/entity-E.txt` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/authorization.json` | ARTIFACT | 589 | `d14a2f850075fe3ce4713dad724a289d83b91c61374e18c4e906ffd52def70e5` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/orchestration-abort.json` | ARTIFACT | 322 | `464d8af21495faab58fd75598afe72f3ee2d85f9ef78e80863f7abdf342908ec` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/run-status.txt` | RUNTIME | 179 | `6f8894c1620c610916860cf6ac8405abb00e6ed6095a5b7d3e79eb5120ee9e43` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/run_manifest.json` | ARTIFACT | 731 | `0821b4e2d63066cedea4e872a3e4338a5af5e6ad312b3df24d490188ee346f05` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/checkpoint-staging/3834c8752bcf62a761393249d06e2aac875ab8bff0fc37efe659462497fb01ee.json` | ARTIFACT | 278 | `3834c8752bcf62a761393249d06e2aac875ab8bff0fc37efe659462497fb01ee` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/checkpoint-staging/index.json` | ARTIFACT | 454 | `e1988bee93f4a37f58e5ebf43d23a8e0ad1f7e99d35ebe556d252f14000b908d` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/old.stderr.txt` | ARTIFACT | 565 | `e7f47998ea90c2bb6933a5e4e33c371f847a39c91b4a32c635bd5b7cc3310bbf` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `c49e9ca3cff4c90b3221aec5ccc270cd3cab6324fdc379080968b9ece3173666` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204848Z-45707/runs/C-A/workspace/execution-state.json` | ARTIFACT | 278 | `3834c8752bcf62a761393249d06e2aac875ab8bff0fc37efe659462497fb01ee` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/CContinuationStudy-crash.ips` | RUNTIME | 5808 | `8be9c7b26557b6852ae1091f6cadcb6bfddcc013c0c1472ad51f83d92d033b3f` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/authorization.json` | ARTIFACT | 589 | `42bacddadf665b4aff596b3ca7695de1e9cf30a2b5a6482d4d96b05f18e33ffa` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/evidence-sha256.txt` | INTEGRITY | 6286 | `c312d2ab06b7a9522ffa4968ed0da2a1dacdcdca2b454be3994cd1bfe9ae27b4` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/execution-deviation.json` | ARTIFACT | 858 | `41583bf99dbc8b5f44e1026a35ead00d72e363298fb88d18fc378c73c991443a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/result-classification.json` | ARTIFACT | 371 | `dd869146fbe3a4e96719f9f7498c67ad70b9185b08eeb8e0685c8c8677167ca0` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/run-status.txt` | RUNTIME | 389 | `d9bcf1977c98774f7ab6869c6b723305b1772d579c9c43465d8d6d146567c2b4` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/run_manifest.json` | ARTIFACT | 731 | `4b18131499d5fdc5814e3a2b68944488f1e2da71bfc882f56863420024785265` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/checkpoint-staging/776686ab365bd7434786eb31b76047793ad3a1ba4e091c0f462e7e06ddc422ea.json` | ARTIFACT | 278 | `776686ab365bd7434786eb31b76047793ad3a1ba4e091c0f462e7e06ddc422ea` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/checkpoint-staging/a4ae30e98052311e2fa1d7cba3b7d9554831dc5a93d3554452f61d9bea6c8fc0.json` | ARTIFACT | 279 | `a4ae30e98052311e2fa1d7cba3b7d9554831dc5a93d3554452f61d9bea6c8fc0` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/checkpoint-staging/index.json` | ARTIFACT | 906 | `dda12e6bac4461ed0aba73986abcdd7e02530c2cc1c9a559e52272840652f471` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/evaluation.json` | ARTIFACT | 261 | `734574efb460a13717c61675024dc3618e9f37ec39423c46026a612c49d85c60` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/evaluation.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/evaluation.stdout.json` | ARTIFACT | 262 | `23b06c9309ea17fe90f6fcc97d45d38d13666f325cb982727798615f5c93fb88` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/fresh.exit-code` | ARTIFACT | 2 | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/fresh.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/fresh.stdout.json` | ARTIFACT | 135 | `13ac5575edf570a30ea114d5603be78298032a798a0920bff18d3da4024672d4` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `e514b0ec0ac44eb58c641840ebd105be6ae45c93b9bf66f99fdf5ce68af15f03` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/continuation-evidence.json` | ARTIFACT | 6129 | `6341c6faeaa5d936430d3a9f87f80b4ca9d01cec3b08123f5fbc118314b735c1` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/continuation-report.json` | ARTIFACT | 134 | `caffde26c45ee962c3a86993ea54c66c04b6a527b836a6ab981cd1481b0c3e6b` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/execution-state.json` | ARTIFACT | 279 | `a4ae30e98052311e2fa1d7cba3b7d9554831dc5a93d3554452f61d9bea6c8fc0` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/fresh-process-started.json` | RUNTIME | 96 | `88fbe35d833c793ee26c3c816deae75d70df292f86fb8eb14b0ecce4cf50b91f` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/invocation-evidence.jsonl` | RUNTIME | 7624 | `04447c57e79f58e5d21d2aaa564e4c559e6e79d201f56db8b7f0dc46806d521f` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/old-process-terminated.json` | RUNTIME | 97 | `f5017fcc21cb04f949356d6db34c8c4205af25dcce144c5c8b76744507963763` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-A/workspace/physical-change-evidence.json` | ARTIFACT | 468 | `4daf428bed62f6e18bb4e41e658f52b56d14471d629d9ae1f7ede9eb6be6a1ed` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/declared/task-charter.json` | ARTIFACT | 365 | `f330d40769ff364387c762d83eb885c2cbae9cd19985884c7d427a4e3f74a2e0` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/physical/entity-E.txt` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/workspace/execution-state.json` | ARTIFACT | 278 | `32363fbe3540f9f607d90221d330960d5c01d9b3d1d794436ce7434556b97397` |
| `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/runs/C-B/workspace/information.sqlite` | DATABASE | 12288 | `dc719c7254af040ac5e98e577f197d124e26afe667c599d94417397bb13861a4` |


### RC1 Attempt 3 files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/authorization.json` | ARTIFACT | 717 | `28ad8aa2980c540d3781bf544b13b524381dbbf8f09b14584dbe57504d1a847f` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/orchestration-abort.json` | ARTIFACT | 298 | `1ddd2d8c53188669272d1faa303df85542d6963871896707bbc271604d7b36a3` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/run-status.txt` | RUNTIME | 117 | `985b1b6d2450f5b59f99815324a7f98d9d8e91dc3a08cfab7ce0c154c4ccba98` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/run_manifest.json` | ARTIFACT | 731 | `be3f92096e85354f1edb2ee1bbe097cde817ac268db39760067ee0db5eb159e7` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/runs/C-A/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/runs/C-A/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/runs/C-A/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211316Z-48817/runs/C-A/physical/entity-E.txt` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/CContinuationStudy-crash.ips` | RUNTIME | 5502 | `b5efbb546213e51bf8e208d0d1d8d6a22644d057533c3ed3619892085570692a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/authorization.json` | ARTIFACT | 717 | `5082a7ffc743ac984ac772ef9f146e9ee685d53a884075b7978c6c0bc60c2122` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/evidence-sha256.txt` | INTEGRITY | 9327 | `f94984a000345d4ff19bda4910e36fb65d028813248364eebe29a58857197d60` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/execution-deviation.json` | ARTIFACT | 740 | `eb2f25e682ce8bc38e6546bbbd1c7e46a98e392c786766761dfe2cd6f0639987` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/result-classification.json` | ARTIFACT | 361 | `e97639d11a0f8345be0ead216c77b204d7d1d8799126595c96ac4a05b89f33c1` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/run-status.txt` | RUNTIME | 405 | `4273e6b6689d0696e237b2c99ba707aec69892cc6405f7f0304357cfe5be18ce` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/run_manifest.json` | ARTIFACT | 731 | `6e8118233444866d5f062f4e9d228e352db273911d626fa7ea00cf7239be590c` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/arm-summary.json` | ARTIFACT | 1976 | `7105740525172571369cd35b769779e39a0b58e3766fa76335412a3ac5afc4a6` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/checkpoint-staging/7982ead4c710e5983a8b09c247ece4d2de93e24067b12630d59c69ae8b7fbd10.json` | ARTIFACT | 279 | `7982ead4c710e5983a8b09c247ece4d2de93e24067b12630d59c69ae8b7fbd10` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/checkpoint-staging/cd43ea738e272030e4e920fd583300b42a733c6c1181efa362ed8acafb71a784.json` | ARTIFACT | 278 | `cd43ea738e272030e4e920fd583300b42a733c6c1181efa362ed8acafb71a784` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/checkpoint-staging/index.json` | ARTIFACT | 906 | `7832bbac82ac8039dcc1de9d21779d9b83d72e93e730ad8346280e4fe19c753d` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/evaluation.json` | ARTIFACT | 261 | `734574efb460a13717c61675024dc3618e9f37ec39423c46026a612c49d85c60` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `72e5f340edf7e5d06f20a92ca9b4aa21066642d67cc57c731be8a45dc3f39b2f` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/continuation-evidence.json` | ARTIFACT | 6296 | `dd0d1d4c002e78cd2bc2261e04119f5c2713ef5bf352bd4243b8cf4e81a52a89` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/continuation-report.json` | ARTIFACT | 134 | `caffde26c45ee962c3a86993ea54c66c04b6a527b836a6ab981cd1481b0c3e6b` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/execution-state.json` | ARTIFACT | 279 | `7982ead4c710e5983a8b09c247ece4d2de93e24067b12630d59c69ae8b7fbd10` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/fresh-process-started.json` | RUNTIME | 96 | `0ab488305f7213eb796d30080af6a329be766ff3c766c3b077307cbf582dba9f` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/invocation-evidence.jsonl` | RUNTIME | 7624 | `830668bcf53dcad4399b9a12b2227fd0ea9fbd60fa8c596c3c3fad406fdfd39d` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/old-process-terminated.json` | RUNTIME | 97 | `5b91926eae057e61ba87ece6a79f0ef63d8b4a2da18f90dba0dfd58ad6cdd767` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-A/workspace/physical-change-evidence.json` | ARTIFACT | 468 | `c0c0fae0b20482dd4121c1a97cc7d3bae6a465163222334d48cc7dd958c0f59d` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/arm-summary.json` | ARTIFACT | 2359 | `b9f24797771b08d0ecc11624a8b7a72c21ad42846d1f9014bfcb2ff31df6974b` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/checkpoint-staging/1b813761750b8b5960131b9a82e399bedd245b729f68ce85654c1606bf3088f3.json` | ARTIFACT | 278 | `1b813761750b8b5960131b9a82e399bedd245b729f68ce85654c1606bf3088f3` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/checkpoint-staging/223788865c18f3c4201088d49cb14b9e2c5b70f54adf85bb7ad9eac84b2a9f67.json` | ARTIFACT | 348 | `223788865c18f3c4201088d49cb14b9e2c5b70f54adf85bb7ad9eac84b2a9f67` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/checkpoint-staging/c4fa99ed93cebf82b3a098f06e649ebae5d560c613f3f10ab222bc765e15e29e.json` | ARTIFACT | 441 | `c4fa99ed93cebf82b3a098f06e649ebae5d560c613f3f10ab222bc765e15e29e` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/checkpoint-staging/e1acc10f18e22b04e1776155bacba9821b84e22c62bc32e990554ee9f93d9051.json` | ARTIFACT | 387 | `e1acc10f18e22b04e1776155bacba9821b84e22c62bc32e990554ee9f93d9051` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/checkpoint-staging/index.json` | ARTIFACT | 1924 | `3822d600fd14d31e4a799626ebb987fc2a54ad3b85415fdba0e52f583a2a7ee3` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/evaluation.json` | ARTIFACT | 257 | `772ff6bedc55a5715386a81103e7851b21cbf02988c0e57bf853be1f91b92882` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `71e24eb1a403c463b40fb2b60323a5c8368772b7512cb60cfda64f7fdeff0102` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/continuation-evidence.json` | ARTIFACT | 7497 | `31cdd61f7f76e10b848bde0cc04f3c0e97b3471efd5c1b40347d410028cf251a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/continuation-report.json` | ARTIFACT | 332 | `b239fde0ab37da41c0b3e435484052b98a9f2f2e384633aa0f03a63695803aed` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/execution-state.json` | ARTIFACT | 441 | `c4fa99ed93cebf82b3a098f06e649ebae5d560c613f3f10ab222bc765e15e29e` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/fresh-process-started.json` | RUNTIME | 96 | `90d3ab6837ab91617e34301f50d15066b736eba807ac9d596464a84475d44ff4` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/information.sqlite` | DATABASE | 12288 | `b9fc2088dbdf92038167a50fc7fde43fe6da3ec472ad7f31dc58e866338ea2c8` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/invocation-evidence.jsonl` | RUNTIME | 8587 | `70755fa7392efe06269f12c4ea758ff49e42742cb84ae5255a53b260882bef71` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/old-process-terminated.json` | RUNTIME | 97 | `c4589a890e15a4b8aecc48898cbffb81ff56fdd7a48b9bf902b66e2192408e44` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-B/workspace/physical-change-evidence.json` | ARTIFACT | 468 | `384d3d86d4ac80b81aa922fadda7ac7d395e9af1a739993d0c4ce36951b1088b` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-C/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-C/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-C/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-C/old.stderr.txt` | ARTIFACT | 122 | `78ade214e718bad02840ebbec018691838fe506a117efb562f634b1b237358bf` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-C/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/runs/C-C/physical/entity-E.txt` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |


### RC1 Attempt 4 files

| File | Evidence Type | Bytes | SHA-256 |
|---|---|---:|---|
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/attempt4-summary.json` | ARTIFACT | 7547 | `3507f5a503e15e31fa752f416ca6ca842248b25338e8f86ae785cab0a1f3ce5a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/authorization.json` | ARTIFACT | 484 | `125fc40c8d945c6a8f50d86c5c66296b1814a2d1618c667baaeb8dd299cb4806` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/evidence-audit.json` | ARTIFACT | 431 | `2a953849d85b61938823feb6d1a07ebe20a709086ebfd1872cbd11d6715cc0cd` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/evidence-result-audit.json` | ARTIFACT | 22389 | `e222a40ff8c4e5e871d3b301da1f29de229e6fc451abb71f8a4c19a7773d9614` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/evidence-sha256.txt` | INTEGRITY | 11648 | `bf9b69b510e7db262370a25b6241f6e23a291c173ece7f33c5ee422d790eed15` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/protocol-result.json` | ARTIFACT | 405 | `74ea2abdc4da1ccd97d0c0048e685f651a5885db5a5830dfd91dd230805f5af8` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/run-status.json` | RUNTIME | 228 | `7316d825da15f9992da6f50e848b1ab8b5dd543cd301ee1336dcc011abc8fd88` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/run_manifest.json` | ARTIFACT | 731 | `a26dcfc6ba39e8808247b8eb89b6dbb587a37289d322624c59f22f21973aaf6b` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/arm-summary.json` | ARTIFACT | 1976 | `57852de2909a49dc11525136ae57f7a7037661b2c5651369eae049f05efa0114` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/checkpoint-staging/c645df5b19514b711f075cf1df57442cd6dcee7f9fdaabee8a14f06140118899.json` | ARTIFACT | 278 | `c645df5b19514b711f075cf1df57442cd6dcee7f9fdaabee8a14f06140118899` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/checkpoint-staging/e2466d6afc8c3cd017d4f727f4a86c42767c0bb531f276bbc3bef8071aedf094.json` | ARTIFACT | 279 | `e2466d6afc8c3cd017d4f727f4a86c42767c0bb531f276bbc3bef8071aedf094` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/checkpoint-staging/index.json` | ARTIFACT | 906 | `abf2ff0aee3d9c12824ffe1933c446374f0c77188ec1f9f98fa6724bc140565c` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/evaluation.json` | ARTIFACT | 261 | `734574efb460a13717c61675024dc3618e9f37ec39423c46026a612c49d85c60` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `a59a9702d7c719ba98623e30f539a9eb3086eefbabe3d20584a71297e6f9d427` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/continuation-evidence.json` | ARTIFACT | 6296 | `bdfef557461f8389619d4470e77db9bde2f7f7c9c83ebceaabc7ae763d859661` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/continuation-report.json` | ARTIFACT | 134 | `caffde26c45ee962c3a86993ea54c66c04b6a527b836a6ab981cd1481b0c3e6b` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/execution-state.json` | ARTIFACT | 279 | `e2466d6afc8c3cd017d4f727f4a86c42767c0bb531f276bbc3bef8071aedf094` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/fresh-process-started.json` | RUNTIME | 96 | `1c5616f7796ee855d67a463ee06d59655f4e26142479f0c626026ecd0573f6f9` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/invocation-evidence.jsonl` | RUNTIME | 7624 | `bcd9839d7652d63d162160165f97b6fde2732bcf2facd27e7434564ef38646a9` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/old-process-terminated.json` | RUNTIME | 97 | `a0ebe215b304cd74511e2d77d587ced55c376e32dacb1284676db8effa227ced` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-A/workspace/physical-change-evidence.json` | ARTIFACT | 468 | `ba5c1a5ee6530c06df4ccea6b70b36e142683534fac98c0158acdd736e0b80ca` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/arm-summary.json` | ARTIFACT | 2290 | `d29e8a05b79d81d0c7f9b5e5029d9ba4b5264813201c124eef258e7fffc204b4` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/checkpoint-staging/26b04565a0a692f9bdfe613b3e8f1feeffd7479e5a4f58be66de519b513601e3.json` | ARTIFACT | 348 | `26b04565a0a692f9bdfe613b3e8f1feeffd7479e5a4f58be66de519b513601e3` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/checkpoint-staging/2d4f020e4de4b398007863f7baf36aed60ef2181f9c1a1bb0dfc435b211b4ea5.json` | ARTIFACT | 441 | `2d4f020e4de4b398007863f7baf36aed60ef2181f9c1a1bb0dfc435b211b4ea5` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/checkpoint-staging/7cf64e60721f17430a051e47f239ba12e756b8341843d21d0a2d33bc414de5b3.json` | ARTIFACT | 278 | `7cf64e60721f17430a051e47f239ba12e756b8341843d21d0a2d33bc414de5b3` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/checkpoint-staging/index.json` | ARTIFACT | 1439 | `a3b65cb2ba06e6ced4400f1bc663be1e49f0e5fe7b6e844ae369dc96d8ae311c` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/evaluation.json` | ARTIFACT | 257 | `772ff6bedc55a5715386a81103e7851b21cbf02988c0e57bf853be1f91b92882` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `a595e1eb84351bde5994fb8f715520c69e48b4221b58ebd07db8959c8fdec8d4` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/continuation-evidence.json` | ARTIFACT | 7497 | `480f2aae0c834ef531257065c922a751fa7a50d8e1ede8c08654c5e360d94892` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/continuation-report.json` | ARTIFACT | 332 | `b239fde0ab37da41c0b3e435484052b98a9f2f2e384633aa0f03a63695803aed` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/execution-state.json` | ARTIFACT | 441 | `2d4f020e4de4b398007863f7baf36aed60ef2181f9c1a1bb0dfc435b211b4ea5` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/fresh-process-started.json` | RUNTIME | 96 | `901f3a5400444b621b45d337cbea80b4ddb0395ad367e666ee5a0befd68fb5a7` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/information.sqlite` | DATABASE | 12288 | `83cec786f156745b71b28a00842f3a60386f6d0624343c97b36fe835c5028abf` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/invocation-evidence.jsonl` | RUNTIME | 8587 | `b1557c67acb7e2af199089c38ee5b11266d199bbc8ce562b9e31c2fd65fc5592` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/old-process-terminated.json` | RUNTIME | 97 | `452acaa6ead6ca0ad29388ad035262a7b84f71dca9120e2db23fec3e8cebfe9c` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/physical-change-evidence.json` | ARTIFACT | 468 | `a08a5b589fba0053046f3df320f05b4f3e0490836387a42c19373e0fa1ba7184` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/arm-summary.json` | ARTIFACT | 2308 | `14641bb5986351a86d38b901d7824b864d0d652568c8f1c72c4dd363a856d4bf` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/checkpoint-staging/043daf852a9d914ee258659cbf898a7cb087b0f3709af818c8cb1d410e63fbc6.json` | ARTIFACT | 486 | `043daf852a9d914ee258659cbf898a7cb087b0f3709af818c8cb1d410e63fbc6` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/checkpoint-staging/1d4a88b133f7d8e637567f07b2ac771cfc036ec4efeaca8f1db9eaa6d7dfa0fc.json` | ARTIFACT | 348 | `1d4a88b133f7d8e637567f07b2ac771cfc036ec4efeaca8f1db9eaa6d7dfa0fc` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/checkpoint-staging/40dbd314ca8c82e7cf663f82d935b036ec2e40bb5a3de5d3b9ed98433efc5bd3.json` | ARTIFACT | 278 | `40dbd314ca8c82e7cf663f82d935b036ec2e40bb5a3de5d3b9ed98433efc5bd3` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/checkpoint-staging/index.json` | ARTIFACT | 1457 | `a3dda017d89754bccb4840ba979687f50ced17cb4b074757374f4370bba029f0` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/declared/s0.json` | ARTIFACT | 41 | `3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/declared/s1.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/declared/s1.observed.json` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/declared/task-charter.json` | ARTIFACT | 358 | `dd8f4e78c01aa12137984eca07435ce63fdeaf65c9ed5aa6db3b621804a1d42c` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/evaluation.json` | ARTIFACT | 257 | `772ff6bedc55a5715386a81103e7851b21cbf02988c0e57bf853be1f91b92882` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/old.stderr.txt` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/old.stdout.json` | ARTIFACT | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/physical/entity-E.txt` | ARTIFACT | 42 | `cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/awaiting-external-overwrite.json` | ARTIFACT | 102 | `f2e1a60f9d0185616a58e4abec7e957119755b3668f7d7cb7774fe26125f6369` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/continuation-evidence.json` | ARTIFACT | 8115 | `e0c18083191ab4a1524a6fb3baba1f390109c331a9a8f49f2e43f4657d35d3e9` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/continuation-report.json` | ARTIFACT | 332 | `b239fde0ab37da41c0b3e435484052b98a9f2f2e384633aa0f03a63695803aed` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/execution-state.json` | ARTIFACT | 486 | `043daf852a9d914ee258659cbf898a7cb087b0f3709af818c8cb1d410e63fbc6` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/fresh-process-started.json` | RUNTIME | 96 | `a7255816c65f3c513b4a4d127ca61e9b1fa6685dc172a20387530ebcfc38acfd` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/information.sqlite` | DATABASE | 12288 | `f10b02c6430de2c097ebdec72268c8a280e5e6e634ddd23b897e6554257464a6` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/invocation-evidence.jsonl` | RUNTIME | 8930 | `fbf3be179c55d22680373a6fe747694ac5d9008d7e3a24843c55cabee78a5de4` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/old-process-terminated.json` | RUNTIME | 97 | `59e49b954327345dbd3a586cadfd3653424fc59a95daae1d5bb3c12ab294f024` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/physical-change-evidence.json` | ARTIFACT | 468 | `908474be818caf7f4b583490951d6369270d411c622e771c6d6106c328b09112` |
| `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/relation.json` | ARTIFACT | 459 | `55d7080f518cfcfbc25d95c2a33883168e8ee0f43c09185ac02f0c04349515ff` |


### Key exact evidence pointers


[E001] file: `docs/02-evidence/t4-execution/a-run/db-a.sqlite`
      line/range: table=information; record=1
      type: DATABASE
      exact evidence: identity=9fd1608770a655473b18cddf; produced_at=2026-10-02T16:15:38Z; produced_by=t4ctl; source=ledger.md

[E002] file: `docs/02-evidence/t4-execution/a-run/动作日志.md`
      line/range: 1-4
      type: RUNTIME
      exact evidence: 创建 ledger；调用记忆边界工具逐字存入；identity=9fd1608770a655473b18cddf；登记 todo

[E003] file: `docs/02-evidence/t4-execution/b-e-run/动作日志.md`
      line/range: 1-7
      type: RUNTIME
      exact evidence: fetch 9fd...；生成合同摘要；store f4f.../323...

[E004] file: `docs/02-evidence/t4-execution/b-e-run/db-b-e.sqlite`
      line/range: table=information; rows=1-4
      type: DATABASE
      exact evidence: 9fd..., f4fa3ab1f0aff78b8a2f8afc, 32390793ba4f0098a9bc2e18, 8e4eac7eef6389d32dc3c8e1

[E005] file: `docs/02-evidence/t4-execution/b-n-run/动作日志.md`
      line/range: 1-10
      type: RUNTIME
      exact evidence: target not-found；sentinel 91576421759960b8a6f28fcd；blocker

[E006] file: `docs/02-evidence/t42-execution/a-run/db-a.sqlite`
      line/range: table=information; record=1
      type: DATABASE
      exact evidence: identity=c0da14aabd3d4d22b14cbb2a; source=Release_Plan_REL-56ff.md

[E007] file: `docs/02-evidence/t42-execution/b-e-run/动作日志.md`
      line/range: 1-7
      type: RUNTIME
      exact evidence: 01:06:30 fetch c0d...；01:07:02 record；01:07:10/31 store

[E008] file: `docs/02-evidence/t42-execution/b-n-run/阻塞报告.md`
      line/range: 1-9
      type: ARTIFACT/RUNTIME
      exact evidence: target not-found；不能生成 Production Activation Record

[E009] file: `docs/02-evidence/t5-execution/attempt1/a-run/information.sqlite`
      line/range: table=information; record=1
      type: DATABASE
      exact evidence: identity=a88ec8e16fbd4243aa5adbd8; produced_at=2026-10-03T15:20:08Z

[E010] file: `docs/02-evidence/t5-execution/attempt1/b-e-run/动作日志.md`
      line/range: 1-3
      type: RUNTIME
      exact evidence: four-level dependency chain but three slots；no fake schedule

[E011] file: `docs/02-evidence/t5-execution/attempt1/b-n-run/BLOCKER_REPORT.md`
      line/range: 1-25
      type: ARTIFACT/RUNTIME
      exact evidence: target not-found；DB 0 rows；no schedule

[E012] file: `docs/02-evidence/t5-execution/rev1/a-run/information.sqlite`
      line/range: table=information; record=1
      type: DATABASE
      exact evidence: identity=69c28c24e690d2c294c2b1ad; produced_at=2026-10-03T15:27:26Z

[E013] file: `docs/02-evidence/t5-execution/rev1/b-e-run/Workshop_Final_Schedule.md`
      line/range: 1-23
      type: ARTIFACT
      exact evidence: six rows; SLOT-0222/95D2/176D/0A9332; freeze WIN-8B1DE7

[E014] file: `docs/02-evidence/t5-execution/rev1/b-e-run/information.sqlite`
      line/range: table=information; rows=1-3
      type: DATABASE
      exact evidence: 69c28c24e690d2c294c2b1ad; 618d2991ffe4a8541aecbfa5; 9ef82b67b54b0a43462673a7

[E015] file: `docs/02-evidence/t5-execution/rev1/b-n-run/动作日志.md`
      line/range: 1-11
      type: RUNTIME
      exact evidence: fetch not-found；store blocker 275a137276d0e077dc14f477

[E016] file: `docs/02-evidence/rb1-execution/artifacts/e-run.json`
      line/range: 1
      type: RUNTIME
      exact evidence: pid=34872; InformationStore.store; before=7973612eca7d5e62f6866f18

[E017] file: `docs/02-evidence/rb1-execution/artifacts/x-run.json`
      line/range: 1
      type: RUNTIME
      exact evidence: pid=34906; ExecutionScope.ObservationBaseline.reference; fetch-before;store-after;store-relation

[E018] file: `docs/02-evidence/rb1-execution/artifacts/v-e-run.json`
      line/range: 1
      type: RUNTIME
      exact evidence: fetch_sequence=relation->after->before; exact S0→S1 answer

[E019] file: `docs/02-evidence/rb1-execution/artifacts/v-n-run.json`
      line/range: 1
      type: RUNTIME
      exact evidence: answer=null; blocker=relation-not-found

[E020] file: `docs/02-evidence/rb1-execution/artifacts/post-run-checks.txt`
      line/range: 1-20
      type: TEST_OUTPUT
      exact evidence: 20 PASS lines including machine_checks=PASS

[E021] file: `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/protocol-result.json`
      line/range: 1-23
      type: RUNTIME/ARTIFACT
      exact evidence: execution_integrity=VALID; C-A partial; C-B/C-C full; overall=VALID_THREE_ARM_EXECUTION_COMPLETED

[E022] file: `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-B/workspace/execution-state.json`
      line/range: 1-14
      type: ARTIFACT
      exact evidence: pointers task/s0/s1/progress; lifecycle=POST_CHANGE_OBSERVED

[E023] file: `docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375/runs/C-C/workspace/relation.json`
      line/range: 1-10
      type: ARTIFACT/DATABASE
      exact evidence: after -> observed-change-of -> before

[E024] file: `docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791/run-status.txt`
      line/range: 1-15
      type: RUNTIME
      exact evidence: C-B_old crash; INVALID_INCONCLUSIVE

[E025] file: `docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860/run-status.txt`
      line/range: 1-14
      type: RUNTIME
      exact evidence: C-B full; C-C stopped; INVALID_INCONCLUSIVE
