#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""外部 Agent 前缀体检（只读，不改任何文件，不进 DMG）。

只量「会进每轮请求前缀」的东西：常驻注入的文本文件、技能索引
（name + description，与宿主展示给模型的那行同源）、插件开关数。
技能目录里的 scripts/ 永远不进提示词，所以不按目录体积计——目录大小与
冷 prefill 无关，报出来只会误导。

为什么只读：Codex / QoderCN / ZCode 的配置是别人家的产品数据。SimiGo 的立场是
完整承载外部 Agent 的上下文（工具面、技能、系统提示都不替它裁），「关掉哪些」
只能是 owner 的决定，脚本只把开关现状与索引体积摆出来。
也就不进 DMG：它读的是本机三个 agent 的私有配置，版本一变读数就过期。

冷 prefill 的真实读数不在这里，用引擎遥测：

    python3 tools/prefill_stats.py --since "YYYY-MM-DD HH:MM"

用法:
    python3 tools/agent_prefix_audit.py [--json] [--home DIR]

仅依赖标准库。
"""
import argparse
import json
import os
import re

FRONTMATTER_RE = re.compile(
    r"^\s*(?:name|description)\s*:\s*(.*)$", re.M)
PLUGIN_ON_RE = re.compile(r"^enabled\s*=\s*(true|false)")


def _bytes(path):
    try:
        return os.path.getsize(path) if os.path.isfile(path) else 0
    except OSError:
        return 0


def _skills(directory):
    """(技能数, 索引字节估计)。索引 = 名字 + 描述 + 文件路径，与宿主
    `### 名字: 描述 (file: 路径)` 那一行同构。"""
    if not os.path.isdir(directory):
        return 0, 0
    count = index = 0
    for name in sorted(os.listdir(directory)):
        skill_md = os.path.join(directory, name, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue
        count += 1
        index += len(name) + len(skill_md)
        try:
            with open(skill_md, encoding="utf-8", errors="replace") as handle:
                head = handle.read(4096)
        except OSError:
            continue
        for match in FRONTMATTER_RE.finditer(head):
            index += len(match.group(1).strip())
    return count, index


def codex(home):
    base = os.path.join(home, ".codex")
    config = os.path.join(base, "config.toml")
    enabled = disabled = 0
    section = ""
    if os.path.isfile(config):
        with open(config, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                stripped = line.strip()
                if stripped.startswith("["):
                    section = stripped
                    continue
                if section.startswith("[plugins.") and PLUGIN_ON_RE.match(stripped):
                    if stripped.endswith("true"):
                        enabled += 1
                    else:
                        disabled += 1
    count, index = _skills(os.path.join(base, "skills"))
    files = [("config.toml", config), ("AGENTS.md", os.path.join(base, "AGENTS.md"))]
    return files, {"plugins enabled": enabled, "plugins disabled": disabled,
                   "skills": count, "skill index bytes": index}


def qoder(home):
    user = os.path.join(home, "Library", "Application Support", "QoderCN", "User")
    settings = os.path.join(user, "settings.json")
    keys = []
    if os.path.isfile(settings):
        try:
            with open(settings, encoding="utf-8", errors="replace") as handle:
                data = json.load(handle)
            keys = sorted(data) if isinstance(data, dict) else []
        except (OSError, ValueError):
            keys = ["<unreadable>"]
    count, index = _skills(os.path.join(home, ".qoder", "skills"))
    return [("settings.json", settings)], {
        "settings keys": ", ".join(keys) or "-", "skills": count,
        "skill index bytes": index}


def zcode(home):
    base = os.path.join(home, ".zcode")
    count, index = _skills(os.path.join(base, "skills"))
    files = [("AGENTS.md", os.path.join(base, "AGENTS.md")),
             ("CLAUDE.md", os.path.join(base, "CLAUDE.md"))]
    return files, {"skills": count, "skill index bytes": index}


AGENTS = (("codex", codex), ("qoder", qoder), ("zcode", zcode))


def main():
    parser = argparse.ArgumentParser(description="外部 Agent 前缀体检（只读）")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--home", default=os.path.expanduser("~"))
    args = parser.parse_args()

    report = []
    for name, gather in AGENTS:
        files, counters = gather(args.home)
        rows = [{"file": label, "path": path, "bytes": _bytes(path)}
                for label, path in files]
        report.append({"agent": name, "files": rows, "counters": counters,
                       "prefixBytesUpperBound": sum(r["bytes"] for r in rows)
                       + counters.get("skill index bytes", 0)})

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return

    for item in report:
        print(f"== {item['agent']}  前缀相关字节(上界) {item['prefixBytesUpperBound']:,}")
        for row in item["files"]:
            print(f"   {row['file']:<14} {row['bytes']:>8,}  {row['path']}")
        for key, value in item["counters"].items():
            print(f"   {key:<28} {value:,}" if isinstance(value, int)
                  else f"   {key:<28} {value}")
    print("\n上界里不含工具 schema——那部分由宿主在拼请求时生成，只有 prefill 的 "
          "promptTokens 侧面能看见：\n  python3 tools/prefill_stats.py "
          "--since 'YYYY-MM-DD HH:MM'")


if __name__ == "__main__":
    main()
