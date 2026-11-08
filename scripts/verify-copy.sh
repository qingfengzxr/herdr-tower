#!/usr/bin/env bash
# A disposable copy of a working directory for a verifier to write in.
#   verify-copy.sh create <src> <state_dir>       prints the path to work in
#   verify-copy.sh remove <path> <state_dir>      only under <state_dir>/copies/
set -u
here=${BASH_SOURCE[0]%/*}
. "$here/lib.sh"

abandon() { # a failed copy must not stay registered in the user's repository
  git -C "$top" worktree remove --force "$dest" >/dev/null 2>&1
  die "$1"
}

create() {
  local src=$1 state=$2 prefix
  [ -d "$src" ] || die "source not found: $src"
  mkdir -p "$state/copies" || die "cannot create $state/copies"
  dest=$(mktemp -d "$state/copies/copy.XXXXXX") || die "mktemp failed"
  if top=$(git -C "$src" rev-parse --show-toplevel 2>/dev/null) && git -C "$top" rev-parse -q --verify HEAD >/dev/null; then
    prefix=$(git -C "$src" rev-parse --show-prefix)
    rmdir "$dest"
    git -C "$top" worktree add -q --detach "$dest" HEAD >/dev/null || die "git worktree add failed"
    # Staged and unstaged tracked changes, then untracked files; ignored files stay out.
    if ! git -C "$top" diff --quiet --no-ext-diff HEAD; then
      git -C "$top" diff --binary --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ HEAD | git -C "$dest" apply --whitespace=nowarn || abandon "could not apply uncommitted changes"
    fi
    git -C "$top" ls-files -o --exclude-standard -z | tar -C "$top" --null -T - -cf - | tar -C "$dest" -xf - || abandon "could not copy untracked files"
    printf '%s\n' "${dest%/}/$prefix" | sed 's:/$::'
  else
    cp -a "$src/." "$dest/" || die "copy failed"
    printf '%s\n' "$dest"
  fi
}

remove() {
  local path=$1 state=$2 real root top
  real=$(cd "$path" 2>/dev/null && pwd -P) || die "not found: $path"
  root=$(cd "$state/copies" 2>/dev/null && pwd -P) || die "no copies under: $state"
  case "$real/" in "$root"/?*) ;; *) die "refusing to remove outside $root: $path" ;; esac
  if top=$(git -C "$real" rev-parse --show-toplevel 2>/dev/null) && [ -f "$top/.git" ]; then
    case "$top/" in "$root"/?*) ;; *) die "refusing to remove outside $root: $top" ;; esac
    git -C "$top" worktree remove --force "$top" || die "git worktree remove failed"
  else
    rm -rf "$real"
  fi
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  create) [ $# -eq 2 ] || die "usage: create <src> <state_dir>"; create "$1" "$2" ;;
  remove) [ $# -eq 2 ] || die "usage: remove <path> <state_dir>"; remove "$1" "$2" ;;
  *) die "usage: verify-copy.sh create|remove ..." ;;
esac
