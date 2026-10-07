# camwatch

Watches whether the Mac's camera and microphone are in use and sets a WiZ bulb to match:

| Camera | Mic | State | Bulb |
|---|---|---|---|
| On | either | `video` | Green |
| Off | recording | `mic` | Purple |
| Off | not recording | `off` | Red |

The camera is detected with CoreMediaIO (`kCMIODevicePropertyDeviceIsRunningSomewhere`), the same signal as the green light. The mic is detected per app with CoreAudio (`kAudioProcessPropertyIsRunningInput`, macOS 14.2+), so headphones playing music don't count. It is event-driven and never opens the camera or mic. A state change only takes effect after it has lasted 2 seconds.

Many call apps keep the mic open while muted, so a muted call with video off still shows purple.

## Install

Requires macOS 14.2+, Xcode command-line tools (`xcode-select --install`), and the Mac on the same network as the bulbs.

```sh
gh repo clone marlaevelyn/camwatch ~/camwatch
cd ~/camwatch
./install.sh YOUR_BULB_MAC    # optional bulb IP or MAC; see ./set-bulb
```

`install.sh` builds camwatch, saves the bulb if one is given, and installs a LaunchAgent that starts camwatch at login and restarts it if it exits. Re-run it after pulling changes. If macOS asks whether Terminal or camwatch may find devices on your local network, allow it or the bulb won't respond.

To build by hand:

```sh
swiftc -O camwatch.swift -o camwatch -framework CoreMediaIO -framework CoreAudio
```

## Run

```sh
./camwatch status   # print state once; exit 0 = video, 2 = mic only, 1 = off
./camwatch watch    # print state now and on every change
```

On each change, `watch` runs `on-change.sh <video|mic|off> "<details>"` from the same directory as the binary. That script sets the bulbs listed in `bulb.conf`.

## Choose the bulb

```sh
./set-bulb                      # list WiZ bulbs on the network (* = controlled now)
./set-bulb d8:a0:11:7d:59:76    # control this bulb (IP or MAC; several allowed)
```

This takes effect immediately, with no restart needed. Run it again if the bulb's IP changes.

## Start at login

`install.sh` fills `CAMWATCH_DIR` in `com.camwatch.plist` with the project directory and installs it to `~/Library/LaunchAgents/`. camwatch logs to `camwatch.log`.

```sh
launchctl kickstart -k gui/$(id -u)/com.camwatch   # restart
launchctl bootout gui/$(id -u)/com.camwatch        # stop until next login
rm ~/Library/LaunchAgents/com.camwatch.plist       # ...and don't start at login
```
