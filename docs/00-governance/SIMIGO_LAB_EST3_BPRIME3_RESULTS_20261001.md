# ES-T3 T3-B′-3 Results — Observable-Surface Differential

日期：2026-10-01  
状态：`BPRIME3_EXECUTED / OBSERVABILITY_SURFACE_ESTABLISHED / NULL-DIFFERENCE-UNDER-CURRENT-PROBES`  
授权：human 2026-10-01 三裁定（Lab `5108427`，授权文档
`SIMIGO_LAB_EST3_BPRIME3_AUTHORIZATION_20261001.md`，预注册读数
P-1/P-2/P-3 先于执行锁定）  
执行：`Palace1EST3BPrime3ObservableSurfaceTests.swift`（产品仓，xcodebuild
`-enableCodeCoverage NO` 惯用跑法）；四 cell {b0,b3}×{listing,summary}
逐 cell 独立 `loadSessionCache` restore；greedy（temperature 0，
maxTokens 128）；`tools: nil` 同 B′-2；观测 `bprime3-observations-20261001.jsonl`
（已落库）。

## 1. P-1 观测面判定（listing 对，B′-2 逐字 probe）——CONFIRMED

```text
b0-listing: text=0 字符 | toolCalls=1 | generationTokens=64 | stream=NORMAL
b3-listing: text=0 字符 | toolCalls=1 | generationTokens=64 | stream=NORMAL
tool_call_0（双侧逐字相同）:
  Bash {"command":"find /Users/mr.simi/Desktop/参考文件 -type f -o -type d | sort",
        "description":"递归列出参考文件下所有文件和目录"}
```

**B′-2 的「0 文本」谜底实测揭晓：产物走了 tool-call 通道**（64 token
的 Bash 调用被 vendor 流解析为 `.toolCall` 事件，B′-2 观测面只捕获
`onChunk` 文本故见 0）。两个混淆变量同时坐实：①观测截断（本轮挂载
`onToolCall` + `usage.generationTokens` 后 64 tokens 可见）；②probe
命中会话既有工具模式（find/列目录 = E3 会话历史的 assistant
tool_calls 模式，B′-2 限制文档的疑似机制升级为实测）。P-1 三分支
命中第一支；第二支（过滤吞没）与第三支（零生成）本轮未出现。

附带：tool-call 通道上 b0/b3 亦逐字恒等（同一调用、64/64 tokens）——
GDN 零化在该通道同样未产生差异。

## 2. P-2 差分判定（summary 对，E3-C0 逐字 probe）——恒等（限缩读数）

```text
b0-summary: 43 字符 ANCHORED 文本 | toolCalls=0 | generationTokens=24
b3-summary: 43 字符，与 b0 逐字相同      | toolCalls=0 | generationTokens=24
43 字符：「这个会话在查看桌面文件结构，逐步浏览了"参考文件"目录下
          的"项目部管理制度汇编"内容。」
```

按授权文档 §4 强制限制条款读数：**当前 probe（本样本、greedy、
summary 型）下未观察到 GDN 差异**——不得升格为「GDN 不参与
continuation」。

## 3. P-3 锚定 sanity——PASS（附带观察，不升格）

summary-b0 的 43 字符与 E3-C0（KV 缺席的 meta-only 管线）响应**逐字
一致**。跨管线文本恒等附带支持既有定位（E3：summary 内容由
transcript/history 承载），不做新机制声明。

## 4. 综合判读（B′ 线现状）

```text
✔ 可观测面已建立：text + toolCalls + token 计数三通道挂载后，
  「b0/b3 差异」已能进入观测面——本轮在该面上观测到的是【差异不存在】
  （两 probe 型 × 两通道 × token 计数，四 cell 全恒等）
✔ B′-2 EXECUTED-UNINFORMATIVE 的机制基础由「疑似」升格为实测
✘ 解释 A（state 未挂载/本路径未消费）与解释 B（挂载但对此 probe
  不敏感）仍双未决：恒等在 A 下必然、在 B 下=不敏感，观测无法分离；
  B′-1 源码强不利证据（newCache(parameters:) 无 state 参数）仍偏向 A，
  本轮不改变双未决状态
```

**下一动作归 human**：B′ 续（更强扰动面 / 多 probe 族 / 多会话样本）
或 B′ 封存（登记 A/B 双未决 + 源码偏向 A）。Gate C/D 保持 LOCKED。

## 5. 诚实边界

```text
✔ 单样本（5401315f/Qwen3-Next/Nail）+ 两 probe 型 + greedy——非普适
✔ finishReason 本栈无暴露面；以 onToolCall + usage.generationTokens +
  stream_end 作功能替代（本轮四 cell stream_end 全 NORMAL）
✔ Gate B b2 的「DIFFERS」判定面同为 text-only；其结论不受本轮颠覆
  （b2 产物面与 b0 不同本身成立），但 b2 的非文本通道内容未观测——
  登记不重开
✔ 隔离：restore/rollforward 关；真实 ~/.simigo 未动；
  branch-checkpoints 204→204；prefix-pool 2→2（delta 0）
✔ fixture 取证：b0/b3 cacheSHA256 不同（5ce9dcbd… vs 204952e6…），
  history 均 17——两侧确为不同内容工件
```
