# SimiGo-Lab IS-X Implementation Revision — R1/R2 Specification & Verification Closure

日期：2026-10-03
状态：**REVISION DELIVERED / 独立复审 PENDING**（本门=IS-X implementation
revision review；**attempt #2 NOT AUTHORIZED**；R3-4 LOCKED）
授权：human「开启 IS-X implementation revision review」（2026-10-03）——
只审 R1+R2 implementation revision；修订只修 instrumentation/audit
defect；不得利用 X-08/X-09 结果反向优化探针；不得修改 IS-X Design
rev.2 研究规则/目录/预测器；revision 后须有明确 regression/reaudit 判据。

## 0. 修订范围与不变量

```text
修：isx_lib 效果断言机制（R1）+ isx_second_layer_audit 包含规则（R2）
   + isx_run_cells 构造完整性调用切换（供 attempt #2 使用）
不修：IS-X Design rev.2（研究规则/目录/预测器/分类法零 diff）
不修：Attempt #1 证据（run R33X-…-70152 全量保全；已记录的 path-based
      探针结果原样保留——历史即历史）
不借助：X-08/X-09 outcome 反向优化探针——修订推导来源=op 效果定义
      （key/content/manifest 三类身份代数），对全部 op 一般适用
不动：Attempt #1 战役判读（INCONCLUSIVE 永久保留——reaudit PASS 不改
      战役 verdict，只证明仪器缺陷已修）
```

## 1. R1 — CI-2 对象/效果恒等追踪（object/effect identity tracking）

### 1.1 缺陷回顾（F-3 定性）

rev.1 效果断言按**路径**钉死（如 A-Δ3 ⇒ objects/R-1.json differs）。
当 op_b 合法迁移对象（A-Δ2）时，效果存留于新位点而旧路径消失——探针
误报。实测=「effect remains at this **path**」，意图不变量=「effect
remains on this **object**」——measurement model mismatch。

### 1.2 修订代数（三类对象身份，全部机械、零语义判断）

```text
key-identity（索引键身份）：L.resolve_key 的精确键规则（§5a 钉定）
  状态：resolved / not-found / ambiguous
  bytes_vs_is0：解析内容 vs IS₀ 同键解析内容的字节比较
content-identity（字节身份）：IS₀ 路径内容的全树字节恒等搜索
  结果：hits（找到的路径集）/ 空搜索 = 对象处处不在
manifest/record 断言：结构文件字段与记录身份（路径无关）
```

### 1.3 逐 op 效果断言（OP_EFFECT_SPEC，声明式）

```text
R32-I-Δ1  key-field(runtime-declaration, fixture_class,
            "r3-2-minimal-v1-TAMPERED")
R32-I-Δ2  content-absent(lineage/lineage-root.json)
R32-I-Δ3  file-present(lineage/lineage-root-conflict.json)
          〔rev.2 精化：移除过强的 key-resolves 断言——组合稳健性原则〕
R32-A-Δ1  key-unresolved(anchor:state-diff)
          + content-absent(objects/R-1.json)
R32-A-Δ2  key-resolved-at(anchor:state-diff, universe/R-1.json)
          + manifest-contains(out_of_scope, universe/)
R32-A-Δ3  key-substituted(anchor:state-diff)   ← 修订核心：解析跟随键，
            内容≠IS₀ 即替换效果存续——合法迁移≠效果消失
R32-C-Δ1  key-unresolved(I-S0) + content-absent(objects/I-S0.json)
R32-C-Δ2  invalidation-has(INV-R32-C-Δ2)
R32-C-Δ3  invalidation-has(SUP-R32-C-Δ3)
R32-B-Δ1  manifest-contains(out_of_scope, archive/)
R32N-Δ6   key-resolved-at(I-S0, objects/store-v2/I-S0.json)
          + key-same-bytes(I-S0)
R32N-Δ8   manifest-contains(scope_tags, r3-2-archive-scope)
R32N-Δ9   file-present(extra/extra-note.json)
          + manifest-contains(in_scope, extra/)
R32N-Δ10  key-resolved-at(lineage-root, lineage/store-v2/lineage-root.json)
          + key-same-bytes(lineage-root)
```

### 1.4 「合法迁移 ≠ 效果消失」的机械区分

```text
合法迁移：key-identity 解析成功（精确键规则），解析位点 ≠ IS₀ 位点，
          内容关系符合该 op 声明（key-same-bytes=纯迁移/
          key-substituted=替换随迁）⇒ 探针 PASS
效果消失：声明关系不成立——如 key-substituted 处字节==IS₀（替换被
          还原）、key-resolved-at 处对象不在、content-absent 搜索命中
          （被删对象复活）⇒ 探针 FAIL
无路径依赖：解析走钉定精确键规则；删除断言走字节恒等搜索；
          无隐式语义判断
```

### 1.5 组合稳健性原则（reaudit RC-1 精化，rev.2）

```text
原则：效果断言只声明 op 自身的构造效果——(i) 创建（file-present）、
      (ii) 删除（content-absent）、(iii) 原地变更（key-field/
      key-substituted）、(iv) 迁移目的地（key-resolved-at±
      key-same-bytes）——不断言可被共存 op 自身声明效果合法变换的
      状态性质（如「某键仍可解析」——共存 op 可能按其自身效果合法
      pop 该键）。
reaudit RC-1 首轮定位：I-Δ3 的 key-resolves 断言在 X-09 组合态被
      I-Δ2 的声明效果合法覆盖（pop 键正是 X-09 I-NF 的产生机制）——
      过强断言，非构造缺陷。精化：I-Δ3 保留 file-present(conflict)
      （其创建效果，组合稳健），移除 key-resolves。
登记：X-09 的键覆盖现象保留于 X-09 判读数据（I-NF 与朴素预测一致），
      作为顺序依赖观察的一部分——探针精化不隐藏任何判定相关事实。
```

## 2. R2 — 审计包含规则（INCONCLUSIVE containment）

```text
cell.status == INCONCLUSIVE（任何原因：S-X2 CI 违例/I-1..I-6/
INVALID-COMPOSITION）⇒ 审计**绝对不重算该 cell 的交互分类**；
审计对该 cell 只验证三项：
  (a) INCONCLUSIVE reason 存在且属于预注册 reason 码
  (b) 该 cell 证据链存在（construction/outcome/observations + 哈希钉定）
  (c) containment：该 cell 不进入 ADDITIVE/INTERACTION 统计，
      战役 verdict 遵守传染规则（非零 INCONCLUSIVE ⇒ 战役
      INCONCLUSIVE）
ADDITIVE/MASKING 等分类重算仅施于判读器判为有效分类的 cell。
```

## 3. 验证闭包（regression/reaudit 判据——不因「根因已知」跳过）

```text
RC-1  修订探针作用于 Attempt #1 保全证据：12 对全部效果断言 PASS；
      其中 cell-06 的 A-Δ3 key-substituted PASS = 「合法迁移≠效果
      消失」的直接实证
RC-2  修订审计作用于 Attempt #1 保全证据：cell-06 被包含（不重算
      分类，只验 reason/chain/containment）；原分类重算失配消除；
      审计检查全过
RC-3  判读确定性：判读器对保全证据的重算与 Attempt #1 判读逐 cell
      一致（含 cell-06 = INCONCLUSIVE 维持）
RC-4  研究规则零 diff：IS-X Design rev.2 文件 git diff 为空；修订
      只触及 isx_lib 效果断言 + isx_second_layer_audit 包含规则 +
      isx_run_cells 调用切换
RC-5  语义边界：reaudit PASS **不**修改 Attempt #1 战役判读
      （INCONCLUSIVE 永久保留）；reaudit 只证明「仪器缺陷已修+
      包含规则生效」——attempt #2 仍须新的显式 human execution
      authorization
```

## 4. 独立性护卫（human 四项检查的对应落实）

```text
G-1  R1 只修 instrumentation：断言代数从 op 效果定义推导，对全部 op
     一般适用；X-08/X-09 outcome 不作为探针设计输入（探针规格先于
     本 reaudit 运行冻结于本文档）
G-2  R2 只修 audit containment：分类规则本体（§4 交互分类法）零改动
G-3  IS-X Design rev.2 研究规则/目录/预测器零 diff（RC-4 机械核验）
G-4  Attempt #2 未授权：本门不跑任何新 cell；reaudit 只作用于
     Attempt #1 保全证据
```
