# PALACE 真实工作实验 T1 — 执行登记（human 钉定）

日期：2026-10-02  
状态：`T1 PINNED / AWAITING FRESH-SESSION EXECUTION`
（fresh 会话由 human 在桌面端开启——见 §2 技术事实）  
前置：轨 c 修正登记（ZCode = 执行主体，`7d6bcd3`）+ MCP 接线
与验证（`9bb97ba`）

## 1. 钉定（human，2026-10-02）

```text
Task = T1（0308 数据澄清函）
理由（human）= 不是 T1「最好」，而是它目前最能把「过去的信息
  是否真的成为当前工作的基础」撞出来：
  当前任务 = 0308 原始文件 + 过去已完成的 B 工作
           （12 条遗留 + 28 项核查证据 + 判断依据）
  → 数据澄清函
  不使用 PALACE 仍可能完成浅版，但无法自然获得 B 已形成
  的那层工作成果——落差本身就是实验结果
cwd = palace-v0/workspace/（不选 Lab 仓根：仓根是潜在信息
  替代源，即使不用 MCP 也可能绕过 PALACE 找到答案，会污染
  观察③「PALACE 是不是工作记忆的实际来源」）
源文件直接访问 = 允许（否则是人为逼迫 Agent 使用 PALACE；
  要观察的是「当 PALACE 真正拥有过去工作、本地也有原始
  资料时，ZCode 会不会主动把 PALACE 当成工作记忆」）
Agent = ZCode / Session = fresh / MCP = MemPalace 3.10.0 /
  SimiGo = 不在链中
Instruction = zero PALACE leakage——不出现：PALACE/MemPalace/
  memory/previous work/search history/「请先查已有工作」/
  任何预期答案；只给做什么、输入在哪、交付什么、输出放哪
C-1..C-5 = 记录，不预修；Y = 冻结
双向有效（不预判）=
  若 ZCode 主动找到过去的工作并站在其上继续 → PALACE 第一
  次真正表现出「工作记忆」的性质；
  若完全不用 PALACE 直接完成任务 → 同样非常有价值（说明
  对这类任务，当前信息空间尚未形成足够强的使用理由）
```

## 2. 技术事实与执行方式

```text
探针实测 = 本会话派生的新子代理看不到 mempalace 工具
  （NONE）——MCP 为会话级加载，本会话启动早于 .mcp.json
  接线；桌面端 App 二进制无 headless CLI 入口
⇒ fresh 会话 = human 在桌面端新开会话（cwd = 
  palace-v0/workspace/）并粘贴 §3 任务指令
工作区接线 = palace-v0/workspace/.mcp.json（仓根同内容副本，
  保证 cwd 级 MCP 发现；首次加载客户端可能请求确认，需
  approve mempalace server）
palace 基线快照（第⑦问对照用）= 9,362 drawers：
  秦沈-标后预算 general 9,232 + documents 4 /
  秦沈-经济商务汇报 general 75 / 秦沈-工作会话 technical 51
```

## 3. 任务指令（fresh 会话粘贴用，逐字）

```text
任务：为《秦沈项目经济运行情况汇报（2026-03-08 版）》编制一份《数据澄清函》。

该汇报将由项目部提交上级，其中部分数据在文件内部无法裁定是否存在口径问题，需要编制人确认后再定稿。

要求：
1. 通读该汇报，找出所有「文件内部无法判定、需要编制人确认」的数据问题；
2. 每条问题记录：问题描述、文件内证据（两处原文，注明章节位置）、可能的解释（2–3 个候选）、建议向编制人提问的方式；
3. 按重要程度排序，形成正式《数据澄清函》文档。

输入文件：
/Users/mr.simi/Desktop/26.秦沈项目/08.会议与汇报/02.经济与商务汇报/秦沈项目经济运行情况汇报_20260308.docx

交付：《数据澄清函》保存到你的当前工作目录。

纪律：不得修改输入文件。
```

泄漏自检 = 无 PALACE/MemPalace/memory/previous work/search/
历史工作暗示/预期答案；仅 做什么/输入在哪/交付什么/输出放哪。

## 4. 观察与读数（执行后，记录者职责）

```text
动作链 = rollout JSONL 仪器提取（EXP1 同法；mempalace_* 
  工具调用直接可见）
七问读数 + 补充位 = C-5 wake-up 噪声是否被感知报告 / C-1 
  PDF 缺口是否被撞上 / 写回形态（add_drawer/diary_write/
  event_append 用了什么） / 44 工具用弃谱
第⑦问对照 = 写回后 palace status vs 基线 9,362
交付物审计 = 《数据澄清函》对照 B 的 12 条遗留清单——
  继承覆盖度 vs 重发现（落差读数）
碰撞账本更新（哪个 C 真的妨碍工作）→ human 判读
```
