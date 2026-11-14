```text
██████╗ ███████╗██████╗ ████████╗ ██████╗  ██████╗ ████████╗██╗  ██╗
██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔═══██╗██╔═══██╗╚══██╔══╝██║  ██║
██████╔╝█████╗  ██║  ██║   ██║   ██║   ██║██║   ██║   ██║   ███████║
██╔══██╗██╔══╝  ██║  ██║   ██║   ██║   ██║██║   ██║   ██║   ██╔══██║
██║  ██║███████╗██████╔╝   ██║   ╚██████╔╝╚██████╔╝   ██║   ██║  ██║
╚═╝  ╚═╝╚══════╝╚═════╝    ╚═╝    ╚═════╝  ╚═════╝    ╚═╝   ╚═╝  ╚═╝
```

<div align="center">

[![Shell](https://img.shields.io/badge/Shell-Bash-121011?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-1337_Ubuntu%20%2F%20Linux-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](.)
[![Type](https://img.shields.io/badge/Type-systemd%20user%20unit-1E90FF?style=for-the-badge)](.)
[![Bluetooth](https://img.shields.io/badge/Bluetooth-BlueZ%20(bluetoothctl)-0082FC?style=for-the-badge&logo=bluetooth&logoColor=white)](.)
[![Mode](https://img.shields.io/badge/Mode-Disconnect--only-gold?style=for-the-badge)](.)
[![Status](https://img.shields.io/badge/Status-Beta-orange?style=for-the-badge)](.)

</div>

# RedTooth

> *Remember your post. Free your Bluetooth.*

Session helper for **1337/42 Ubuntu PCs**. Made by Bilal Rouane (42 intra: `brouane`).

It does two things for you, automatically, with **no background process**:

1. **Remembers which post you were on.** At every login it saves your current post hostname (for example `c3r6p4`) to a plain text file in your home, and keeps the *previous* one, so you always know where you were last time.
2. **Disconnects every connected Bluetooth device when you log out**, whatever the brand or the name (AirPods, Oraimo, JBL, Sony, Samsung, Xiaomi, ...), so the next post can connect to them without you having to disconnect them by hand first. Devices you list in an [exclude list](#excluding-devices) (a keyboard, a mouse) stay connected.

It is **disconnect-only**: RedTooth never unpairs or removes a device, never uses `sudo`, and never edits your `.zshrc`, `.bashrc` or `config.fish`. Pairings are preserved, so your devices reconnect normally.

## Setup

Make the script executable and run it once:

```bash
chmod +x redtooth.sh
./redtooth.sh
```

*(running with no arguments is the same as `--on`)*

That one run does everything:

- copies itself to `~/.local/bin/redtooth`
- writes a systemd **user** unit to `~/.config/systemd/user/redtooth.service`
- creates the config in `~/.config/redtooth/`
- enables and starts the unit, so your current post is saved right away

From then on it runs by itself at every login and logout. You never have to run it again, except to check on it or change a setting.

`--on` keeps its output short: it prints only your saved post and your connected devices. It does not list the files it creates or backs up. They are all listed in [Files](#files).

If `./redtooth.sh` says "Permission denied" even after `chmod +x`, your disk may be mounted `noexec`. Use `bash redtooth.sh` instead, it works the same.

Check that it is alive:

```bash
./redtooth.sh --status
```

### Upgrading from the AirPods-only version

Run `./redtooth.sh --on` again. It replaces the installed script and unit (the old ones are backed up as `*.bak.<timestamp>`) and drops the old `airpods_pattern` and `remove` settings from the config. The `--remove-airpods` and `--keep-airpods` flags no longer exist, because RedTooth never unpairs anything now.

## Options

| Flag | Alias | Description |
|---|---|---|
| `--on` | `on` | Install and activate. **This is the default** when no flag is given. Safe to re-run. |
| `--off` | `off` | Deactivate. The hooks stop doing anything and the unit is disabled. Files are kept. |
| `--status` | `status` | Show activation state, saved posts, your **connected** Bluetooth devices and the last log lines. |
| `--disconnect-now` | | Disconnect every connected Bluetooth device right now, without logging out. Excluded devices stay connected. |
| `--uninstall` | | Remove **everything RedTooth created** (unit, script, config, state, log, backups), so the PC is back as it was. Your downloaded `redtooth.sh` is not touched. |
| `--help` | `-h` | Show usage. |
| `_start` / `_stop` | | **Internal.** What systemd calls at login / logout. See [Testing without logging out](#testing-without-logging-out). |

There are no short flags except `-h`. An unknown flag prints an error plus the usage and exits with code `2`.

### Examples

```bash
./redtooth.sh                       # activate (same as --on)
./redtooth.sh --status              # what is saved, is it active, which devices are connected
./redtooth.sh --off                 # deactivate, keep all files
./redtooth.sh --on                  # activate again
./redtooth.sh --disconnect-now      # disconnect all connected devices right now
./redtooth.sh --uninstall           # remove everything
redtooth --status                   # after install, from any folder
```

After the first run the command `redtooth` exists in `~/.local/bin`. If that folder is not on your `PATH`, use the full path: `~/.local/bin/redtooth --status`.

## Modes

- **No arguments / `--on`**: installs (or refreshes the install) and activates. If the unit was already running, your current post is re-saved without triggering a logout hook, so your devices are **not** disconnected by re-running `--on`.
- **`--off`**: sets `enabled=0` in the config, then disables and stops the unit. The setting is written *first*, so the stop hook that systemd fires while stopping does nothing. Turning it off never disconnects your devices.
- **`--status`**: read-only. Prints the activation state, the saved posts, the exclude list (when you set one), the devices that are **connected right now**, and the last 8 log lines. Devices that are not connected are never listed.
- **`--disconnect-now`**: runs the Bluetooth step by itself. It works even when the tool is deactivated and it honors the exclude list.
- **`--uninstall`**: deactivates, then deletes every file RedTooth created: the unit, `~/.local/bin/redtooth`, `~/.config/redtooth/` (config + state), `~/redtooth-logs.txt` and the `*.bak.*` backups. See [Uninstall](#uninstall).

### Mixing flags

- **No flag** means `--on`.
- **If you give two action flags, the last one wins.** `--on --off` ends up off.
- **`--help` exits immediately**, before anything else in the same command runs.

## What it does

### At login

When your session starts, systemd runs `redtooth _start`:

1. Reads the hostname and cuts the domain: `c3r6p4.1337.ma` becomes `c3r6p4`.
2. Compares it with the `current_host` saved last time.
3. If it is **different**, the old `current_host` becomes `previous_host`. If it is the **same** post, `previous_host` is left alone.
4. Writes `~/.config/redtooth/state` and one `LOGIN` line in `~/redtooth-logs.txt`.

The state is written at **login**, not at logout. That means it is correct even if the previous session ended with a crash or a power cut.

```text
current_host=c3r6p4
previous_host=c3r5p7
last_login=2026-11-12 06:23
last_logout=2026-11-12 03:58
```

It is plain `key=value` text. Read it with `cat ~/.config/redtooth/state`.

The first time you ever run it, `previous_host` is empty because there is no earlier post to remember.

### At logout

When your session ends, systemd runs `redtooth _stop`:

1. Writes `last_logout` into the state file and a `LOGOUT` line in the log.
2. Lists every device BlueZ knows about: `bluetoothctl paired-devices` plus `bluetoothctl devices`, merged and de-duplicated by MAC address. The second list also catches a connected device that was never paired.
3. For each device, checks `bluetoothctl info <MAC>`:
   - **Not connected**: nothing to do, the device is left alone.
   - **Connected and on the exclude list**: left connected, and logged as such.
   - **Connected**: `bluetoothctl disconnect <MAC>`.
4. Writes one `DEVICE` line per connected device, with its real name.

It never uses `bluetoothctl devices Connected`, which the BlueZ 5.64 on the posts does not support. The connection state is read per device with `info` instead.

Every Bluetooth call is wrapped in `timeout` (5 s for listing and `info`, 8 s for `disconnect`), so a stuck Bluetooth stack cannot hang your logout. One failing or hanging device never stops the others from being handled.

## Excluding devices

By default every connected device is disconnected at logout. To keep some of them connected (a Bluetooth keyboard or mouse, for example), add them to the exclude list in the config file.

1. Connect the device, then find its name or MAC address. `--status` lists your connected devices with both:
   ```bash
   ./redtooth.sh --status
   ```
   (`bluetoothctl devices` also lists devices that are not connected.)
2. Open the config:
   ```bash
   nano ~/.config/redtooth/config
   ```
3. Set `exclude=` to a comma-separated list:
   ```text
   enabled=1
   exclude=Logitech MX Keys,A4:C1:38:00:11:22
   ```

There is no flag for this, and no reinstall is needed. The list is read every time the logout hook (or `--disconnect-now`) runs.

| Entry looks like | It matches | Example |
|---|---|---|
| A MAC address (`XX:XX:XX:XX:XX:XX`) | That exact device, in any letter case | `A4:C1:38:00:11:22` |
| Anything else | Any device whose name **contains** the text, in any letter case | `MX Keys` matches `Logitech MX Keys` |

Rules:

- Separate entries with commas. Spaces around entries are ignored, and so are empty entries.
- A name entry that is short can match several devices (`Buds` matches `Galaxy Buds2` and `Redmi Buds 4`). Use the MAC address when you need exactness.
- A name that itself contains a comma cannot be used. Use its MAC address instead.
- `exclude=` empty (the default) means nothing is excluded.
- `--status` shows an `Excluded` line with your list and marks matching connected devices with `excluded`. The log records `kept connected (excluded): <name>` at each logout.

## Reading the output

The output is kept minimal on purpose. A section is `▌ Name` (with `ON` / `OFF` for the RedTooth state) followed by its lines. **Only connected devices are ever listed**: a device that is not connected never appears.

`--on` and `--status` print:

```text
  ▌ RedTooth  ON

  ▌ Post
    Now          c2r4p13
    Previous     c3r5p5
    Last login   2026-11-13 20:42
    Last logout  2026-11-12 07:36

  ▌ Bluetooth
    Excluded     Logitech MX Keys
    ● Lenovo EA230             CA:E9:5C:CB:0B:72
    ● Logitech MX Keys         E8:07:BF:99:88:77  excluded

  ▌ Log
    2026-11-12 07:36  LOGOUT   c3r5p5   session ended
    2026-11-12 07:36  DEVICE   c3r5p5   disconnected: Lenovo EA230
    2026-11-13 20:42  LOGIN    c2r4p13  previous post: c3r5p5
```

- `--on` prints only the **Post** and **Bluetooth** sections. `--status` adds **RedTooth** and **Log**.
- The `Excluded` line only appears when your exclude list is not empty.
- When no device is connected, the Bluetooth section says `↷ Nothing connected`.
- The **Post** section is what RedTooth saved in the [state file](#files): the post you are on now, the previous one, and the last login and logout.

`--disconnect-now` (and `_stop` run by hand) print what happened to each connected device:

```text
  ▌ Bluetooth
    ✔ Lenovo EA230             CA:E9:5C:CB:0B:72  disconnected
    ↷ Logitech MX Keys         E8:07:BF:99:88:77  kept connected
```

- **Icons:** `✔` done, `↷` kept or skipped, `✖` failed, `●` connected.
- **Colors** switch off automatically when the output is not a terminal, or when `NO_COLOR` is set. Set `FORCE_COLOR=1` to keep them in a pipe.
- **The hooks are quiet** when systemd runs them. They only print when you run `_start` / `_stop` by hand in a terminal.

### The log

`~/redtooth-logs.txt` sits directly in your home. It is a plain text file with **one line per event**, in fixed columns: date, time, event, post, details. It is trimmed to the last 500 lines at each login.

```text
2026-11-12 03:58  LOGOUT   c3r5p7   session ended
2026-11-12 03:58  DEVICE   c3r5p7   disconnected: AirPods T5S
2026-11-12 03:58  DEVICE   c3r5p7   disconnected: Oraimo FreePods 3
2026-11-12 03:58  DEVICE   c3r5p7   kept connected (excluded): Logitech MX Keys
2026-11-12 06:23  LOGIN    c3r6p4   previous post: c3r5p7
```

| Event | Details | Meaning |
|---|---|---|
| `LOGIN` | `previous post: c3r5p7` | Login on a different post than last time |
| `LOGIN` | `same post as last time` | Login on the same post |
| `LOGIN` | `first login recorded` | The very first login RedTooth saw |
| `LOGOUT` | `session ended` | The logout hook ran |
| `DEVICE` | `disconnected: <name>` | The device was connected and is now disconnected |
| `DEVICE` | `FAILED to disconnect: <name>` | `bluetoothctl disconnect` failed or timed out |
| `DEVICE` | `kept connected (excluded): <name>` | The device is on the exclude list |
| `NOTE` | `no connected Bluetooth devices` | Devices are known, but none was connected |
| `NOTE` | `no Bluetooth devices found (Bluetooth off or none paired)` | BlueZ listed no device at all |
| `NOTE` | `bluetoothctl not found` | Bluetooth tools are not installed |
| `NOTE` | `skipped (RedTooth is off)` | The tool is deactivated with `--off` |

The `<name>` is the device's real name as BlueZ reports it (its MAC address if it has no name). The `post` column is the post where the event happened. A `LOGOUT` line is the proof that the logout hook really fired, even when there was nothing to disconnect.

## Files

| Path | What it is |
|---|---|
| `~/.local/bin/redtooth` | The installed copy of the script |
| `~/.config/systemd/user/redtooth.service` | The systemd user unit |
| `~/.config/systemd/user/default.target.wants/redtooth.service` | Symlink that systemd creates when the unit is enabled |
| `~/.config/redtooth/config` | Settings: `enabled`, `exclude` |
| `~/.config/redtooth/state` | `current_host`, `previous_host`, `last_login`, `last_logout` |
| `~/redtooth-logs.txt` | Simple log, one line per event |

Two of these files are easy to mix up:

- **`~/redtooth-logs.txt`** is the **log**. It is in your home folder (for example `/home/brouane/redtooth-logs.txt`) and records what happened, one line per event.
- **`~/.config/redtooth/state`** is the **saved post**. It holds the post you are on and the previous one, which is what the **Post** section of the output shows. It is not a log, and the script no longer prints its path.

Backups: when `--on` overwrites an installed script or a changed unit, the old file is first copied next to it as `<name>.bak.<timestamp>` (for example `~/.local/bin/redtooth.bak.1794602525`). This is not shown in the output. These backups are never deleted automatically.

Nothing outside these paths is created or modified. In particular, **RedTooth never adds a line to `.zshrc`, `.bashrc`, `config.fish` or any other existing configuration file**, so there is nothing to remove from them: deleting the files above removes everything RedTooth added.

## Configuration

`~/.config/redtooth/config` is plain `key=value` text:

| Key | Default | Set with | Meaning |
|---|---|---|---|
| `enabled` | `1` | `--on` / `--off` | `0` makes both hooks do nothing |
| `exclude` | *(empty)* | edit the file by hand | Comma-separated MAC addresses or name fragments that stay connected. See [Excluding devices](#excluding-devices) |

## Disconnect only

RedTooth never unpairs, removes or blocks a device. The pairing keys stay in BlueZ on the post, so after a disconnect the device:

- can reconnect to the same post normally;
- is free to connect to the next post, which is the whole point.

If you ever want a device forgotten by a post, do it yourself with `bluetoothctl remove <MAC>`. RedTooth will not do it for you.

## How it works on 1337

This was designed after inspecting a real post (`c3r6p4`), not assumed from a generic Linux desktop:

- **Hostname format.** Posts look like `c3r6p4.1337.ma`. The short part `c3r6p4` follows the usual `cXrYpZ` cluster / row / post pattern. It changes whenever you sit somewhere else.
- **Your home follows you.** `/home/brouane` is an iSCSI network disk, so the state file is the same on every post. `/goinfre` is local to each machine, so it is deliberately not used.
- **Why a systemd user unit.** The session is GNOME on X11 with a user systemd manager (`Linger=no`), which lives exactly as long as your login. A oneshot unit gives a hook at login and a hook at logout with **no process left running in between**.
- **Why not a background script.** logind is set to `KillUserProcesses=yes`, so anything started from a shell or an autostart entry is killed at logout. A unit in the user manager is not part of the session scope, so its stop hook still runs.
- **Why not shell hooks.** Your login shell is `zsh` but the terminal opens `fish`, and a `.bash_logout`-style hook does not fire when a graphical session ends. A systemd unit does not depend on the shell at all.
- **Bluetooth is local.** The post has its own BlueZ (5.64) and controller. This version does not support `bluetoothctl devices Connected`, so the script lists devices and checks each one with `info <MAC>`.
- **Any device, any brand.** Nothing in the script matches a brand or a name. The only filter is your own exclude list.

## Verify it works

### Hostname persistence

1. Run `./redtooth.sh` and then `cat ~/.config/redtooth/state`. `current_host` should be your post.
2. Log out, **wait at least 20 seconds**, and log in on another post.
3. Run `cat ~/.config/redtooth/state` again. `current_host` is the new post and `previous_host` is the one you left.

### Bluetooth disconnection

1. Connect one or more Bluetooth devices.
2. Log out and **wait at least 20 seconds**. logind keeps your user manager alive for about 10 seconds (`UserStopDelaySec=10`) after the last session ends, and the stop hook runs when it shuts down. If you log back in sooner, the same manager is reused and **no stop hook fires**.
3. Check that the devices are free (they show as disconnected, or connect to your phone) and read the log:

```bash
tail -n 10 ~/redtooth-logs.txt
```

You should see a `LOGOUT` line followed by one `DEVICE ... disconnected: <name>` line per device, and a `kept connected (excluded)` line for each excluded one.

### Testing without logging out

The two internal commands are what systemd runs. You can run them yourself:

```bash
~/.local/bin/redtooth _stop    # simulates logout: disconnects your devices, sets last_logout
~/.local/bin/redtooth _start   # simulates login: re-saves the current post
```

When run by hand in a terminal they print a short report. `_stop` **really disconnects** your connected devices (except the excluded ones), and does nothing if the tool is deactivated.

## Safety guarantees

- **Disconnect only.** `bluetoothctl remove`, unpairing and blocking are never called.
- **Pairing is preserved.** Devices can reconnect normally, here or on another post.
- **Your exclude list is respected.** Excluded devices are never disconnected, by the logout hook or by `--disconnect-now`.
- **No `sudo`, no system-wide changes.** Everything lives under `~/.config`, `~/.local/bin` and one log file in your home.
- **Your shell configuration is never modified.** `.zshrc`, `.bashrc` and `config.fish` are not touched.
- **Backups before overwriting.** An installed script or unit that gets replaced is copied to `*.bak.<timestamp>` first.
- **No background process.** The unit is a oneshot: nothing runs between login and logout.
- **Cannot hang your logout.** All Bluetooth calls are wrapped in `timeout`, and the unit has `TimeoutStopSec=30`.
- **Failures are quiet and isolated.** Missing `bluetoothctl`, Bluetooth switched off, a device already disconnected, a device that fails or hangs: each is logged and skipped, and the other devices are still handled. The hooks always exit with success.
- **Safe writes.** The state and config are written to a temporary file and then moved into place, so a half-written file is never left behind.
- **`--off` really means off.** When deactivated, both hooks return immediately.
- **Self-limiting log.** The log is trimmed to the last 500 lines at each login.

## Limitations

- **A hard power-off, a crash or a forced session kill can skip the stop hook.** In that case your devices stay connected until you disconnect them. The saved hostname is still correct, because it is written at login.
- **If the network home is unmounted before the stop hook runs**, the installed script is no longer reachable and the hook cannot run. Use the log to confirm the hook fires on your post (see [Verify it works](#verify-it-works)).
- **Logging back in within about 10 seconds of logging out** reuses the existing user manager, so no logout hook fires for that logout.
- **Only devices known to this post's BlueZ can be seen.** A device that was never paired or connected on this post is not listed, so there is nothing to disconnect.
- **A device whose `info` call takes more than 5 seconds is treated as not connected** and skipped for that run.
- **The exclude list cannot hold a name that contains a comma.** Use the MAC address.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `--status` says `Active: no` | Run `./redtooth.sh --on` again |
| No `LOGOUT` line in the log after a logout | You logged back in too fast (wait 20 s), or the hook did not fire: share `--status` and the log |
| `LOGOUT` line but a device is still connected | Look at the next lines: `FAILED to disconnect`, `kept connected (excluded)` or `no Bluetooth devices found` tell you which |
| A device you wanted to keep gets disconnected | Check the spelling in `exclude=`, or use its MAC address from `--status` |
| A device you wanted disconnected stays connected | It may match an `exclude=` entry: a short name fragment can match several devices |
| `Nothing connected` although a device is connected | Check `bluetoothctl devices`. The log tells the two cases apart: `no Bluetooth devices found` (Bluetooth off, or no device known to this post) or `no connected Bluetooth devices` |
| `bluetoothctl not found, skipping` | Bluetooth tools are missing on this post |
| Nothing happens at all | `--status` may show the tool as off. Run `--on` |

## Uninstall

```bash
./redtooth.sh --uninstall
```

This deactivates RedTooth without touching your devices, then deletes **everything it created**:

- the unit `~/.config/systemd/user/redtooth.service` and its enable link
- the installed script `~/.local/bin/redtooth`
- the config and state folder `~/.config/redtooth/`
- the log `~/redtooth-logs.txt`
- the `*.bak.*` backups of the script and the unit
- the folders `~/.local/bin`, `~/.config/systemd/user` and `~/.config/systemd`, **only if they are empty** after that (so they are not left behind when RedTooth had to create them)

Nothing else is changed, because nothing else was ever modified: no line was added to `.zshrc`, `.bashrc`, `config.fish` or any other file, so there is no original configuration to restore. The only file left is the `redtooth.sh` you downloaded, which is yours to keep or delete.

Running it twice, or on a PC where RedTooth was never installed, is harmless.

Manual version, if the script is gone:

```bash
systemctl --user disable --now redtooth.service
rm -f ~/.config/systemd/user/redtooth.service ~/.config/systemd/user/redtooth.service.bak.*
rm -f ~/.local/bin/redtooth ~/.local/bin/redtooth.bak.*
rm -rf ~/.config/redtooth
rm -f ~/redtooth-logs.txt
systemctl --user daemon-reload
```

Note that the manual `disable --now` fires the logout hook once, which disconnects your connected devices. Run `./redtooth.sh --off` first to avoid that.
