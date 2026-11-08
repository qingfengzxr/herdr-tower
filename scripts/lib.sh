# Shared helpers. Source this file; it has no side effects.

die() { echo "error: $*" >&2; exit 2; }

# First value of a string field in Herdr's compact JSON.
field() { grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }

tower_state_root() { printf '%s' "${HERDR_TOWER_STATE:-$HOME/.local/state/herdr-tower}"; }
tower_config_file() { printf '%s' "${HERDR_TOWER_CONFIG:-$HOME/.config/herdr-tower/roles.conf}"; }

# mkdir is atomic on every platform we support, unlike flock.
lock_acquire() { # dir, seconds
  local dir=$1 limit=${2:-30} start=$SECONDS
  mkdir -p "$(dirname "$dir")" || return 1
  until mkdir "$dir" 2>/dev/null; do
    # A holder that died must not block everyone forever.
    if [ -n "$(find "$dir" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
      rmdir "$dir" 2>/dev/null
      continue
    fi
    [ $(( SECONDS - start )) -ge "$limit" ] && return 1
    sleep 0.2
  done
}
lock_release() { rmdir "$1" 2>/dev/null; }

# Dialog parsing. Agents can print anything into the pane, so only the bottom-most menu counts.
trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
menu_tail() { # marker, screen: from the last line starting with the marker to the end
  printf '%s\n' "$2" | awk -v re="^[[:space:]]*$1 " '$0 ~ re { buf=""; on=1 } on { buf=buf $0 "\n" } END { printf "%s", buf }'
}
menu_line() { # n, menu: the nth non-blank line, trimmed
  printf '%s\n' "$2" | grep -v '^[[:space:]]*$' | sed -n "$1p" | trim
}
menu_context() { # marker, screen: the menu and up to 10 lines above it, without what follows its options
  printf '%s\n' "$2" | awk -v re="^[[:space:]]*$1 " '
    { l[NR]=$0; if ($0 ~ re) { m=NR; e=NR } else if (m && $0 ~ /^[[:space:]]*[0-9]+\. /) e=NR }
    END { if (m) for (i=(m>10?m-10:1); i<=e; i++) print l[i] }'
}
dialog_code() { # text on stdin; timers change, so digits don't count
  tr -d '0-9' | cksum | cut -d' ' -f1
}
