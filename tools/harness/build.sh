#!/bin/bash
# SimiGo 协议层回归骨架编译（P0 验收矩阵 + 自包含回归场景）。
# 场景: normal | cancel | disconnect | cancel_requeue | p0（需真实 app 运行于 :8000）
# usage: tools/harness/build.sh && tools/harness/harness <场景>
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
OUT="${HARNESS_OUT:-$DIR/.build}"
mkdir -p "$OUT"
swiftc -swift-version 5 -o "$OUT/harness" \
    "$DIR/main.swift" \
    "$ROOT/SimiGo/Protocol/HTTPServer.swift" \
    "$ROOT/SimiGo/Protocol/HTTPServerChat.swift" \
    "$ROOT/SimiGo/Protocol/HTTPServerCompletions.swift" \
    "$ROOT/SimiGo/Protocol/HTTPServerResponses.swift" \
    "$ROOT/SimiGo/Lifecycle/RuntimeLifecycle.swift" \
    "$ROOT/SimiGo/Observability/TraceLogger.swift" \
    "$ROOT/SimiGo/Lifecycle/RuntimeTuning.swift" \
    "$ROOT/SimiGo/Model/TypesBridge.swift" \
    "$ROOT/SimiGo/Model/ModelTypes.swift"
echo "BUILD OK: $OUT/harness"
