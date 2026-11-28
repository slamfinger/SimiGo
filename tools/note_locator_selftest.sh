#!/bin/bash
# Isolated self-test for tools/note_locator.swift.
# Builds into a temp dir and queries a temp SQLite DB only; never opens the
# production store and never writes outside the temp root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/note-locator-selftest.XXXXXX")"
BIN="$WORK/note_locator"
DB="$WORK/test.sqlite3"
trap 'rm -rf "$WORK"' EXIT

command -v swiftc >/dev/null || { echo "FAIL: swiftc not found" >&2; exit 3; }
command -v sqlite3 >/dev/null || { echo "FAIL: sqlite3 not found" >&2; exit 3; }
command -v python3 >/dev/null || { echo "FAIL: python3 not found" >&2; exit 3; }

echo "== build =="
swiftc -O -parse-as-library "$ROOT/tools/note_locator.swift" -lsqlite3 -o "$BIN"
echo "built: $BIN"

sqlite3 "$DB" <<'SQL'
CREATE TABLE project_notes(
    note_id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    claim TEXT NOT NULL,
    supersedes TEXT,
    object_id TEXT NOT NULL,
    recorded_at TEXT NOT NULL
);
INSERT INTO project_notes VALUES
 ('11111111-1111-4111-8111-111111111111','claim@L2','alpha',NULL,'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','1000'),
 ('22222222-2222-4222-8222-222222222222','claim@L2','alpha v2','11111111-1111-4111-8111-111111111111','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','2000'),
 ('33333333-3333-4333-8333-333333333333','claim@L1','beta',NULL,'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc','1500'),
 ('44444444-4444-4444-8444-444444444444','decision@owner','100% done_thing',NULL,'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd','2500'),
 ('55555555-5555-4555-8555-555555555555','claim@L3','gamma',NULL,'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee','3500');
SQL

DB_BEFORE="$(shasum -a 256 "$DB" | awk '{print $1}')"
pass=0

check() {
  local name="$1" expected_count="$2" expected_first="$3" expected_all_current="$4"
  shift 4
  local out rc
  set +e
  out="$("$BIN" --db "$DB" "$@")"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name: exit $rc"
    exit 1
  fi
  python3 - "$name" "$expected_count" "$expected_first" "$expected_all_current" "$out" <<'PY'
import json, sys
name = sys.argv[1]
expected_count = int(sys.argv[2])
expected_first = sys.argv[3]
expected_all_current = sys.argv[4] == "1"
rows = json.loads(sys.argv[5])
assert isinstance(rows, list), (name, type(rows))
assert len(rows) == expected_count, (name, len(rows), expected_count)
if expected_first:
    assert rows[0]["note_id"].startswith(expected_first), (name, rows[0]["note_id"])
if expected_all_current:
    assert all(r["is_current"] is True for r in rows), (name, [r["is_current"] for r in rows])
for r in rows:
    for key in ("note_id", "kind", "claim", "object_id", "recorded_at",
                "recorded_at_iso", "recorded_at_cst", "is_current", "supersedes"):
        assert key in r, (name, key)
print("PASS", name, "n=%d" % len(rows))
PY
  pass=$((pass + 1))
}

echo "== cases =="
check "kind exact (history, newest first)" 2 22222222 0 --kind claim@L2
check "kind exact + current-only" 1 22222222 1 --kind claim@L2 --current-only
check "kind prefix claim@" 4 55555555 0 --kind-prefix claim@
check "note-id exact lowercase" 1 22222222 0 --note-id 22222222-2222-4222-8222-222222222222
check "note-id prefix" 1 11111111 0 --note-id-prefix 11111111
check "time window inclusive" 3 44444444 0 --after 1500 --before 3000
check "ISO time" 5 55555555 0 --after 2001-01-01T00:00:00Z
check "LIKE wildcard % literal" 0 "" 0 --kind-prefix 'decision@ow%'
check "LIKE wildcard _ literal" 0 "" 0 --kind-prefix 'decision@ow_er'
check "exact kind decision" 1 44444444 0 --kind decision@owner
check "limit 2" 2 55555555 0 --kind-prefix claim@ --limit 2
check "empty result" 0 "" 0 --kind absent@nowhere

set +e
"$BIN" --db "$DB" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
  echo "FAIL no-selector: exit $rc (want 2)"
  exit 1
fi
echo "PASS no-selector exit=2"
pass=$((pass + 1))

set +e
"$BIN" --db "$WORK/missing.sqlite3" --kind claim@L2 >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 3 ]; then
  echo "FAIL missing-db: exit $rc (want 3)"
  exit 1
fi
echo "PASS missing-db exit=3"
pass=$((pass + 1))

"$BIN" --help | grep -q '用法'
echo "PASS help"
pass=$((pass + 1))

DB_AFTER="$(shasum -a 256 "$DB" | awk '{print $1}')"
if [ "$DB_BEFORE" != "$DB_AFTER" ]; then
  echo "FAIL read-only: temp DB bytes changed"
  exit 1
fi
if [ -e "$DB-wal" ] || [ -e "$DB-journal" ]; then
  echo "FAIL read-only: journal sidecar created"
  exit 1
fi
echo "PASS read-only (db sha unchanged, no journal sidecar)"
pass=$((pass + 1))

echo "== SELFTEST PASS $pass cases =="