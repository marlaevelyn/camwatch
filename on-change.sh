#!/bin/bash
# Called by `camwatch watch` whenever the state changes (and once at startup).
#   $1 = video (camera on) | mic (mic on, camera off) | off
#   $2 = details, e.g. "camera: FaceTime HD Camera; mic: us.zoom.xos" (empty when off)

# Sets the WiZ bulb(s) in bulb.conf to show the state: video = green,
# mic only = purple, off = red. Change bulbs with ./set-bulb.

conf="$(dirname "$0")/bulb.conf"
state="$1"
details="$2"

echo "[on-change] $state${details:+ ($details)}"

case "$state" in
  video) color='"r":0,"g":255,"b":0' ;;
  mic)   color='"r":150,"g":0,"b":255' ;;
  *)     color='"r":255,"g":0,"b":0' ;;
esac

# WiZ bulbs take JSON over UDP port 38899 on the local network. UDP can drop
# packets, so send twice.
if [ ! -f "$conf" ]; then
  echo "[on-change] no bulb configured; run ./set-bulb"
  exit 0
fi

pilot="{\"method\":\"setPilot\",\"params\":{\"state\":true,$color,\"dimming\":100}}"
while read -r bulb _; do
  [ -n "$bulb" ] || continue
  for _ in 1 2; do
    echo "$pilot" | nc -u -w1 "$bulb" 38899 >/dev/null
  done
done < "$conf"
