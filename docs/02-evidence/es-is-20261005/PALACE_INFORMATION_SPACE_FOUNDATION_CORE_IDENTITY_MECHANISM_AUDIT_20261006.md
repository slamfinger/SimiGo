# InformationCore / RelationCore Identity Mechanism Audit

Date: 2026-10-06  
Status: `DELIVERED / AWAITING HUMAN REVIEW`  
Seam: `IS-IDLOC-SEAM-01 / v0.1`  
Scope: `READ-ONLY SOURCE AUDIT · NO IMPLEMENTATION · NO CONTRACT CHANGE`  
Frozen Contracts: `UNCHANGED`  
Audited tree: `HEAD @94f27c1`

## 1. Question

Do existing InformationCore, RelationCore, and Store mechanisms already provide
the substrate required by the mature identity / revision / locator / history
model, or is the remaining work genuinely higher-layer semantics?

## 2. Existing mechanisms found

| Mechanism | Existing implementation | Audit result |
|---|---|---|
| Opaque identity | `InformationID.rawValue` is opaque; identity recipes remain mechanism-side. | PRESENT |
| Immutable Information | `Information` is immutable; `store` is idempotent first-write-wins; no update path. | PRESENT |
| Identity-referencing relations | `Relation.subject` and `Relation.object` use `InformationID`, not path strings. | PRESENT |
| Backend indirection | `InformationStore` is a protocol with SQLite and InMemory implementations. | PRESENT |
| Filing separation | SQLite `PhysicalFiling` is optional storage metadata and does not surface on `Information`. | PARTIAL PRESENT |
| Relation identity | Relation identity is deterministically minted from subject/predicate/object. | PRESENT |
| Revision model | No revision, successor, predecessor, or version surface exists. | NOT PRESENT |
| Locator layer | No current locator resolver over carrier/commit/path/digest exists. | NOT PRESENT |
| Historical pin | No first-class historical pin object or pin-resolution API exists. | NOT PRESENT |
| Representation availability | No detached / unavailable / tombstone distinction exists; absence is nil. | NOT PRESENT |
| Semantic applicability | No applicability, validity, membership, judgment, or ES-access semantics exist. | NOT PRESENT / HIGHER LAYER |

## 3. Important details

### Stable identity

`InformationID` is deliberately opaque, and `Information` stores no recipe or
hash surface. This matches the required separation between identity and
mechanism.

However, current minting recipes derive identity from content and source-formation
facts:

```text
SQLiteStore:
  content + provenance.source + position.chunkIndex

InMemoryStore:
  backend namespace + content + provenance.source + position.chunkIndex
```

Therefore current identity is closer to a formed-fact / representation-formation
identity than a durable logical entity identity that persists across arbitrary
source refiling or semantic revision. Cross-recipe identity equivalence is
already out of current scope.

### Physical filing

SQLite can persist optional `filing_wing` and `filing_room`. These are explicit
organizational fields and do not appear on `Information`. This is a useful precedent
for keeping locator/filing metadata out of the semantic value, but it is not a
current locator resolver.

### Relations

Relations already reference endpoints by `InformationID`; they do not reference
paths. This is the correct substrate for logical relations. Relation identity is
deterministic and first-write-wins, but there is no relation revision or temporal
validity model.

### History and absence

Stores preserve immutable stored facts and expose absence as `nil`. This prevents
accidental mutation, but it does not distinguish:

```text
Information does not exist
Information exists but current representation is unavailable
Information exists but is outside current Information Space
Information exists but is not accessible to current Execution State
```

Those distinctions belong to higher-layer semantics, not the current minimal
store boundary.

## 4. Mapping to mature systems

| Mature mechanism | Existing SimiGo substrate | Gap classification |
|---|---|---|
| Stable ID ≠ path | Opaque `InformationID`; relations use IDs. | Substrate present; durable logical-entity semantics unresolved. |
| Immutable revision | Immutable Information; first-write-wins stores. | Immutable value present; revision/succession absent. |
| Content digest | Identity minting uses SHA-256-derived truncated digest inputs. | Mechanism present, but no explicit representation-digest contract. |
| Locator indirection | Optional SQLite filing fields; backend protocol. | Store separation present; general locator layer absent. |
| Historical pin | Immutable rows plus external Git commits. | Pin is implicit/external, not first-class. |
| Semantic identity continuity | Not present. | SimiGo higher-layer question. |
| Applicability / membership / ES access | Not present. | SimiGo higher-layer question. |

## 5. Audit verdict

```text
InformationCore / RelationCore / Store
  already provide:
    opaque formed-fact identity,
    immutable value storage,
    identity-based relations,
    backend-boundary separation,
    and partial filing/locator separation.

They do not provide:
    logical-entity revision succession,
    general representation locator resolution,
    first-class historical pins,
    representation availability semantics,
    or Information Space membership / applicability semantics.
```

Therefore the narrow claim is:

```text
Do not add a database layer or mutate InformationCore now.
The remaining work is a higher-layer semantic mapping over existing substrate.
```

This does not reopen the accepted Core Sufficiency Audit. That audit was bounded
to the current PRQ-ISF-01 continuation domain. This audit is a new, narrower
mechanism-mapping audit for IS-IDLOC-SEAM-01.

## 6. Non-claims

```text
No implementation is proposed.
No Store primitive is declared necessary.
No backend is selected.
No current contract is changed.
No experiment or repository reorganization is authorized.
No universal Information Space claim is made.
```
