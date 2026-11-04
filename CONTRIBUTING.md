# Contributing to SimiGo

## Scope

Welcome contributions include Contract conformance cases, representation
declarations, backend adapters, execution-state graph features, persistence,
documentation fixes, and evidence reproducibility improvements.

Do not open a pull request that silently changes the frozen Execution State
Contract semantics. A semantic change requires a separate Closure Revision Gate
proposal and explicit human review.

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
xcodebuild test -project SimiGo.xcodeproj -scheme SimiGo \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/test -enableCodeCoverage NO \
  -only-testing:SimiGoTests/ExecutionStateGraphTests
```

Tests are **not** side-effect free by default: the test bundle is loaded into the
real app process (`TEST_HOST`), and the full `SimiGoTests` suite has been measured to
write the real `~/.simigo` (IS WAL/SHM, prefix pool, branch checkpoints,
`logs/native_mlx_trace.log`) unless the roots are overridden. Targeted runs have not
been measured individually and are therefore not assumed safe.

Run the suite through the in-repo runner:

```bash
tools/run_isolated_tests.sh --tag local-run1
```

It creates a fresh isolation root, rewrites the build's xctestrun so that
`SIMIGO_HOME`, `SIMIGO_CACHE_ROOT` and `SIMIGO_STATE_GRAPH_STORE` all point inside
that root, snapshots the protected roots before and after, and diffs them. Evidence
lands in `build/test-isolation/<utc>/` and the app defaults to
`build/test/Build/Products/Debug/SimiGo.app`. It fails closed on an unsafe isolation
root, a plist diff beyond the three roots, a failing or unparsable suite, or any
user-state write outside the isolation root, and it only deletes the isolation root
it created itself. A plain `xcodebuild test` without those three roots is not
equivalent and must not be cited as evidence that the suite leaves user state
untouched.

Do not commit local model paths, Hugging Face caches, device serials, signing
team IDs, DMG files, build products, or model weights.

GitHub Actions runs the open-source audit on every PR. The macOS targeted-test
job uses `macos-26`; while the hosted SDK matrix is being validated, that job is
allowed to fail without marking the workflow red.
