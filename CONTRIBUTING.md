# Contributing to SimiGo

## Scope

Welcome contributions include Contract conformance cases, representation
declarations, backend adapters, execution-state graph features, persistence,
documentation fixes, and evidence reproducibility improvements.

Changes to externally observable ES / IS / API contracts must be explicit in the
pull request description and include the intended behavior, compatibility impact,
focused tests, and evidence limits. Do not silently change semantics, but do not
assume that a research contract is permanently frozen or that a separate Closure
Revision Gate is required by this guide.

## Licensing

By contributing, you agree that:

- code and executable material are licensed under Apache-2.0;
- documentation and research artifacts are licensed under CC-BY-4.0;
- you have the right to submit the contribution;
- no model weights or personal-machine paths are included.

Keep source-code changes Apache-2.0. Documentation changes are CC-BY-4.0. Do
not add third-party material without identifying its source and license.

## Release hygiene checks

Before opening a pull request, run:

```bash
tools/open_source_audit.sh
tools/run_isolated_tests.sh --tag contributor-check
```

App-hosted tests load the test bundle into the real app process (`TEST_HOST`) and
may write user state. The full `SimiGoTests` suite has been measured to write
the real `~/.simigo` (IS WAL/SHM, prefix pool, branch checkpoints,
`logs/native_mlx_trace.log`) unless roots are overridden. Targeted runs are not
assumed safe unless isolated.

The in-repo runner creates a fresh isolation root, rewrites the build's
xctestrun so that `SIMIGO_HOME`, `SIMIGO_CACHE_ROOT` and
`SIMIGO_STATE_GRAPH_STORE` point inside that root, snapshots protected roots
before and after, and diffs them. Evidence lands in
`build/test-isolation/<utc>/`; the app defaults to
`build/test/Build/Products/Debug/SimiGo.app`. It fails closed on unsafe
isolation, unexpected plist differences, test failure, or user-state writes
outside the isolation root, and only deletes the root it created. A plain
`xcodebuild test` without these overrides is not equivalent and must not be
cited as evidence that tests leave user state untouched.

Do not commit local model paths, Hugging Face caches, device serials, signing
team IDs, DMG files, build products, or model weights.

GitHub Actions runs the open-source audit on every PR. The macOS targeted-test
job uses `macos-26`; while the hosted SDK matrix is being validated, that job
is allowed to fail without marking the workflow red.
