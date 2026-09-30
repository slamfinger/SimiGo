# PALACE-1 E2 Results — Prefix Pool Dependence

日期：2026-09-30  
状态：`E2 COMPLETE / AWAITING SECOND-LAYER`  
问题（human 裁定措辞）：**把 Prefix Pool 物理 Representation 全部拿掉，
cold reconstruction 的语义能力是否仍然存在？**  
方法：证据组合（无新建模、无删除、无性能 claim）

```text
observed capability ≠ inferred role ≠ performance claim（本轮零计时结论）
```

## 1. 证据组成

### 1.1 池缺席 → 语义能力存在（R2n 已证，本轮正式归位 E2）

R2n 在 `SIMIGO_PREFIX_POOL=0` 下运行——**池在该轮运行中物理缺席**（不读、
不写、hook 不装），cold reconstruction 全部正常：

```text
n0a/n0b =「继续执行。」（greedy 确定性，语义正确的编码会话延续）
N-1 内容扰动 → continuation 质变；N-2 工具历史删除 → 指代崩塌
——池缺席不改变任何语义行为，只改变 prefill 成本
```

### 1.2 池在场 → 本 workload 会全量命中（E2 新增，只读探测）

对真实池（15G，2 namespaces × 24 对）做**只读 admission 探测**
（`pool.admit` = 纯链哈希查找，零写入；export/eviction 未触发）：

```text
think:1 fp=none   → HIT coveredMessages = 17 / 17（全覆盖！）
                     boundary=199f82cc086b805f
think:0 fp=none   → MISS
think:* fp=probe  → MISS（指纹变体全部拒绝）
```

**三层事实**：
1. 真实池里存着本会话（5401315f）的**全覆盖快照**——若 R2n 开池运行，
   整个 prefill 会被池替代（47.6s 冷税 → 快照加载 + delta，产品注释口径）；
2. **即便如此，R2n 的池缺席运行产生了语义等价的 continuation**——
   「池在场会加速」与「池缺席不失语义」同时成立；
3. 命名空间隔离按登记工作：think 变体与指纹变体正确区分（HIT/MISS 边界
   精确）。

### 1.3 代码路径合并（E0/provenance/本轮）

```text
池命中 → 快照加载 + poolBind（内存 registry）+ delta prefill
池缺席 → cold reconstruction（R2n 证明语义等价）
池损坏 → P-I1 响亮失败自愈（条目删除）→ 回退冷路径，
         「绝不静默续算在未对账表示上」
导出   → 仅轮末 best-effort 写入（pool-enabled 时）——本轮未触发
```

## 2. E2 结论（candidate 保持纪律）

```text
Prefix Pool = 可替换的 Physical Optimization（性能层 Representation），
              不是 continuation nucleus 的组成部分：
✔ 池缺席 → 语义能力完整存在（R2n 正式归位本轮）
✔ 池在场 → 本 workload 全量命中（17/17）——纯加速证据
✔ 损坏路径 → fail-closed 自愈回退（代码 + 登记）
✘ 未做：性能对比（计时归 RQ3 纪律）；池命中下的 greedy 等价性运行时
  对照（需要 pool-enabled generate = 写真实池，授权边界外）
```

## 3. PALACE 证据链总图（E0 → E1 → E1.5 → R2n → E2）

```text
不可替代候选（observed）
  caller-key 寻址 + history（continuation-bearing：E1.5-Q2 + R2n）
可替代表示（observed）
  KV checkpoint（E1：restore 前置，cold path 可替代）
  Prefix Pool（E2：缺席不失语义；在场 = 全量命中加速）
保护机制（E1.5）
  generation（presence）/ cacheSHA256（表示字节）/ modelId（兼容门）
信息性/未决（E0）
  meta.storageKey 字段值 / forkPoint（write-only）/ kvFingerprint（缺席）
```

## 4. Non-claims

```text
✔ 只读探测（admit 纯查找；export/eviction 未触发；15G 池未修改）
✔ 未把 Prefix Pool 命名为任何 State（可替换性能表示，candidate 纪律）
✔ 无性能/计时结论；R2n 引用遵守其自身边界（单样本、贪心、存在性）
✘ 池命中下的语义等价运行时对照 = 授权边界外（pool-enabled generate
  会写真实池），登记为 PENDING
```
