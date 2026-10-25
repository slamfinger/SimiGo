# 证据索引 — simigo-v2.2.0rc1-os-page-return-20261024

生成于 2026-10-24T14:19:08+0800；清单条目 61，合计 31.0 MiB。

## A. 结论 → 证据映射

| 结论 | 文件 | 关键字段 |
| --- | --- | --- |
| GUI 前置条件复核（截图 / 辅助功能 / 前台 / 控制台会话 / 候选身份） | `evidence/gui_preconditions.json` | `verdict / blockers` |
| GUI 仍阻塞的唯一原因：screencapture 无法取帧 | `evidence/gui_preconditions.json` | `checks.screen_capture + its stderr` |
| GUI 未用 headless 生成或 AX 失败冒充通过（边界声明） | `REPORT.md §6` | `GUI 一节列出的未做三件事` |
| OS 级采样器测什么：kernel 全局页计数 + proc_pid_rusage + 存活探针 | `driver/run_os_page_return.py` | `VMStatistics64 / target_rusage / alive` |
| os3 原始记录（10 ms、baseline 20 s、memprobe 角色） | `evidence/os_page_return_raw_os3.json` | `series / memprobe_evidence / start_epoch_ms` |
| os3 判定（脚本派生，锚定 shipped suspend 事件） | `evidence/os_page_return_verdict_os3.json` | `checks / numbers / verdict` |
| shipped suspend 事件序列（reference_release / resource_reclaim / lifecycle_suspend） | `runs/os3/memprobe_os3.json` | `suspend_events_ordered / footprint_pre_bytes` |
| kernel 侧把页还回来了（不是进程自己报的数） | `evidence/os_page_return_verdict_os3.json` | `numbers.kernel_returned_gib / kernel_returned_over_drop` |
| compressor 不是这些页的去处 | `evidence/os_page_return_verdict_os3.json` | `numbers.compressor_delta_gib` |
| 低占用平台持续时间与连续样本数 | `evidence/os_page_return_verdict_os3.json` | `numbers.longest_low_streak_samples / low_streak_seconds` |
| 退出 teardown 单独测量且不计入判定 | `evidence/os_page_return_verdict_os3.json` | `numbers.exit_teardown_used_for_verdict / exit_teardown_free_gain_bytes` |
| 判定时进程仍活着（证据文件写入时间晚于观测窗结束） | `evidence/os_page_return_verdict_os3.json` | `numbers.evidence_write_epoch_ms / post_window_end_epoch_ms` |
| os1/os2 旧规则（R1–R9）判定，保留但已被 os3 取代 | `evidence/os_page_return_verdict_os{1,2}.json` | `checks.R4 / checks.R5` |
| 旧规则为何被取代：argmin 落在 exit teardown 上 | `REPORT.md §4.1–§4.3` | `方法学更正` |
| resume 之后重新分配（说明这不是关机或换进程） | `evidence/os_page_return_verdict_os3.json` | `numbers.available_max_at_series_ms + raw series` |
| 逐层 forward_calls 仍未插桩（不允许估值） | `REPORT.md §7` | `NOT_INSTRUMENTED` |

## B. 全量文件清单

| 路径 | 字节 | SHA-256 |
| --- | --- | --- |
| `REPORT.md` | 14996 | `bf5d4b0fffab6132af8e5c7cdef33db30747c02b2f49c268753561300f38c8d8`
| `default.profraw` | 8014160 | `862af9e76697b53e777343eca355091b765fc06d8e5fde6d60426f882974315a`
| `driver/make_evidence_index.py` | 5249 | `e9dccd7cd8d2ef3eefb953f55fcf3014995cc2a0da3236c517d260b005f7f67e`
| `driver/make_gate_addendum.py` | 4739 | `9dd89a8c6b11be8e2c15863e7582465b52b54c222b25fd611a0c421e70220b4f`
| `driver/make_manifest.py` | 1974 | `25a94720aec4c0b49d3c57c7cd789f097f2f77fdc747a423ddb6714329cbdc74`
| `driver/probe_gui_preconditions.py` | 4695 | `c96adb5f9c75880db1b638547918d85c8582b6743e4580dd4d63883b019cc702`
| `driver/pty_run.py` | 912 | `9af954d4f478d71588b7c6a69c15ea3cf60c45448324324fe0d5a16622daad38`
| `driver/run_os_page_return.py` | 12471 | `95bb284546f0fa98007a24fe64b78803aa9c7181f9eb027668653e272c5d3351`
| `driver/verify_manifest.sh` | 320 | `9ae40095aa8773f483fb42f00d0b9f4ebb896258a276885a4f53b29889657b09`
| `driver/verify_os_page_return.py` | 11590 | `ce6de056164be9a0ee46aa7713e7bc7976ac6da104815ab4d2bfda50429d97bf`
| `evidence/gui_preconditions.json` | 1928 | `b005281ccabee93cde0f9027359835e6eea271aaf01dfd3e326471be294f17d9`
| `evidence/os_page_return_raw.json` | 3346490 | `98d6ddbeed289e4c81d28dbd428e34220030bc9c202320bb9796306e4c400a91`
| `evidence/os_page_return_raw_os1.json` | 409864 | `432c14eba778273622528c95cd0b12eeb297307864818964d733a1f62388a2b7`
| `evidence/os_page_return_raw_os2.json` | 3199324 | `ccba65df8436e727cbdddddc4360495faed7dad36f24986ca7bd76f1d749703b`
| `evidence/os_page_return_raw_os3.json` | 3346490 | `98d6ddbeed289e4c81d28dbd428e34220030bc9c202320bb9796306e4c400a91`
| `evidence/os_page_return_verdict.json` | 2672 | `074e05269a47fb9356ad43fdca3e7f8c4e8f6657ca02170d20077370aa9cfffe`
| `evidence/os_page_return_verdict_os1.json` | 2807 | `8a3b4b5904bfa098e0e7a9342f3ee774d6791b6ae3a1c221367c22b34d6437dd`
| `evidence/os_page_return_verdict_os2.json` | 2807 | `aaa6cb44f99781a08963e6a5b8268f8e0e9b90856abf632fdd13625af6a807c0`
| `evidence/os_page_return_verdict_os3.json` | 2522 | `a5375c4d5f2a386d38a23ff598285ab0c5e452bd903bff3e689db67709d9a830`
| `evidence/physical_page_return_gate_addendum.json` | 3000 | `fc8f4e09a85f23e50a42738f09c4ab7dec34ed3c49c1589abcdd545ad664dd5f`
| `logs/os_probe_os1.log` | 228 | `18e877cc8b859fa82625552c12ecf3054a875c60cb7d6ad9313a8e8269194ac6`
| `logs/os_probe_os2.log` | 229 | `1fd7f9da7e083ca9ba7a58a4586c4080c0b510220bd1ff3d60e449f2ce614b57`
| `logs/os_probe_os3.log` | 229 | `e02c422b481979bd18a24015a9479aa22a0576b3faa6df823836e963d9d434df`
| `logs/verify_os1.log` | 584 | `6127a69ef3136dc9b3957bdbc12b1660bf42fe202bb8d8aba2fc4d5cd8f74309`
| `logs/verify_os3.log` | 647 | `856b6d2ff560695a6cf6748bf7efe91c436b1edf567fd3879c2eb894e309e096`
| `runs/os1/memprobe.log` | 298 | `0bcd150b970d092fb2a2a161b51ed22b90bf719edb64bda131d6d92018a2e92d`
| `runs/os1/memprobe_os1.json` | 7441 | `2344cf1dcc49754ad73f6fdb9aab5b4d5f00e061f3a10e40461465ff2ef3c406`
| `runs/os1/cache/branch-checkpoints/default_memprobe_main.meta.json` | 508 | `8d4a898ac6a1c875cbc55cce07db2ab0436873bbcef0288281d475d63e470a79`
| `runs/os1/cache/branch-checkpoints/default_memprobe_main.safetensors` | 2269760 | `68e763245cd953b0389bf79112e6f84feebaedbc28e2da4c9bb1c4e1042852e5`
| `runs/os1/cache/prefix-pool/7cc94e3f614b3e35/3b4947891b8872b2-4.json` | 181 | `59acc834722872d3bc83b6beaa00508b445004e3d2a6405d64225e4d0bfd653c`
| `runs/os1/cache/prefix-pool/7cc94e3f614b3e35/3b4947891b8872b2-4.safetensors` | 2269760 | `68e763245cd953b0389bf79112e6f84feebaedbc28e2da4c9bb1c4e1042852e5`
| `runs/os1/home/simigo.sqlite3` | 86016 | `f0ba1169ba084123415857e2e9f62485a134dd1d6c11797ec5898838534535fb`
| `runs/os1/home/simigo.sqlite3-shm` | 32768 | `92acb0992f128236a7ab250f55b3f4e8893061f57098f8a520d0f084056688c8`
| `runs/os1/home/simigo.sqlite3-wal` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
| `runs/os1/home/localb/.fl0712DE11` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
| `runs/os1/home/localb/transport-identity.keychain-db` | 28368 | `f806c45ce484bead5eba2fa60416804ade44b3b722849f95159673e7bd5feca2`
| `runs/os1/home/logs/native_mlx_trace.log` | 1989 | `b7b6e7b4cbf95e4ba2b410b96ab1020bd8e55fead83c80486c4117f43ae4f7ee`
| `runs/os2/memprobe.log` | 298 | `80120def7d353097e728cfdc62fc44c99205361e4a8f96a3064dddb57c873346`
| `runs/os2/memprobe_os2.json` | 7441 | `6537764978d1a22b6028db46d23903ff9b99ad88c4a7a4d66022eca723c7bde1`
| `runs/os2/cache/branch-checkpoints/default_memprobe_main.meta.json` | 508 | `ec26d129d9eef3034134233c39b41761ecd9fef27bdf51efb91df2ab69b8f8fb`
| `runs/os2/cache/branch-checkpoints/default_memprobe_main.safetensors` | 2269760 | `4fa101de398cd52c25fb05164321af76f8a0b3e693756dbb647291d73ef74838`
| `runs/os2/cache/prefix-pool/7cc94e3f614b3e35/3b4947891b8872b2-4.json` | 181 | `f9905966dfe5c7be801c2a8875a36523a49e51ab1cc9f800ac64f5b4ea997af3`
| `runs/os2/cache/prefix-pool/7cc94e3f614b3e35/3b4947891b8872b2-4.safetensors` | 2269760 | `fb26fa757fb72951d7e35a13075df3f352cd976d2b212ca85ce92975781fe2e1`
| `runs/os2/home/simigo.sqlite3` | 86016 | `4c8771e7ff2c4d3314d844440e6f18bbb1a59af85a1679e23e548dbd7a1abab0`
| `runs/os2/home/simigo.sqlite3-shm` | 32768 | `96b3f0389a818de19bf3c3f71383e07aa6736c2733069266e969410c484a260c`
| `runs/os2/home/simigo.sqlite3-wal` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
| `runs/os2/home/localb/.fl0712DE11` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
| `runs/os2/home/localb/transport-identity.keychain-db` | 28368 | `cf26a5b618c2e03203b411f5ebdc2b11e8f5ca4d44edfc57db0ff614e8e887d8`
| `runs/os2/home/logs/native_mlx_trace.log` | 1989 | `255a3fd541e305afe8f9aca94c0f201446342c799a43699341882129d8e11ca3`
| `runs/os3/memprobe.log` | 298 | `09f10a953208185108dbde6f422b80511189eb247cc53ac194d784c124d69067`
| `runs/os3/memprobe_os3.json` | 7441 | `149d8e8bd66fef625684cde99d572138c3a9bf3419099fc974bbf43c9c1a4b68`
| `runs/os3/cache/branch-checkpoints/default_memprobe_main.meta.json` | 508 | `03fb7859ccb174f8684905d4676ce4f7ac3a8641bf833098dd41262d1625801d`
| `runs/os3/cache/branch-checkpoints/default_memprobe_main.safetensors` | 2269760 | `e88c55c8cb6d6b69dbe7a807a73eb77f9a75ac43d2746d655cf169bf500ee218`
| `runs/os3/cache/prefix-pool/7cc94e3f614b3e35/3b4947891b8872b2-4.json` | 181 | `9dda645eec22f85dec58f00afec49c00edb47687e83747f2ac115a0b1dd2c035`
| `runs/os3/cache/prefix-pool/7cc94e3f614b3e35/3b4947891b8872b2-4.safetensors` | 2269760 | `c52d5d6cadb41d73e79a5aad0cd048f40e0837a7ba676468bf74f41f86319247`
| `runs/os3/home/simigo.sqlite3` | 86016 | `b8842daba4555bd583b6bfa8ff7e8db86136bbbdd43ab28b9fec33bfb5c54222`
| `runs/os3/home/simigo.sqlite3-shm` | 32768 | `215615a4a39eb98dc87ebe78433a7af16d39a3108e9682e2cc361cf06eb47fb6`
| `runs/os3/home/simigo.sqlite3-wal` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
| `runs/os3/home/localb/.fl0712DE11` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
| `runs/os3/home/localb/transport-identity.keychain-db` | 28364 | `839489382757dacc07ab362b427ef367f6f0d9a22388e65b18f0a2bb701f6a3d`
| `runs/os3/home/logs/native_mlx_trace.log` | 1989 | `a6184bff9cc0234c507a213084eb37d1ec6b37ccff68f379e8e1e56346a93355`
