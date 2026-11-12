#!/usr/bin/env bash
# RedTooth
#
# Made for 1337 Ubuntu PCs
# Made by Bilal Rouane — 42 intra: brouane
#
# What it does:
# - At login:  saves the post (hostname) you are on, and remembers the
#              previous one.
# - At logout: disconnects your AirPods so the next post can connect to
#              them without you doing it by hand.
#
# Policy:
# - Runs as a systemd USER unit. No sudo, no daemon, nothing running
#   between login and logout.
# - Only devices whose name matches "AirPods" are ever touched.
# - Disconnect only by default. Unpairing is opt-in (--remove-airpods).
# - Never edits .zshrc / .bashrc / config.fish.
#
# Running with no arguments = --on (install + activate).
#
# Files:
#   ~/redtooth-logs.txt              simple log, one line per event
#   ~/.config/redtooth/state         current_host / previous_host / last_*
#   ~/.config/redtooth/config        enabled / airpods_pattern / remove
#   ~/.local/bin/redtooth            installed copy of this script
#   ~/.config/systemd/user/redtooth.service
#
# Output style: every section prints the same way —
#   ▌ Name   TAG   what it does
#       ✔ item
# Colors are disabled automatically when output is not a terminal, or
# when NO_COLOR is set. Set FORCE_COLOR=1 to keep them in a pipe.
#
# Useful examples:
#   ./redtooth.sh
#   ./redtooth.sh --status
#   ./redtooth.sh --off
#   ./redtooth.sh --disconnect-now
#   ./redtooth.sh --on --remove-airpods

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
	C_DIM=$'\033[2m'
	C_ACCENT=$'\033[38;5;39m'
	C_INFO=$'\033[38;5;75m'
	C_OK=$'\033[38;5;78m'
	C_WARN=$'\033[38;5;221m'
	C_ERR=$'\033[38;5;203m'
	C_MUTED=$'\033[38;5;245m'
else
	C_RESET="" C_BOLD="" C_DIM="" C_ACCENT="" C_INFO=""
	C_OK="" C_WARN="" C_ERR="" C_MUTED=""
fi

###############################################################################
# OUTPUT HELPERS (one look for every message in the script)
###############################################################################

ui_ok()   { printf "  %s✔%s %s\n" "$C_OK" "$C_RESET" "$*"; }
ui_info() { printf "  %s›%s %s\n" "$C_INFO" "$C_RESET" "$*"; }
ui_warn() { printf "  %s⚠%s %s%s%s\n" "$C_WARN" "$C_RESET" "$C_WARN" "$*" "$C_RESET"; }
ui_err()  { printf "  %s✖ %s%s\n" "$C_ERR" "$*" "$C_RESET" >&2; }

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

short_path() {
	# Show $HOME as ~ to keep lines readable.
	local p="$1"
	case "$p" in
		"$HOME") printf '~' ;;
		"$HOME"/*) printf '%s' "~${p#"$HOME"}" ;;
		*) printf '%s' "$p" ;;
	esac
}

section_begin() {
	# section_begin "Name" safe|medium|wipe|setup|info|on|off "what it does"
	local tag tagc
	case "$2" in
		safe)   tag="SAFE";   tagc="$C_OK" ;;
		medium) tag="MEDIUM"; tagc="$C_WARN" ;;
		wipe)   tag="WIPE";   tagc="$C_ERR" ;;
		setup)  tag="SETUP";  tagc="$C_ACCENT" ;;
		info)   tag="INFO";   tagc="$C_ACCENT" ;;
		on)     tag="ON";     tagc="$C_OK" ;;
		off)    tag="OFF";    tagc="$C_MUTED" ;;
		*)      tag="";       tagc="" ;;
	esac

	printf "\n  %s▌%s %s%-12s%s %s%s%-6s%s  %s%s%s\n" \
		"$C_ACCENT" "$C_RESET" \
		"$C_BOLD" "$1" "$C_RESET" \
		"$C_BOLD" "$tagc" "$tag" "$C_RESET" \
		"$C_MUTED" "$3" "$C_RESET"
}

section_skip() {
	printf "    %s↷ %s%s\n" "$C_MUTED" "$*" "$C_RESET"
}

row() {
	# row ICON COLOR "Label" "value"
	printf "    %s%s%s %s%-12s%s %s%s%s\n" \
		"$2" "$1" "$C_RESET" "$C_BOLD" "$3" "$C_RESET" "$C_MUTED" "$4" "$C_RESET"
}

dev_row() {
	# dev_row ICON COLOR "status" "name" "mac"
	printf "    %s%s%s %-20s %s%-14s%s %s%s%s\n" \
		"$2" "$1" "$C_RESET" "$3" "$C_BOLD" "$4" "$C_RESET" "$C_MUTED" "$5" "$C_RESET"
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
	printf "  %s%sRemember your post%s  %s·  free your AirPods at logout%s\n" \
		"$C_BOLD" "$C_ACCENT" "$C_RESET" "$C_MUTED" "$C_RESET"
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
	printf "\n  %s%sRedTooth%s  %s— remember your post, free your AirPods%s\n" \
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
		"Re-running never disconnects your AirPods."
	help_opt "--off" "Deactivate. Hooks do nothing, files are kept."
	help_opt "--status" \
		"Show active state, saved posts, your AirPods and the" \
		"last log lines."
	help_opt "--disconnect-now" "Disconnect the AirPods right now (no logout needed)"
	help_opt "--remove-airpods" \
		"At logout also UNPAIR the AirPods (you must re-pair" \
		"them next time). Off by default."
	help_opt "--keep-airpods" "At logout only disconnect (default)"
	help_opt "--uninstall" \
		"Remove unit, script, config and state." \
		"The log file in your home is kept."
	help_opt "--help, -h" "Show this help"

	help_heading "FILES"
	cat <<EOF
    ~/redtooth-logs.txt           simple log: one line per login/logout
    ~/.config/redtooth/state      current_host / previous_host / last_login
    ~/.config/redtooth/config     enabled / airpods_pattern / remove
EOF

	help_heading "EXAMPLES"
	cat <<EOF
    $SCRIPT_NAME
    $SCRIPT_NAME --status
    $SCRIPT_NAME --off
    $SCRIPT_NAME --disconnect-now
    $SCRIPT_NAME --on --remove-airpods
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

st_get() { sed -n "s/^$1=//p" "$STATE" 2>/dev/null | tail -n1; }

short_host() { hostname 2>/dev/null | cut -d. -f1; }

is_enabled() { [ "$(cfg_get enabled)" != "0" ]; }

remove_mode() {
	local r
	r=$(cfg_get remove)
	[ "$r" = "1" ]
}

ap_mode() { if remove_mode; then echo medium; else echo safe; fi; }

ap_desc() {
	if remove_mode; then
		echo "Disconnect + unpair at logout  (re-pair needed)"
	else
		echo "Disconnect at logout  (pairing kept)"
	fi
}

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
	kv "Saved in" "$(short_path "$STATE")" "$C_MUTED"
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
		section_begin "Login" info "Saving the post you are on"
		show_post
		echo
	fi
	return 0
}

###############################################################################
# AIRPODS
###############################################################################

# prints "MAC<TAB>NAME" for paired devices whose name matches the pattern
airpods_list() {
	command -v bluetoothctl >/dev/null 2>&1 || return 0
	local pat list mac name
	pat=$(cfg_get airpods_pattern); : "${pat:=AirPods}"
	list=$(timeout 5 bluetoothctl paired-devices 2>/dev/null)
	[ -n "$list" ] || list=$(timeout 5 bluetoothctl devices 2>/dev/null)
	[ -n "$list" ] || return 0
	while read -r _ mac name; do
		[ -n "$mac" ] || continue
		case "${name,,}" in *"${pat,,}"*) printf '%s\t%s\n' "$mac" "$name" ;; esac
	done <<< "$list"
}

is_connected() {
	timeout 5 bluetoothctl info "$1" 2>/dev/null | grep -q 'Connected: yes'
}

disconnect_airpods() {
	local n_disc=0 n_already=0 n_fail=0 n_removed=0 n_found=0 mac name

	if ! command -v bluetoothctl >/dev/null 2>&1; then
		log_event NOTE "bluetoothctl not found"
		[ "$UI" -eq 1 ] && section_skip "bluetoothctl not found — skipped"
		return 0
	fi

	while IFS=$'\t' read -r mac name; do
		[ -n "$mac" ] || continue
		n_found=$((n_found + 1))

		if is_connected "$mac"; then
			if timeout 8 bluetoothctl disconnect "$mac" >/dev/null 2>&1; then
				n_disc=$((n_disc + 1))
				log_event AIRPODS "disconnected: $name"
				[ "$UI" -eq 1 ] && dev_row "✔" "$C_OK" "disconnected" "$name" "$mac"
			else
				n_fail=$((n_fail + 1))
				log_event AIRPODS "FAILED to disconnect: $name"
				[ "$UI" -eq 1 ] && dev_row "✖" "$C_ERR" "disconnect FAILED" "$name" "$mac"
			fi
		else
			n_already=$((n_already + 1))
			log_event AIRPODS "already disconnected: $name"
			[ "$UI" -eq 1 ] && dev_row "↷" "$C_MUTED" "already disconnected" "$name" "$mac"
		fi

		if remove_mode; then
			if timeout 5 bluetoothctl remove "$mac" >/dev/null 2>&1; then
				n_removed=$((n_removed + 1))
				log_event AIRPODS "unpaired: $name"
				[ "$UI" -eq 1 ] && dev_row "✔" "$C_WARN" "unpaired" "$name" "$mac"
			else
				n_fail=$((n_fail + 1))
				log_event AIRPODS "FAILED to unpair: $name"
				[ "$UI" -eq 1 ] && dev_row "✖" "$C_ERR" "unpair FAILED" "$name" "$mac"
			fi
		fi
	done < <(airpods_list)

	if [ "$n_found" -eq 0 ]; then
		log_event NOTE "no AirPods found (Bluetooth off or nothing paired)"
		[ "$UI" -eq 1 ] && section_skip "No AirPods found (Bluetooth off, or none paired)"
		return 0
	fi

	if [ "$UI" -eq 1 ]; then
		if [ "$n_fail" -gt 0 ]; then
			printf "    %s✖ %d failed%s\n" "$C_ERR" "$n_fail" "$C_RESET"
		elif [ "$n_disc" -eq 0 ] && [ "$n_removed" -eq 0 ]; then
			printf "    %s✔ Already disconnected%s\n" "$C_MUTED" "$C_RESET"
		else
			printf "    %s✔ %d disconnected" "$C_OK" "$n_disc"
			[ "$n_removed" -gt 0 ] && printf " · %d unpaired" "$n_removed"
			printf "%s\n" "$C_RESET"
		fi
	fi
	return 0
}

show_airpods_devices() {
	local mac name n=0

	while IFS=$'\t' read -r mac name; do
		[ -n "$mac" ] || continue
		n=1
		if is_connected "$mac"; then
			dev_row "●" "$C_OK" "connected" "$name" "$mac"
		else
			dev_row "○" "$C_MUTED" "not connected" "$name" "$mac"
		fi
	done < <(airpods_list)

	[ "$n" -eq 1 ] || section_skip "No AirPods found (Bluetooth off, or none paired)"
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

	[ "$UI" -eq 1 ] && section_begin "AirPods" "$(ap_mode)" "$(ap_desc)"
	disconnect_airpods
	[ "$UI" -eq 1 ] && echo
	return 0
}

do_disconnect_now() {
	section_begin "AirPods" "$(ap_mode)" "Disconnect now"
	disconnect_airpods
	echo
	ui_ok "${C_BOLD}Done.${C_RESET}"
}

###############################################################################
# INSTALL / ACTIVATE / DEACTIVATE
###############################################################################

unit_text() {
cat <<'EOF'
[Unit]
Description=RedTooth: save your 1337 post at login, disconnect AirPods at logout

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=%h/.local/bin/redtooth _start
ExecStop=%h/.local/bin/redtooth _stop
TimeoutStopSec=20

[Install]
WantedBy=default.target
EOF
}

do_on() {
	command -v systemctl >/dev/null 2>&1 || { ui_err "systemctl not found"; exit 1; }

	local self was_active ts err
	ts=$(date +%s)

	section_begin "Install" setup "Script, systemd unit & config"

	mkdir -p "$HOME/.local/bin" "$UNIT_DIR" "$CONF_DIR" || { ui_err "cannot create directories"; exit 1; }

	# Script
	self=$(readlink -f "$0")
	if [ "$self" != "$(readlink -f "$BIN" 2>/dev/null)" ]; then
		if [ -e "$BIN" ]; then
			cp -p "$BIN" "$BIN.bak.$ts"
			section_skip "Old script backed up: $(short_path "$BIN.bak.$ts")"
		fi
		cp "$self" "$BIN" && chmod 755 "$BIN" || { ui_err "cannot install $(short_path "$BIN")"; exit 1; }
	fi
	row "✔" "$C_OK" "Script" "$(short_path "$BIN")"

	# Unit
	unit_text > "$UNIT.new"
	if [ -e "$UNIT" ] && ! cmp -s "$UNIT" "$UNIT.new"; then
		cp -p "$UNIT" "$UNIT.bak.$ts"
		section_skip "Old unit backed up: $(short_path "$UNIT.bak.$ts")"
	fi
	mv "$UNIT.new" "$UNIT"
	row "✔" "$C_OK" "Unit" "$(short_path "$UNIT")"

	# Config
	cfg_set enabled 1
	[ -n "$(cfg_get airpods_pattern)" ] || cfg_set airpods_pattern AirPods
	[ -n "$(cfg_get remove)" ] || cfg_set remove 0
	row "✔" "$C_OK" "Config" "$(short_path "$CONF")"

	# Activate
	was_active=$(systemctl --user is-active "$NAME.service" 2>/dev/null)
	systemctl --user daemon-reload
	err=$(systemctl --user enable --now "$NAME.service" 2>&1) \
		|| { ui_err "could not enable the unit: $err"; exit 1; }
	# unit already running: refresh the saved post without a logout hook
	[ "$was_active" = "active" ] && "$BIN" _start >/dev/null 2>&1
	row "✔" "$C_OK" "Activated" "runs at every login & logout"

	section_begin "Post" setup "Saved at every login"
	show_post

	section_begin "AirPods" "$(ap_mode)" "$(ap_desc)"
	kv "Matches" "names containing \"$(cfg_get airpods_pattern)\"" "$C_MUTED"
	show_airpods_devices

	section_begin "Log" info "One simple line per login / logout"
	kv "File" "$(short_path "$LOG")" "$C_MUTED"

	echo
	ui_ok "${C_BOLD}RedTooth is active.${C_RESET}"
}

do_off() {
	section_begin "RedTooth" off "Deactivate"
	# enabled=0 first, so the stop hook fired by --now does nothing
	cfg_set enabled 0
	systemctl --user disable --now "$NAME.service" >/dev/null 2>&1
	row "✔" "$C_OK" "Hooks" "login & logout do nothing now"
	row "✔" "$C_OK" "Files" "kept, nothing deleted"
	echo
	ui_info "Turn it back on with:  $SCRIPT_NAME --on"
}

rm_item() {
	# rm_item "Label" path
	if [ -e "$2" ]; then
		/bin/rm -rf -- "$2" 2>/dev/null
		row "✔" "$C_OK" "$1" "$(short_path "$2")"
	else
		section_skip "$1 — not found, skipped"
	fi
}

do_uninstall() {
	section_begin "Uninstall" wipe "Remove unit, script, config & state"
	cfg_set enabled 0
	systemctl --user disable --now "$NAME.service" >/dev/null 2>&1
	rm_item "Unit" "$UNIT"
	rm_item "Script" "$BIN"
	rm_item "Config" "$CONF_DIR"
	systemctl --user daemon-reload >/dev/null 2>&1

	echo
	if [ -e "$LOG" ]; then
		ui_info "Log kept: $(short_path "$LOG")  (delete it by hand if you want)"
	fi
	ui_info "Any *.bak.* backups next to the removed files were left in place."
	ui_ok "${C_BOLD}RedTooth removed.${C_RESET}"
}

###############################################################################
# STATUS
###############################################################################

do_status() {
	local active mode line

	active=$(systemctl --user is-active "$NAME.service" 2>/dev/null)

	if [ ! -f "$UNIT" ]; then
		section_begin "RedTooth" off "Not installed"
		section_skip "Run  $SCRIPT_NAME --on  to install and activate"
	else
		if is_enabled && [ "$active" = "active" ]; then mode=on; else mode=off; fi
		section_begin "RedTooth" "$mode" "Login & logout hooks"
		if [ "$mode" = on ]; then
			kv "Active" "yes" "$C_OK$C_BOLD"
		else
			kv "Active" "no  (config enabled=$(or_dash "$(cfg_get enabled)"), systemd: ${active:-unknown})" "$C_WARN"
		fi
		kv "At login" "saves the post you are on" "$C_MUTED"
		if remove_mode; then
			kv "At logout" "disconnects + unpairs AirPods" "$C_WARN"
		else
			kv "At logout" "disconnects AirPods (pairing kept)" "$C_MUTED"
		fi
	fi

	section_begin "Post" info "Where you are, where you were"
	show_post

	section_begin "AirPods" "$(ap_mode)" "$(ap_desc)"
	show_airpods_devices

	section_begin "Log" info "$(short_path "$LOG")  (last 8)"
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
rm_set=""

while [ $# -gt 0 ]; do
	case "$1" in
		--on|on)           action=on ;;
		--off|off)         action=off ;;
		--status|status)   action=status ;;
		--disconnect-now)  action=disconnect ;;
		--uninstall)       action=uninstall ;;
		--remove-airpods)  rm_set=1 ;;
		--keep-airpods)    rm_set=0 ;;
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

[ -z "$action" ] && [ -z "$rm_set" ] && action=on

###############################################################################
# MAIN
###############################################################################

# Hooks (_start/_stop) are quiet under systemd and only print when run by
# hand in a terminal. Everything you run yourself always prints.
case "$action" in
	_start|_stop) ;;
	*) UI=1; banner ;;
esac

if [ -n "$rm_set" ]; then
	cfg_set remove "$rm_set"
	echo
	if [ "$rm_set" = 1 ]; then
		ui_warn "At logout the AirPods will be disconnected AND unpaired (re-pair needed)."
	else
		ui_ok "At logout the AirPods will only be disconnected."
	fi
fi

case "$action" in
	on)         do_on ;;
	off)        do_off ;;
	status)     do_status ;;
	disconnect) do_disconnect_now ;;
	uninstall)  do_uninstall ;;
	_start)     do_start ;;
	_stop)      do_stop ;;
	"")         echo ;;
esac

exit 0
