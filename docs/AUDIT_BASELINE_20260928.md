# SimiGo Beta 代码审核基线（AUDIT-TREE PIN）— 2026-09-28

按既定纪律（beta.3 审计处置第 1 条）：每次审核必须声明被审 commit
与被审树。本文件即当前代码审核的基线锚。

## 被审树

```text
audited commit   e168555（main 与 release/v2.0.0-beta 同树同点，
                 双方已推送）
branch state     所有非 vendor 分支完全包含于 main（0 领先）；
                 vendor/mlx-swift-lm-5ba0bc1 为 vendor 谱系引用，
                 按裁定不合并
fork dependency  slamfinger/mlx-swift-lm@release/v2.0-beta-ml
                 @ 6d01a13c（UPSTREAM_BACKUP_ON_FORK：仅远端
                 备份，不推 ml-explore 上游）
release          暂不发布 v2.0.0-beta 代码（无 tag / 无发布动作）；
                 本基线为发布前代码审核准备态
```

## 基线验证证据（本 commit 实测）

```text
sweep    xcodebuild test（全量 SimiGoTests，SIMIGO_FORK_EXP=1）
         79 executed / 2 skipped（环境门控）/ 0 failures /
         430.9s — 含 Oversized 41.76GiB E2E、F3 真机电池、
         B-5 池电池、BranchFork 3 用例（STEP-10 断言内含）
prior    F3_DEVICE_ACCEPTANCE = PASSED（owner-verified）
         外审两轮：R1-R5 架构 PASS；P1×2 + P2 文档项已修复
         （9956e64）；B-5 trace 竞态已修（轮询式断言）
known    deferred（不阻塞审核，已登记）：usage projection /
         disk GC / whole-fork 事务原子性
```

## 复现

```text
git checkout e168555
TEST_RUNNER_SIMIGO_FORK_EXP=1 xcodebuild test \
  -project SimiGo.xcodeproj -scheme SimiGo \
  -destination 'platform=macOS' -enableCodeCoverage NO \
  -only-testing:SimiGoTests
```

审核输入建议顺序：本文件 → docs/RELEASE_v2.0.0-beta.md →
docs/RESEARCH_STATE.md（Lab 仓，权威研究状态）→ 上述证据。
