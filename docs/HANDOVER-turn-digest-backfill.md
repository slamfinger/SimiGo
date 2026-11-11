# 交接单：轮次摘要补写（交给另一个 agent 的模型写）

日期 2026-11-11 · 接手方：另一个 agent（用你自己的内置 API / 模型）

## 一、任务

给 `chat_turn_ledger` 里还没有摘要的轮次补写摘要 + 关键词，写进下面三张表：

| 表 | 一行是什么 |
|---|---|
| `turn_digests` | 一轮一条：`digest`（≤300 字）+ `keywords`（空格分隔） |
| `keywords` | 去重后的词表 |
| `turn_keywords` | 轮次与词的关联 |

**不用本地大模型。** 不要调 `http://127.0.0.1:8000`——那是 SimiGo 自己的服务，
调它会把摘要写成一对假问答（历史上这样产生过 796 行，已经标成 `internal`）。
摘要由你用自己的模型写，脚本只负责读写数据库。

当前账（2026-11-11 23:2x）：

| 项 | 数 |
|---|---|
| 轮次账 | 3060 |
| 已有摘要 | 518 |
| 待补 | **2542** |

## 二、两步走

### 第一步：导出待补轮次

```sh
python3 tools/backfill_turn_digests.py --emit /tmp/dg_batch.jsonl --limit 50
```

- 只读，不写库，不调任何模型。
- `--limit` 是批量大小，建议 20–50 一批（一批写完后能单独校验，出问题不牵连全部）。
- `--session "某个会话 id"` 可以只导一个会话。
- 每行一个 JSON：

| 字段 | 含义 |
|---|---|
| `session` / `turn` | 定位键，写回时必须原样带回 |
| `question` | 本轮提问（已截到 1200 字） |
| `answer_fed` | 已按分层规则压过的回答正文，直接拿去写摘要 |
| `layered` | 是否发生过代码层裁剪（true 表示代码体被略去） |
| `answer_chars` | 回答原文长度，用来判断压掉了多少 |

`answer_fed` 已经是投喂形态：散文行全留，每个代码块只留前 6 行，声明行最多 12 条、
报错行最多 8 条，末尾附一行 `【代码概况】N 个代码块，共 M 行；声明：…`。
封顶 1800 字（加代码概况行后会略超，实测约 2085）。

### 第二步：写完再落库

把你写好的结果存成 JSONL，一行一轮，字段：

```json
{"session": "…", "turn": 79, "digest": "…", "keywords": "词1 词2 词3 词4 词5"}
```

```sh
python3 tools/backfill_turn_digests.py --ingest /tmp/dg_batch.done.jsonl \
        --model "agent:<你的名字>"
```

- 写库是幂等的：同一轮重复 ingest 会覆盖。
- 一行失败不影响其它行，会打 `[fail]` 并跳过。
- `digest` 超过 300 字会被截断；`keywords` 超过 8 个只留前 8 个。
- `model` 列写来源标记，建议 `agent:你的名字`，便于以后分辨是谁写的。

## 三、摘要写什么（验收就看这几条）

1. 只写三件事：**这一轮要解决什么 / 结论是什么 / 哪件事明确没做**。
2. 措辞必须跟原文一致：原文是提议就写"提出/建议"，用户认可过才写"已裁定/已定"。
   **用户没认可的一律不许写成"决定"。**
3. 不写"用户说/助手回答"这类套话，不抄原句。
4. 不评价代码完不完整。`layered=true` 时你看到的代码是被裁过的——原文只要有代码块，
   就说明这一轮把代码给出了，**不许写"只给了片段""未提供完整代码"**。
5. 关键词 5–8 个，每个 2–8 字，尽量用原文里出现过的词（以后靠它反查原文）。
6. 具体数字、参数不进摘要（IS 只存归一化索引，要数值回原文取）。

## 四、验收

自动：

```sh
sqlite3 "file:$HOME/.simigo/simigo.sqlite3?mode=ro" \
  "SELECT COUNT(*) FROM chat_turn_ledger l WHERE NOT EXISTS (
     SELECT 1 FROM turn_digests d
      WHERE d.session_id=l.session_id AND d.turn_index=l.turn_index);"
```

应为 0，或只剩已知失败轮次。抽一批看 `model` 列是否都是你写的标记。

人工：随机抽 10 轮对原文，看四件事——三要素在不在、有没有把提议写成决定、
有没有"只给了片段"这类假话、关键词能不能在原文里找到。

## 五、已验证

端到端跑通过 3 轮（`aistudio:Branch of Branch of NativeMLX 推理优化与配置`
的 t79 / t80 / t81），model 标记 `agent:handover-demo`，`turn_digests` 与
`turn_keywords`（每轮 6 个词）都正确落行。这 3 轮已经从待补里消失。

## 六、已知边界

- 长文章（≥8000 字且代码 <20%）：没有代码块就不会裁，会撞 1800 封顶，摘要只看到头尾。
  `answer_chars` 远大于 `answer_fed` 长度时就是这种情况，写的时候留意别把它当全文。
- `turn_digests.created_at` 是「2001-01-01 起秒数」的 `%.17g`，不是 Unix 秒。不要自己写时间。
- 库可能被 App 持有：脚本已设 `busy_timeout=30000`；不要并发跑两个 ingest。
- 不要删改任何历史行；有疑问就留下不写，比写错好。
- 改库前先备份：`sqlite3 ~/.simigo/simigo.sqlite3 ".backup ~/backups/xxx.sqlite3"`。

## 七、不要做的事

- 不要改投喂规则去"让摘要更漂亮"。
- 不要为了省事只写一句"这轮讨论了 X"——那是摘要的字数下限，不是内容下限。
- 不要把同一轮的摘要拆成多条行。
- 不要动 `chat_messages` 的 `turn_state`（已有的 `internal` 标记是有意为之）。
