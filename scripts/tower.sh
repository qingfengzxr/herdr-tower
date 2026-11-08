#!/usr/bin/env bash
# Mark this pane as the tower for one job.
#   tower.sh init <slug>            prints the job's state directory
#   tower.sh finish <state_dir>     restores the pane's previous label
set -u
here=${BASH_SOURCE[0]%/*}
. "$here/lib.sh"

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  init)
    [ $# -eq 1 ] || die "usage: init <slug>"
    case "$1" in ''|.|..|*/*|*[[:space:]]*) die "invalid job name: $1" ;; esac
    [ "${HERDR_ENV:-}" = 1 ] || die "not running inside a Herdr pane"
    state="$(tower_state_root)/$1"
    mkdir -p "$state/runs" || die "cannot create $state"
    info=$(herdr pane get "$HERDR_PANE_ID") || die "tower pane not found"
    if [ ! -f "$state/tower-pane" ]; then
      printf '%s' "$HERDR_PANE_ID" > "$state/tower-pane"
      printf '%s' "$info" | field label > "$state/tower-label"
    fi
    herdr pane rename "$HERDR_PANE_ID" "🗼 塔台" >/dev/null || die "could not label the tower pane"
    printf '%s\n' "$state"
    ;;
  finish)
    [ $# -eq 1 ] || die "usage: finish <state_dir>"
    [ -f "$1/tower-pane" ] || die "not a tower state directory: $1"
    pane=$(cat "$1/tower-pane")
    old=$(cat "$1/tower-label" 2>/dev/null)
    if [ -n "$old" ]; then herdr pane rename "$pane" "$old" >/dev/null
    else herdr pane rename "$pane" --clear >/dev/null; fi
    ;;
  *) die "usage: tower.sh init|finish ..." ;;
esac
