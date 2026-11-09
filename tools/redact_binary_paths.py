#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抹掉 Release 可执行文件里编译期写死的构建路径（等长字节替换 + 重新 adhoc 签名）。

为什么需要：C++ 的 `__FILE__` 与 Swift 的 `#filePath` 会把 `/Users/<name>/…`
原样编进可执行文件。本机实测：2.2.6(37) 的 Release 二进制里 225 条不同路径、
38,312 次出现，几乎全部来自 mlx-swift 里的 fmt/assert。发布门的
`forbidden_literals`（`/Users/`、用户名）与 `home_paths` 规则因此必红，
而文本级清洗救不了 Mach-O：变长替换会让后续偏移与代码签名一起作废。

所以用等长替换：`/Users/` → `/build/`（7 字节对 7 字节），用户名 → 等长填充。
任何偏移都不移动，__cstring 里的指针仍然指向同一位置。替换后原签名必然失效，
脚本随即 `codesign --force --sign -`（adhoc），与既定发布形态一致。

只动路径字符串，不动任何指令：这些串只被 assert/诊断信息引用。

用法:
    python3 tools/redact_binary_paths.py <binary> [--apply]

不带 --apply 只报告命中数，不写文件。仅依赖标准库 + 系统 codesign。
"""
import argparse
import os
import shutil
import subprocess
import sys

FORBIDDEN = ("/Users/", "mr.simi", "YPXU8M53F9", "slamfinger@163.com")
HOME_PREFIX = b"/Users/"
HOME_ALIAS = b"/build/"


def replacements():
    """(原始字节, 等长替身) 列表。替身长度与原始一致，绝不移动偏移。"""
    user = os.path.basename(os.path.expanduser("~")).encode()
    pairs = [(HOME_PREFIX, HOME_ALIAS)]
    if user != HOME_ALIAS.strip(b"/"):
        pairs.append((user, b"b" * len(user)))
    for literal in FORBIDDEN[2:]:
        raw = literal.encode()
        pairs.append((raw, b"x" * len(raw)))
    return pairs


def main():
    parser = argparse.ArgumentParser(description="等长抹除二进制内的构建路径")
    parser.add_argument("binary")
    parser.add_argument("--apply", action="store_true", help="写回文件并重新 adhoc 签名")
    parser.add_argument("--no-backup", action="store_true",
                        help="不写 .unredacted-binary 副本（用于打包时的临时拷贝）")
    args = parser.parse_args()

    with open(args.binary, "rb") as handle:
        data = handle.read()
    original_size = len(data)

    counts = {}
    for raw, alias in replacements():
        assert len(raw) == len(alias), (raw, alias)
        hits = data.count(raw)
        if hits:
            counts[raw.decode()] = hits
            data = data.replace(raw, alias)

    leftover = [literal for literal in FORBIDDEN
                if literal.encode() in data]
    for label, hits in sorted(counts.items()):
        print(f"  {label!r}: {hits:,}")
    print(f"size {original_size:,} -> {len(data):,} (must be equal)")
    print(f"leftover forbidden literals: {leftover or 'none'}")
    if len(data) != original_size or leftover:
        print("REFUSED: replacement would move offsets or left a literal behind")
        return 1

    if not args.apply:
        print("dry run: nothing written (pass --apply to rewrite and re-sign)")
        return 0

    if not counts:
        # 已经是干净的：不写备份、不重新签名，免得把一颗 76 MB 的副本
        # 留在 staging 目录里被打进 DMG。
        print("already clean: nothing to rewrite")
        return 0

    app = os.path.abspath(os.path.join(os.path.dirname(args.binary), "..", ".."))
    # Backups go beside the bundle, never inside it: a stray file under
    # Contents/MacOS becomes a nested code object and breaks --deep verification.
    backup = app + ".unredacted-binary"
    if args.no_backup:
        backup = None
    if backup and not os.path.exists(backup):
        shutil.copy2(args.binary, backup)
    with open(args.binary, "wb") as handle:
        handle.write(data)
    subprocess.run(["codesign", "--force", "--sign", "-", app], check=True)
    print(f"rewritten and adhoc re-signed: {app}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
