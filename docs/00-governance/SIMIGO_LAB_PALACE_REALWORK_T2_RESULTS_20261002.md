# T2 极小对照终读数 — R1 成立：读路径由任务结构自然激活

Run：`T2 @ sess_fdbd3c2c`（fresh ZCode session，cwd =
palace-v0/workspace/，MCP 45 工具在列）  
日期：2026-10-02  
状态：`RESULTS AT HUMAN`  
判定：**R1 成立（完整形态）**——读路径在任务结构自带历史
依赖时自然激活，且覆盖 pre-execution / mid-execution /
post-execution 三个生命周期阶段。

## 1. 硬事实（rollout 逐条核实）

```text
工具谱 = TodoWrite 3 / Bash 13 / Read 11 / Write 4 / Edit 10 /
  mempalace_search 6 / mempalace_checkpoint 1（共 48 调用/26
  records；除 mempalace 外零其他 MCP 工具）
读向（6 次搜索，两阶段）：
  t1 定位前沿 = 「未完成事项 清单 数据核查 停止点」
             ＋「数据澄清函 17项 问题 核查」（第二轮查询由
             第一轮返回结果长出——搜索词 Agent 迭代形成）
  t8 定向探测 = 「标后预算 利润率 24.46 公司下达」/
             「标后盈利 1,250.15」/「定标总金额 107,697 91笔」/
             「主材 损耗率 标后单价」——在宣布「仍需编制人」
             之前先探空间
写向（1 次）= t21 checkpoint（agent_name=zcode-t2-closeout，
  diary 自述「读conversations(A/B报告)+palace(drawers)+git→
  三源清单合并(B12×T1 17→Q1-Q18)」）
palace 增量 = 9,365 → 9,369（自建 wing_zcode/diary 1 +
  经济商务汇报 wing 下「数据核查收尾」room 2 抽屉）
混合通道 = palace 搜索之外，直读 conversations/ 目录中 B 的
  报告原文（比检索摘要完整）；git 历史可见性被 Agent 自行
  声明并做渠道归因（透明度处理）
交付 = 收尾报告_秦沈0308数据核查_20261002.md + t2-closeout/
  证据底稿（已固化 docs/02-evidence/palace-realwork-t1/，
  报告 SHA256 73f8ef6c…）
```

## 2. 单一问题的答案

```text
问 = 任务本身明确具有历史未完成工作依赖时，Agent 是否自然
     激活 PALACE 的读路径？
答 = 是（R1）。且激活后 palace 的语义角色覆盖三个阶段：
  pre-execution   定位前沿（找到 B 12 条 + T1 17 项）
  mid-execution   定向探测（外部项宣布开放前先探语料——
                  其中 1 项找到文外旁证：4 月平衡报告开累
                  营收 41,348.32（3月末）< 汇报 46,338（自称
                  2025 年末），单调性矛盾证明后者口径非财务
                  营收——palace 语料被用作证据来源）
  post-execution  checkpoint 存档（工作记录 + 收尾报告要点）
对照 T1（self-contained 任务）= palace 仅 post-execution
  archive ⇒ **F-8 精化：palace 的语义角色是任务框架依赖的**
  ——语义在任务结构里，不在工具里。升级问题（「什么条件下
  Information Space 被判断为必要信息来源」）的第一刀答案 =
  任务结构携带对历史未完成工作的依赖
```

## 3. 继承质量（对照 EXP1-B 的 12 条与 T1 的 17 项）

```text
清单合并 = B12 × T1 17 → 18 个问题族（Q1–Q18），逐项有归宿，
  无遗失无悬空；自述已写入报告
复用且核验（非盲信）= 约 40 项可复算关系全部重算全绿——
  B 和 T1 的既有结论无一需要修正；T1 澄清函各「复核计算」
  经重算无误
方法层继承（补上 T1 的缺口）= B 清单指向的元数据专属项
  （修订号 110/115、03-07/04-01、TotalTime 54/33）被本会话
  用自己的解包独立证实——T1 缺失的方法层经记录传递恢复
字节链 = 输入文件 MD5 d12e06ee… 与 T1 checkpoint 登记值一致
  ——三代会话核的是同一份字节级未变文件（palace 记录被用作
  完整性对账）
新发现 6 项 = 三层日期（封面 03-07/文件名 03-08/元数据
  04-01）/质保金 2%·1.5% 精确重建→表2缺8排查方向/损耗率
  收敛为 5 行待核/4.9% 文内候选解释（2,573.26÷53,000.50=
  4.855%≈4.9%）/表5 全需求口径/平衡报告单调性矛盾
```

## 4. 判读（记录者读数）

```text
G-1 R1 成立 = 续作语义由任务结构自然激活（无人工告知查
  palace）——用户裁定预设的「第一次证明」兑现
G-2 生命周期全景（T1→T2 合并）= Information Space 在
  Execution 中的语义地位是任务框架的函数：
  self-contained 任务 → 只剩 post-hoc archive；
  continuation 任务 → pre + mid + post 三段全激活
G-3 继承纪律 = 接手者「站在清单上，但重算每一格」——
  继承 + 验证并行，与 X1 的 B 行为一致；「重推导 vs 继承」
  在真实载体上表现为两者并行而非二选一
G-4 方法层经记录传递 = T1 缺失的元数据取证被 B 的记录
  「点名将方法」后恢复——工作记录的价值再次落在
  「怎么知道的」
G-5 透明度行为 = git 历史可见性自行声明 + 逐证据渠道归因
  + 未审计范围自我圈定——Agent 在多源环境下自发做了
  provenance 式纪律（未被告知）
G-6 诚实限定 = n=1；「提及过去工作存在」即本实验操纵变量
  （by design）；仓库/git 通道在本 cwd 可见，三渠道贡献
  无法完全分离（渠道归因由 Agent 自报，记录者未逐条复核
  归属）；palace 语料内定向探测的「未命中」未做穷尽性验证
```

## 5. 结果门待裁（human）

```text
① R1 判定验收 + G-1..G-6 定性（含 F-8 精化为「任务框架
   依赖」是否采纳）
② 下一步方向候选：
   a. 第三轮：检验激活的必要条件（同续作任务但去掉指令中
      「此前工作」表述，测纯靠空间内容能否激活——激进）
   b. 把 T1/T2 行为证据并入 Boundary Study Y 探针设计
      （读方向语义 = 续作任务的函数，恰好是 Y 的靶心）
   c. 进入「Information Space 在 Execution 生命周期各阶段
      的语义地位」架构讨论（连接 Contract / SimiGo）
   d. 多跑自然任务再归纳
```
