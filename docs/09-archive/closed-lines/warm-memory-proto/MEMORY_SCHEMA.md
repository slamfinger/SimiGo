# 结构化温记忆 Schema v0（原型）

目标：以 checkpoint 血统为依据，把一个已完结会话的工作状态压缩为
**可追溯、可校验、可回退**的结构化记忆，供新 session 以更低上下文
成本恢复关键状态。KV 是执行优化，不是跨会话记忆的唯一载体（架构
原则见 README）。

## 顶层结构

```json
{
  "schema": "simigo.warm-memory.v0",
  "lineage": {
    "storageKey": "default/<uuid>/main",
    "checkpointAt": "2026-10-16T09:40:21Z",
    "cacheSHA256": "<checkpoint 指纹>",
    "messageCount": 83
  },
  "generated": { "at": "...", "model": "...", "windows": 12 },
  "memory": {
    "decisions":   [ { "text": "...", "provenance": [idx, ...] } ],
    "facts":       [ { "text": "...", "provenance": [idx, ...] } ],
    "pending":     [ { "text": "...", "provenance": [idx, ...] } ],
    "constraints": [ { "text": "...", "provenance": [idx, ...] } ],
    "sources":     [ { "idx": 32, "kind": "commit|pr|file|ruling",
                        "ref": "e22a3cab→…→f0ee2083" } ]
  }
}
```

## 字段纪律

- `provenance[].idx` 必须指向原转录（transcript.jsonl）的消息序号；
  每条 memory 项至少一个来源——无来源的项在校验时剔除（可证明性）。
- `sources` 只登记外部可核验引用（commit 链、PR、文件路径），登记时
  保留原文形（不转写），供回退与审计。
- 生成按窗口进行（每窗 ~10 消息），窗口产物合并去重；合并记录保留
  窗口号，任何一条可回放定位。

## 回退契约

以下任一触发时，放弃结构化记忆、回退 Arm A（客户端摘要）或提示按
需读取原始材料：

1. schema 校验失败（缺 lineage / provenance 越界 / 空核心段）；
2. provenance 抽查（≥3 条）与原文不符（quote 不匹配）；
3. 生成窗口覆盖率 < 80%（有窗口失败且未重试成功）。

## 与三项验证的映射

- 更省：`memory` 序列化后的 token 数 vs 客户端摘要（Arm A）token 数。
- 更准：qa_regression.json 在双臂上的 PASS/PARTIAL/FAIL。
- 可追溯可回退：provenance 校验 + 回退契约的触发记录。
