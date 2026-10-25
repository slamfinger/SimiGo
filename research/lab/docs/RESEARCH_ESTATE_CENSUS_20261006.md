# Research Estate Census — 2026-10-06

Status: PHASE-1 CENSUS / BASELINE AUDIT ONLY  
Base: `27bc8053e34117497f4979995f7f7ad70a180a65`  
Manifest: `docs/RESEARCH_ESTATE_CENSUS_20261006.tsv`

## 1. Purpose and boundary

This census makes the existing Git research estate visible to a fresh agent. It
does not create a database, move files, reinterpret history, rerun experiments,
or change the authority of `docs/RESEARCH_STATE.md`.

The machine manifest was generated from every Git-tracked path. For each path it
records type, byte size, HEAD blob identity, top/secondary group, date token
found in the path, coarse research-line hints, text-discovery hits, and an
orphan-candidate flag. Git blob and history remain the provenance authority.

## 2. Scale

```text
TRACKED_FILES = 3402
TEXT_DISCOVERY_MATCHED_FILES = 2580
ORPHAN_CANDIDATES = 2427
ORPHAN_CANDIDATE_BYTES = 20,663,013
```

Top-level distribution:

| Top group | Files |
|---|---:|
| docs | 2684 |
| simigo2-experimental | 486 |
| trackE-residency | 80 |
| boundary-study | 59 |
| trackD-memory | 47 |
| trackB-execution-state | 18 |
| repository root | 12 |
| tools | 6 |
| exp06-roofline | 4 |
| pre-research | 4 |
| runtime2-skeleton | 1 |
| trackA-kernel | 1 |

Dominant text/data types include 1713 JSON, 920 Markdown, 365 TXT, 172 Swift,
92 Python, 52 JSONL, and 24 binary files. A path date is present for 2576 files;
826 have no date token in the path and require history or document context for
dating.

## 3. Discovery method

The whole-tree text scan searched for the plan's discovery vocabulary:
`Execution State`, `Information Space`, `PALACE`, `MemPalace`, `Information`,
`IPAC`, `continuation`, `research`, `experiment`, `evidence`, `finding`,
`decision`, `closure`, `freeze`, `sealed`, `paused`, `closed`, `open`, `next`,
`ruling`, `gate`, `result`, `L0`, `L1`, `L2`, `L3`, `L4`, `summary`,
`checkpoint`, `recovery`, `capsule`, and `context`.

The match column is a discovery aid, not a relevance rating. A miss does not
prove a file is nonresearch; JSON, images, and binaries may still be evidence.

## 4. Orphan-candidate rule

`orphan_candidate=YES` means the basename was not found in the selected
recovery/navigation set: current L0, current State, Archive Index, Session
Entry, continuity entry, capsule directory, and the primary governance
registers. It is deliberately conservative and can produce false positives when
navigation uses a stem without the extension or when a parent document covers a
directory.

Therefore the label means:

```text
ORPHAN / NEEDS REVIEW — not a deletion, move, or low-value judgment.
```

The full candidate list is in the manifest. Do not act on individual candidates
without first locating an authoritative line document, ruling, or evidence
parent.

## 5. Initial research-line map

This map is an orientation derived from the census and existing governance
entry points. It does not alter any registered status.

| Line / area | Primary physical entries | Current orientation at baseline |
|---|---|---|
| ES ↔ IS core | `docs/RESEARCH_CONTEXT_INDEX.md`, `docs/RESEARCH_STATE.md`, `docs/research-capsules/v1` | Active core; current recovery route is Path A / Information Space Foundation. |
| I-1 / I-1c / I-1d | Capsules C04-C06; governance contracts and evidence | Frozen/accepted chain registered in L0 and State. |
| PRQ-ISF-01 | Evidence under `docs/02-evidence/es-is-20261005`; C08-C09 | Probe accepted/closed; no independent carrier tested. |
| Carrier studies | PICS-01 and CCVS-01 evidence under `docs/02-evidence/es-is-20261005` | PICS-01 bounded pass/closed; CCVS-01 Phase C authorized/in progress. |
| Palace V2 / durable information | `docs/02-evidence/palace-*`, C14, governance records | Historical closed research; not current active route. |
| MemPalace feasibility | `docs/02-evidence/es-is-20261005`, State | As-is NO-GO for direct PRQ-ISF-01 carrier; retained historical negative evidence. |
| Folder Information / InformationCore experiment | `folder-information-initialization-20261004`, C12 | Historical/bounded/stopped; no Lab-wide database mandate. |
| Local Closure / Information Reduction | `docs/02-evidence/local-execution-information-closure`, C15 | Bounded research evidence; authority remains in L2/L3 records. |
| Boundary Study / EXP1-X1 / Y | `boundary-study` | Paused / historical work-position material; do not infer completion. |
| Execution State / runtime identity | `trackB-execution-state`, governance runtime chain, State | Historical closed/frozen evidence. |
| Residency / Track E | `trackE-residency` | Closed/sealed/archived historical line. |
| Architecture 2.0 / pre-research | `docs/07-history`, `pre-research`, historical docs | Historical direction and provenance, not current authority. |
| CCVS implementation assets | `simigo2-experimental` | Authorized Phase C assets plus broader experimental history; status must come from State, not path age. |

## 6. Immediate coverage finding

The estate has a strong core recovery path, but it is not yet a full estate
recovery layer:

1. The formal layer model is L0-L3.
2. Fifteen capsules cover key nodes, but no capsule coverage index exists.
3. There is no single global historical map connecting closed, paused, stopped,
   prepared-but-unexecuted, and current work.
4. The orphan candidate count is high, confirming that thin L0 plus capsules do
   not yet provide estate-wide visibility.

The next legal recovery-layer artifact is a coverage map and global orientation
summary derived from this census, not another information experiment.
