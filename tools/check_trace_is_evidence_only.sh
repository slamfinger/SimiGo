#!/bin/sh
# trace 日志是外部证据，不是运行期输入（2026-11-06 纪律检查）。
#
# 允许：RuntimeTraceLogger 写日志；EnvManager 生成人看的 `tail -f` 命令。
# 禁止：任何产品源码读取 logs/ 下的文件、或把 trace 文本当作判断依据。
# 进程内状态请用 RuntimeLifecycleCoordinator.snapshot()；
# 跨进程状态请读 state/runtime.json。
set -eu
cd "$(dirname "$0")/.."

bad=$(grep -rn --include="*.swift" "native_mlx_trace" SimiGo/ \
      | grep -v "Observability/TraceLogger.swift" \
      | grep -v "System/EnvManager.swift" \
      | grep -vE ':[0-9]+:[[:space:]]*//' || true)
if [ -n "$bad" ]; then
  echo "FAIL: 产品源码引用了 trace 日志路径"
  echo "$bad"
  exit 1
fi

bad=$(grep -rn --include="*.swift" -E "contentsOfFile|forReadingAtPath|String\(contentsOf" SimiGo/ \
      | grep -iE "logs|trace" || true)
if [ -n "$bad" ]; then
  echo "FAIL: 产品源码读取日志文件"
  echo "$bad"
  exit 1
fi

echo "PASS: trace 日志在产品源码中只写不读"

# 测试侧的 trace 读取是「真机证据」，不是运行期输入。它不是零成本债务：
# 日志格式一改、行一降噪，断言就静默失效。允许保留的只有已登记的真机电池；
# 出现新的读取方就 fail，逼着先想清楚该读哪个结构化面。
allowed="
SimiGoTests/CancelPathSupport.swift
SimiGoTests/RealModelStreamingCancelRetryE2ETests.swift
SimiGoTests/BranchFork/BranchForkTests.swift
SimiGoTests/GenerationCompletionRealModelE2ETests.swift
SimiGoTests/GovernedContinuationKVRestoreRealModelE2ETests.swift
SimiGoTests/LiveSessionCeilingEvictionRealModelTests.swift
SimiGoTests/SessionAdoptionE2ETests.swift
SimiGoTests/ToolEchoContinuationRealModelE2ETests.swift
"
# 只看真正读文件/解析文本的用法；`CancelTrace.shortID` 是纯字符串工具。
readers=$(grep -rn --include="*.swift" -E \
  "native_mlx_trace|CancelTrace\.(size|lines|window|count|waitForLine|token|timestamp|shortArriveID)" \
  SimiGoTests/ \
  | grep -vE ':[0-9]+:[[:space:]]*//' \
  | cut -d: -f1 | sort -u || true)
unexpected=""
for file in $readers; do
  case "$(printf '%s\n' "$allowed")" in
    *"$file"*) ;;
    *) unexpected="$unexpected$file\n" ;;
  esac
done
if [ -n "$unexpected" ]; then
  echo "FAIL: 未登记的测试文件在解析 trace 文本（请改用结构化读数，或登记理由）"
  printf '%b' "$unexpected"
  exit 1
fi
echo "PASS: trace 读取方都在登记清单内（$(printf '%s\n' $readers | wc -l | tr -d ' ') 个真机电池）"
