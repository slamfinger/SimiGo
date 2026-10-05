# PALACE / Information Space Foundation — Carrier Path Decision

Date: 2026-10-05  
Status: `HUMAN RULING COMPLETE · CARRIER PATH A SELECTED · MEMPALACE LOCAL FILE-BACKED CORE = FIRST INDEPENDENT CANDIDATE CARRIER`  
Prior PRQ-ISF-01 execution: `ACCEPTED / CLOSED` at `547df19`  
Route research question: still `INDETERMINATE / NO-INDEPENDENT-CARRIER-UNDER-TEST` until the selected candidate is tested  
Frozen Contracts: `UNCHANGED`  
Current phase guard: `READ-ONLY FEASIBILITY AUDIT ONLY · NO ADAPTER IMPLEMENTATION · NO CARRIER INTEGRATION · NO PROBE EXECUTION AGAINST MEMPALACE · NO CONTRACT CHANGE · NO EXPERIMENT`

## 1. Ruling

Human selected Carrier Path **A**.

```text
Carrier Path                = A / select independent candidate carrier
Independent candidate       = MemPalace local file-backed core
Role                        = first independent carrier under test
Selection meaning           = candidate selected for feasibility audit
Carrier validation meaning  = NOT YET ESTABLISHED
Next entry                  = MemPalace IS-MCI Adapter Feasibility Audit
```

This selection does **not** mean MemPalace has been validated. It means MemPalace
is now the first independent candidate whose native capabilities will be audited
against `IS-MCI-01..08`.

## 2. Candidate definition

The selected candidate is the **MemPalace local file-backed core**, treated as an
independent Information Space carrier candidate.

It is not:

```text
an MCP server
a knowledge base product
a database schema
a production PALACE application
a semantic search layer
an Execution State carrier
a future adapter API
```

The exact audit specimen, version, configuration, and read-only snapshot boundary
must be pinned at the start of the feasibility audit. If the existing local
MemPalace instance is inspected, the audit must preserve its independence and
must not modify it to fit the probe.

## 3. Why this candidate was selected

MemPalace was selected as the first candidate because it is independently real,
locally file-backed, and historically observed, while its deterministic core does
not inherently require semantic inference.

This is not a claim that MemPalace can satisfy the obligations. Its selection is
precisely the way to expose whether native capabilities, adapter boundaries, or
gaps exist.

## 4. Next entry

```text
MemPalace IS-MCI Adapter Feasibility Audit
```

The audit must classify each obligation as one of:

```text
DIRECT    native MemPalace capability already satisfies the obligation
ADAPTER   a thin, explicitly registered mapping could satisfy it without
          semantic inference or probe-side repair
GAP       native MemPalace cannot satisfy it; adding capability would be a
          carrier modification or semantic oracle and must not be done here
```

Obligations to audit:

```text
IS-MCI-01  immutable content
IS-MCI-02  canonical records
IS-MCI-03  typed references
IS-MCI-04  separated provenance
IS-MCI-05  pinning and historical retrieval
IS-MCI-06  evolution events
IS-MCI-07  traversable lineage
IS-MCI-08  mechanical failure discipline
```

For each item, the audit must record:

1. the native MemPalace surface or absence;
2. whether it is `DIRECT`, `ADAPTER`, or `GAP`;
3. the exact evidence path;
4. any semantic-oracle risk;
5. any candidate-modification risk;
6. whether the item can participate in `PRQ-ISF-01`.

## 5. Forbidden inferences

The feasibility audit must not conclude that:

- MemPalace is validated as an Information Space carrier;
- semantic search satisfies identity resolution;
- LLM-derived summaries satisfy canonical content;
- semantic inference satisfies lineage;
- fuzzy retrieval satisfies historical pinning;
- automatic completion satisfies mechanical failure discipline;
- a proposed adapter that changes MemPalace is still an independent MemPalace test;
- Frozen Contracts authorize a MemPalace schema or carrier.

## 6. Authorization boundary

This ruling authorizes only the read-only feasibility audit. It does **not**
authorize:

```text
adapter implementation
MemPalace modification
carrier integration
PRQ-ISF-01 execution against MemPalace
new experiments
backend integration
Frozen Contract change
```

After the audit, Human review decides whether the route proceeds, is revised, or
is paused.
