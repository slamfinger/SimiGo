# 作废：m4b 第一次 round2 运行用错了 target

本轮启动 m4b 时没有导出 `SIMIGO_EXPERIMENT_TARGET`，驱动回落到默认值 `hello`，
因此 u1/u2 与 m4a 相同（`hello` / `RESULT=hello-U2`），**不能**作为受控差异证据。
原始文件保留在此，不删除；正式 m4b 已在 `m4/m4b/` 重跑（target=delta9, baseline=hello）。
