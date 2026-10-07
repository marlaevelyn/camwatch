#!/bin/bash
# Build camwatch and start it at login. Safe to re-run, e.g. after `git pull`.
#
#   ./install.sh               build and (re)start the LaunchAgent
#   ./install.sh <ip|mac> ...  also choose the WiZ bulb(s) to control

set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
label="com.camwatch"
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

cd "$dir"

# Mic detection needs macOS 14.2+.
version="$(sw_vers -productVersion)"
if [ "$(printf '%s\n' 14.2 "$version" | sort -V | head -1)" != 14.2 ]; then
  echo "camwatch needs macOS 14.2 or later (this Mac has $version)." >&2
  exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Run: xcode-select --install   then re-run ./install.sh" >&2
  exit 1
fi

echo "Building camwatch..."
# Build to a temp file and move it into place so a running copy isn't disturbed.
swiftc -O camwatch.swift -o camwatch.new -framework CoreMediaIO -framework CoreAudio
mv camwatch.new camwatch

if [ $# -gt 0 ]; then
  ./set-bulb "$@"
elif [ ! -f bulb.conf ]; then
  echo
  echo "No bulb chosen yet. camwatch will run, but won't change any lights until you run:"
  echo "  ./set-bulb              # list bulbs"
  echo "  ./set-bulb <ip or mac>  # choose one"
  echo
fi

echo "Installing LaunchAgent..."
mkdir -p "$(dirname "$plist")"
sed "s|CAMWATCH_DIR|$dir|g" com.camwatch.plist > "$plist"
if launchctl bootout "$domain/$label" 2>/dev/null; then
  # bootout returns before the job is fully gone; bootstrapping too soon fails with error 5.
  for _ in $(seq 20); do
    launchctl print "$domain/$label" >/dev/null 2>&1 || break
    sleep 0.25
  done
fi
launchctl bootstrap "$domain" "$plist"

sleep 2
if launchctl print "$domain/$label" | grep -q "state = running"; then
  echo "camwatch is running and will start at every login."
  echo "Log: $dir/camwatch.log"
  tail -2 camwatch.log 2>/dev/null || true
else
  echo "LaunchAgent loaded but camwatch isn't running. Check: launchctl print $domain/$label" >&2
  exit 1
fi
