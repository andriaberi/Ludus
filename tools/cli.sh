#!/usr/bin/env bash
# Ludus developer CLI, driven by the makefile.
#
#   cli.sh build [name]   build the library (src) or an example
#   cli.sh run   [name]   build and run an example
#   cli.sh test           run the test suite
#   cli.sh clean          remove build artifacts
#
# Without a name, build and run open an interactive picker.

set -uo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR=${BUILD_DIR:-build}
EXAMPLES_DIR=$BUILD_DIR/examples
CXX=${CXX:-g++}
CXXFLAGS=${CXXFLAGS:--std=c++20 -Wall -Wextra -Iinclude}

# Style

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
	BOLD=$'\e[1m' DIM=$'\e[2m' RESET=$'\e[0m'
	ACCENT=$'\e[36m' GREEN=$'\e[32m' RED=$'\e[31m' YELLOW=$'\e[33m'
	CXXFLAGS+=" -fdiagnostics-color=always"
else
	BOLD='' DIM='' RESET='' ACCENT='' GREEN='' RED='' YELLOW=''
fi

ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
note() { printf '%s•%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; }

# rule — a dim line across the terminal.
rule() {
	local line
	printf -v line '%*s' "$(tput cols 2>/dev/null || echo 40)" ''
	printf '%s%s%s\n' "$DIM" "${line// /─}" "$RESET"
}

# Picker

UI_ACTIVE=0

ui_enter() {
	exec 3<>/dev/tty
	UI_STTY=$(stty -g <&3)
	stty -echo -icanon <&3
	printf '\e[?1049h\e[?25l' >&3   # alternate screen, hide cursor
	UI_ACTIVE=1
}

ui_leave() {
	(( UI_ACTIVE )) || return 0
	printf '\e[?25h\e[?1049l' >&3   # show cursor, restore screen
	stty "$UI_STTY" <&3
	exec 3>&-
	UI_ACTIVE=0
}

trap ui_leave EXIT
trap 'exit 130' INT TERM

# pick TITLE OPTION... — sets PICKED; returns 1 if the user cancels.
pick() {
	local title=$1; shift
	local options=("$@") count=$# sel=0 i key rest frame

	ui_enter
	while :; do
		frame=$'\e[H\e[J'"${BOLD}${title}${RESET}"$'\n\n'
		for i in "${!options[@]}"; do
			if (( i == sel )); then
				frame+="${ACCENT}${BOLD}❯ ${options[i]}${RESET}"$'\n'
			else
				frame+="  ${BOLD}${options[i]}${RESET}"$'\n'
			fi
		done
		frame+=$'\n'"${DIM}↑↓ select · enter confirm · esc cancel${RESET}"
		printf '%s' "$frame" >&3

		IFS= read -rsn1 -u 3 key
		case $key in
			$'\e')
				IFS= read -rsn2 -t 0.05 -u 3 rest
				case ${rest:1} in
					A) (( sel = (sel - 1 + count) % count )) ;;
					B) (( sel = (sel + 1) % count )) ;;
					'') ui_leave; return 1 ;;
				esac ;;
			k) (( sel = (sel - 1 + count) % count )) ;;
			j) (( sel = (sel + 1) % count )) ;;
			q) ui_leave; return 1 ;;
			'') break ;;
		esac
	done
	ui_leave

	PICKED=${options[sel]}
}

# Steps

# step NAME OUTPUT CMD... — runs CMD quietly behind a spinner, printing its log only on failure.
step() {
	local name=$1 output=$2; shift 2
	local log pid status
	log=$(mktemp)

	"$@" >"$log" 2>&1 &
	pid=$!
	trap 'kill $pid 2>/dev/null; printf "\r\e[K\e[?25h"; rm -f "$log"; exit 130' INT TERM

	if [[ -t 1 ]]; then
		local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0
		printf '\e[?25l'
		while kill -0 "$pid" 2>/dev/null; do
			printf '\r%s%s%s Building %s' "$ACCENT" "${frames[i++ % 10]}" "$RESET" "$name"
			sleep 0.08
		done
		printf '\r\e[K\e[?25h'
	fi

	wait "$pid"; status=$?
	trap 'exit 130' INT TERM

	if (( status == 0 )); then
		ok "Built $name $DIM→ $output$RESET"
	else
		fail "Failed to build $name"
		cat "$log" >&2
	fi
	rm -f "$log"
	return "$status"
}

# Commands

examples() { find examples -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort; }

# resolve_name TITLE NAME OPTION... — sets PICKED from NAME, or from the picker.
resolve_name() {
	local title=$1 name=$2; shift 2
	if [[ -n $name ]]; then
		PICKED=$name
	elif (( $# == 0 )); then
		note "No examples found"; exit 0
	elif [[ -t 0 && -t 1 ]]; then
		pick "$title" "$@" || exit 0
	else
		fail "No terminal for the picker; pass NAME=<$(IFS='|'; echo "$*")>"; exit 1
	fi
}

build_library() {
	step ludus "$BUILD_DIR" bash -c 'cmake -S . -B "$1" && cmake --build "$1"' _ "$BUILD_DIR"
}

build_example() {
	local name=$1 dir=examples/$1 sources
	if [[ ! -d $dir ]]; then
		fail "No example named '$name'"; exit 1
	fi
	mapfile -t sources < <(find "$dir" src -name '*.cpp' 2>/dev/null)
	mkdir -p "$EXAMPLES_DIR"
	# shellcheck disable=SC2086  # CXXFLAGS is a word list
	step "$name" "$EXAMPLES_DIR/$name" "$CXX" $CXXFLAGS "${sources[@]}" -o "$EXAMPLES_DIR/$name"
}

cmd_build() {
	local list; mapfile -t list < <(examples)
	resolve_name Build "${1:-}" src "${list[@]}"
	if [[ $PICKED == src ]]; then build_library; else build_example "$PICKED"; fi
}

cmd_run() {
	local list; mapfile -t list < <(examples)
	resolve_name Run "${1:-}" "${list[@]}"
	build_example "$PICKED" || exit 1
	rule
	exec "./$EXAMPLES_DIR/$PICKED"
}

cmd_test() { note "Tests are not implemented yet"; }

cmd_clean() { rm -rf "$BUILD_DIR"; ok "Removed $BUILD_DIR/"; }

case ${1:-} in
	build|run|test|clean) cmd=$1; shift; "cmd_$cmd" "$@" ;;
	*) sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 1 ;;
esac
