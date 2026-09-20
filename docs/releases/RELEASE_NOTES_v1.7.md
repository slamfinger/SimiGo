# SimiGo v1.7 发布说明

日期：2026-09-20
依赖基准：mlx-swift-lm `dc3ca6197171`（Package.resolved pin，与 v1.5/v1.6
一致；发布构建时工作区检出临时对齐 pin——检出 8f37dbc 漂移已避开，构建后
恢复）、mlx-swift `0.31.6`。生产 Swift 代码与 v1.6 build 4（b8ed758）零
差异——本版为 V1.7 实验季发布收口，无新生产机制。

## 本版主题：V1.7 实验季收官定版

v1.6 把 Execution Runtime 架构定型后，V1.7 不再加生产机制，而是用三阶段
实验把 Runtime 能力边界第一次量化成认证级证据（usage 来自官方计数、
cached 不估算、anomaly 不伪造）：

- **V1.7-0 Runtime Matrix**：认证级测量通道；build 4 十K 行实证
  restore ≈ cold 的 1/15
- **V1.7-1 长上下文**：restore 9/9 命中（120K 处 18.2s vs cold 624s，
  ≈1:34）；cold 超线性复核成立；rebuild/cold 并案
- **V1.7-2 并发探针**：8 探针 26 场景 26 pass；serializeGeneration 时间
  线实证（门交接同毫秒 gap=0.000s ×4 轮双向验证）；毒 session P0 回归
  通过；外审 P1-1 计时精度修复（datetime 保留毫秒）
- **V1.7-3 办公原型**：Runtime 首次端到端承载真实办公任务——Excel 分类
  0.90/提取零误报/汇总精确命中；Word/PPT/PDF 全满分；文件整理 10/10、
  多文档整合 8/8；扫描件真 OCR 闭环 attempt-3 满分；t2（tool 尾）轮
  restore 在全部任务形状自发命中

## 本版工程修正（外审对证，实验 harness 层）

- 扫描件 OCR 分支三处死代码潜伏 bug 修复：/usr/bin 硬编码（改 PATH
  解析）、pdftoppm `-r200` 合并写法被 poppler 26 拒绝、tesseract
  `--psm6` 合并写法被拒且失败静默吞空串（改失败显式抛错）
- generate_scan_pdf 真栅格化（图片型 PDF）；genMode/extractMode
  provenance 随 results 入库，pypdf-textlayer 与 tesseract-ocr 分开计
  证据等级
- 扫描评分 key 归一化（尾部数字段，INV-2026-301/inv-301/301 同一业务
  编号）+ 回归测试 11/11；原始提交键保留审计，未放宽字符串比较
- 能力口径对齐：文本层闭环=已验证，OCR=attempt-3 起真实验证；
  范围边界=固定合成扫描件（无旋转/倾斜/印章遮挡/多栏/手写/跨页），
  非通用发票 OCR 质量保证

## 已知边界

- V1.7 实验 harness（tools/v17_3_*）为实验层 Python，不随 app 分发
- 扫描件 OCR 证据基于本机 Tesseract 5 + chi_sim（brew 安装），未捆绑
- DPO/训练侧、多用户并发、网络分发安全不在本版范围

## 验收

- 单测：73 tests / 5 skipped / 0 failures（与 v1.6 build 4 基线一致）
- Release 构建：fresh derivedDataPath（build/release-v17），vendor 检出
  对齐 pin dc3ca61；nm 验证 conditionalRestore/rollforward 符号族在位
- codesign TeamIdentifier YPXU8M53F9，strict verify 通过；DMG
  hdiutil verify VALID，内嵌 app 版本 1.7(5)
- 扫描件 attempt-3 真 OCR 满分实跑记录在案
  （results_v17_3_office_docs_smoke.json，meta.provenanceNote 区分
  build 4 文本层与 1.7(5) 真 OCR 两代证据）

## build 6 更新（2026-09-20 同日替换包，CFBundleVersion 5→6）

首发 build 5 后同日三项生产修正，替换 DMG 分发（tag v1.7 附件 --clobber）：

- 菜单栏「本机/局域网」拖曳切换改为点击切换：点目标侧即切换、点当前侧
  不动作，视觉样式零改动（移除全仓唯一 DragGesture）
- 设置视窗统一命令控制台：命令成功完成后输入框自动恢复初始原样
  （`hf download ` 预填），状态行保留「下载完成」等终态作提示；失败路径
  保留输入便于修改重试；「记录」tail 流程不属命令完成语义，未动
- 轮末遥测 restore 归因补全：checkpoint 恢复会话在 vendor 侧无
  conversation 账本，归因块整体跳过，恒报 cacheHitTokens=0/
  cacheEff=0.00/无 mode，与冷启/重建同形歧义；现按实测补全为
  mode=restore、cacheHitTokens=N（cacheTokens 官方计数）、
  cacheEff=N/(N+d)，不写死 1（delta 确实预填）。usage 上报保持
  vendor 原值透传（P1-2 契约不做估算）不变

验收：单测 73/5 skipped/0 failures 与基线一致（Debug 配置）；vendor
检出对齐 pin dc3ca61 增量 Release 构建通过；codesign TeamIdentifier
YPXU8M53F9 strict verify 通过；DMG hdiutil verify VALID，内嵌 app
版本 1.7(6)。
