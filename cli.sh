#!/usr/bin/env bash
# Ludus developer CLI, driven by the makefile. Run `./cli.sh help` for usage.

set -uo pipefail
cd "$(dirname "$0")"

BUILD_DIR=${BUILD_DIR:-build}
EXAMPLES_DIR=$BUILD_DIR/examples
VERSION_FILE=CMakeLists.txt
CXX=${CXX:-g++}
CXXFLAGS=${CXXFLAGS:--std=c++20 -Wall -Wextra -Iinclude}

# Style

# Colour on a terminal or in GitHub Actions; NO_COLOR turns it off.
if [[ -z ${NO_COLOR:-} && ( -t 1 || -n ${GITHUB_ACTIONS:-} ) ]]; then
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

cmd_help() {
	local A=$ACCENT R=$RESET B=$BOLD D=$DIM
	cat <<EOF
${B}Ludus${R} ${D}— make <command>${R}

${B}Build${R}
  ${A}build${R}     Build the library or an example     ${D}make build NAME=src|<example>${R}
  ${A}run${R}       Build and run an example            ${D}make run NAME=<example>${R}
  ${A}clean${R}     Remove build artifacts

${B}Test${R}
  ${A}test${R}      Run the tests                       ${D}not implemented yet${R}
  ${A}check${R}     Build everything and test           ${D}what CI runs${R}

${B}Project${R}
  ${A}version${R}   Print the current version
  ${A}bump${R}      Bump the version                    ${D}make bump TO=patch|minor|major|1.2.3${R}

${D}Without NAME, build and run open a picker.${R}
EOF
}

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

cmd_check() {
	local status=0 name list
	mapfile -t list < <(examples)
	build_library || status=1
	for name in "${list[@]}"; do
		build_example "$name" || status=1
	done
	cmd_test || status=1
	printf '\n'
	if (( status == 0 )); then
		printf '%s%sAll checks passed.%s\n' "$GREEN" "$BOLD" "$RESET"
	else
		printf '%s%sChecks failed.%s\n' "$RED" "$BOLD" "$RESET"
	fi
	return "$status"
}

cmd_clean() { rm -rf "$BUILD_DIR"; ok "Removed $BUILD_DIR/"; }

# The project() VERSION in CMakeLists.txt.
current_version() { sed -n 's/^ *VERSION \([^ ]*\)$/\1/p' "$VERSION_FILE"; }

cmd_version() { current_version; }

cmd_bump() {
	local to=${1:-patch} old new major minor patch
	old=$(current_version)
	if [[ ! $old =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		fail "No X.Y.Z VERSION in $VERSION_FILE"; exit 1
	fi
	IFS=. read -r major minor patch <<<"$old"
	case $to in
		major) new="$((major + 1)).0.0" ;;
		minor) new="$major.$((minor + 1)).0" ;;
		patch) new="$major.$minor.$((patch + 1))" ;;
		*)
			if [[ ! $to =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
				fail "TO must be patch, minor, major or X.Y.Z, got '$to'"; exit 1
			fi
			new=$to ;;
	esac
	sed "s/^\( *VERSION \)$old$/\1$new/" "$VERSION_FILE" >"$VERSION_FILE.tmp" \
		&& mv "$VERSION_FILE.tmp" "$VERSION_FILE"
	ok "Bumped version $DIM$old → $new$RESET"
}

case ${1:-help} in
	help|build|run|clean|test|check|version|bump) cmd=$1; shift; "cmd_$cmd" "$@" ;;
	*) fail "Unknown command '$1'"; printf '\n' >&2; cmd_help >&2; exit 1 ;;
esac
