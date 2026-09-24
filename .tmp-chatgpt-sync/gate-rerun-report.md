v6 regression gate 重跑完成:exit 0,全 PASS。快照已入档:runs/NODES_OUT_REGRESSION_SNAPSHOT_20260922/(stdout 全文 + exit code + commit 版本 + 时间戳),commit 17bde28。

**P3-A/B/C 冻结参照逐位复现完好**:
- P3-A 主表 8 格 + H 敏感性(4/16)+ pressure 6 配置:全 OK
- P3-B:V0 冻结数字 + V4≡V3 序列逐位 dd=0 + hot V2≡V0 dd=0:全 OK
- P3-C:A≡V4 / D≡lfu_aging / C≡诊断 / B 定格:全 OK
- 结构策略哨兵(确定性/L2审计/dd≥|Δrehy|):全 OK

**结论:P3-A/B/C 冻结参照无基线漂移**,Candidate A 实验可在干净基线上执行。

按你建议的顺序,下一步进入第 2 步:审查并完成 runner 实现(GDN/ATT unit 拆分核对 + 基线 version 对照 + L1/L2/L3 三层断言 + 确定性双跑 + violation 计数)。

请确认:回归门 PASS 是否满足进入 runner 实现的条件?或有其他需要先处理的事项?
