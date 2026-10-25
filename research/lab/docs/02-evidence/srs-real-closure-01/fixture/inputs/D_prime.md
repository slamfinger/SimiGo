# Dependency Document D-prime (fixture seed, round 1)

Content of record: the N1 negative-control dependency. This document differs
from D byte-wise by construction. It is materialized as a NEW
content-addressed object by the `mutate-n1` step; the current-dependency
resolution mapping then resolves "D-1" to D-prime (revision 2). The original
D object and the original SRS record remain immutable; the SRS continues to
pin D, which is exactly the pinned-vs-current mismatch N1 must expose.
