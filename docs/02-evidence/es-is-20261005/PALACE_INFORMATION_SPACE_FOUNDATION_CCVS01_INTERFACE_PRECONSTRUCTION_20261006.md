# CCVS-01 — Carrier-Neutral Interface Preconstruction

Date: 2026-10-06  
Status: `DELIVERED / AWAITING HUMAN REVIEW`  
Study: `CCVS-01 — Carrier Candidate & Performance Validation Study`  
Predecessor deliverable: `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEA_DESIGN_20261006.md`  
Frozen Contracts: `UNCHANGED`  
InformationCore / RelationCore: `UNCHANGED`  
Scope: `CARRIER-NEUTRAL INTERFACE PRECONSTRUCTION ONLY · NO BACKEND ADAPTER · NO OSS INTEGRATION · NO DATABASE SCHEMA · NO BENCHMARK EXECUTION · NO MIGRATION`

## 1. Authorization boundary

Human authorized preconstruction of the carrier-neutral interface layer so all
future candidates can be evaluated through the same operations, conformance
checks, and metric collection.

Allowed:

```text
protocols;
DTOs and opaque carrier IDs;
dependency-injected composition root;
fake/memory implementation for tests only;
conformance suite;
benchmark harness;
metrics collector.
```

Forbidden and absent:

```text
SQLite-specific adapter;
PostgreSQL-specific adapter;
DAG-specific persistence adapter;
graph database schema;
object-store layout;
actual OSS integration;
database schema or DDL;
migration;
production index.
```

## 2. Implemented carrier responsibilities

| CCVS responsibility | Interface |
|---|---|
| C1 Entity Representation Store | `EntityRepresentationStore` |
| C2 Information Registry | `InformationRegistry` |
| C3 Locator / File Index | `LocatorIndex` |
| C4 Relation / History | `RelationHistoryStore` |
| C5 Session Information | `SessionInformationStore` |
| C6 Derived Search Index | `DerivedSearchIndex` |
| C7 Availability / Integrity | `AvailabilityStore`, `CarrierIntegrityReporter` |
| C8 Carrier ↔ SimiGo Interface | `CarrierExecutionInterface` |

`CarrierExecutionInterface` exposes:

```text
resolve
produce
consume
pin
continuationContext
```

It does not execute IPAC, applicability, validity, judgment, or continuation
reasoning. It only returns/exposes identity, revision, representation, locator,
pin, and availability facts.

## 3. Dependency-injected composition root

`CarrierComposition` injects:

```text
registry
representation store
locator index
relation/history store
session store
derived search index
availability store
```

`InformationSpaceRuntime` sequences operations across these boundaries. It does
not make cross-component transaction semantics universal; those differences are
part of what future candidates must expose and be measured for.

## 4. Fake implementation

`MemoryCarrier*` types provide an in-memory fake carrier only. They are not a
candidate backend, production implementation, or database selection.

They allow the interface, conformance suite, and harness to compile and run
without choosing a real carrier.

## 5. Conformance suite

`CarrierConformanceSuite` currently checks:

```text
locator move preserves Information identity;
revision preserves historical representation;
delete changes availability without destroying representation;
historical pin remains stable across locator change;
session event order is preserved;
search rebuild preserves retrieval equivalence;
C8 exposes continuation facts without semantic judgment.
```

A separate integrity test checks that an orphan representation is detected and
that adding locator plus availability clears the fake-carrier integrity report.

## 6. Benchmark preparation

`CarrierBenchmarkHarness` defines a common operation sequence over the injected
runtime:

```text
create
move
revise
session append
relation append
search
```

`CarrierBenchmarkPlan` defines `SMALL`, `MEDIUM`, `LARGE`, and `STRESS`
recommended sizes. `CarrierMetricsCollector` records operation latency samples
and computes count, errors, P50, P95, P99, max, and total.

No benchmark was executed for candidate validation. Swift tests only exercised
interface correctness and metrics arithmetic.

## 7. Verification

```text
swift build --target CarrierInterface       = PASS
swift test --filter CarrierInterfaceTests   = PASS
swift test (trackD-memory)                  = PASS
```

No backend-specific term, adapter, schema, or storage layout appears in
`Sources/CarrierInterface` or `Tests/CarrierInterfaceTests`.

## 8. Non-claims

```text
No carrier architecture is selected.
No benchmark result exists.
No candidate is validated.
No production carrier exists.
No Information Space completeness claim is made.
No Frozen Contract is changed.
No InformationCore or RelationCore API is changed.
```
