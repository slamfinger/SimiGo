# Workshop Dependency Plan

Plan identity: Workshop_Dependency_Plan.md

## Six-workshop inventory

| Workshop | Enrollment | Prerequisites |
|---|---:|---|
| WS-3FAB94 | 29 | None |
| WS-C36165 | 21 | WS-3FAB94 |
| WS-C7B0F0 | 21 | WS-C36165 |
| WS-394151 | 10 | WS-3FAB94 |
| WS-ED9D08 | 30 | WS-C7B0F0, WS-394151 |
| WS-70677C | 30 | WS-C36165 |

## Room inventory

| Room | Capacity |
|---|---:|
| RM-CDB7 | 48 |
| RM-5446 | 30 |
| RM-8A08 | 21 |

## Eligible room sets

| Workshop | Enrollment | Eligible rooms |
|---|---:|---|
| WS-3FAB94 | 29 | RM-CDB7, RM-5446 |
| WS-C36165 | 21 | RM-CDB7, RM-5446, RM-8A08 |
| WS-C7B0F0 | 21 | RM-CDB7, RM-5446, RM-8A08 |
| WS-394151 | 10 | RM-CDB7, RM-5446, RM-8A08 |
| WS-ED9D08 | 30 | RM-CDB7, RM-5446 |
| WS-70677C | 30 | RM-CDB7, RM-5446 |

## Prerequisite edges

| Prerequisite | Workshop |
|---|---|
| WS-3FAB94 | WS-C36165 |
| WS-C36165 | WS-C7B0F0 |
| WS-3FAB94 | WS-394151 |
| WS-C7B0F0 | WS-ED9D08 |
| WS-394151 | WS-ED9D08 |
| WS-C36165 | WS-70677C |

## Dependency levels

| Level | Workshops |
|---|---|
| L1 | WS-3FAB94 |
| L2 | WS-C36165, WS-394151 |
| L3 | WS-C7B0F0, WS-70677C |
| L4 | WS-ED9D08 |

## Ordered slots

| Slot | Time |
|---|---|
| SLOT-0222 | 09:30 |
| SLOT-95D2 | 11:00 |
| SLOT-176D | 14:00 |
| SLOT-0A9332 | 16:00 |

## Freeze window

WIN-8B1DE7 = frozen
