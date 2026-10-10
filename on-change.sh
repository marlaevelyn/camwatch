#!/bin/bash
# Called by `camwatch watch` whenever the state changes (and once at startup).
#   $1 = video (camera on) | mic (mic on, camera off) | off
#   $2 = details, e.g. "camera: FaceTime HD Camera; mic: us.zoom.xos" (empty when off)
#   $3 = "refresh" for camwatch's 5-minute re-check of an unchanged state
#
# Sets the WiZ bulb(s) in bulb.conf to show the state: video = green,
# mic only = purple, off = copy the reference bulb (./set-bulb follow), or
# switch off if it can't be read. Change bulbs with ./set-bulb.

state="$1"
details="$2"
mode="$3"

[ "$mode" = refresh ] || echo "[on-change] $state${details:+ ($details)}"

case "$state" in
  video) args="color 0 255 0" ;;
  mic)   args="color 150 0 255" ;;
  *)     args="match" ;;
esac

# exec so that when camwatch stops this hook for a newer state, the stop
# reaches set-bulb directly.
exec "$(dirname "$0")/set-bulb" $args ${mode:+--$mode}
