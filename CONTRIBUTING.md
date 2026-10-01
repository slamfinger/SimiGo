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

Do not commit local model paths, Hugging Face caches, device serials, signing
team IDs, DMG files, build products, or model weights.

GitHub Actions runs the open-source audit on every PR. The macOS targeted-test
job uses `macos-26`; while the hosted SDK matrix is being validated, that job is
allowed to fail without marking the workflow red.
