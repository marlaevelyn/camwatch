#!/bin/bash
# Called by `camwatch watch` whenever the state changes (and once at startup).
#   $1 = video (camera on) | mic (mic on, camera off) | off
#   $2 = details, e.g. "camera: FaceTime HD Camera; mic: us.zoom.xos" (empty when off)

# WiZ bulb to show the state: video = green, mic only = purple, off = red.
WIZ_BULB="YOUR_BULB_IP"   # MAC YOUR_BULB_MAC

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
pilot="{\"method\":\"setPilot\",\"params\":{\"state\":true,$color,\"dimming\":100}}"
for _ in 1 2; do
  echo "$pilot" | nc -u -w1 "$WIZ_BULB" 38899 >/dev/null
done
