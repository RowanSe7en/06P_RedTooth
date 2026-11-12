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
[![Mode](https://img.shields.io/badge/Mode-Disconnect--only%20by%20default-gold?style=for-the-badge)](.)
[![Status](https://img.shields.io/badge/Status-Beta-orange?style=for-the-badge)](.)

</div>

# RedTooth

> *Remember your post. Free your AirPods.*

Session helper for **1337/42 Ubuntu PCs**. Made by Bilal Rouane (42 intra: `brouane`).

It does two things for you, automatically, with **no background process**:

1. **Remembers which post you were on.** At every login it saves your current post hostname (for example `c3r6p4`) to a plain text file in your home, and keeps the *previous* one, so you always know where you were last time.
2. **Disconnects your AirPods when you log out**, so the next post can connect to them without you having to disconnect them by hand first.

It is **safe by default**: the normal behavior only ever *disconnects* your AirPods. It never unpairs them, never touches any other Bluetooth device, never uses `sudo`, and never edits your `.zshrc`, `.bashrc` or `config.fish`. A separate, explicitly opt-in `--remove-airpods` setting exists for anyone who also wants the pairing deleted from the post at logout.

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

If `./redtooth.sh` says "Permission denied" even after `chmod +x`, your disk may be mounted `noexec`. Use `bash redtooth.sh` instead, it works the same.

Check that it is alive:

```bash
./redtooth.sh --status
```

## Options

| Flag | Alias | Description |
|---|---|---|
| `--on` | `on` | Install and activate. **This is the default** when no flag is given. Safe to re-run. |
| `--off` | `off` | Deactivate. The hooks stop doing anything and the unit is disabled. Files are kept. |
| `--status` | `status` | Show activation state, saved hosts, your AirPods and the last log lines. |
| `--disconnect-now` | | Disconnect the AirPods right now, without logging out. |
| `--remove-airpods` | | At logout, also **unpair** the AirPods (you must re-pair them later). See [Disconnect vs remove](#disconnect-vs-remove). |
| `--keep-airpods` | | At logout, only disconnect (**default**). |
| `--uninstall` | | Remove the unit, the installed script, the config and the state. The log in your home is **kept**. |
| `--help` | `-h` | Show usage. |
| `_start` / `_stop` | | **Internal.** What systemd calls at login / logout. See [Testing without logging out](#testing-without-logging-out). |

There are no short flags except `-h`. An unknown flag prints an error plus the usage and exits with code `2`.

### Examples

```bash
./redtooth.sh                       # activate (same as --on)
./redtooth.sh --status              # what is saved, is it active, are the AirPods connected
./redtooth.sh --off                 # deactivate, keep all files
./redtooth.sh --on                  # activate again
./redtooth.sh --disconnect-now      # disconnect the AirPods right now
./redtooth.sh --remove-airpods      # change the setting only: unpair at logout
./redtooth.sh --keep-airpods        # back to disconnect-only
./redtooth.sh --on --remove-airpods # activate AND unpair at logout
./redtooth.sh --uninstall           # remove everything
redtooth --status                   # after install, from any folder
```

After the first run the command `redtooth` exists in `~/.local/bin`. If that folder is not on your `PATH`, use the full path: `~/.local/bin/redtooth --status`.

## Modes

- **No arguments / `--on`**: installs (or refreshes the install) and activates. If the unit was already running, your current post is re-saved without triggering a logout hook, so your AirPods are **not** disconnected by re-running `--on`.
- **`--off`**: sets `enabled=0` in the config, then disables and stops the unit. The setting is written *first*, so the stop hook that systemd fires while stopping does nothing. Turning it off never disconnects your AirPods.
- **`--status`**: read-only. Prints the activation state, the saved posts, the AirPods found (connected or not) and the last 8 log lines.
- **`--disconnect-now`**: runs the AirPods step by itself. It works even when the tool is deactivated. It **does** honor the `remove` setting, so if you set `--remove-airpods`, this also unpairs them.
- **`--remove-airpods` / `--keep-airpods`**: only change the `remove` setting in the config. They do not install or activate anything on their own.
- **`--uninstall`**: deactivates, then deletes the unit, `~/.local/bin/redtooth` and `~/.config/redtooth/` (config + state). `~/redtooth-logs.txt` is left in place, delete it by hand if you want.

### Mixing flags

```bash
./redtooth.sh --on --remove-airpods   # install + unpair at logout
./redtooth.sh --status --keep-airpods # set to disconnect-only, then show status
```

Rules of thumb when mixing:

- **No action flag and no setting flag** means `--on`.
- **`--remove-airpods` / `--keep-airpods` alone** only change the setting. They do not run `--on` for you.
- **If you give two action flags, the last one wins.** `--on --off` ends up off.
- **If you give both `--remove-airpods` and `--keep-airpods`, the last one wins.**
- **`--help` exits immediately**, before any other flag in the same command is applied.

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

1. Writes `last_logout` into the state file.
2. Lists your **paired** Bluetooth devices (`bluetoothctl paired-devices`, with `bluetoothctl devices` as a fallback).
3. Keeps only the devices whose **name contains** `AirPods` (case-insensitive, configurable).
4. For each one, checks `bluetoothctl info <MAC>`:
   - `Connected: yes` leads to `bluetoothctl disconnect <MAC>`.
   - Anything else is logged as "already disconnected" and left alone.
5. Only if `remove=1`: runs `bluetoothctl remove <MAC>` after the disconnect.

Every Bluetooth call is wrapped in `timeout` (5 s for listing, info and remove, 8 s for disconnect), so a stuck Bluetooth stack can never hang your logout.

## Reading the output

Every section prints the same way, so a run is easy to scan:

```text
  ▌ AirPods      SAFE    Disconnect at logout  (pairing kept)
    ✔ disconnected         AirPods T5S    8D:8B:CE:9C:0A:63
    ✔ 1 disconnected
```

- **Header:** `▌ Name  TAG  what it does`. The tag is `SETUP` / `INFO` (information), `ON` / `OFF` (state), `SAFE` (disconnect only), `MEDIUM` (disconnect + unpair) or `WIPE` (uninstall).
- **Icons:** `✔` done, `↷` skipped or nothing to do, `✖` failed, `●` connected, `○` not connected, `⚠` warning.
- **Colors** switch off automatically when the output is not a terminal, or when `NO_COLOR` is set. Set `FORCE_COLOR=1` to keep them in a pipe.
- **The hooks are quiet** when systemd runs them. They only print when you run `_start` / `_stop` by hand in a terminal.

### `--status`

```text
  ▌ RedTooth     ON      Login & logout hooks
    Active       yes
    At login     saves the post you are on
    At logout    disconnects AirPods (pairing kept)

  ▌ Post         INFO    Where you are, where you were
    Now          c3r6p4
    Previous     c3r5p7
    Last login   2026-11-12 06:23
    Last logout  2026-11-12 03:58
    Saved in     ~/.config/redtooth/state

  ▌ AirPods      SAFE    Disconnect at logout  (pairing kept)
    ● connected            AirPods T5S    8D:8B:CE:9C:0A:63

  ▌ Log          INFO    ~/redtooth-logs.txt  (last 8)
    2026-11-12 03:58  LOGOUT   c3r5p7   session ended
    2026-11-12 03:58  AIRPODS  c3r5p7   disconnected: AirPods T5S
    2026-11-12 06:23  LOGIN    c3r6p4   previous post: c3r5p7
```

### The log

`~/redtooth-logs.txt` sits directly in your home. It is a plain text file with **one line per event**, in fixed columns: date, time, event, post, details. It is trimmed to the last 500 lines at each login.

```text
2026-11-12 03:58  LOGOUT   c3r5p7   session ended
2026-11-12 03:58  AIRPODS  c3r5p7   disconnected: AirPods T5S
2026-11-12 06:23  LOGIN    c3r6p4   previous post: c3r5p7
```

| Event | Details | Meaning |
|---|---|---|
| `LOGIN` | `previous post: c3r5p7` | Login on a different post than last time |
| `LOGIN` | `same post as last time` | Login on the same post |
| `LOGIN` | `first login recorded` | The very first login RedTooth saw |
| `LOGOUT` | `session ended` | The logout hook ran |
| `AIRPODS` | `disconnected: <name>` | AirPods were connected and are now disconnected |
| `AIRPODS` | `already disconnected: <name>` | Nothing to do |
| `AIRPODS` | `FAILED to disconnect: <name>` | `bluetoothctl disconnect` failed or timed out |
| `AIRPODS` | `unpaired: <name>` | Only with `--remove-airpods` |
| `AIRPODS` | `FAILED to unpair: <name>` | Unpair failed |
| `NOTE` | `no AirPods found (Bluetooth off or nothing paired)` | Nothing matched |
| `NOTE` | `bluetoothctl not found` | Bluetooth tools are not installed |
| `NOTE` | `skipped (RedTooth is off)` | The tool is deactivated with `--off` |

The `post` column is the post where the event happened. A `LOGOUT` line is the proof that the logout hook really fired, even when there were no AirPods to disconnect.

## Files

| Path | What it is |
|---|---|
| `~/.local/bin/redtooth` | The installed copy of the script |
| `~/.config/systemd/user/redtooth.service` | The systemd user unit |
| `~/.config/systemd/user/default.target.wants/redtooth.service` | Symlink that systemd creates when the unit is enabled |
| `~/.config/redtooth/config` | Settings: `enabled`, `airpods_pattern`, `remove` |
| `~/.config/redtooth/state` | `current_host`, `previous_host`, `last_login`, `last_logout` |
| `~/redtooth-logs.txt` | Simple log, one line per login / logout |

Backups: when `--on` overwrites an installed script or a changed unit, the old file is first copied next to it as `<name>.bak.<timestamp>`. These are never deleted automatically.

Nothing outside these paths is created or modified.

## Configuration

`~/.config/redtooth/config` is plain `key=value` text:

| Key | Default | Set with | Meaning |
|---|---|---|---|
| `enabled` | `1` | `--on` / `--off` | `0` makes both hooks do nothing |
| `airpods_pattern` | `AirPods` | edit the file by hand | Case-insensitive substring matched against device names |
| `remove` | `0` | `--remove-airpods` / `--keep-airpods` | `1` also unpairs at logout |

To match a different device or a more specific name, edit the pattern, for example:

```text
airpods_pattern=AirPods T5S
```

Every paired device whose name contains that text is handled, and nothing else.

## Disconnect vs remove

`--remove-airpods` is the only setting that changes pairing. By default it is **off**.

| | Disconnect (default) | Disconnect + remove |
|---|---|---|
| Frees the AirPods for the next post | Yes | Yes |
| Pairing stays on this post | Yes | **No**, deleted |
| Next time on this post | Reconnect directly | **Re-pair** (AirPods in pairing mode) |
| Leaves your pairing on a shared PC | Yes | No |

**Disconnect alone is what makes the AirPods available for the next post.** Removing is optional: it is useful if you do not want your AirPods left paired on a PC that other students use, but it costs you a re-pair every time. BlueZ stores pairings on each post's local disk, not in your home, so each post has its own pairing anyway.

```bash
./redtooth.sh --remove-airpods   # opt in
./redtooth.sh --keep-airpods     # back to the default
```

## How it works on 1337

This was designed after inspecting a real post (`c3r6p4`), not assumed from a generic Linux desktop:

- **Hostname format.** Posts look like `c3r6p4.1337.ma`. The short part `c3r6p4` follows the usual `cXrYpZ` cluster / row / post pattern. It changes whenever you sit somewhere else.
- **Your home follows you.** `/home/brouane` is an iSCSI network disk, so the state file is the same on every post. `/goinfre` is local to each machine, so it is deliberately not used.
- **Why a systemd user unit.** The session is GNOME on X11 with a user systemd manager (`Linger=no`), which lives exactly as long as your login. A oneshot unit gives a hook at login and a hook at logout with **no process left running in between**.
- **Why not a background script.** logind is set to `KillUserProcesses=yes`, so anything started from a shell or an autostart entry is killed at logout. A unit in the user manager is not part of the session scope, so its stop hook still runs.
- **Why not shell hooks.** Your login shell is `zsh` but the terminal opens `fish`, and a `.bash_logout`-style hook does not fire when a graphical session ends. A systemd unit does not depend on the shell at all.
- **Bluetooth is local.** The post has its own BlueZ (5.64) and controller. This version does not support `bluetoothctl devices Connected`, so the script uses `paired-devices` plus `info <MAC>` instead.
- **Matching by name, not MAC.** The pattern works on any post without hard-coding an address.

## Verify it works

### Hostname persistence

1. Run `./redtooth.sh` and then `cat ~/.config/redtooth/state`. `current_host` should be your post.
2. Log out, **wait at least 20 seconds**, and log in on another post.
3. Run `cat ~/.config/redtooth/state` again. `current_host` is the new post and `previous_host` is the one you left.

### AirPods disconnection

1. Connect your AirPods.
2. Log out and **wait at least 20 seconds**. logind keeps your user manager alive for about 10 seconds (`UserStopDelaySec=10`) after the last session ends, and the stop hook runs when it shuts down. If you log back in sooner, the same manager is reused and **no stop hook fires**.
3. Check that the AirPods are free (they show as disconnected, or connect to your phone) and read the log:

```bash
tail -n 10 ~/redtooth-logs.txt
```

You should see a `stop host=...` line followed by `disconnected <MAC> (AirPods ...)`.

### Testing without logging out

The two internal commands are what systemd runs. You can run them yourself:

```bash
~/.local/bin/redtooth _stop    # simulates logout: disconnects the AirPods, sets last_logout
~/.local/bin/redtooth _start   # simulates login: re-saves the current post
```

When run by hand in a terminal they print a short report. `_stop` **really disconnects** your AirPods (and unpairs them if `remove=1`), and does nothing if the tool is deactivated.

## Safety guarantees

- **Only the AirPods are touched.** Other Bluetooth devices are never disconnected or removed.
- **Never unpairs unless you ask.** `bluetoothctl remove` is only called when `remove=1`.
- **No `sudo`, no system-wide changes.** Everything lives under `~/.config`, `~/.local/bin` and one log file in your home.
- **Your shell configuration is never modified.** `.zshrc`, `.bashrc` and `config.fish` are not touched.
- **Backups before overwriting.** An installed script or unit that gets replaced is copied to `*.bak.<timestamp>` first.
- **No background process.** The unit is a oneshot: nothing runs between login and logout.
- **Cannot hang your logout.** All Bluetooth calls are wrapped in `timeout`, and the unit has `TimeoutStopSec=20`.
- **Failures are quiet.** Missing `bluetoothctl`, Bluetooth switched off, AirPods already disconnected, nothing paired: each is logged and skipped. The hooks always exit with success.
- **Safe writes.** The state and config are written to a temporary file and then moved into place, so a half-written file is never left behind.
- **`--off` really means off.** When deactivated, both hooks return immediately.
- **Self-limiting log.** The log is trimmed to the last 500 lines at each login.

## Limitations

- **A hard power-off, a crash or a forced session kill can skip the stop hook.** In that case the AirPods stay connected until you disconnect them. The saved hostname is still correct, because it is written at login.
- **If the network home is unmounted before the stop hook runs**, the installed script is no longer reachable and the hook cannot run. Use the log to confirm the hook fires on your post (see [Verify it works](#verify-it-works)).
- **Logging back in within about 10 seconds of logging out** reuses the existing user manager, so no logout hook fires for that logout.
- **Pairing is per post.** If the AirPods have never been paired on a post, there is nothing for the script to disconnect there, and the log says `no AirPods found`.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `--status` says `systemd active: inactive` | Run `./redtooth.sh --on` again |
| No `stop` line in the log after a logout | You logged back in too fast (wait 20 s), or the hook did not fire: share `--status` and the log |
| `stop` line but AirPods still connected | Look at the next line: `disconnect FAILED` or `no AirPods found` tells you which |
| `no AirPods found` | Check the name with `bluetoothctl paired-devices` and adjust `airpods_pattern` |
| `bluetoothctl not found, skipping` | Bluetooth tools are missing on this post |
| Nothing happens at all | `--status` may show `enabled in config : 0`. Run `--on` |

## Uninstall

```bash
./redtooth.sh --uninstall
```

This deactivates the tool without touching your AirPods, then removes the unit, the installed script, the config and the state. `~/redtooth-logs.txt` is kept. Because nothing of yours was ever modified, there is no original configuration to restore. Any `*.bak.*` files this tool created for itself are left in place and can be deleted by hand.

Manual version, if the script is gone:

```bash
systemctl --user disable --now redtooth.service
rm -f ~/.config/systemd/user/redtooth.service ~/.local/bin/redtooth
rm -rf ~/.config/redtooth
rm -f ~/redtooth-logs.txt     # optional
systemctl --user daemon-reload
```

Note that the manual `disable --now` fires the logout hook once, which disconnects your AirPods. Run `./redtooth.sh --off` first to avoid that.
