# 动作日志（只追加，不回改）

- [2026-10-02] 确认输入文件存在：`/Users/mr.simi/Documents/SimiGo-Lab/boundary-study/exp1-x1/information-space/inputs/秦沈项目经济运行情况汇报_20260307.docx`、`秦沈项目经济运行情况汇报_20260308.docx`（大小分别约 323724 / 323806 字节，均为只读对象）。
- [2026-10-02] 创建工作目录 `/Users/mr.simi/Documents/SimiGo-Lab/boundary-study/exp1-x1/a-workspace/`。
- [2026-10-02] 检查本机可用工具：textutil 可用；pandoc 不可用；python3 可用且 python-docx 可用。选定 python-docx 做结构化提取（段落+表格），textutil 作交叉校验。
- [2026-10-02] 创建本文件（动作日志.md）与 工作记录.md。
- [2026-10-02] 创建 `extract_docx.py`（python-docx 按文档顺序提取段落[带样式]+表格[含合并单元格标记]，只读原件）。
- [2026-10-02] 运行提取：生成 `extract_0307.txt`、`extract_0308.txt`（各 142 行、5 张表）；textutil 转纯文本生成 `extract_0307_textutil.txt`、`extract_0308_textutil.txt`（各 548 行）。
- [2026-10-02] 逐行 diff 两个 python-docx 提取文件：发现 5 处差异行（25、80-81、100、109、115 行）；textutil 交叉校验：同 5 处 + 1 处行尾空格差异（标后预算段），两法结论一致。
- [2026-10-02] 解包两 docx 对比：文件部件清单一致（各 23 项）；无 w:ins/w:del 修订标记、无批注；页眉页脚可见文字仅页码"4"，一致；图片 image1.png/image2.jpeg 字节一致。
- [2026-10-02] document.xml 全部 w:t 文本 run 级 diff（657 vs 678 runs）：9 组变化，其中 5 组为实质差异、4 组为 run 边界重排（可见文字相同）；确认除这 9 组外无其他文字变化。
- [2026-10-02] 其余部件对比（strip rsid 后）：footer1-4/footnotes/endnotes 完全一致；settings.xml（缩放 120→130%、新增 docVars）、styles.xml（toc/header/footer 样式 qFormat 标记）、fontTable.xml（字体 sig）、custom.xml（ICV 指纹）均为格式/软件自动差异；core.xml（修订号 110→115、修改时间 2026-03-07T15:23Z→2026-04-01T13:16Z）、app.xml（Words 1133→1141 等）为元数据差异。
- [2026-10-02] 读取提取文件上下文，核对 5 处差异所在章节（一(三)、二(一)、四(二)表4及零星材料小节、四(五)、五(一)）并记录原文证据；另确认两版"二(三)开累效益"均为"截至2025年末"（0308 未同步更新的内部不一致）。
- [2026-10-02] 创建 `版本差异报告.md`（差异明细+证据+理解+版本判断+遗留疑点）；更新 `工作记录.md` 至最终状态。
- [2026-10-02] 工作到自然停止点结束：逐节比对全部完成，无未读区域，无未归档差异。
