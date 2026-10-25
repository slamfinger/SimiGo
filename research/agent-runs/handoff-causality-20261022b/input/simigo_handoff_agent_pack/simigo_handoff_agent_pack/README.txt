SimiGo Handoff-Causality autonomous implementation pack

1. Unzip outside the repository, or place these files in a temporary local agent input folder.
2. Open AGENT_TASK.md as the local agent's task prompt. The task explicitly requires source-code implementation and real experiments, not another plan-only response.
3. Before the agent changes source code, run:
   python3 workspace_guard.py snapshot --repo /path/to/SimiGo-Lab --out "$HOME/SimiGo-Agent-Runs/handoff-causality-20261022b/manifests/workspace-before.json"
4. After implementation and runs, run (adjust allow patterns to exact source/test files actually changed):
   python3 workspace_guard.py verify --repo /path/to/SimiGo-Lab \
     --before "$HOME/SimiGo-Agent-Runs/handoff-causality-20261022b/manifests/workspace-before.json" \
     --out "$HOME/SimiGo-Agent-Runs/handoff-causality-20261022b/manifests/workspace-after.json" \
     --allow-change 'simigo2-experimental/Sources/RealModelHandoff/**' \
     --allow-change 'simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift' \
     --allow-change 'simigo2-experimental/Tests/SimiGo2ExperimentalTests/ProductionRuntimeInformationIntegrationTests.swift' \
     --allow-change 'simigo2-experimental/Tests/RealModelHandoffTests/**'

The guard refuses all changes to run-20261022a, docs/02-evidence, docs/00-governance, any G2 path, the restored five SRS-VAL-01 files and docs/09-archive, regardless of the allowlist. It also verifies HEAD/branch/staged-diff remain unchanged. It is read-only and does not restore or alter any file. Review the actual paths before running; update allow globs narrowly if the local source layout differs.

No repository files are included in this pack and no local experiment was run from this hosted environment.
