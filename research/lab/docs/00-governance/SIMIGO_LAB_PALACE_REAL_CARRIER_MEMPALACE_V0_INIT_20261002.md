# MemPalace v0 初始化与首日观察 — 真实载体轨迹 DAY 1

日期：2026-10-02  
状态：`MEMPALACE V0 INITIALIZED / DAY-1 OBSERVATIONS REGISTERED`  
授权：改轨登记 `SIMIGO_LAB_PALACE_REAL_CARRIER_ROUTE_CHANGE_20261002.md`
（commit `b33f5ed`）  
版本链：mempalace 3.10.0（PyPI，venv Python 3.12.12，与 G0 运行时
审计同一版本链；G0 已知缺口清单 = 本次碰撞预期先验）

## 1. v0 载体事实

```text
Palace 根 = SimiGo-Lab/palace-v0/palace（gitignore；数据不入 git）
隔离 = 独立 HOME（palace-v0/mp-home），与 G0 审计沙箱完全隔离
init = --yes --no-llm --lang zh（无 LLM 依赖，与 G0 同链）
导入真实文件（L0 原位只读摄取，原件未触碰）：
  秦沈-标后预算 wing ← 04.成本与资金/02.标后预算/标后预算成本数据/
    = 41 files OK + 4 SKIP_EXTRACTION_ERROR；9,232 drawers
  秦沈-经济商务汇报 wing ← 08.会议与汇报/02.经济与商务汇报/
    = 13 files OK；75 drawers
导入真实对话（EXP1-X1 真实工作会话记录 4 件）：
  秦沈-工作会话 wing / technical room = 4 files
总量 = 9,311 drawers；re-mine 幂等（mtime 跳过，零重复）
```

## 2. 检索烟雾测试（已知答案查询）

```text
✓ 「水稳场站建设」→ 首位命中 EXP1-会话A 版本差异报告，逐字
   引用差异 5 全文证据（0307/0308 两版原文+单位口径分析）
✓ 「50,384.03 开累批复计量金额」→ 首位命中会话 B 报告
   （bm25 4.891），含 121.48% 绑定推导链
✓ 「遗留事项 需外部核实」→ 首位命中会话 B 工作记录-续
   （cosine 0.682 + bm25 0.963）——工作前沿记录精确可达
✗ 「313,356 完工总收入」→ 首位 = 试验室成本测算 xlsx NaN
   噪声行（cosine 0.291/bm25 0，数字巧合命中）；含该数字的
   D 族汇报 docx 不进前五
✗ 「现场管理费」「2,881.34」「经济运行情况 水稳劳务施工」
   「提质年 专项行动」→ 前五全为会话记录或 xlsx，源 docx
   均不出现
```

## 3. 在场性裁定（直读 palace/chroma.sqlite3）

```text
0308 docx = 14 drawers 在库且内容完整：
  现场管理费 ×2 / 2,881.34 ×1 / 水稳劳务施工 ×2（chroma:document
  层逐条核实）
结论 = 失败在排序层，非缺失层：源文档内容在空间里，
  但检索面在两侧把它埋掉（数字查询被 xlsx 噪声淹没；
  叙词查询被会话记录覆盖）
```

## 4. 碰撞登记（C-1..C-5——human 预期碰撞面的首日实测）

```text
C-1 PDF 摄入全灭 = 4 份 PDF 附件（西岸/东岸顶推方案变更调价 +
  两份专业分包合同）SKIP_EXTRACTION_ERROR——合同与调价内容
  完全不在信息空间（G0 OQ-A CJK PDF 预警的真实语料坐实，
  且比 G0 fixture 更严重：直接报错而非乱码）
C-2 xlsx 压平爆炸 = 41 文件 → 9,232 drawers（~225 抽屉/文件）；
  NaN 噪声行成段进入语料（G0 RQ-1 坐实于真实规模）
C-3 数字检索失真 = 已知在库的承重数字（313,356 / 2,881.34）
  被无关 xlsx 数值巧合挤出前五——「数字查源」在纯
  MemPalace 路径上不可靠（G0 RQ-1 Cell/Formula 丢失的
  检索层后果）
C-4 会话/源文档排序倒挂 = 工作对话记录（叙事丰富）在所有
  查询上压过源文档——对「工作前沿」类查询是优点（前沿
  精确可达），对「源文件到底写了什么」类查询是缺陷
  （源层不可见）——两面性如实登记
C-5 wake-up 通道污染 = L1「ESSENTIAL STORY」~804 tokens 几乎
  全为单一工作簿的 NaN 压平碎片；identity 未配置——
  「让 SimiGo 使用」的入口面当前不可用
正向事实 = 会话/工作记录检索质量优异（工作前沿、判断依据、
  证据引用全部精确可达——X1 的「显式待办/判断+依据结构是
  最强存活形态」发现，在真实载体的检索层得到同样方向性
  支持）；幂等重建成立（G0 RQ-3 延伸到真实规模）
```

## 5. Next（待 human 指示优先序）

```text
a. SimiGo 接入 = mempalace mcp（MCP 通道）——C-5 修复前
   接入意义受限，可与 C-5 处置一起裁定
b. C-1/C-3/C-5 的处置方向观察（原样使用下 SimiGo 实际工作
   会不会绕开/撞上——不预先修 MemPalace，先让碰撞充分暴露）
c. 真实使用阶段：SimiGo/Agent 经 palace 做一次真实工作
   （信息空间质量本身成为实验变量）
d. Boundary Study 轨：Y = ES Boundary Candidate Probe
   （REGISTERED / NOT STARTED，时点归 human）
```

纪律：本文件只记录观察与缺口，不构成 PALACE Schema 设计；
不修改 MemPalace 代码；L0 原件全程未触碰。
