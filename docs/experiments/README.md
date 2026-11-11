# 实验索引

本目录保存实验方案、原始观察与结论边界。证据原件留在各实验文件及其登记位置；本索引不复制结果。

## 阅读原则

- 实验通过只支持其明确范围，不自动成为产品能力或架构不变量。
- 区分设计登记、执行、观察、结论和后续授权。
- 历史实验保持原样；当前状态以实验正文、代码和实际证据为准。
- 文件名、状态标签或不同目录位置不构成独立证据；需核对样本、来源、协议和基线是否重叠。

## 主要入口

- [EVOLUTION_TRACK.md](EVOLUTION_TRACK.md)：归档的 Batch → Paged/Block KV → Continuous Serving 路线。是历史参考，不是当前实现说明或开发授权。
- [OFFICIAL_CAPABILITY_MATRIX.md](OFFICIAL_CAPABILITY_MATRIX.md)：2026-09-12 指定 mlx-swift-lm revision 的能力快照，不是当前能力矩阵。
- [MODEL_COMPATIBILITY_MATRIX.md](MODEL_COMPATIBILITY_MATRIX.md)：2026-09-11 指定 build / 模型 / 依赖组合的兼容性快照。
- [C2 Session Readiness Matrix](C2_SESSION_READINESS_MATRIX_20260922.md)：历史预注册方案；该文件本身不包含执行结果。
- [EXECUTION_FORK_F0_PROBE_20260918.md](EXECUTION_FORK_F0_PROBE_20260918.md)：Execution Fork F0 探针。该实验已执行，结果见 [F0 Results](EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md)；旧索引的“未动工”状态已过期。
- [Upstream issue #629 submission archive](UPSTREAM_ISSUE_SUBMISSION_READY.md)：2026-09-19 的提交内容快照；提交时 OPEN 不代表当前上游状态。
- [ESIS gap closure（2026-11-10）](ESIS_GAP_CLOSURE_20261110/README.md)：载体独立性 SIGKILL→冷启动→零调用消费、intake paired trials、图增长与 E1/E2 四臂。全部 n=1，结论边界见正文「本目录不主张的事」。
- [GGUF D6 KV invalidation（2026-11-10）](GGUF_D6_KV_INVALIDATION_20261110/README.md)：槽擦除 / sleep-wake / RAM cache 缺席 / 引擎重启后，续接靠 IS 取回的值继续（真机 4 臂，`cached_tokens=0`）；无原始日志，读数按提交信息转写。

## 其他实验

- [Long-context field observation](FIELD_OBSERVATION_20260913_LONG_CONTEXT_TASK.md)：v1.2、指定模型与机器上的单任务现场观察。
- [Branch-fork roll-forward exploration](BRANCH_FORK_ROLLFORWARD_EXPLORATION_20260918.md)：历史设计探索与待验证推论，不是当前开发计划。
- [V1.7 Runtime Matrix](V17_RUNTIME_MATRIX/README.md)：历史 Runtime / Residency 实验矩阵。
- [Benchmarks](../benchmarks/README.md)：单项性能与 fork / roll-forward 测量档案。

新实验入口应链接研究问题、协议、实际证据和结论；不为重复报告增加额外文档。
