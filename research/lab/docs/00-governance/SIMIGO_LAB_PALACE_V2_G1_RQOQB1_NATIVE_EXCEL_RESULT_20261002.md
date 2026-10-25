# PALACE V2 G1 RQ-OQB-1 复测结果 — Excel 原生编辑 vs 工具编辑

日期：2026-10-02  
状态：`RQ-OQB-1 EXECUTED / RESULT AT HUMAN`  
问题（human 批准）：22 个表示噪声是 openpyxl 特有现象，还是 Excel
工作流本身也会产生？  
执行方式：真实 Microsoft Excel（本机 Excel.app）+ AppleScript 原生
驱动——v1 = L0 原件的**新鲜副本**（回滚至 450.29 基线，
sha `1dd8372a…`，19841 cells 快照含 raw type 记录）→ Excel 打开 →
单 cell `附表1!F8 = 480.29`（numeric）→ 原生保存（XML 工作簿格式
保持）→ 关闭 → openpyxl 只读 diff（键归一后对照）

## 结果

```text
[O] OB-1 五字段：
    size  : 1258847 → 1259863（+1,016 bytes——Excel 重写内部
            结构/文档属性级变化）
    mtime : 更新
    sha256: 全文件变化（整文件重写预期内）
[O] OB-2 cell 级 diff：**变更 = 1 / 消失 = 0 / 新增 = 0**
    唯一变化 = 附表1!r8c6: '450.29' → '480.29'（float 保留）
[O] 其余 19,840 个 cell 的值在 Excel 原生保存后**逐字稳定**
```

## 对照结论（RQ-OQB-1 答案）

```text
openpyxl 工具编辑：23 cell 变化（1 语义 + 22 序列化噪声）
                  + size -101,443 bytes（重压缩/丢失内部结构）
Excel 原生编辑：   1 cell 变化（纯语义）
                  + size +1,016 bytes（内部元数据级）
=> 22 个表示噪声 = **openpyxl 工具往返特有现象**，
   非 Excel 工作流固有
=> 「内容变化 ≠ 单元格值变化 ≠ 表示变化」三层在原生路径上
   收敛为单点语义变化——工具选择决定观测污染程度
   （RQ-OQB-2 精度感知语义 diff 的必要性因此收窄为
   「非原生工具路径」的前提条件）
```

诚实边界：

```text
[O] 字节级（sha/size）在两条路径上都大变——表示层与语义层的
    分离再次被印证（G1 主探针第三类证据的工具版重演）
[O] 本复测 = 单 cell/单文件/本机 Excel 版本；多 cell、跨版本
    Excel、WPS/Numbers 等其他编辑器路径未测（不外推）
[O] Excel 重写会更新文档属性（如修改时间元数据）——cell 值层
    之外的非值变化存在于内部结构层（未逐项审计）
```

## Gate state

```text
RQ-OQB-1 = EXECUTED / ANSWERED（噪声 = openpyxl 特有）
OQ-B 线  = 完整收束（OB-1..4 + 复测）
下一门   = E6 Design Entry（human 顺序裁定生效）：
          E6 问题（human 措辞，低一层抽象）= 「当信息空间中的
          原始内容发生变化时，PALACE 如何知道当前工作所依据的
          信息是否仍然有效？」——设计草案为下一动作
```
