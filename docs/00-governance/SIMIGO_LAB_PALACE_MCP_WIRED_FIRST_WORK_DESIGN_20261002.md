# SimiGo MCP 接入完成 + 首次真实工作实验设计（轨 c）

日期：2026-10-02  
状态：`MCP WIRED & VERIFIED / FIRST-WORK DESIGN REGISTERED`
（c 的执行 = 下一 fresh SimiGo 会话——MCP 配置对当前会话不
生效，新会话自动加载）  
授权：human 优先序裁定（本件 §1 登记）  
前置：MemPalace v0 initialized + 首日碰撞 C-1..C-5（`d8e8cee`）

## 1. 优先序裁定登记（human，2026-10-02）

```text
优先序 = a → c；b 作为伴随观察线；d 继续冻结
  （Y = REGISTERED / NOT STARTED）
最重要的纪律 = a 不等于修 C-5：
  wake-up 的 NaN 噪声原样保留。若 SimiGo 接入后发现
  「PALACE 有 9311 drawers，但我启动时得到的上下文是垃圾」
  ——这是非常有价值的第一手碰撞
C-1..C-5 = substrate defects / collision ledger：记录，不修
  C-1 PDF / C-2 xlsx flatten / C-3 数字查源失真 /
  C-4 会话压过源文档 / C-5 wake-up NaN —— 全部「记录不修」
原则 = 「看起来有问题」≠「必须解决的问题」：
  C-4 人工检索角度看严重，但若 SimiGo 实际工作发现
  「先找到工作会话，再沿来源追到原文」反而很好，就未必按
  现在设想的方式修；反过来某个小问题若直接让 Execution
  无法继续，那才是真优先
两线不混 = 本线回答「一个真实 Information Space 能不能先
  成为 SimiGo 的工作基础设施」；Y 线回答「Information Space
  到底在哪里无法承载 Execution State」
```

## 2. MCP 接入记录（a = 完成事实）

```text
接入 = 项目级 .mcp.json（SimiGo-Lab 根，ZCode 新会话自动加载）
服务器 = mempalace-mcp --palace palace-v0/palace
  （env HOME 隔离至 palace-v0/mp-home；非 --read-only——
  写回是轨 c 的组成部分）
端到端验证（JSONRPC stdio 实调）：
  initialize OK（server = mempalace）
  tools/list = 44 工具全谱：mempalace_search / get_drawer /
    list_drawers（读）+ add_drawer / update_drawer /
    diary_write / event_append / event_list / task_create /
    kg_add / kg_supersede / artifact_put / checkpoint / mine /
    sync（写回）+ kg_query / traverse / hallways / tunnels
    （图）+ patch_submit
  mempalace_search 实调 OK：「水稳场站建设 遗留事项」命中，
    带源标注，7,127 字节
备选 = mempalace-light-mcp（3 合并工具）登记不切换；
  44 工具的 schema token 成本本身是后续观察点
C-5 保留不修 = wake-up 噪声将进入 SimiGo 启动上下文 =
  预期碰撞点（观察 SimiGo 是否/如何感知并报告它）
```

## 3. 轨 c = 首次真实 SimiGo 工作（观察七问，human 原语冻结）

执行模式 = 下一 fresh SimiGo 会话；真实工作任务驱动 PALACE
使用（非检索测试）；完整链 = 需要信息 → MCP → PALACE → 取得
信息 → 模型推理 → 形成判断/工作结果 → 再写回 PALACE。

```text
① SimiGo 会主动搜什么？
② 搜索词是谁形成的？
③ 搜到的是源文件还是历史会话？
④ NaN 噪声会不会干扰模型？
⑤ 模型会不会发现「信息存在但排序不对」？
⑥ 哪些信息被模型认为值得重新写回 PALACE？
⑦ 一次工作完成后，PALACE 里留下的东西是否比原始摄取
   更有用？
补充观察位：
  · C-5 wake-up 噪声是否被感知/报告
  · C-1 PDF 缺口是否在实际工作中被撞上（任务涉及合同
    内容时必然）
  · 写回形态 = SimiGo 自己用 add_drawer / diary_write /
    event_append 写什么、怎么写——不做预注册格式设计
  · 44 工具面上 SimiGo 实际用哪些、绕开哪些
```

## 4. 执行序列

```text
第 0 步 = 任务提名（≥2 真实任务候选，秦沈语料范围内、
  答案可检验）→ human 钉定
→ fresh 会话真实工作（MCP → PALACE 全程自然使用）
→ 观察记录原样落盘（含七问读数 + 碰撞账本更新：
  哪个 C 真的妨碍工作）
→ 写回后 palace 状态对照（⑦）
→ human 判读
```

纪律：不修 MemPalace；不自研 Schema（Schema 由碰撞逼出）；
L0 只读；本文件不构成 PALACE Schema 设计。
