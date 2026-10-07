# camwatch

Watches whether the Mac's camera and microphone are in use and sets a WiZ bulb to match:

| Camera | Mic | State | Bulb |
|---|---|---|---|
| On | either | `video` | Green |
| Off | recording | `mic` | Purple |
| Off | not recording | `off` | Red |

The camera is detected with CoreMediaIO (`kCMIODevicePropertyDeviceIsRunningSomewhere`), the same signal as the green light. The mic is detected per app with CoreAudio (`kAudioProcessPropertyIsRunningInput`, macOS 14.2+), so headphones playing music don't count. It is event-driven and never opens the camera or mic. A state change only takes effect after it has lasted 2 seconds.

## Install

Requires macOS 14.2+, Xcode command-line tools (`xcode-select --install`), and the Mac on the same network as the bulbs.

```sh
gh repo clone marlaevelyn/camwatch ~/camwatch
cd ~/camwatch
./install.sh a1b2c3d4e5f6    # optional bulb IP or MAC; see ./set-bulb
```

`install.sh` builds camwatch, saves the bulb if one is given, and installs a LaunchAgent that starts camwatch at login and restarts it if it exits. Re-run it after pulling changes. If macOS asks whether Terminal or camwatch may find devices on your local network, allow it or the bulb won't respond.

**Where to put it:** anywhere in your home folder except Desktop, Documents, Downloads, iCloud Drive, cloud-synced folders (Dropbox, Google Drive) or external drives. macOS blocks login services from those locations, so `install.sh` refuses to install there. `~/camwatch` is a good default.

## Uninstall

```sh
~/camwatch/uninstall.sh   # stop camwatch and remove it from login
rm -rf ~/camwatch         # optional: delete the code
```

Run `uninstall.sh` before moving or deleting the folder. Otherwise macOS keeps trying to start the missing program.

## Known limitations

- **Muted calls still count as mic on.** Many call apps keep the mic open while muted, so a muted call with video off still shows purple.
- **Always-listening apps keep the bulb purple.** Dictation apps (Superwhisper, Wispr Flow), noise filters (Krisp), Discord sitting in a voice channel and macOS Voice Control record continuously. Anything that keeps the mic open means `mic` for as long as it runs. Check the log to see which app it is: `tail ~/camwatch/camwatch.log`.
- **VPNs and work laptops.** A VPN that routes all traffic through your company (common on work laptops) usually blocks access to devices on your home network, so the bulb never changes. Look for an "allow local network access" option in the VPN app. Work Macs may also block local-network access or installing developer tools.
- **One Mac per bulb.** If two Macs control the same bulb, they overwrite each other on every change and every 5 minutes.

## Log

camwatch logs each state change to `camwatch.log`. Entries older than 24 hours are removed, and the log is capped at 2000 lines.

To build by hand:

```sh
swiftc -O camwatch.swift -o camwatch -framework CoreMediaIO -framework CoreAudio
```

## Run

```sh
./camwatch status   # print state once; exit 0 = video, 2 = mic only, 1 = off
./camwatch watch    # print state now and on every change
```

On each change, `watch` runs `on-change.sh <video|mic|off> "<details>"` from the same directory as the binary. That script picks the color (edit it to change colors) and runs `./set-bulb color R G B`, which sets the bulbs listed in `bulb.conf`.

**Missed updates are retried.** Each bulb must confirm the change; unconfirmed bulbs are retried for about a minute, then logged as not responding. If a bulb stops answering, `set-bulb` searches the network for its MAC and updates `bulb.conf` when the bulb has a new IP. Every 5 minutes camwatch also re-checks the bulbs and corrects any that missed an update.

**Changing the bulb by hand.** camwatch sets its colors at 99% brightness, an invisible difference that marks the setting as its own. The 5-minute re-check only corrects bulbs showing a camwatch color (99%, no scene) that's wrong for the current state. If you change the bulb in the WiZ app or switch it off, your setting stays until the next camera or mic change, when camwatch takes over again. The one exception is picking exactly red, green or purple at exactly 99% by hand: camwatch can't tell that from its own setting.

## Choose the bulb

```sh
./set-bulb                      # list WiZ bulbs on the network (* = controlled now)
./set-bulb a1:b2:c3:d4:e5:f6    # control this bulb (IP or MAC; several allowed)
```

This takes effect immediately, with no restart needed. Run it again if the bulb's IP changes.

## Start at login

`install.sh` fills `CAMWATCH_DIR` in `com.camwatch.plist` with the project directory and installs it to `~/Library/LaunchAgents/`. camwatch logs to `camwatch.log`.

```sh
launchctl kickstart -k gui/$(id -u)/com.camwatch   # restart
```
