# camwatch

Watches whether the Mac's camera and microphone are in use and sets a WiZ bulb to match:

| Camera | Mic | State | Bulb |
|---|---|---|---|
| On | either | `video` | Green |
| Off | recording | `mic` | Purple |
| Off | not recording | `off` | Red |

The camera is detected with CoreMediaIO (`kCMIODevicePropertyDeviceIsRunningSomewhere`), the same signal as the green light. The mic is detected per app with CoreAudio (`kAudioProcessPropertyIsRunningInput`, macOS 14.2+), so headphones playing music don't count. It is event-driven and never opens the camera or mic. A state change only takes effect after it has lasted 2 seconds.

Many call apps keep the mic open while muted, so a muted call with video off still shows purple.

## Build

```sh
swiftc -O camwatch.swift -o camwatch -framework CoreMediaIO -framework CoreAudio
```

## Run

```sh
./camwatch status   # print state once; exit 0 = video, 2 = mic only, 1 = off
./camwatch watch    # print state now and on every change
```

On each change, `watch` runs `on-change.sh <video|mic|off> "<details>"` from the same directory as the binary. Set `WIZ_BULB` in that script to your bulb's IP.

## Start at login

`com.camwatch.plist` is a LaunchAgent that starts `camwatch watch` at login and restarts it if it exits. It logs to `camwatch.log`. Edit the paths in it if the project lives somewhere other than `~/camwatch`.

```sh
cp com.camwatch.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.camwatch.plist

launchctl kickstart -k gui/$(id -u)/com.camwatch   # restart after rebuilding
launchctl bootout gui/$(id -u)/com.camwatch        # stop
```
