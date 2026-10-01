# PALACE V2 G0 中间观察 ② — MemPalace 运行时实测（RQ-1 / RQ-3 / RQ-7）

日期：2026-10-02  
状态：`INTERMEDIATE OBSERVATION #2 / MEMPALACE / RUNTIME AUDIT`  
**FROZEN（human 2026-10-02：MemPalace Observation Set 冻结——不作 PALACE 设计结论）**  
环境：隔离沙箱（HOME 重定向 `.build/mp-home`；venv Python 3.12；
mempalace[extract] PyPI 安装；模型 all-MiniLM-L6-v2 79.3MB 本地 ONNX；
零真实个人数据）  
对象：四格式 fixture（成本测算.xlsx 含双 Sheet+公式 E17=C17*1000 与跨
Sheet 引用 / 商务策划.docx 含标题层级 / 项目汇报.pptx 8 页第 8 页含
关键事实 / 试验室租赁合同.pdf 两页）  
命令链：`init --yes --no-llm --lang zh` → `mine --mode extract` →
`search` → re-mine → 直读 ChromaDB  
协议：G0 Audit Protocol（FROZEN / APPROVED）

## 1. RQ-1 判读 — xlsx 结构保留边界（已获运行时答案）

对 `成本测算.xlsx`（材料量价 Sheet：A1 项目名称/B1 秦沈高速；
A17 物资名称/B17 钢筋/C17 4200/D17 元/t；E17 公式 =C17*1000；
汇总 Sheet：B1 =材料量价!E17）实测：

```text
[O] Sheet 名保留      = 「## 材料量价」「## 汇总」成为 Markdown 标题
[O] Cell 坐标丢失     = 内容为无坐标 Markdown 表；B17/C17/D17 位置
                        压缩消失，行内容左移错位（物资名称落在
                        「项目名称」列位、钢筋落在「秦沈高速」列位
                        ——列语义破坏）
[O] 公式丢失          = E17 =C17*1000 完全缺席；跨 Sheet 引用
                        =材料量价!E17 同样缺席（汇总表仅剩「合计」）
[O] NaN 噪声          = 行 2–16 的 15 个空行以
                        「| NaN | NaN | NaN | NaN |」形式进入正文
                        ——数据模型污染进入检索语料
[O] 数值本身保留      = 4200 / 480 / 元/t 均在
```

**RQ-1 结论（Observation 级）**：Sheet 层可溯源；Cell/Formula/
列对应关系在 MarkItDown 转换层丢失。协议 §6 预警的压平风险
**运行时坐实**。对人工作场景的含义（Inference，bounded）：E5 级
溯源（Sheet2!B17）与 E3 级跨表比较在纯 MemPalace 路径上无支撑——
正是 G3 需要回答的缺口形态。

## 2. RQ-7 判读 — Source Trace Depth（各格式最深回溯粒度）

```text
[O] docx = 标题/段落级（# 标题结构保留；docx 无页概念）
[O] xlsx = 仅 Sheet 级（## 表头）；Cell 级无
[O] pptx = Slide 级（「<!-- Slide number: 8 -->」注释标记保留——
    第 8 页钢筋采购事实可归属到页）
[O] pdf  = 页级分隔可见（"Page 1" 标记）；⚠️ fixture 限制：报告脚本
    用 Helvetica 无 CJK 字形，PDF 内中文本身即乱码（提取结果
    「nnnn… 426 nnn」），故「MemPalace 对 CJK PDF 的提取能力」
    本次未获有效观测——两说都不成立，需 CID 字体 fixture 复测
[O] 端用户检索输出（mempalace search）的 provenance 深度 =
    wing / hall / Source 文件名 + 双通道分数——行号在 metadata
    有（line_start/line_end），但指向 Markdown 表示层行号，
    非原件坐标
```

**RQ-7 结论**：回溯链 Answer → drawer → source_file 全通；
原件内位置粒度 = docx 段落 / pptx 页 / pdf 页 / xlsx 仅 Sheet。
元数据 17 键实测清单：added_by / chunk_index / content_date /
content_date_source / entities（仅部分文件出现——实体检测命中
不对称）/ extract_mode / filed_at / hall / id_recipe / ingest_mode /
last_modified / line_end / line_start / normalize_version / room /
source_file / source_mtime / wing。

## 3. RQ-3 判读 — 重 mine 确定性

```text
[O] 二次 mine --mode extract：Files seen 4 / extracted 0 /
    skipped 4 / drawers +0——未变更文件按 source_mtime 跳过，
    drawer 总数稳定 4，零重复
[O] id_recipe 元数据键暗示确定性 drawer ID 推导
[O] 未测部分（留 E6）：变更文件后新旧 drawer 是替换还是共存；
    dedup 后备路径实际触发条件
```

**RQ-3 结论**：增量 = mtime 跳过式；确定性成立（同输入零漂移）。

## 4. Database Inspection 实测补充

```text
[O] palace 目录实存 = chroma.sqlite3（212KB）+ HNSW 二件套
    （data_level0.bin/length.bin）+ mempalace_embedder.json
    ——单 collection mempalace_drawers
[O] 删库恢复实测（协议 §5 核心问的快速验证）：删除 palace 目录后
    重 mine 可完整重建（L1 转换 + L2 抽取全链重跑；确定性见 RQ-3）
    ——即 MemPalace 侧无「仅存于记忆、不可由 L0 重建」的事实；
    L2 的全部价值 = 预计算加速，非语义增量
[I] 推断：这直接呼应 V1 暂存问题——该架构里 identity/lineage 层
    「不需要」的前提 = 摄取是纯函数。E6 若暴露非纯函数点
    （LLM closet / KG 抽取），前提动摇
```

## 5. Capability Matrix 修订（运行时修正静态判读）

```text
Ingestion/原文保存     = 修正：库内为 L1 转换文本，非「原件 verbatim」
                        （README verbatim 指「不摘要不改写」，
                        指文本表示忠实，非字节级保存）
Retrieval/keyword      = 确认（BM25 通道实测扛住中文关键词命中：
                        cosine 0.19 低、bm25 0.783 高——英文 embedding
                        模型下 BM25 是中文场景主力，Inference）
Context/provenance     = 确认 drawer 级；粒度上限见 §2
```

## 6. 新增 Open Questions

```text
OQ-A  CJK PDF 提取（CID 字体 fixture 复测）
OQ-B  变更文件 re-mine 的新旧版本语义（E6 前置）
OQ-1  维持：closet/KG 抽取确定性与模型依赖
```

**中间观察 ② 状态**：RQ-1/RQ-3/RQ-7 已答；MemPalace 审计主体完成。
下一步依序：Mem0 源码级审计 → Graphiti 源码级审计（各交付独立
中间观察）→ G0 结论门（AUDIT_RESULT 九节）。
