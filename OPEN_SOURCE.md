# SimiGo Open Source Boundary

SimiGo uses an open research/core / bounded product structure. The current
public repository contains the research specification, reference runtime,
conformance material, and the v2.1 Execution State reference app.

## Asset layers

| Layer | Access | License | Boundary |
|---|---|---|---|
| Execution State Contract, research documents, evidence records | Open | CC-BY-4.0 | Attribution; no automatic endorsement |
| Runtime, adapters, conformance code, v2.1 reference app | Open | Apache-2.0 | Commercial use, forks, and derivative implementations are allowed |
| Future hosted, enterprise, management, and support products | Not in this repository | Separate commercial terms | May be offered independently |
| Proprietary backend integrations | Not necessarily in this repository | Separate commercial terms | Must conform to a published Representation Declaration |

## What this license permits

External researchers and vendors may implement the frozen Execution State
Contract, build alternate representations, run conformance suites, fork the
runtime, and use those implementations commercially, subject to Apache-2.0.
This is intentional: independent implementations strengthen the contract.

## What is not licensed

- The `SimiGo` name, logo, and official-project identity are not licensed by
  the code license. See `TRADEMARKS.md`.
- Hosted, enterprise, support, and future commercial components are not granted
  by this repository unless explicitly stated.
- Model weights never belong to SimiGo. This repository ships no model weights;
  users must obtain each model under its own license.

## Public evidence boundary

The repository may show that an implementation passed a version-pinned test
battery. It does not change Contract semantics or turn bounded evidence into
universal, backend-independent, or mathematically minimal claims.
