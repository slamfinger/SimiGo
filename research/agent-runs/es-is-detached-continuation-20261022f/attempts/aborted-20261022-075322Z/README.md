# Aborted attempt (preserved, not evidence for a condition)

This attempt ran under the same trust root and stopped before the six conditions were complete. Recorded cause: the previous pass completed all six conditions OBSERVED, but afterwards the executionID API was refactored back to a non-breaking shape (static executionID kept, instance taskExecutionID) so the committed Swift test target compiles; the conditions were re-executed against the delivered binaries so the run evidence is bound to the delivered source build. The earlier pass is preserved verbatim in this archive.

The raw per-process evidence, lifecycles, databases and logs are kept verbatim below; nothing was deleted or rewritten. The run that follows this archive is the first attempt that executes the six conditions end to end.
