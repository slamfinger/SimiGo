#!/usr/bin/env bash
# Audit the tracked tree for open-source release blockers.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

check() {
  local label=$1
  shift
  if "$@"; then
    echo "PASS: $label"
  else
    echo "FAIL: $label" >&2
    fail=1
  fi
}

path_re='/Users''/'
user_re='mr''\.simi'
team_re='YPXU''8M53F9'
email_re='slamfinger''@163''\.com'

check "no tracked local absolute paths or local user identifiers" \
  bash -c '! git grep -I -n -E "$0|$1" -- .' "$path_re" "$user_re"
check "no tracked signing team or private email" \
  bash -c '! git grep -I -n -E "$0|$1" -- .' "$team_re" "$email_re"
check "no tracked model-weight artifacts" \
  bash -c '! git ls-files | grep -Ei "\.(safetensors|gguf|bin|pth|ckpt|weights)$"'
check "no tracked packaged app or DMG" \
  bash -c '! git ls-files | grep -Ei "(^|/)(SimiGo\.app|.*\.dmg)$"'
check "required code and documentation licenses" \
  bash -c 'test -s LICENSE && test -s LICENSE-DOCS'
check "third-party notice exists" \
  bash -c 'test -s THIRD_PARTY_NOTICES.md'
check "trademark boundary exists" \
  bash -c 'test -s TRADEMARKS.md'
check "security policy exists" \
  bash -c 'test -s SECURITY.md'
check "continuous integration workflow exists" \
  bash -c 'test -s .github/workflows/ci.yml'

exit "$fail"
