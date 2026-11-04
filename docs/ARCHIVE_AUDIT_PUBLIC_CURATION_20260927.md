# SimiGo Public Archive — Content-Level Audit

Status: PASSED / PUBLIC CURATION COMPLETED
Date: 2026-09-27

## Audit scope

This audit compared the public SimiGo documentation structure with the private SimiGo-Lab research archive, with particular attention to the current Execution State / Runtime line and the final 2026-09-26 validation state.

## Publicity criteria

A document was eligible only when it:

- describes a stable technical result, architecture, invariant, or reproducible validation;
- can stand alone without access to SimiGo-Lab recovery state;
- does not expose internal research-memory, recovery, governance, or personal workflow material;
- does not present superseded hypotheses as current facts;
- does not overclaim backend independence or production GA status.

## Promoted

| Public document | Treatment | Reason |
|---|---|---|
| Execution State Research Story | published | stable research origin and bounded closure |
| Runtime Consistency Contract D1 | curated summary | current Runtime consistency semantics; avoids stale pre-implementation wording |
| Failure Matrix Final | published | final P1=0 verification artifact |
| O6 oversized Execution State validation | published | strongest current oversized-model lifecycle evidence |
| GA-0 Floor Residency Policy | curated summary | final policy ruling, separated from internal gate workflow |

## Kept private

The following classes were deliberately not promoted:

- SimiGo-Lab state/recovery files;
- agent context and research-memory protocols;
- internal experiment registers and dependency maps;
- intermediate/debug/fault-injection logs;
- raw internal gate workflow documents;
- superseded architecture drafts and exploratory attacks;
- Token Ledger gate definition while it remains a pre-implementation gate rather than a stabilized public feature.

## Content-level findings

1. The public repository already has a suitable document taxonomy: architecture, audit, decisions, evolution, experiments, knowledge, lessons, releases, and research.
2. The Lab archive contains substantially more material than the public repository should expose. Most of it is evidence provenance rather than public-facing documentation.
3. The strongest current public evidence is the final Failure Matrix plus O6 oversized validation. These should be treated as evidence, not as claims of GA.
4. D1 needed curation because the original Lab gate document predates its implementation. The public copy therefore states the implemented semantics rather than copying the old review workflow.
5. GA-0 needed curation because the Lab gate document records an open policy choice while the subsequent ruling is TARGET_DEPENDENT. The public copy records the final ruling.

## Result

**PUBLIC ARCHIVE AUDIT: PASS.**

The selected Lab material has been distilled into the existing SimiGo documentation taxonomy. No dependency on the private SimiGo-Lab repository is required for the published documents.