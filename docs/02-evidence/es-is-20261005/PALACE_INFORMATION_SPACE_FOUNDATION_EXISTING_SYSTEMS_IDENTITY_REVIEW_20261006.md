# Existing Systems Review — Identity, Revision, Locator, and History

Date: 2026-10-06  
Status: `DELIVERED / AWAITING HUMAN REVIEW`  
Seam: `IS-IDLOC-SEAM-01 / v0.1`  
Scope: `EXTERNAL-MECHANISM MAPPING ONLY · NO IMPLEMENTATION · NO BACKEND SELECTION · NO CONTRACT CHANGE`  
Frozen Contracts: `UNCHANGED`

## 1. Purpose

Compare five mature systems only as mechanism references for the registered
identity / representation / locator seam. This review does not select a backend
or define a new schema.

## 2. Semantic comparison

| System | Identity contribution | Revision / history | Locator semantics | Best inheritance for SimiGo |
|---|---|---|---|---|
| Nextcloud | Stable `fileid` is intentionally separate from path and storage metadata. | Current filecache metadata; separate version mechanisms can exist. | `fileid`, storage, path, parent, name, and path hash are cache fields, not one conflated identity. | Stable entity ID decoupled from path; identity-to-location migration must be explicit. |
| Git | Object ID is immutable content-object identity, not semantic document identity. | Commits, trees, and blobs are immutable; commit DAG gives snapshots. | A tree maps names/paths to object IDs in a snapshot. | Immutable representation + historical snapshot substrate. |
| DVC | File hash is content identity for cache purposes. | DVC metadata plus Git represents versions. | Workspace path is separated from content-addressed cache storage. | Content addressing + explicit workspace/location mapping. |
| Noms | Value hash identifies an immutable logical value in a Merkle DAG. | Commit progression preserves prior states. | Dataset is a named pointer into the DAG, not the physical location of a value. | Immutable value + logical pointer + retained history. |
| lakeFS | Logical object identity is not the underlying physical address. | Commits are immutable checkpoints; branches/tags are mutable or named references. | lakeFS paths translate to physical object-store paths; unchanged objects may be reused across versions. | Explicit logical-address ↔ physical-address indirection. |

## 3. Mechanism inventory

```text
DIRECTLY INHERITABLE SUBSTRATE
  stable identifier distinct from path
  immutable revision / value representation
  content or object digest
  locator indirection
  historical pin / commit
  snapshot / history view
  diff / lineage substrate

USEFUL BUT NOT SUFFICIENT AS SEMANTIC IDENTITY
  Git rename/copy similarity detection
  DVC content hash
  Noms value hash
  lakeFS logical address mapping

SIMIGO-SPECIFIC HIGHER-LAYER QUESTIONS
  Information semantic identity
  identity continuity across semantic revision
  Information ↔ Representation relationship
  Information-space membership
  applicability / validity
  judgment and exclusion semantics
  provenance semantics
  semantic lineage
  ES accessibility
  continuation relevance
```

## 4. Primary source basis

Reviewed primary sources:

```text
https://github.com/nextcloud/server/blob/master/lib/private/Files/Cache/Cache.php
https://github.com/nextcloud/server/issues/60611
https://github.com/git/git/blob/master/Documentation/gitdatamodel.adoc
https://github.com/git/git/blob/master/Documentation/git-status.adoc
https://doc.dvc.org/user-guide/project-structure/internal-files
https://github.com/attic-labs/noms/blob/master/doc/intro.md
https://docs.lakefs.io/concepts/internals/
```

Observed basis:

```text
Nextcloud server Cache.php
  cache entry fields include fileid, path, path_hash, storage, parent, and
  name; lookup can be by path or fileid.

Nextcloud issue 60611
  backend/mount changes can orphan metadata if storage_id/fileid mappings are
  not migrated; the issue records fileids as stable identifiers and metadata
  as keyed on them, while asking for a supported remapping interface.

Git data model and git-status documentation
  commits/trees/blobs are immutable; trees map filenames to object IDs;
  rename/copy output is similarity-based status detection.

DVC internal-files documentation
  cache is content-addressable; hashes are calculated from file contents;
  same-content files with different names share one cache object.

Noms technical overview
  values are hashed nodes in a Merkle DAG; chunks are immutable; datasets are
  named pointers; commits preserve history.

lakeFS internals documentation
  lakeFS manages pointers/metadata over an object store; storage namespace is
  physical, lakeFS paths are logical, unchanged objects may map across versions,
  and commits are immutable checkpoints.
```

## 5. Non-claims

```text
No backend is selected.
No system is adopted wholesale.
No new Store schema is proposed.
No InformationCore change is proposed.
No Higher-Layer Charter is opened.
No claim is made that any one system provides SimiGo semantic identity.
```

The review supports only this bounded conclusion:

```text
Mature infrastructure can provide most identity-revision-locator-history
substrate; SimiGo's distinct work is the semantic layer above it.
```
