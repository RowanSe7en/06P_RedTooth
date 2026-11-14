#!/usr/bin/env bash
# RedTooth
#
# Made for 1337 Ubuntu PCs
# Made by Bilal Rouane — 42 intra: brouane
#
# What it does:
# - At login:  saves the post (hostname) you are on, and remembers the
#              previous one.
# - At logout: disconnects EVERY connected Bluetooth device (any brand,
#              any name) so the next post can connect to them without you
#              doing it by hand. Devices on the exclude list stay connected.
#
# Policy:
# - Runs as a systemd USER unit. No sudo, no daemon, nothing running
#   between login and logout.
# - Disconnect ONLY. RedTooth never unpairs or removes a device, so the
#   pairing is preserved and the device can reconnect normally.
# - Devices in the "exclude" list are never disconnected (keyboard, mouse).
# - Never edits .zshrc / .bashrc / config.fish or any other existing file:
#   it only creates its own files (listed below).
# - --uninstall deletes every file RedTooth created (unit, script, config,
#   state, log, backups), so the PC is back as it was.
#
# Running with no arguments = --on (install + activate).
#
# Excluding devices (keep a device connected at logout):
#   Edit  ~/.config/redtooth/config  and set a comma-separated list:
#     exclude=Logitech MX Keys,A4:C1:38:00:11:22
#   Each entry is either a MAC address (exact match) or a device name
#   (case-insensitive substring match). Connect the device and run
#   --status to see its name and MAC address.
#
# Files:
#   ~/redtooth-logs.txt              log, one line per event (in your home)
#   ~/.config/redtooth/state         the post you are on + the previous one
#   ~/.config/redtooth/config        enabled / exclude
#   ~/.local/bin/redtooth            installed copy of this script
#   ~/.config/systemd/user/redtooth.service
#
# Output: kept minimal on purpose. A section is  ▌ Name  [ON|OFF]  followed
# by its lines. Only CONNECTED devices are ever listed.
# Colors are disabled automatically when output is not a terminal, or
# when NO_COLOR is set. Set FORCE_COLOR=1 to keep them in a pipe.
#
# Useful examples:
#   ./redtooth.sh
#   ./redtooth.sh --status
#   ./redtooth.sh --off
#   ./redtooth.sh --disconnect-now

###############################################################################
# SHELL / SAFETY
###############################################################################

set -u

###############################################################################
# CONFIG
###############################################################################

NAME=redtooth
BIN="$HOME/.local/bin/$NAME"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/$NAME.service"
CONF_DIR="$HOME/.config/$NAME"
CONF="$CONF_DIR/config"
STATE="$CONF_DIR/state"
LOG="$HOME/redtooth-logs.txt"
LOG_MAX_LINES=500
SCRIPT_NAME="$(basename "$0")"

MAC_RE='^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'

###############################################################################
# COLORS
###############################################################################
# Palette: red banner, blue accent, green = ok, amber = caution,
# red = danger, grey = secondary text. Real escape characters are stored
# (not "\033" text) so the same variables work in printf and heredocs.

UI=0
[ -t 1 ] && UI=1

if { [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; } && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_ACCENT=$'\033[38;5;39m'
	C_INFO=$'\033[38;5;75m'
	C_OK=$'\033[38;5;78m'
	C_WARN=$'\033[38;5;221m'
	C_ERR=$'\033[38;5;203m'
	C_MUTED=$'\033[38;5;245m'
else
	C_RESET="" C_BOLD="" C_ACCENT="" C_INFO=""
	C_OK="" C_WARN="" C_ERR="" C_MUTED=""
fi

###############################################################################
# OUTPUT HELPERS
###############################################################################

ui_ok()  { printf "  %s✔%s %s\n" "$C_OK" "$C_RESET" "$*"; }
ui_err() { printf "  %s✖ %s%s\n" "$C_ERR" "$*" "$C_RESET" >&2; }

fg256() {
	# 256-color foreground escape, or nothing when colors are off.
	[ -n "$C_RESET" ] && printf '\033[38;5;%sm' "$1"
}

rule() {
	local i line=""
	for ((i = 0; i < 58; i++)); do line+="─"; done
	printf "  %s%s%s\n" "$C_MUTED" "$line" "$C_RESET"
}

kv() {
	# kv "Label" "value" [color]
	printf "    %s%-12s%s %s%s%s\n" "$C_MUTED" "$1" "$C_RESET" "${3:-$C_BOLD}" "$2" "$C_RESET"
}

or_dash() {
	if [ -n "$1" ]; then printf '%s' "$1"; else printf '—'; fi
}

section_begin() {
	# section_begin "Name" [on|off]
	local tag="" tagc=""
	case "${2:-}" in
		on)  tag="ON";  tagc="$C_OK" ;;
		off) tag="OFF"; tagc="$C_MUTED" ;;
	esac

	printf "\n  %s▌%s %s%s%s" "$C_ACCENT" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
	[ -n "$tag" ] && printf "  %s%s%s%s" "$C_BOLD" "$tagc" "$tag" "$C_RESET"
	printf "\n"
}

section_skip() {
	printf "    %s↷ %s%s\n" "$C_MUTED" "$*" "$C_RESET"
}

dev_row() {
	# dev_row ICON COLOR "name" "mac" ["word"]
	printf "    %s%s%s %s%-24s%s %s%s%s" \
		"$2" "$1" "$C_RESET" "$C_BOLD" "$3" "$C_RESET" "$C_MUTED" "$4" "$C_RESET"
	[ -n "${5:-}" ] && printf "  %s%s%s" "$2" "$5" "$C_RESET"
	printf "\n"
}

###############################################################################
# BANNER / HELP
###############################################################################

banner() {
	# R E D T O O T H — one gradient color per letter (deep red -> amber)
	local g=(124 160 196 202 203 209 215 221)
	local r1=("█▀▀▄ " "█▀▀▀▀" "█▀▀▄ " "▀▀█▀▀" "▄▀▀▀▄" "▄▀▀▀▄" "▀▀█▀▀" "█   █")
	local r2=("█▄▄▀ " "█▀▀▀ " "█   █" "  █  " "█   █" "█   █" "  █  " "█▀▀▀█")
	local r3=("█  ▀▄" "█▄▄▄▄" "█▄▄▀ " "  █  " "▀▄▄▄▀" "▀▄▄▄▀" "  █  " "█   █")

	local l1="" l2="" l3="" c i

	for i in "${!r1[@]}"; do
		c="$(fg256 "${g[i]}")"
		l1+="${c}${r1[i]}  "
		l2+="${c}${r2[i]}  "
		l3+="${c}${r3[i]}  "
	done

	echo
	printf "  %s\n" "${C_BOLD}${l1}${C_RESET}"
	printf "  %s\n" "${C_BOLD}${l2}${C_RESET}"
	printf "  %s\n" "${C_BOLD}${l3}${C_RESET}"
	echo
	printf "  %sMade by Bilal Rouane · 42 intra: brouane%s\n" "$C_MUTED" "$C_RESET"
	rule
}

help_heading() {
	printf "\n  %s%s%s\n" "$C_BOLD$C_ACCENT" "$1" "$C_RESET"
}

help_opt() {
	# help_opt "--flag, -f" "first line" ["more lines" ...]
	local flag="$1" line
	shift
	printf "    %s%-22s%s%s\n" "$C_INFO" "$flag" "$C_RESET" "$1"
	shift
	for line in "$@"; do
		printf "    %-22s%s%s%s\n" "" "$C_MUTED" "$line" "$C_RESET"
	done
}

usage() {
	printf "\n  %s%sRedTooth%s  %s— remember your post, free your Bluetooth devices%s\n" \
		"$C_BOLD" "$C_ACCENT" "$C_RESET" "$C_MUTED" "$C_RESET"

	help_heading "USAGE"
	cat <<EOF
    $SCRIPT_NAME [options]

    Running with no options installs and activates RedTooth (--on).
    After that it runs by itself at every login and logout.
EOF

	help_heading "OPTIONS"
	help_opt "--on" \
		"Install + activate (default). Safe to re-run." \
		"Re-running never disconnects your devices."
	help_opt "--off" "Deactivate. Hooks do nothing, files are kept."
	help_opt "--status" \
		"Show active state, the saved posts, your connected" \
		"Bluetooth devices and the last log lines."
	help_opt "--disconnect-now" \
		"Disconnect every connected Bluetooth device right now" \
		"(excluded devices stay connected)"
	help_opt "--uninstall" \
		"Remove everything RedTooth created (unit, script, config," \
		"state, log, backups). Nothing else was ever changed."
	help_opt "--help, -h" "Show this help"

	help_heading "EXCLUDING DEVICES"
	cat <<EOF
    RedTooth disconnects every connected Bluetooth device. To keep some
    connected (a keyboard, a mouse), list them in
    ~/.config/redtooth/config as a comma-separated list:

      exclude=Logitech MX Keys,A4:C1:38:00:11:22

    Each entry is a MAC address (exact match) or a device name
    (case-insensitive substring). Connect the device and run
    $SCRIPT_NAME --status to see its name and MAC address.
    Changes apply at the next logout.
    RedTooth never unpairs or removes any device.
EOF

	help_heading "FILES"
	cat <<EOF
    ~/redtooth-logs.txt           log: one line per login / logout / device
    ~/.config/redtooth/state      the post you are on + the previous one
    ~/.config/redtooth/config     enabled / exclude
EOF

	help_heading "EXAMPLES"
	cat <<EOF
    $SCRIPT_NAME
    $SCRIPT_NAME --status
    $SCRIPT_NAME --off
    $SCRIPT_NAME --disconnect-now
    $SCRIPT_NAME --uninstall
EOF
	echo
}

###############################################################################
# GENERIC HELPERS
###############################################################################

cfg_get() { sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -n1; }

cfg_set() {
	mkdir -p "$CONF_DIR" || return 1
	touch "$CONF"
	grep -v "^$1=" "$CONF" > "$CONF.tmp" 2>/dev/null
	printf '%s=%s\n' "$1" "$2" >> "$CONF.tmp"
	mv "$CONF.tmp" "$CONF"
}

cfg_unset() {
	[ -f "$CONF" ] || return 0
	grep -v "^$1=" "$CONF" > "$CONF.tmp" 2>/dev/null
	mv "$CONF.tmp" "$CONF"
}

st_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | tail -n1; }

short_host() { hostname 2>/dev/null | cut -d. -f1; }

is_enabled() { [ "$(cfg_get enabled)" != "0" ]; }

log_event() {
	# log_event EVENT "details"
	# 2026-11-12 06:23  LOGIN    c3r6p4   previous post: c3r5p7
	printf '%s  %-8s %-8s %s\n' \
		"$(date '+%Y-%m-%d %H:%M')" "$1" "$(short_host)" "$2" >> "$LOG" 2>/dev/null
}

trim_log() {
	if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt "$LOG_MAX_LINES" ]; then
		tail -n "$LOG_MAX_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	fi
}

show_post() {
	kv "Now" "$(short_host)" "$C_OK$C_BOLD"
	kv "Previous" "$(or_dash "$(st_get previous_host)")"
	kv "Last login" "$(or_dash "$(st_get last_login)")" "$C_MUTED"
	kv "Last logout" "$(or_dash "$(st_get last_logout)")" "$C_MUTED"
}

###############################################################################
# HOSTNAME TRACKING
###############################################################################

do_start() {
	if ! is_enabled; then
		log_event NOTE "skipped (RedTooth is off)"
		return 0
	fi

	local cur saved prev msg
	cur=$(short_host)
	saved=$(st_get current_host)
	prev=$(st_get previous_host)

	if [ -z "$saved" ]; then
		msg="first login recorded"
	elif [ "$saved" != "$cur" ]; then
		prev=$saved
		msg="previous post: $saved"
	else
		msg="same post as last time"
	fi

	mkdir -p "$CONF_DIR" || return 0
	{
		echo "current_host=$cur"
		echo "previous_host=$prev"
		echo "last_login=$(date '+%F %H:%M')"
		echo "last_logout=$(st_get last_logout)"
	} > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

	log_event LOGIN "$msg"
	trim_log

	if [ "$UI" -eq 1 ]; then
		section_begin "Login"
		show_post
		echo
	fi
	return 0
}

###############################################################################
# BLUETOOTH
###############################################################################

# Prints "MAC<TAB>NAME" once for every device BlueZ knows about: the paired
# devices plus anything else it lists (so a connected device that is not
# paired is still found). Works on old BlueZ: it never uses
# "devices Connected", connection state is checked per device with "info".
bt_devices() {
	command -v bluetoothctl >/dev/null 2>&1 || return 0
	local kind mac name
	{
		timeout 5 bluetoothctl paired-devices 2>/dev/null
		timeout 5 bluetoothctl devices 2>/dev/null
	} | while read -r kind mac name; do
		[ "$kind" = "Device" ] || continue
		[[ "$mac" =~ $MAC_RE ]] || continue
		printf '%s\t%s\n' "$mac" "${name:-$mac}"
	done | awk -F'\t' '!seen[toupper($1)]++'
}

is_connected() {
	timeout 5 bluetoothctl info "$1" 2>/dev/null | grep -q 'Connected: yes'
}

# is_excluded MAC NAME — true if the device matches an entry of the
# "exclude=" list in the config (MAC = exact, name = substring, any case).
is_excluded() {
	local mac="$1" name="$2" list item
	local -a items
	list=$(cfg_get exclude)
	[ -n "$list" ] || return 1
	IFS=',' read -ra items <<< "$list"
	for item in "${items[@]}"; do
		item="${item#"${item%%[![:space:]]*}"}"
		item="${item%"${item##*[![:space:]]}"}"
		[ -n "$item" ] || continue
		if [[ "$item" =~ $MAC_RE ]]; then
			[ "${item^^}" = "${mac^^}" ] && return 0
		else
			case "${name,,}" in *"${item,,}"*) return 0 ;; esac
		fi
	done
	return 1
}

disconnect_devices() {
	local n_acted=0 n_found=0 mac name

	if ! command -v bluetoothctl >/dev/null 2>&1; then
		log_event NOTE "bluetoothctl not found"
		[ "$UI" -eq 1 ] && section_skip "bluetoothctl not found"
		return 0
	fi

	while IFS=$'\t' read -r mac name; do
		[ -n "$mac" ] || continue
		n_found=$((n_found + 1))

		# not connected: nothing to do, nothing to show
		is_connected "$mac" || continue
		n_acted=$((n_acted + 1))

		if is_excluded "$mac" "$name"; then
			log_event DEVICE "kept connected (excluded): $name"
			[ "$UI" -eq 1 ] && dev_row "↷" "$C_MUTED" "$name" "$mac" "kept connected"
			continue
		fi

		if timeout 8 bluetoothctl disconnect "$mac" >/dev/null 2>&1; then
			log_event DEVICE "disconnected: $name"
			[ "$UI" -eq 1 ] && dev_row "✔" "$C_OK" "$name" "$mac" "disconnected"
		else
			log_event DEVICE "FAILED to disconnect: $name"
			[ "$UI" -eq 1 ] && dev_row "✖" "$C_ERR" "$name" "$mac" "disconnect failed"
		fi
	done < <(bt_devices)

	if [ "$n_found" -eq 0 ]; then
		log_event NOTE "no Bluetooth devices found (Bluetooth off or none paired)"
	elif [ "$n_acted" -eq 0 ]; then
		log_event NOTE "no connected Bluetooth devices"
	fi
	[ "$n_acted" -eq 0 ] && [ "$UI" -eq 1 ] && section_skip "Nothing connected"
	return 0
}

# Lists only the CONNECTED devices (and the exclude list when it is set).
show_devices() {
	local mac name n=0 excl
	excl=$(cfg_get exclude | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

	[ -n "$excl" ] && kv "Excluded" "$excl" "$C_WARN"

	while IFS=$'\t' read -r mac name; do
		[ -n "$mac" ] || continue
		is_connected "$mac" || continue
		n=1
		if is_excluded "$mac" "$name"; then
			dev_row "●" "$C_WARN" "$name" "$mac" "excluded"
		else
			dev_row "●" "$C_OK" "$name" "$mac"
		fi
	done < <(bt_devices)

	[ "$n" -eq 1 ] || section_skip "Nothing connected"
}

do_stop() {
	if ! is_enabled; then
		log_event NOTE "skipped (RedTooth is off)"
		return 0
	fi

	if [ -f "$STATE" ]; then
		{ grep -v '^last_logout=' "$STATE"; echo "last_logout=$(date '+%F %H:%M')"; } > "$STATE.tmp" \
			&& mv "$STATE.tmp" "$STATE"
	fi
	log_event LOGOUT "session ended"

	[ "$UI" -eq 1 ] && section_begin "Bluetooth"
	disconnect_devices
	[ "$UI" -eq 1 ] && echo
	return 0
}

do_disconnect_now() {
	section_begin "Bluetooth"
	disconnect_devices
	echo
}

###############################################################################
# INSTALL / ACTIVATE / DEACTIVATE
###############################################################################

unit_text() {
cat <<'EOF'
[Unit]
Description=RedTooth: save your 1337 post at login, disconnect Bluetooth devices at logout

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=%h/.local/bin/redtooth _start
ExecStop=%h/.local/bin/redtooth _stop
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF
}

do_on() {
	command -v systemctl >/dev/null 2>&1 || { ui_err "systemctl not found"; exit 1; }

	local self was_active ts err
	ts=$(date +%s)

	mkdir -p "$HOME/.local/bin" "$UNIT_DIR" "$CONF_DIR" || { ui_err "cannot create directories"; exit 1; }

	# Script (an older installed copy is backed up as redtooth.bak.<time>)
	self=$(readlink -f "$0")
	if [ "$self" != "$(readlink -f "$BIN" 2>/dev/null)" ]; then
		[ -e "$BIN" ] && cp -p "$BIN" "$BIN.bak.$ts"
		cp "$self" "$BIN" && chmod 755 "$BIN" || { ui_err "cannot install $BIN"; exit 1; }
	fi

	# Unit (an older, different unit is backed up as redtooth.service.bak.<time>)
	unit_text > "$UNIT.new"
	if [ -e "$UNIT" ] && ! cmp -s "$UNIT" "$UNIT.new"; then
		cp -p "$UNIT" "$UNIT.bak.$ts"
	fi
	mv "$UNIT.new" "$UNIT"

	# Config (also drops the keys of the old AirPods-only version)
	cfg_set enabled 1
	grep -q '^exclude=' "$CONF" 2>/dev/null || cfg_set exclude ""
	cfg_unset airpods_pattern
	cfg_unset remove

	# Activate
	was_active=$(systemctl --user is-active "$NAME.service" 2>/dev/null)
	systemctl --user daemon-reload
	err=$(systemctl --user enable --now "$NAME.service" 2>&1) \
		|| { ui_err "could not enable the unit: $err"; exit 1; }
	# unit already running: refresh the saved post without a logout hook
	[ "$was_active" = "active" ] && "$BIN" _start >/dev/null 2>&1

	section_begin "Post"
	show_post

	section_begin "Bluetooth"
	show_devices

	echo
	ui_ok "${C_BOLD}RedTooth is active.${C_RESET}"
}

do_off() {
	# enabled=0 first, so the stop hook fired by --now does nothing
	cfg_set enabled 0
	systemctl --user disable --now "$NAME.service" >/dev/null 2>&1
	section_begin "RedTooth" off
	echo
	ui_ok "${C_BOLD}RedTooth is off.${C_RESET}"
}

do_uninstall() {
	# enabled=0 first, so the stop hook fired by --now does nothing
	cfg_set enabled 0
	systemctl --user disable --now "$NAME.service" >/dev/null 2>&1

	# everything RedTooth ever created
	/bin/rm -rf -- \
		"$UNIT" "$UNIT.new" "$UNIT".bak.* \
		"$UNIT_DIR/default.target.wants/$NAME.service" \
		"$BIN" "$BIN".bak.* \
		"$CONF_DIR" \
		"$LOG" "$LOG.tmp" 2>/dev/null

	# folders RedTooth may have created: removed only if they are now empty
	rmdir "$UNIT_DIR/default.target.wants" "$UNIT_DIR" \
		"$HOME/.config/systemd" "$HOME/.local/bin" 2>/dev/null

	systemctl --user daemon-reload >/dev/null 2>&1
	echo
	ui_ok "${C_BOLD}RedTooth removed.${C_RESET}"
}

###############################################################################
# STATUS
###############################################################################

do_status() {
	local active line

	active=$(systemctl --user is-active "$NAME.service" 2>/dev/null)

	if [ ! -f "$UNIT" ]; then
		section_begin "RedTooth" off
		section_skip "Not installed — run  $SCRIPT_NAME --on"
	elif is_enabled && [ "$active" = "active" ]; then
		section_begin "RedTooth" on
	else
		section_begin "RedTooth" off
		section_skip "Run  $SCRIPT_NAME --on"
	fi

	section_begin "Post"
	show_post

	section_begin "Bluetooth"
	show_devices

	section_begin "Log"
	if [ -s "$LOG" ]; then
		tail -n 8 "$LOG" | while IFS= read -r line; do
			printf "    %s%s%s\n" "$C_MUTED" "$line" "$C_RESET"
		done
	else
		section_skip "Nothing logged yet"
	fi
	echo
}

###############################################################################
# ARG PARSING
###############################################################################

action=""

while [ $# -gt 0 ]; do
	case "$1" in
		--on|on)           action=on ;;
		--off|off)         action=off ;;
		--status|status)   action=status ;;
		--disconnect-now)  action=disconnect ;;
		--uninstall)       action=uninstall ;;
		_start)            action=_start ;;
		_stop)             action=_stop ;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			ui_err "Unknown option: $1"
			usage >&2
			exit 2
			;;
	esac
	shift
done

[ -z "$action" ] && action=on

###############################################################################
# MAIN
###############################################################################

# Hooks (_start/_stop) are quiet under systemd and only print when run by
# hand in a terminal. Everything you run yourself always prints.
case "$action" in
	_start|_stop) ;;
	*) UI=1; banner ;;
esac

case "$action" in
	on)         do_on ;;
	off)        do_off ;;
	status)     do_status ;;
	disconnect) do_disconnect_now ;;
	uninstall)  do_uninstall ;;
	_start)     do_start ;;
	_stop)      do_stop ;;
esac

exit 0
