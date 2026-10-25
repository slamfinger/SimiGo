#!/bin/bash
# Re-verify every file listed in MANIFEST_SHA256.txt from inside the batch dir.
set -u
cd "$(dirname "$0")/.." || exit 2
shasum -a 256 -c MANIFEST_SHA256.txt 2>&1 | awk '
  /: OK$/ {ok++}
  /FAILED/ {bad++; print}
  END {printf "manifest_ok=%d manifest_failed=%d\n", ok, bad+0;
       exit (bad+0 ? 1 : 0)}'
