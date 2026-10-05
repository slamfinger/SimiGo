# IS-IDLOC-SEAM-01 — Identity / Representation / Locator Mechanism Mapping

Date: 2026-10-06  
Status: `REGISTERED / OPEN / NOT FROZEN / REFINED BY HUMAN REVIEW`  
Commission: `REGISTRATION + READ-ONLY EXISTING-MECHANISM AUDIT ONLY`  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Higher-Layer Charter: `NOT AUTHORIZED`  
Frozen Contracts: `UNCHANGED`  
Scope guard: `REGISTRATION + READ-ONLY AUDIT · NO IMPLEMENTATION · NO MIGRATION · NO REORGANIZATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE · NO INFORMATIONCORE CHANGE`

## 1. Registered seam

Human observation after the Path A entry-surface result:

> Physical paths can be locators, but they must not become Information
> Identity. Otherwise repository refiling, renaming, or archival can break a
> logically stable Information Space.

This is registered as an open research seam, not as a frozen conclusion.

Human review subsequently narrowed the task:

> Do not invent a new correspondence theory or database. Map mature identity,
> revision, locator, and history mechanisms onto Information Space, then audit
> whether existing InformationCore / RelationCore / Store mechanisms already
> carry the needed substrate.

```text
SEAM ID = IS-IDLOC-SEAM-01
STATUS  = REGISTERED / OPEN / NOT FROZEN / v0.1
REVIEW  = PALACE_INFORMATION_SPACE_FOUNDATION_EXISTING_SYSTEMS_IDENTITY_REVIEW_20261006.md
AUDIT   = PALACE_INFORMATION_SPACE_FOUNDATION_CORE_IDENTITY_MECHANISM_AUDIT_20261006.md
```

## 2. Candidate distinctions

The seam separates four concepts that must not be collapsed:

```text
Information Identity
  answers: which logical information is this?

Representation Identity
  answers: which exact representation / version of that information is this?

Physical Locator
  answers: where can a representation currently be found?

Historical Pin
  answers: which exact historical representation was used or verified?
```

A proposed non-collapsed relation is:

```text
Logical Information
  ↓ stable identity
InformationID
  ↓ has / had representation
Representation
  ↓ is located by
Carrier + Commit + Path + Content Digest
```

For the Git-backed Lab estate, a path is therefore only part of a locator:

```text
Path = where to find it now.
Path ≠ who the information is.
Path ≠ the logical relation itself.
```

## 3. Narrowed research question

The seam is no longer framed as a general physical-to-logical correspondence
theory. Its practical question is:

```text
Which mature identity / revision / locator / history mechanisms are sufficient
substrate for physical-to-logical correspondence, and which remaining parts are
actually SimiGo-specific higher-layer semantics?
```

The registered review and audit answer only at mapping/audit level. They do not
open implementation work.

## 4. Important boundary cautions

```text
Same path + different digest
  must not automatically imply the same logical information version.

Different path + same digest
  may imply the same representation was refiled, but that must be represented
  explicitly rather than inferred from Git rename detection alone.

Git rename detection
  is a useful heuristic; it is not, by itself, semantic identity assignment.

Content digest
  identifies exact representation bytes for this text-bounded estate; it does
  not automatically define a logical InformationID.
```

## 5. Candidate future validation shape

A later, separately authorized study could use a real controlled refiling as
the experimental condition:

```text
BEFORE
  resolve logical relation by InformationID
  record current locator + historical pin

MOVE / RENAME / ARCHIVE
  do not rewrite semantic relations

AFTER
  resolve current representation through the locator layer
  preserve old pin to exact prior commit/path/digest
  compare logical retrieval and historical verification
```

This validation is not authorized by this registration.

## 6. Non-claims

This registration does not claim that:

```text
a global InformationID system exists;
all existing Lab files require immediate InformationIDs;
paths are forbidden;
directories are semantically meaningless;
the four-way distinction is already frozen;
a refiling experiment is authorized;
Higher-Layer Continuation Graph Semantics is opened.
```

It also does not modify the current PRQ-ISF-01 text-domain ruling or any Frozen
Contract.

## 7. Next gate

No next work is auto-selected.

```text
IS-IDLOC-SEAM-01 remains a registered candidate input.
It may later enter a Higher-Layer scope charter only by explicit Human ruling.
Until then, implementation, migration, reorganization, probe execution, and
experiment remain NOT AUTHORIZED.
```
