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

# macOS privacy protections stop a login service from running or logging in these
# folders, so camwatch would silently never work there.
case "$dir/" in
  "$HOME"/Desktop/* | "$HOME"/Documents/* | "$HOME"/Downloads/* | \
  "$HOME"/Library/Mobile\ Documents/* | "$HOME"/Library/CloudStorage/* | /Volumes/*)
    echo "camwatch can't run from $dir" >&2
    echo "macOS blocks background services in Desktop, Documents, Downloads, iCloud Drive," >&2
    echo "cloud-synced folders and external drives. Move it, e.g.:" >&2
    echo "  mv \"$dir\" ~/camwatch && ~/camwatch/install.sh" >&2
    exit 1
    ;;
esac

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
if [ ! -f reference.conf ]; then
  echo "No reference bulb chosen, so the bulb turns off when the camera and mic are off."
  echo "To copy another bulb instead: ./set-bulb follow <mac>"
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
