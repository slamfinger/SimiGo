#!/bin/bash
# 迁移演练：证明「旧包读得开 35 → 新包升到 36 → 行数不变 → 旧包再也打不开」。
#
# 全程用 SIMIGO_HOME 指向副本库，不碰 ~/.simigo/simigo.sqlite3。
#
#   tools/migration_drill.sh --new build/drill-dd/Build/Products/Release/SimiGo.app
#
# 旧包默认取 /Applications/SimiGo.app（已装 build 54，schema 35）。
set -uo pipefail

OLD_APP="/Applications/SimiGo.app"
NEW_APP=""
SRC_DB="$HOME/.simigo/simigo.sqlite3"
WORK="${TMPDIR:-/tmp}/simigo-drill-$(date +%Y%m%d-%H%M%S)"
# SIMIGO_HOME 指的就是 `.simigo` 这一层（ManagedPaths.managedRoot 直接返回它），
# 所以库在 $HOME/simigo.sqlite3，不在 $HOME/.simigo/simigo.sqlite3。第一版把副本
# 放进 .simigo/ 子目录，两个包都找不到库、各自 bootstrap 了一个空库，全程没测到
# 迁移——数字全是空的，还看不出错。
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

head_of() { sqlite3 "file:$1?mode=ro&immutable=1" ".timeout 10000" "select max(version) from schema_migrations;" 2>/dev/null; }
counts() {
  # 必须 immutable=1：.backup 出来的副本是 WAL 模式且没有 -wal/-shm，
  # 只读打开会因为建不了 -shm 直接失败（第一版招牌就栽在这，四个数全空）。
  sqlite3 "file:$1?mode=ro&immutable=1" ".timeout 10000" \
    "select '$2', (select max(version) from schema_migrations), $(echo "$TABLES" | tr ' ' '\n' | sed 's/.*/ (select count(*) from &)/' | paste -sd, -);" 2>/dev/null
}
run_app() {  # $1=app $2=home $3=秒 $4=日志名
  local bin="$1/Contents/MacOS/$(basename "${1%.app}")"
  [ -x "$bin" ] || bin=$(ls "$1/Contents/MacOS/"* | head -1)
  # 日志按步骤分开：三处都写 app.log 的话，第 3 步会把新包的日志盖掉，
  # 新包为什么没升库就查不到了。
  SIMIGO_HOME="$2" "$bin" >"$2/$4" 2>&1 &
  local pid=$!
  for _ in $(seq 1 "$3"); do sleep 1; kill -0 $pid 2>/dev/null || break; done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  # 旧包会在这个空 home 里跑一遍 ggml 的 cmake 构建，日志尾巴全是编译行，
  # 直接 tail 看不见迁移相关的报错，所以先挑关键行再补末 2 行。
  echo "-- $4 关键行 --"
  grep -iE "migration|schema|refus|太新|downgrade|error|fail" "$2/$4" | head -6
  echo "-- $4 末 2 行 --"; tail -2 "$2/$4"
}

echo "源库：$SRC_DB"
echo "工作区：$WORK"
for side in old new; do
  mkdir -p "$WORK/$side"
  sqlite3 "file:$SRC_DB?mode=ro&immutable=1" ".timeout 30000" ".backup '$WORK/$side/simigo.sqlite3'" || exit 1
done

echo
echo "== 0. 副本起点 =="
echo "$(counts "$WORK/old/simigo.sqlite3" before)"

echo
echo "== 1. 旧包打开副本（应停在 35，不升库）=="
run_app "$OLD_APP" "$WORK/old" 25 old-app.log
echo "$(counts "$WORK/old/simigo.sqlite3" old-app)"

echo
echo "== 2. 新包打开副本（应升到 36）=="
run_app "$NEW_APP" "$WORK/new" 40 new-app.log
echo "$(counts "$WORK/new/simigo.sqlite3" new-app)"

echo
echo "== 3. 旧包再开已升级的库（应拒开）=="
run_app "$OLD_APP" "$WORK/new" 25 old-reopen.log
echo "旧包 log 末 3 行："; tail -3 "$WORK/new/old-reopen.log"
echo "$(counts "$WORK/new/simigo.sqlite3" after-old-reopen)"

echo
echo "判据：1 行 35；2 行 36 且各表行数与 0 行相同；3 行仍是 36 且旧包报 migration 错。"
