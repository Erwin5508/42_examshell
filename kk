#!/usr/bin/env bash
# kk — 42 exam shell launcher / dev helper
#
# Subcommands:
#   ./kk              launch the interactive exam menu (= bash exam.sh)
#   ./kk run <exo>    run tester.sh for one exo (auto-found in any rank)
#   ./kk new <exo>    scaffold rendu/<exo>/ so you can start coding
#   ./kk diff <exo>   diff your rendu against the reference solution
#   ./kk done <exo>   test → commit → push your rendu/<exo>
#   ./kk sync         fetch upstream + merge + push to your fork
#   ./kk list [rank]  list exos in a rank (or all ranks)
#   ./kk help         this message

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

c_green='\033[0;32m'; c_red='\033[0;31m'; c_yellow='\033[1;33m'
c_blue='\033[0;34m'; c_dim='\033[2m'; c_off='\033[0m'

ok()    { printf "${c_green}✔${c_off} %s\n" "$*"; }
err()   { printf "${c_red}✗${c_off} %s\n" "$*" >&2; }
warn()  { printf "${c_yellow}⚠${c_off} %s\n" "$*"; }
head1() { printf "\n${c_blue}── %s ──${c_off}\n" "$*"; }

# Find the canonical .resources/rankXX/levelY/<exo>/ dir for a given exo name.
# Returns the relative path or empty if not found.
find_exo_dir() {
	local exo="$1"
	find .resources -type d -name "$exo" 2>/dev/null | head -1
}

cmd_help() {
	cat <<EOF
kk — 42 exam shell

Usage:
  ./kk                  launch the interactive exam menu
  ./kk run <exo>        compile + test one exo by name
  ./kk new <exo>        scaffold rendu/<exo>/ from the reference
  ./kk diff <exo>       diff rendu/<exo>/ vs the reference solution
  ./kk done <exo>       test → git commit → git push origin main
  ./kk sync             fetch upstream + merge + push origin
  ./kk list [rank]      list exos (in a rank or all)
  ./kk help             this message
EOF
}

cmd_run() {
	local exo="$1"
	[ -z "$exo" ] && { err "usage: ./kk run <exo>"; return 1; }
	local exo_dir
	exo_dir=$(find_exo_dir "$exo")
	[ -z "$exo_dir" ] && { err "exo '$exo' not found in .resources"; return 1; }
	head1 "tester $exo  ($exo_dir)"
	# tester.sh expects to be run FROM the exo dir; rendu lives at repo root.
	( cd "$exo_dir" && bash tester.sh )
}

cmd_new() {
	local exo="$1"
	[ -z "$exo" ] && { err "usage: ./kk new <exo>"; return 1; }
	local exo_dir
	exo_dir=$(find_exo_dir "$exo")
	[ -z "$exo_dir" ] && { err "exo '$exo' not found in .resources"; return 1; }
	mkdir -p "rendu/$exo"
	if [ -f "$exo_dir/sub.txt" ]; then
		cp "$exo_dir/sub.txt" "rendu/$exo/"
	fi
	if [ -f "$exo_dir/main.c" ]; then
		cp "$exo_dir/main.c" "rendu/$exo/main.c.ref"
	fi
	if [ ! -f "rendu/$exo/$exo.c" ]; then
		printf '// %s — your solution goes here\n' "$exo" > "rendu/$exo/$exo.c"
	fi
	ok "rendu/$exo/ ready"
	echo
	head1 "subject"
	cat "rendu/$exo/sub.txt" 2>/dev/null || warn "no sub.txt for $exo"
}

cmd_diff() {
	local exo="$1"
	[ -z "$exo" ] && { err "usage: ./kk diff <exo>"; return 1; }
	[ ! -f "rendu/$exo/$exo.c" ] && { err "rendu/$exo/$exo.c not found"; return 1; }
	local exo_dir
	exo_dir=$(find_exo_dir "$exo")
	[ -z "$exo_dir" ] && { err "ref exo '$exo' not found"; return 1; }
	head1 "diff rendu/$exo/$exo.c  vs  $exo_dir/$exo.c"
	diff -u "rendu/$exo/$exo.c" "$exo_dir/$exo.c" || true
}

cmd_done() {
	local exo="$1"
	[ -z "$exo" ] && { err "usage: ./kk done <exo>"; return 1; }
	[ ! -d "rendu/$exo" ] && { err "rendu/$exo/ doesn't exist — run ./kk new first"; return 1; }
	head1 "test before commit"
	if ! cmd_run "$exo"; then
		err "tester failed — fix before commit"
		return 1
	fi
	head1 "git commit + push"
	git add "rendu/$exo"
	git commit -m "rendu($exo): pass"
	git push origin main
	ok "$exo committed + pushed to origin"
}

cmd_sync() {
	head1 "fetch upstream"
	git fetch upstream
	head1 "merge upstream/main"
	git merge upstream/main
	head1 "push origin"
	git push origin main
	ok "synced"
}

cmd_list() {
	local target="$1"
	if [ -z "$target" ]; then
		for r in .resources/rank02 .resources/rank03 .resources/rank04 .resources/rank05 .resources/rank06; do
			[ -d "$r" ] || continue
			head1 "$(basename $r)"
			for L in "$r"/level*; do
				[ -d "$L" ] || continue
				printf "  %s : %s\n" "$(basename $L)" "$(ls "$L" 2>/dev/null | tr '\n' ' ')"
			done
		done
	else
		local r=".resources/$target"
		[ ! -d "$r" ] && { err "rank '$target' not found"; return 1; }
		for L in "$r"/level*; do
			[ -d "$L" ] || continue
			printf "  %s : %s\n" "$(basename $L)" "$(ls "$L" 2>/dev/null | tr '\n' ' ')"
		done
	fi
}

case "${1:-launch}" in
	""|launch)        bash exam.sh ;;
	run)              shift; cmd_run "$@" ;;
	new)              shift; cmd_new "$@" ;;
	diff)             shift; cmd_diff "$@" ;;
	done)             shift; cmd_done "$@" ;;
	sync)             cmd_sync ;;
	list)             shift; cmd_list "$@" ;;
	help|-h|--help)   cmd_help ;;
	*)                err "unknown : $1"; cmd_help; exit 1 ;;
esac
