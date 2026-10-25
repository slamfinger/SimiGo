# Post-run analysis (not run facts)

Everything in this directory was produced **after** the P0 run `20261020T072607Z` finished, by
read-only diagnostics that load no model. The run's own facts live in `../20261020T072607Z/` and
were not modified.

- `identity_enumeration.json` — output of `../diagnostics/identity_enumeration_probe.swift` on the
  frozen artifact directory. It reproduces `EngineModelIdentity.compute`'s enumeration rule and
  shows why the engine's digest is the digest of the empty string while the binding's rows are
  non-empty: all 17 entries are symlinks, and `isRegularFile` is `false` for a symlink.

Interpretation belongs to `../P0_RESULT_20261020.md`; the JSON is raw output.
