#!/bin/bash
# 迁移演练：证明「旧包读得开 35 → 停在 35 → 新包升到 36 且行数不变 → 旧包再开被拒」。
#
#   tools/migration_drill.sh --new build/drill-dd/Build/Products/Release/SimiGo.app
#
# 这个脚本是**可判定的**：每一条判据都程序化比较，任一不符就以非零退出。
# 只打印数字不算证据——第二轮代码审核指出过这一点，这里按它改。
#
# 全程用 SIMIGO_HOME 指向副本库，不碰 ~/.simigo/simigo.sqlite3。
# 注意 SIMIGO_HOME 就是 `.simigo` 那一层（ManagedPaths.managedRoot 直接返回它），
# 所以库在 $SIMIGO_HOME/simigo.sqlite3，不在它下面的 .simigo/ 里。
set -uo pipefail

OLD_APP="/Applications/SimiGo.app"
NEW_APP=""
SRC_DB="$HOME/.simigo/simigo.sqlite3"
WORK="${TMPDIR:-/tmp}/simigo-drill-$(date +%Y%m%d-%H%M%S)"
TABLES="chat_messages turn_digests is_objects spaces space_turns keywords settlements"

while [ $# -gt 0 ]; do
  case "$1" in
    --old) OLD_APP="$2"; shift 2;;
    --new) NEW_APP="$2"; shift 2;;
    --db)  SRC_DB="$2"; shift 2;;
    --work) WORK="$2"; shift 2;;
    *) echo "未知参数 $1"; exit 2;;
  esac
done
[ -n "$NEW_APP" ] || { echo "缺 --new <新包 .app>"; exit 2; }
mkdir -p "$WORK"

FAILED=0
check() {  # $1=判据 $2=期望 $3=实际
  if [ "$2" = "$3" ]; then
    echo "PASS  $1：$3"
  else
    echo "FAIL  $1：期望 [$2] 实际 [$3]"
    FAILED=1
  fi
}
contains() {  # $1=判据 $2=子串 $3=实际
  case "$3" in
    *"$2"*) echo "PASS  $1：$3";;
    *) echo "FAIL  $1：期望包含 [$2] 实际 [$3]"; FAILED=1;;
  esac
}

# 副本是 WAL 模式且没有 -wal/-shm，只读打开必须 immutable=1，否则开不了。
head_of() {
  sqlite3 "file:$1?mode=ro&immutable=1" ".timeout 10000" \
    "select max(version) from schema_migrations;" 2>/dev/null
}
rows_of() {  # 各表行数拼成一行，用来比较「迁移没有动数据」
  sqlite3 "file:$1?mode=ro&immutable=1" ".timeout 10000" \
    "$(echo "$TABLES" | tr ' ' '\n' | sed 's/.*/select count(*) from &;/' | paste -sd' ' -)" \
    2>/dev/null | paste -sd'|' -
}
report_step() {  # $1=home $2=step id → "status|detail" 或 MISSING
  python3 - "$1/manifests/bootstrap-report.json" "$2" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
try:
    doc = json.load(open(path))
except Exception:
    print("MISSING")
    raise SystemExit
for step in doc.get("steps", []):
    if step.get("id") == wanted:
        print(f"{step.get('status')}|{step.get('detail')}")
        break
else:
    print("MISSING")
PY
}

run_app() {  # $1=app $2=home $3=秒 $4=日志名 → 退出码进 APP_EXIT
  local bin="$1/Contents/MacOS/$(basename "${1%.app}")"
  [ -x "$bin" ] || bin=$(ls "$1/Contents/MacOS/"* | head -1)
  SIMIGO_HOME="$2" "$bin" >"$2/$4" 2>&1 &
  local pid=$!
  for _ in $(seq 1 "$3"); do sleep 1; kill -0 $pid 2>/dev/null || break; done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  APP_EXIT=$?
  # 变量后紧跟中文必须加花括号：这个 locale 下 bash 会把中文首字节当成变量名的一部分。
  echo "-- $4 退出码 ${APP_EXIT}，关键行 --"
  grep -iE "migration|schema|refus|bootstrap" "$2/$4" | head -4
}

echo "源库：$SRC_DB"
echo "工作区：$WORK"
for side in old new; do
  mkdir -p "$WORK/$side"
  sqlite3 "file:$SRC_DB?mode=ro&immutable=1" ".timeout 30000" \
    ".backup '$WORK/$side/simigo.sqlite3'" || { echo "备份失败"; exit 1; }
done

BASE_ROWS=$(rows_of "$WORK/old/simigo.sqlite3")
BASE_HEAD=$(head_of "$WORK/old/simigo.sqlite3")

echo
echo "== 0. 副本起点 =="
echo "schema=$BASE_HEAD 行数=$BASE_ROWS"
check "起点 schema" "35" "$BASE_HEAD"
[ -n "$BASE_ROWS" ] && [ "$BASE_ROWS" != "$(printf '0|%.0s' 1 2 3 4 5 6)0" ] \
  || { echo "FAIL 副本行数为空"; FAILED=1; }

echo
echo "== 1. 旧包打开副本（应停在 35，不动数据）=="
run_app "$OLD_APP" "$WORK/old" 25 old-app.log
check "旧包后 schema" "35" "$(head_of "$WORK/old/simigo.sqlite3")"
check "旧包后行数" "$BASE_ROWS" "$(rows_of "$WORK/old/simigo.sqlite3")"
contains "旧包确实启动并写了报告" "ok" "$(report_step "$WORK/old" "migrate-schema")"

echo
echo "== 2. 新包打开副本（应升到 36，不动数据）=="
run_app "$NEW_APP" "$WORK/new" 40 new-app.log
check "新包后 schema" "36" "$(head_of "$WORK/new/simigo.sqlite3")"
check "新包后行数" "$BASE_ROWS" "$(rows_of "$WORK/new/simigo.sqlite3")"
contains "新包迁移步骤" "ok|schemaVersion=36" "$(report_step "$WORK/new" "migrate-schema")"

echo
echo "== 3. 旧包再开已升级的库（应明确拒绝迁移）=="
run_app "$OLD_APP" "$WORK/new" 25 old-reopen.log
check "旧包重开后 schema 未被改回" "36" "$(head_of "$WORK/new/simigo.sqlite3")"
check "旧包重开后行数" "$BASE_ROWS" "$(rows_of "$WORK/new/simigo.sqlite3")"
contains "旧包拒绝了更高的 schema" \
  "failed|sql(\"migration head 36 != declared 35\")" \
  "$(report_step "$WORK/new" "migrate-schema")"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "全部判据通过。"
  exit 0
fi
echo "有判据未通过（上面的 FAIL 行）。"
exit 1
