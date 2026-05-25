#!/usr/bin/env bash
# kk — 42 exam shell launcher / dev helper
#
# Subcommands:
#   ./kk              launch the interactive exam menu (= bash exam.sh)
#   ./kk run <exo>    run tester.sh for one exo (auto-found in any rank)
#   ./kk new <exo>    scaffold rendu/<exo>/ so you can start coding
#   ./kk diff <exo>   diff your rendu against the reference solution
#   ./kk done <exo>   test → mark done → commit → push your rendu/<exo>
#   ./kk skip <exo>   mark exo as deferred (still counted as 'not done')
#   ./kk reset <exo>  un-mark done / skip
#   ./kk next         pick the next exo not yet done, in rank/level order
#   ./kk progress     print done X / 73 + per-rank breakdown
#   ./kk sync         fetch upstream + merge + push to your fork
#   ./kk list [rank]  list exos in a rank (or all ranks)
#   ./kk help         this message

set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"
PROGRESS_FILE="$REPO_DIR/.progress"

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

# All exos = every directory that owns BOTH tester.sh AND sub.txt.
# Catches the level/<exo> shape (rank02-05) and the rank06/<exo> shape
# (mini_db, mini_serv) that has no level subdir. The 'sub.txt' requirement
# filters out orphan testers like .resources/rank04/level1/tester.sh.
all_exos() {
	find .resources -type f -name sub.txt -printf "%h\n" 2>/dev/null \
		| sort \
		| sed 's|^\.resources/||'
}

# Mark status for one exo in .progress.
# format per line :  <exo>	<done|skip>
mark_status() {
	local exo="$1"; local status="$2"
	touch "$PROGRESS_FILE"
	# strip any existing entry, then append
	grep -v "^${exo}	" "$PROGRESS_FILE" > "${PROGRESS_FILE}.tmp" || true
	mv "${PROGRESS_FILE}.tmp" "$PROGRESS_FILE"
	printf '%s\t%s\n' "$exo" "$status" >> "$PROGRESS_FILE"
}

get_status() {
	local exo="$1"
	[ ! -f "$PROGRESS_FILE" ] && { echo "todo"; return; }
	local row
	row=$(grep "^${exo}	" "$PROGRESS_FILE" || true)
	if [ -z "$row" ]; then echo "todo"
	else echo "$row" | awk -F'\t' '{print $2}'
	fi
}

cmd_help() {
	cat <<EOF
kk — 42 exam shell

Usage:
  ./kk                  launch the interactive exam menu
  ./kk run <exo>        compile + test one exo by name
  ./kk new <exo>        scaffold rendu/<exo>/ from the reference
  ./kk diff <exo>       diff rendu/<exo>/ vs the reference solution
  ./kk done <exo>       test → mark done → commit → push origin main
  ./kk skip <exo>       mark exo as deferred
  ./kk reset <exo>      un-mark done / skip
  ./kk next             pick the next exo not yet done
  ./kk progress         show overall progress + per-rank breakdown
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
	mark_status "$exo" "done"
	head1 "git commit + push"
	git add "rendu/$exo" "$PROGRESS_FILE" 2>/dev/null || git add "rendu/$exo"
	git commit -m "rendu($exo): pass"
	git push origin main
	ok "$exo done + pushed to origin"
}

cmd_skip() {
	local exo="$1"
	[ -z "$exo" ] && { err "usage: ./kk skip <exo>"; return 1; }
	mark_status "$exo" "skip"
	ok "$exo marked as skipped"
}

cmd_reset() {
	local exo="$1"
	[ -z "$exo" ] && { err "usage: ./kk reset <exo>"; return 1; }
	[ ! -f "$PROGRESS_FILE" ] && { warn "$exo wasn't marked anyway"; return 0; }
	grep -v "^${exo}	" "$PROGRESS_FILE" > "${PROGRESS_FILE}.tmp" || true
	mv "${PROGRESS_FILE}.tmp" "$PROGRESS_FILE"
	ok "$exo reset"
}

cmd_next() {
	while IFS= read -r path; do
		local exo
		exo=$(basename "$path")
		local st
		st=$(get_status "$exo")
		if [ "$st" = "todo" ]; then
			head1 "next : $exo  ($path)"
			cat ".resources/$path/sub.txt" 2>/dev/null | head -25
			echo
			ok "Run ./kk new $exo to start, then ./kk done $exo when it passes."
			return 0
		fi
	done < <(all_exos)
	ok "All exos done or skipped. 🎉"
}

cmd_progress() {
	local total done_n skip_n todo_n
	total=$(all_exos | wc -l)
	if [ -f "$PROGRESS_FILE" ]; then
		done_n=$(grep -c "	done$" "$PROGRESS_FILE" || echo 0)
		skip_n=$(grep -c "	skip$" "$PROGRESS_FILE" || echo 0)
	else
		done_n=0; skip_n=0
	fi
	todo_n=$((total - done_n - skip_n))
	head1 "overall : $done_n done / $skip_n skipped / $todo_n todo / $total total"

	# Per-rank breakdown — find dirs that have sub.txt.
	for r in rank02 rank03 rank04 rank05 rank06; do
		[ -d ".resources/$r" ] || continue
		local r_total r_done r_skip
		r_total=$(find ".resources/$r" -name sub.txt -type f 2>/dev/null | wc -l)
		r_done=0; r_skip=0
		while IFS= read -r d; do
			local e
			e=$(basename "$d")
			local s
			s=$(get_status "$e")
			[ "$s" = "done" ] && r_done=$((r_done + 1))
			[ "$s" = "skip" ] && r_skip=$((r_skip + 1))
		done < <(find ".resources/$r" -name sub.txt -type f -printf "%h\n" 2>/dev/null)
		local pct=$((r_done * 100 / (r_total > 0 ? r_total : 1)))
		printf "  %s : %d done / %d skip / %d total  (%d%%)\n" \
			"$r" "$r_done" "$r_skip" "$r_total" "$pct"
	done
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
	skip)             shift; cmd_skip "$@" ;;
	reset)            shift; cmd_reset "$@" ;;
	next)             cmd_next ;;
	progress|status)  cmd_progress ;;
	sync)             cmd_sync ;;
	list)             shift; cmd_list "$@" ;;
	help|-h|--help)   cmd_help ;;
	*)                err "unknown : $1"; cmd_help; exit 1 ;;
esac
