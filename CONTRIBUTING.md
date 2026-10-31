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

## Release hygiene and package checks

Before opening a pull request, run the public-tree audit and the isolated
Qoder collection package tests:

```bash
tools/open_source_audit.sh
swift test --package-path Packages/SimiGoCollection --filter SimiGoCollectionTests
```

The collection package test target is a required macOS CI job. It tests the
read-only transcript collector, durable inbox, cursor recovery, and delivery
semantics without loading the App test host. It does not establish the separate
real-Qoder/App quit-and-relaunch lifecycle acceptance.

The App-hosted Execution State tests remain subject to the isolation procedure
below. Do not run them against the default user roots.

```bash
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

It creates a fresh isolation root and rewrites the build's xctestrun so that
`SIMIGO_HOME`, `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE` and
`QODER_PROJECTS_DIR` all point inside it. The Qoder collector therefore scans only
the isolated `qoder-projects/` directory during App tests; it never tails the real
`~/.qoder-cn/projects` tree. The harness snapshots and diffs the protected roots
before and after, including `~/.simigo`, the SimiGo Application Support root, and
the app preference plists (`~/Library/Preferences/SwiftUI.SimiGo.plist` and the
short-name `SimiGo.plist`). Evidence lands in `build/test-isolation/<utc>/` and the app
defaults to `build/test/Build/Products/Debug/SimiGo.app`. It fails closed on an
unsafe isolation root, a plist diff beyond the four injected roots and explicitly
requested target opt-ins, a failing or unparsable suite, or any user-state write
outside the isolation root. It only deletes the isolation root it created itself.
A plain `xcodebuild test` without those four roots is not equivalent and must not
be cited as evidence that the suite leaves user state untouched.

Target-specific experiment switches are opt-in and allowlisted. Pass them only for
the relevant XCTest target, for example:

```bash
tools/run_isolated_tests.sh --tag prefix-checkpoints \
  --only SimiGoTests/KVFreeContinuityTests \
  --target-env SimiGoTests:SIMIGO_PREFIX_POOL=1 \
  --target-env SimiGoTests:SIMIGO_BRANCH_CHECKPOINTS=1

tools/run_isolated_tests.sh --tag tool-echo-budget \
  --only SimiGoTests/ToolEchoContinuationRealModelE2ETests \
  --target-env SimiGoTests:SIMIGO_REQUEST_BUDGET_MS=0
```

The runner accepts only `SIMIGO_PREFIX_POOL=1`, `SIMIGO_BRANCH_CHECKPOINTS=1` and
`SIMIGO_REQUEST_BUDGET_MS=0`; it does not change product defaults, and it refuses
an unknown XCTest target or a conflicting pre-existing xctestrun value. Each
injected opt-in is recorded in `xctestrun_isolation.json`.

Do not commit local model paths, Hugging Face caches, device serials, signing
team IDs, DMG files, build products, or model weights.

GitHub Actions runs the open-source audit on every PR. The macOS targeted-test
job uses `macos-26`; while the hosted SDK matrix is being validated, that job is
allowed to fail without marking the workflow red.
