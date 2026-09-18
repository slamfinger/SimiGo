# 事件记录：App 空闲崩溃 + 服务全局挂起（2026-09-19 凌晨）

**二进制**：两起事件均在 v1.5/v1.6-era 构建（7ccd136 基线，/Applications 安装版）——
**S1–S5 新代码不在其内，V1.6 五分片免责**；两起均为 V1.6.1 候选生产缺陷。

## 事件 A：空闲 SIGABRT 崩溃（03:39:26）

- 现场：App 空闲约 20 分钟（首份矩阵冒烟提交后），无请求在途
- 崩溃签名：EXC_CRASH / SIGABRT，主线程，`_objc_fatal → lookUpImpOrForward`
  （ObjC 运行时 fatal，疑似向已释放实例发消息）
- 崩溃历史：同签名家族 .ips 在 Sep 18 17:05 / 19:48 / 23:28 与 Sep 13 03:14
  均有出现——**反复发生的既有问题**，非本晚首发
- 证据：`~/Library/Logs/DiagnosticReports/SimiGo-2026-09-19-033926.ips`
  （已拷贝至 V17_RUNTIME_MATRIX/evidence/）

## 事件 B：服务全局挂起（04:03:03 后）

- 现场：calibrated harness 依次完成 r1（cold 9.4k）/ r2（rebuild ~18k）后，
  warm-setup 请求被 accept（TCP ESTABLISHED）但**永远无响应**；此后
  /v1/models 等全部端点同样挂起（连接 accept 但零响应）
- 关键观测：trace 中**无该请求的 `[EXEC] begin`**——请求从未进入 generate()；
  卡点在 HTTPServer 请求处理层（generate 之前）
- sample（5s，17 线程）：主线程正常 AppKit 事件循环；MLX C++ 线程池全部
  空闲等待；**未捕获任何 SimiGo Swift 处理线程**——处理该连接的 Swift
  任务要么不存在要么 sample 未覆盖 Swift 并发线程池
- 证据：`evidence/simigo_hang_sample_0418.txt`（full sample）
- 恢复：SIGTERM→SIGKILL 重启后服务需手动开启（正常行为）

## 初步判读（待复现验证）

- 事件 A/B 是否同根未知（A 是 ObjC 层 abort，B 是 Swift 层处理停滞）
- 事件 B 的"accept 后零处理"指向 HTTPServer 连接处理线程死亡或
  全局串行队列被上一请求占死——**V1.6.1 最优先候选**：给 HTTPServer
  加存活探针 + 卡死请求超时 + 连接处理线程状态可观测
- 复现路径候选：矩阵 harness 的长会话反复 rebuild 序列（r1 cold →
  r2 rebuild → warm-setup 挂）

## 关联

- V1.7-0 harness 冒烟：`docs/experiments/V17_RUNTIME_MATRIX/`
- 事件期间 harness/样本均已保全，无数据丢失
