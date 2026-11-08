#!/usr/bin/env bash
# Role -> agent CLI + model settings, and agent CLI checks.
#   tower-config.sh set <role> <cli> <model|->
#   tower-config.sh get <role>      prints cli<TAB>model; exit 1 if unset
#   tower-config.sh list | remove <role>
#   tower-config.sh detect          prints cli<TAB>path-or-missing
#   tower-config.sh check <cli>     exit 1 if the CLI is not ready to run
set -u
here=${BASH_SOURCE[0]%/*}
. "$here/lib.sh"
CLIS='claude codex grok'
file=$(tower_config_file)
tab=$'\t'

valid_cli() { case " $CLIS " in *" $1 "*) return 0 ;; esac; return 1; }
valid_role() {
  case "$1" in
    ''|*/*|*"$tab"*|*$'\n'*) return 1 ;;
  esac
}
lookup() { # role -> cli<TAB>model
  [ -f "$file" ] || return 1
  local r c m
  while IFS="$tab" read -r r c m; do
    [ "$r" = "$1" ] && { printf '%s\t%s\n' "$c" "$m"; return 0; }
  done < "$file"
  return 1
}
write_without() { # role: print every other line
  [ -f "$file" ] || return 0
  local r c m
  while IFS="$tab" read -r r c m; do
    [ "$r" = "$1" ] || printf '%s\t%s\t%s\n' "$r" "$c" "$m"
  done < "$file"
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  set)
    [ $# -eq 3 ] || die "usage: set <role> <cli> <model|->"
    valid_role "$1" || die "invalid role name: $1"
    valid_cli "$2" || die "unsupported CLI: $2 (supported: $CLIS)"
    case "$3" in ''|*"$tab"*|*$'\n'*) die "invalid model: $3" ;; esac
    mkdir -p "${file%/*}" || die "cannot create config directory"
    { write_without "$1"; printf '%s\t%s\t%s\n' "$1" "$2" "$3"; } > "$file.tmp" && mv "$file.tmp" "$file"
    ;;
  get)
    [ $# -eq 1 ] || die "usage: get <role>"
    lookup "$1"
    ;;
  list) [ -f "$file" ] && cat "$file"; exit 0 ;;
  remove)
    [ $# -eq 1 ] || die "usage: remove <role>"
    write_without "$1" > "$file.tmp" && mv "$file.tmp" "$file"
    ;;
  detect)
    for c in $CLIS; do
      p=$(command -v "$c") && printf '%s\t%s\n' "$c" "$p" || printf '%s\tmissing\n' "$c"
    done
    ;;
  check)
    [ $# -eq 1 ] || die "usage: check <cli>"
    valid_cli "$1" || die "unsupported CLI: $1"
    command -v "$1" >/dev/null || { echo "$1: not installed"; exit 1; }
    case "$1" in
      claude) out=$(claude auth status 2>&1); rc=$?; case "$out" in *'"loggedIn": true'*) ;; *) rc=1 ;; esac ;;
      codex) out=$(codex login status 2>&1); rc=$? ;;
      grok) out=$(grok models 2>&1 </dev/null); rc=$?; case "$out" in *'logged in'*) ;; *) rc=1 ;; esac ;;
    esac
    [ "$rc" -eq 0 ] && echo "$1: ready" || { echo "$1: not ready: $(printf '%s' "$out" | head -3)"; exit 1; }
    ;;
  *) die "usage: tower-config.sh set|get|list|remove|detect|check ..." ;;
esac
