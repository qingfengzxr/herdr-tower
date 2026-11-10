#!/usr/bin/env bash
# Choose or create the pane for the next subagent; print its ID.
#   layout.sh place --cwd DIR      the tower is $HERDR_PANE_ID
# Ownership comes from Herdr itself: a pane labelled with the rocket belongs to the tower.
set -u
here=${BASH_SOURCE[0]%/*}
. "$here/lib.sh"
OWN_PREFIX='🚀'
OVERFLOW_PREFIX='🚀 调度 '
PER_TAB=4
TOWER_SHARE=0.4
lock=''
trap '[ -n "$lock" ] && lock_release "$lock"' EXIT

panes_in_tab() { # tab_id, from the workspace pane list on stdin of $all_panes
  printf '%s' "$all_panes" | grep -o '"pane_id":"[^"]*"\|"tab_id":"[^"]*"' | {
    local pane='' line
    while read -r line; do
      case "$line" in
        '"pane_id"'*) pane=${line#*:\"}; pane=${pane%\"} ;;
        '"tab_id":"'"$1"'"') printf '%s\n' "$pane" ;;
      esac
    done
  }
}
is_owned() { case "$(herdr pane get "$1" | field label)" in "$OWN_PREFIX"*) return 0 ;; esac; return 1; }

tallest_of() { # panes as arguments; first listed wins a tie, so upper panes split first
  local best='' best_h=-1 p h
  for p in "$@"; do
    h=$(herdr pane layout --pane "$p" | grep -o "\"pane_id\":\"$p\",\"rect\":{\"height\":[0-9]*" | grep -o '[0-9]*$')
    [ "${h:-0}" -gt "$best_h" ] && { best=$p best_h=$h; }
  done
  printf '%s' "$best"
}
new_split() { # target, direction, ratio, cwd
  herdr pane split "$1" --direction "$2" --ratio "$3" --cwd "$4" --no-focus | field pane_id
}

all_owned() { # panes as arguments
  local p
  for p in "$@"; do is_owned "$p" || return 1; done
}

overflow_tab() { printf '%s' "$overflow" | grep "^$1=" | head -1 | cut -d= -f2-; }

place() {
  local cwd=$1 tower=$HERDR_PANE_ID info workspace tab new='' others=() n
  [ -n "$tower" ] || die "HERDR_PANE_ID is not set"
  info=$(herdr pane get "$tower" 2>/dev/null) || die "tower pane not found: $tower"
  workspace=$(printf '%s' "$info" | field workspace_id)
  tab=$(printf '%s' "$info" | field tab_id)
  lock="$(tower_state_root)/locks/${workspace//[^A-Za-z0-9]/_}"
  lock_acquire "$lock" 30 || die "could not lock the layout"
  all_panes=$(herdr pane list --workspace "$workspace") || die "could not list panes"

  # Right column of the tower tab, unless someone else's pane lives there.
  while read -r p; do [ -n "$p" ] && [ "$p" != "$tower" ] && others+=("$p"); done < <(panes_in_tab "$tab")
  if [ "${#others[@]}" -eq 0 ]; then
    new=$(new_split "$tower" right "$TOWER_SHARE" "$cwd")
  elif [ "${#others[@]}" -lt "$PER_TAB" ] && all_owned "${others[@]}"; then
    new=$(new_split "$(tallest_of "${others[@]}")" down 0.5 "$cwd")
  fi

  # Otherwise the first overflow tab with room, in number order.
  if [ -z "$new" ]; then
    local tabs line label id numbers='' t panes
    tabs=$(herdr tab list --workspace "$workspace" | grep -o '"label":"[^"]*"\|"tab_id":"[^"]*"')
    local overflow='' # "number=tab" per line; macOS ships bash 3.2 without associative arrays
    while read -r line; do
      case "$line" in
        '"label"'*) label=${line#*:\"}; label=${label%\"} ;;
        '"tab_id"'*) id=${line#*:\"}; id=${id%\"}
          case "$label" in "$OVERFLOW_PREFIX"*)
            n=${label#"$OVERFLOW_PREFIX"}
            case "$n" in ''|*[!0-9]*) ;; *) overflow+="$n=$id"$'\n'; numbers+="$n " ;; esac ;;
          esac ;;
      esac
    done <<< "$tabs"
    for n in $(printf '%s\n' $numbers | sort -n); do
      panes=(); while read -r p; do [ -n "$p" ] && panes+=("$p"); done < <(panes_in_tab "$(overflow_tab "$n")")
      [ "${#panes[@]}" -gt 0 ] && [ "${#panes[@]}" -lt "$PER_TAB" ] && all_owned "${panes[@]}" || continue
      new=$(new_split "$(tallest_of "${panes[@]}")" down 0.5 "$cwd")
      break
    done
    if [ -z "$new" ]; then
      n=2; while [ -n "$(overflow_tab "$n")" ]; do n=$(( n + 1 )); done
      new=$(herdr tab create --workspace "$workspace" --label "$OVERFLOW_PREFIX$n" --cwd "$cwd" --no-focus | field pane_id)
    fi
  fi

  [ -n "$new" ] || die "could not create a pane"
  # Label before unlocking, so the next placement counts this pane as ours.
  herdr pane rename "$new" "$OWN_PREFIX 启动中" >/dev/null || die "could not label pane $new"
  printf '%s\n' "$new"
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  place)
    cwd=$PWD
    while [ $# -gt 0 ]; do
      case "$1" in --cwd) [ $# -ge 2 ] || die "--cwd needs a value"; cwd=$2; shift 2 ;; *) die "unknown option: $1" ;; esac
    done
    [ -d "$cwd" ] || die "cwd not found: $cwd"
    place "$cwd"
    ;;
  *) die "usage: layout.sh place --cwd DIR" ;;
esac
