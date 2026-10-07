#!/bin/bash
# Stop camwatch and remove its login service. Leaves this folder in place;
# delete it afterwards if you no longer want the code.

label="com.camwatch"
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

if launchctl bootout "$domain/$label" 2>/dev/null; then
  echo "Stopped camwatch."
else
  echo "camwatch wasn't running."
fi

if [ -f "$plist" ]; then
  rm "$plist"
  echo "Removed $plist, so it won't start at login."
fi

echo "Uninstalled. The bulb keeps its last color. You can now delete $(cd "$(dirname "$0")" && pwd)"
