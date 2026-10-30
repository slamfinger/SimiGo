# Open Problems

记录已确认存在、但尚未得到稳定解决的问题。这里只登记，不宣告结论：
已关闭的判定必须另有验收读数，不能因为本文撤下某条就算修复。

当前清单（2026-10-30）。每条都给出可回放入口；没有读数支撑的猜测不进表。

| # | 问题 | 当前状态 | 证据 / 入口 |
|---|---|---|---|
| 1 | IS「可检索」态未在真机观测 | 未关闭 | `docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md` §10：本窗口无同 scope 后续轮，`replay=1` 未出现 |
| 2 | 取消的本地轮没有终止态 | 未关闭（待裁定） | 同上 §10 事实 1：被断连的行停在 `pending`；fail-closed 成立但行状态不再反映请求已死 |
| 3 | 本地路径不写请求身份 | 未关闭（待裁定） | 同上 §10 事实 2：`request_id` / `source_provider` 仅外部转发路径写入 |
| 4 | 外部转发路径缺真机端到端读数 | 未关闭 | 同上 §8：现结论来自代码与隔离测试层，不能替代安装版验收 |
| 5 | Agent 分类取证未完成 | 未关闭 | 同上 §9 末：后台 rollout / 内部记账的 `thread_source` 取值未取；检索资格也未按类别裁定 |
| 6 | W4 预算门冷启动样本未记录 | 路线已裁定撤销；样本污染仍独立未关 | 同上 §8 末条；真机日志 `skip_record reason=model_warmup`。owner 2026-10-30 裁定不做 prefill 时间门控：`docs/decisions/ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md`。不得以「新窗口没有样本」判定已修复 |
| 7 | 取消→重试与冷 prefill 时长不匹配 | 未关闭（裁定已定，实现已落地 build 31，待真机验收） | `docs/lessons/cancel-mid-prefill-poisoned-session-2026-09-17.md`：取消后前缀被驱逐，重试从头冷算；替代方向见上述 ADR（断连=detach，手动取消仍生效；detached 轮记 recorded、不自动提交；孤儿上限 1 为并发化前过渡） |

使用规则：

- 一条问题只有在取得「修复前 / 修复后」同窗口读数后才移出本表，并在对应
  `docs/audit/` 或 `docs/experiments/` 落地证据。
- 冻结证据（`docs/audit/`、`docs/experiments/`、`docs/benchmarks/`、`docs/lessons/`、
  `research/`）不得因精简而删除；本表只索引，不复制其内容。
- 新增条目建议包含：Problem / Known constraints / Current evidence /
  Competing hypotheses / Next experiment。
