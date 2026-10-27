#!/bin/zsh
# C-1 overwrite install of the post-fix Release bundle. Mirrors the B-7 install
# record: quit the old instance, replace the bundle, verify identity, keep the
# first-run marker (so the wizard / engine bootstrap do not rerun), relaunch.
set -u
SRC=${1:-/tmp/simigo_rel/Build/Products/Release/SimiGo.app}
EV=${2:?evidence dir}
APP=/Applications/SimiGo.app
EXE=$APP/Contents/MacOS/SimiGo
{
  echo "== install $(date '+%F %T') =="
  echo "src=$SRC"
  echo "src_exe_sha256=$(shasum -a 256 "$SRC/Contents/MacOS/SimiGo" | cut -d' ' -f1)"
  echo "old_pid=$(pgrep -f "$EXE" | tr '\n' ' ')"
  pkill -f "$EXE" 2>/dev/null
  sleep 2
  echo "old_pid_after_quit=$(pgrep -f "$EXE" | tr '\n' ' ')"
  rm -rf "$APP"
  cp -R "$SRC" "$APP"
  echo "installed_exe_sha256=$(shasum -a 256 "$EXE" | cut -d' ' -f1)"
  echo "installed_exe_mtime=$(stat -f %Sm -t '%F %T' "$EXE")"
  if codesign --verify --deep --strict "$APP"; then echo "codesign_verify=ok"; else echo "codesign_verify=FAILED"; fi
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^Identifier|^Signature|^TeamIdentifier'
  if [[ -f "$HOME/.simigo/manifests/first-run-done.json" ]]; then
    echo "first_run_marker_kept=yes"
  else
    echo "first_run_marker_kept=no"
  fi
  open "$APP"
  echo launched
} 2>&1 | tee "$EV/install.log"
