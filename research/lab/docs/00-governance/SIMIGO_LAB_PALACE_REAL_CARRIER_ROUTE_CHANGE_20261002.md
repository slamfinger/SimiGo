# PALACE 改轨登记 — Boundary Study 收口为窄验证线 + MemPalace 真实载体初始化（human 方向）

日期：2026-10-02  
状态：`ROUTE CHANGED / MEMPALACE V0 INITIALIZATION AUTHORIZED`  
性质：human 方向裁定登记——非实验结果  
前置：EXP1-X1 全链完成（A 半程 → B 放行 → B 半程 → Evidence
Table v2 → 真值核对；RESULTS AT HUMAN `fa0c2af`）

## 1. X1 结果门裁定（human）

```text
X1 = ACCEPT（表七行归属 + F-1..F-6 + 停止点形态全验收）
human 判语核心 = X1 已经完成了它最重要的事情：
  显式工作前沿 / 判断依据 / 信息可信性 / 未完成执行位置
  之间存在不同层次（方向已给出）
```

## 2. 两线分立（human 原文结构，冻结）

```text
Boundary Study：X1 ──► Y ──► 是否存在真正 ES Boundary
                             （继续验证研究命题）
PALACE：MemPalace ──► 初始化 Information Space
                      ──► 真实使用 ──► 碰撞
不绑死。继续扩四 case = 「为了把理论证明完整而做实验」的风险。
```

## 3. 轨 1：Y 降级为独立验证探针（登记非启动）

```text
Y = ES Boundary Candidate Probe
目的（唯一）= 验证「工具执行之后、下一步尚未发生」的状态，
  是否可以仅靠 Information Space 合法恢复
（对应 X1 发现 F-5(c)：可信性/执行状态保证不在信息本身——
  本实验由信息可闭合；其 ES 候选化条件正是 Y 的靶点）
不扩研究框架；不因此暂停 PALACE；启动时点待 human 指示；
执行规范 = Boundary Study 设计草案 §12–§14 保留适用
```

## 4. 轨 2：PALACE 改轨启动

```text
不是设计 PALACE。是把 MemPalace 原样跑起来：
  MemPalace → 初始化本地 Information Space
           → 导入真实文件
           → 导入真实对话
           → 检索
           → 让 SimiGo 使用
           → 观察
预期碰撞面（human 列举）= 对话保存粒度 / 文件保存粒度 /
  摘要粒度 / 来源 / 版本 / 关系 / 决策 / 待办 / 工作前沿 /
  外部 API 对话
碰撞之后 PALACE Schema 才开始有现实依据：
  记录实际缺口 → 再决定 Schema 扩展
站在巨人的肩膀上（human）：没必要继续站在原地研究「巨人的
  肩膀应该长什么样」——直接站上去走，走两步，哪里硌脚，
  PALACE 就从哪里开始长。
```

## 5. 与既有裁定的关系（诚实登记）

```text
G0 基座裁定 Substrate W（参考实现路线）= v0 载体阶段被本
  human 指示取代：MemPalace 从「审计对象」升级为「运行载体」；
  G0 机制清单继续作参考（xlsx 压平/Cell·Formula 丢失/NaN 噪声
  等已知缺口 = 碰撞预期清单的先验）
2026-09-29 硬边界「不实现 Palace database / 不选存储」= 本
  裁定按 human 方向解除——MemPalace = 现成系统原样运行
  （PyPI mempalace 3.10.0，G0 运行时实测同一版本链），非自研
  实现；自研 Schema 设计仍然禁止（Schema 由碰撞逼出）
依旧禁止 = 修改 SimiGo Execution State 契约与产品线 /
  L0 原件写入 / Gate① 复活 / 把 MemPalace 改造成 RAG 管线
Information Space v0 位置 = SimiGo-Lab/palace-v0/（gitignore，
  数据不入 git；观察记录照常入仓）
```

## 6. Gate state

```text
Boundary Study = X1 ACCEPT / CLOSED（四 case 全量不执行——
                 设计保留不废弃）
Y = ES Boundary Candidate Probe / REGISTERED / NOT STARTED
PALACE = REAL CARRIER TRACK OPEN / MemPalace v0 INITIALIZATION
         AUTHORIZED
SimiGo 接入 = MCP 通道（mempalace mcp）待 v0 检索通过后接线
```
