# Equivalence observation plan draft

This draft prepares, but does not execute, the future equivalence campaign.

## Observation points

```text
O0 after empty initialization;
O1 after materialize;
O2 after ES1;
O3 after ES2 REUSE + continuation;
O4 after mutate-n1;
O5 after ESN BLOCK.
```

## Required observations at every point

```text
logical object set;
object bytes and SHA256;
logical index records and append order;
dependency history and append order;
LAST-entry current resolution;
read results;
transaction/visibility state;
absence of extra semantic state.
```

## Comparisons against document-form EXEC-006

```text
D object bytes = 806fffa…;
D' object bytes = 8553f524…;
SRS object bytes = 26025863…;
continuation object bytes = 1703f2d6…;
dependency history:
  D-1 revision 1 initial;
  D-1 revision 2 N1 advance;
ES2 REUSE;
ESN BLOCK;
ES1 U ledger = 1;
ES2/ESN U ledgers = 0.
```

A future plan must record all observations, not only final decisions.

## Stop

This draft does not authorize a campaign. It is preparation only.
