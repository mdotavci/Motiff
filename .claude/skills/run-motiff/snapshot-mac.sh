#!/usr/bin/env bash
# Opens the Mac app once per route and saves a PNG of its window for each.
#
#   snapshot-mac.sh <path/to/Motiff.app> <out-dir> <route>...
#   route: library | inbox | boards | canvas:<title>, then optional |-separated extras:
#          select=<node title, or its start>  inspector  detail  paste=<text>  shortcuts
#   e.g.   "canvas:Product photography look|select=Light|inspector"
#
# The app draws its own window into Snapshots/<name>.png (-MotiffSnapshot), so this needs no
# screen-recording permission. Debug builds only: the launch arguments are compiled out of Release.
set -euo pipefail

APP="$1"
OUT="$2"
shift 2

SNAPS="$HOME/Library/Containers/com.mdotavci.motiff/Data/Library/Application Support/Motiff/Snapshots"
mkdir -p "$OUT"

i=0
for route in "$@"; do
  i=$((i + 1))
  slug=$(printf '%s' "$route" | tr -c 'A-Za-z0-9' '-' | sed -e 's/--*/-/g' -e 's/-$//')
  name=$(printf '%02d-%s' "$i" "$slug")

  pkill -x Motiff 2>/dev/null || true
  sleep 1
  rm -f "$SNAPS/$name.png"
  IFS='|' read -r -a parts <<< "$route"
  args=(-MotiffOpen "${parts[0]}" -MotiffSnapshot "$name")
  # macOS bash 3.2: an empty array can't be expanded under `set -u`, so index instead.
  for ((p = 1; p < ${#parts[@]}; p++)); do
    extra="${parts[$p]}"
    case "$extra" in
      select=*) args+=(-MotiffSelect "${extra#select=}") ;;
      inspector) args+=(-MotiffInspector YES) ;;
      detail) args+=(-MotiffDetail YES) ;;
      paste=*) args+=(-MotiffPaste "${extra#paste=}") ;;
      shortcuts) args+=(-MotiffShortcuts YES) ;;
      *) echo "Unknown extra: $extra" >&2 ;;
    esac
  done
  open -n "$APP" --args "${args[@]}"

  for _ in $(seq 1 30); do
    [ -f "$SNAPS/$name.png" ] && break
    sleep 1
  done

  if [ -f "$SNAPS/$name.png" ]; then
    cp "$SNAPS/$name.png" "$OUT/$name.png"
    echo "Saved $OUT/$name.png ($route)"
  else
    echo "No snapshot for $route after 30s; trying screencapture" >&2
    screencapture -x "$OUT/$name-screen.png" || true
  fi
done

pkill -x Motiff 2>/dev/null || true
