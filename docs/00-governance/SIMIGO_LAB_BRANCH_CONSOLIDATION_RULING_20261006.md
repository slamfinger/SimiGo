# SimiGo-Lab Branch Consolidation Ruling

> **Status:** REGISTERED
> **Date:** 2026-10-06
> **Scope:** repository branch topology for the Lab
> **Registered ancestry fact (verified this date):**
> `integration/path-a-information-place` (27bc805) is a STRICT ANCESTOR of
> `codex/research-recovery-layer-v0.1` (87cd820) — the codex branch contains
> 13 commits the integration branch lacks; the integration branch contains 0
> commits the codex branch lacks. They are two archives of one research
> line, which is the source of the state ambiguity this ruling removes.

## Human ruling message (verbatim)

是，**现在分支确实开始有点乱了**。但乱的不是研究内容本身，而是**"历史备份分支、当前工作分支、正式主线"没有及时收拢**。

我重新看了谱系后，建议现在做一次**收口**，而不是继续堆分支。

### 现在的实际关系

最关键的是：

```text
main
  ↓
0a23fb0
  ↓
...
27bc805
  ↓
codex/research-recovery-layer-v0.1
  ↓
cc2912b
```

而：

```text
integration/path-a-information-place
  = 27bc805 的继续分支
```

也就是说，`integration/path-a-information-place` 已经是 `cc2912b` 这条线的**严格祖先/子集**。

所以现在实际上有两个"同一研究路线的存档"：

```text
integration/path-a-information-place
        └── 27bc805

codex/research-recovery-layer-v0.1
        └── 27bc805 → 恢复/审查 → UA v0.3 → cc2912b
```

这就是你觉得乱的根源。

---

## 我的建议：应该合并，但不是现在直接无脑合并

我建议把目标结构收敛成：

```text
main
  = 正式研究状态 / canonical state

research branch
  = 当前工作区，只在下一阶段工作期间存在
```

具体来说：

### 第一件事：不要再维护 `integration/path-a-information-place`

它已经被 `codex/research-recovery-layer-v0.1` 完整包含。

`27bc805` 是两条线的共同锚点，而现在 `cc2912b` 已经包含：

* Path A 当前状态
* Recovery Layer
* Evidence Inheritance Matrix
* UA v0.2 review
* Human ruling
* UA v0.3
* Targeted Review

所以继续让 `integration/path-a-information-place` 单独存在，**没有新的信息价值，只增加状态歧义**。

---

## 第二件事：`codex/research-recovery-layer-v0.1` 暂时应该作为"当前工作分支"

它现在最有价值的地方不是"最终实现"，而是：

> **把当前正式研究状态完整聚合起来。**

而 `cc2912b` 自己仍然明确写着：

`UA v0.3 → HUMAN REVIEW / FREEZE GATE`

所以现在把它直接当最终冻结结果合并进 `main`，会让 Git 历史和治理语义稍微混在一起。

我的建议是：

```text
现在：
main                              0a23fb0
                                  │
codex/research-recovery-layer     cc2912b
                                  │
                                  └─ UA v0.3 Human Freeze
```

先完成这次 Freeze Review。

**Human 接受 UA v0.3 后，再把整个 `codex/research-recovery-layer-v0.1` no-ff 合并进 `main`。**

这样合并本身表示：

> "这一轮研究状态已经成为正式 Lab state。"

而不是：

> "某个 Agent 分支突然把一个仍在审查中的协议塞进 main。"

这会干净很多。

---

## 第三件事：`main` 应该成为唯一权威盘面

这是最重要的。

现在真正应该确立的是：

```text
main
= 正式 Research State

codex/research-recovery-layer-v0.1
= 临时工作分支

integration/path-a-information-place
= 历史备份，合并后归档

codex/execution-state-research-20260929
= 旧 ES 分支，冻结/归档

research/es-reuse-program-20260930
= 独立旧研究线，保留历史，不参与当前 PALACE 主线
```

这样以后 Agent 再接手时，只需要：

```text
main
  ↓
Research State
  ↓
当前合法下一步
```

而不是让 Agent 猜：

> 27bc805 和 cc2912b 哪个才是真正的当前状态？

---

# 另外一个重要点：不要把"合并"与"实验推进"混在一起

我现在反而不建议：

> 合并 → 马上 U-2 → 再继续改 main

正确顺序应该是：

```text
现在
  ↓
UA v0.3 Freeze Review
  ↓
ACCEPT/FREEZE
  ↓
U-2 独立授权
  ↓
Unified Carrier implementation
  ↓
实验
  ↓
形成新的研究证据
  ↓
再合并新的阶段性结果
```

这样 Git history 就非常清楚：

```text
main
├─ 已接受的研究结论
├─ 已冻结的协议
├─ 已验证的实验
└─ 当前阶段出口
```

而不是把：

```text
设计
审查
实验
未授权
授权
恢复
并行 Agent
```

全都塞在同一条不断前进的工作线上。

---

## 所以我的明确判断

**是，现在应该开始收口。**

但我建议：

> **先不要立即 merge `cc2912b` → `main`。**

先把 **UA v0.3 的 Freeze Review 做完**；如果 Human 接受，就：

```text
codex/research-recovery-layer-v0.1
        ↓ no-ff merge
main
```

然后把：

```text
integration/path-a-information-place
```

标成历史备份，不再继续开发。

这会是目前最干净的分支结构。

而且从 Git 谱系看，这不是大规模重组，因为 `integration/path-a-information-place` 本身已经被当前研究分支包含，**不存在需要重新拼装两套内容的问题**。

一句话概括：

> **现在不是"分支太多"，而是已经出现了一个明显的 canonical branch，却还保留着它的旧祖先工作分支。应该收口，但应在 UA v0.3 Freeze 后收口到 `main`。**

---

## Registered consequences

```text
BR-1  NO IMMEDIATE MERGE. codex/research-recovery-layer-v0.1 remains the
      current working branch until UA v0.3 is accepted/frozen by Human.
      Nothing merges into main before that ruling.

BR-2  POST-FREEZE MERGE PROCEDURE: after the Human ACCEPT/FREEZE ruling
      for UA v0.3, the whole codex/research-recovery-layer-v0.1 branch
      is merged into main with --no-ff. The merge commit then means
      "this research round is now official Lab state". The merge is a
      separate governance action from the freeze ruling and from any
      U-2 authorization.

BR-3  integration/path-a-information-place = ARCHIVED HISTORICAL
      BACKUP, effective immediately: no further commits, no further
      development, not deleted (history preserved). Its full content is
      contained in the codex line (verified strict ancestry). Until the
      post-freeze merge, the codex branch tip is the ONLY operative
      current-state surface.

BR-4  TARGET END-STATE after the merge:
        main                                  = sole canonical
                                                Research State
        codex/research-recovery-layer-v0.1    = temporary working
                                                branch, exists only
                                                during active phase
                                                work
        integration/path-a-information-place  = archived backup
        codex/execution-state-research-20260929 = old ES line, frozen/
                                                archived
        research/es-reuse-program-20260930    = independent historical
                                                line, not part of the
                                                current PALACE mainline
      Future agent entry after the merge: main -> Research State ->
      next legal step. No guessing between 27bc805 and the codex tip.

BR-5  MERGE NEVER MIXED WITH EXPERIMENT PROGRESSION. Sequence: Freeze
      Review -> ACCEPT/FREEZE -> U-2 independent authorization ->
      Unified Carrier implementation -> experiments -> new evidence ->
      separate stage merge into main. Design/review/experiment/
      authorized/unauthorized/recovery/parallel-agent work is not all
      glued onto one ever-advancing line; main accumulates only
      accepted conclusions, frozen protocols, validated experiments,
      and stage exits.

BR-6  State documents updated in the same commit: INDEX and
      SESSION_LOG record the new branch topology (integration =
      ARCHIVED; main = canonical target; codex = current working
      branch; merge = post-freeze, no-ff, separate action).
```


## Superseding Human ruling — immediate consolidation

The Human subsequently superseded BR-1 and the timing portion of BR-2 by
explicitly ordering immediate consolidation into `main` because the remaining
branch count was judged excessive.

Effective ruling:

```text
SR-1  The current codex branch state is merged into `main` NOW.

SR-2  The merge is no-ff. It is a repository-topology consolidation action
      only; it does NOT freeze UA v0.3 and does NOT authorize U-2.

SR-3  `main` is the sole canonical Research State immediately after the merge.

SR-4  `integration/path-a-information-place` remains historical and receives
      no new work; it is a strict ancestor/subset of the merged codex line.

SR-5  The old ES branch and the ES-reuse research line remain historical
      references and are not merged merely for branch-count reduction.

SR-6  All current work and state updates now target `main`; the superseded
      codex branch is no longer an operative current-state surface.

```

Substantive research gate remains unchanged:

```text
UA v0.3 Freeze Gate = OPEN
U-2                  = NOT AUTHORIZED
Unified benchmark    = NOT AUTHORIZED
```


## Superseding consolidation instruction — 2026-10-06

The Human subsequently instructed that the Lab repository itself should be consolidated now.

Operational consequence:

    main = sole canonical Research State

    codex/research-recovery-layer-v0.1
      -> topology-only merge into main @ 772d1225
      -> stale post-merge governance commit remains historical only

    research/es-reuse-program-20260930
      -> topology-only merge into main @ 6ad81046
      -> historical ES-reuse artifacts are NOT imported into the current tree

    integration/path-a-information-place
      -> already fully behind / ancestral; no additional content merge required

    codex/execution-state-research-20260929
      -> already fully behind / ancestral; no additional content merge required

This is repository-history consolidation, not semantic adoption of the old
ES-reuse research line and not authorization of any new ES work.

The current research tree remains unchanged by the topology-only merges.

    UA v0.3 Freeze Gate = OPEN
    U-2                  = NOT AUTHORIZED
    Unified benchmark    = NOT AUTHORIZED
    Backend selection    = NOT AUTHORIZED

Remote branch refs are still present because the current GitHub connector does
not expose branch-ref deletion. They are historical / non-operative and must
not be treated as current-state entry points.
