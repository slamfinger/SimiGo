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

check "no tracked local absolute paths or local user identifiers" \
  bash -c '! git grep -I -n -E "/Users/|mr\.simi" -- .'
check "no tracked signing team or private email" \
  bash -c '! git grep -I -n -E "YPXU8M53F9|slamfinger@163\.com" -- .'
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

exit "$fail"
