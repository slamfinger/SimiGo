# R0: Environment & Instrumentation Audit — Design

日期：2026-10-01
状态：`DESIGN / AWAITING IMPLEMENTATION`
前置：P6 FROZEN, Replication Audit Phase-1 计划已发布
性质：实验基础设施，非研究结论

---

## R0-1 Execution Authenticity

每次实验由 `ReplicationAuditRunner` 统一管理：

```text
启动 → 生成 runUUID（audit-YYYYMMDD-xxxxxxxx）
     → 记录 git commit / model hash / checkpoint hash
     → 执行实验
     → 写入 artifacts
     → 完成 → 记录 finishedAt
```

禁止：无 runUUID 的实验结果。

## R0-2 Artifact Isolation

目录结构（每次执行独立）：

```text
results/replication/{runUUID}/
  ├── metadata.json
  ├── execution.jsonl
  ├── summary.json
  └── hashes.json
```

metadata.json 内容：

```json
{
  "runUUID": "audit-20261001-xxxxxxxx",
  "gitCommit": "abc1234",
  "gitDirty": false,
  "modelHash": "sha256:...",
  "checkpointHash": "sha256:...",
  "configHash": "sha256:...",
  "backend": "mlx|llama",
  "startedAt": "2026-10-01T13:00:00Z",
  "finishedAt": "2026-10-01T13:05:00Z"
}
```

## R0-3 Runtime Evidence（事件流）

execution.jsonl（JSONL，按时间序追加）：

```jsonl
{"event":"run_start","runUUID":"...","monotonic_ns":0}
{"event":"model_load_start","monotonic_ns":...}
{"event":"model_load_complete","duration_ms":4500,"monotonic_ns":...}
{"event":"restore_start","monotonic_ns":...}
{"event":"restore_complete","position":21,"duration_ms":350,"monotonic_ns":...}
{"event":"generate_start","monotonic_ns":...}
{"event":"generate_complete","tokens":24,"duration_ms":1200,"monotonic_ns":...}
{"event":"checkpoint_start","monotonic_ns":...}
{"event":"checkpoint_complete","duration_ms":200,"monotonic_ns":...}
{"event":"run_complete","verdict":"...","monotonic_ns":...}
```

## R0-4 Time Integrity

双时钟：

```swift
let clock = ContinuousClock()
let start = clock.now
// ... operation
let elapsed = clock.now - start
```

墙钟仅辅助阅读。顺序由 monotonic_ns 保证。

## R0-5 Source Integrity

```swift
// 实验开始时记录
let gitCommit = shell("git rev-parse HEAD")
let gitDirty = !shell("git diff --stat").isEmpty
let gitStatus = shell("git status --short")
```

写入 metadata.json。非 clean 状态必须显式标记。

## R0-6 Dependency Isolation

```json
{
  "mlx": {
    "MLX": "gitRevisionOrVersion",
    "MLXLMCommon": "...",
    "MLXLLM": "...",
    "Tokenizers": "..."
  },
  "llama": {
    "binaryHash": "sha256:...",
    "modelFileHash": "sha256:...",
    "adapterCommit": "..."
  }
}
```

## R0-7 Rerun Test

同一 harness 连续两次：

```text
Run A → results/replication/{runUUID-A}/
Run B → results/complication/{runUUID-B}/
```

比较：
- execution path 一致（事件序列相同）
- invariant 判定一致
- artifact schema 一致

不要求 token / 时间完全一致。

## R0 通过标准

| 项 | 要求 |
|---|---|
| UUID 隔离 | 每次执行独立目录 |
| 无旧 artifact 读取 | 结果只来自当前 runUUID |
| runtime trace 完整 | execution.jsonl 包含完整事件流 |
| commit 可追溯 | metadata.json 含 git commit + dirty status |
| backend 依赖记录 | metadata.json 含框架版本 |
| 双运行一致 | Run A 和 Run B 的 execution path + invariant 一致 |
