#!/usr/bin/env bash
# Launches the iOS app in a booted simulator once per route and screenshots each.
#
#   snapshot-ios.sh <simulator udid> <out-dir> <route>...
#   route: library | inbox | boards | board:<title> (or canvas:<title>), then optional |-separated extras:
#          select=<node title, or its start>  inspector  detail  filter=<category>  view=map|outline|graph  find=<text>
#   e.g.   "canvas:Product photography look|view=map"
#
# The app must already be installed (xcrun simctl install). Debug builds only: the launch
# arguments are compiled out of Release.
set -euo pipefail

UDID="$1"
OUT="$2"
shift 2
BUNDLE=com.mdotavci.motiff

mkdir -p "$OUT"

i=0
for route in "$@"; do
  i=$((i + 1))
  slug=$(printf '%s' "$route" | tr -c 'A-Za-z0-9' '-' | sed -e 's/--*/-/g' -e 's/-$//')
  name=$(printf 'ios-%02d-%s' "$i" "$slug")

  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 1
  IFS='|' read -r -a parts <<< "$route"
  args=(-MotiffOpen "${parts[0]}")
  for ((p = 1; p < ${#parts[@]}; p++)); do
    extra="${parts[$p]}"
    case "$extra" in
      select=*) args+=(-MotiffSelect "${extra#select=}") ;;
      inspector) args+=(-MotiffInspector YES) ;;
      detail) args+=(-MotiffDetail YES) ;;
      filter=*) args+=(-MotiffFilter "${extra#filter=}") ;;
      view=*) args+=(-MotiffView "${extra#view=}") ;;
      find=*) args+=(-MotiffFind "${extra#find=}") ;;
      *) echo "Unknown extra: $extra" >&2 ;;
    esac
  done
  xcrun simctl launch "$UDID" "$BUNDLE" "${args[@]}" > /dev/null
  # The route waits 1.5s for seeding, then thumbnails load.
  sleep 7
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" > /dev/null 2>&1
  echo "Saved $OUT/$name.png ($route)"

  # If the app hung or died on this route, keep what explains it next to the screenshot:
  # a sample of the running process (its main thread), or the newest crash report.
  pid=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null \
    | awk '/UIKitApplication:com\.mdotavci\.motiff\[/ { print $1; exit }' || true)
  if [ -n "$pid" ] && [ "$pid" != "-" ]; then
    sample "$pid" 1 -file "$OUT/$name.sample.txt" > /dev/null 2>&1 || true
  else
    crash=$(ls -t "$HOME"/Library/Logs/DiagnosticReports/Motiff*.ips 2>/dev/null | head -1 || true)
    if [ -n "$crash" ]; then cp "$crash" "$OUT/$name.crash.ips"; fi
    echo "  App is not running after $route"
  fi
done

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
