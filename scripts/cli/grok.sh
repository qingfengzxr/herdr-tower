# Grok Build adapter. Verified on 1.0.77: start, result file, /exit, deny.
# Its menu numbering changes per tool: 3 means "No" for Bash but "Yes" for Edit, and option 1
# is always "always approve". So keys are read from the row's text, never fixed. Esc does not deny.
CLI_EXIT_TEXT=/exit
. "${BASH_SOURCE[0]%/*}/../lib.sh"

cli_args() { # model|- auto|manual run_dir name
  CLI_ARGV=(grok)
  [ "$1" = - ] || CLI_ARGV+=(-m "$1")
  # The user's config may say always-approve, so ask mode must be explicit.
  # No --add-dir: with it the initial prompt stays unsubmitted in the composer.
  # --minimal: in a short pane the fullscreen UI hides the approval rows entirely.
  CLI_ARGV+=(--permission-mode default --minimal)
}
cli_startup_key() { :; }
cli_trust_keys() {
  printf '%s\n' "$1" | grep -Eq '^[^[:alnum:]]*Do you trust the contents' || return 0
  [ -n "$(_grok_block "$1")" ] || printf y
}
cli_trust_cursor_ok() { :; }
cli_background_busy() { return 1; }

# Agents can print anything, so only the marked block at the very bottom counts.
# Fullscreen mode adds a footer below it; --minimal has none.
_grok_block() { # screen
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*┃/ { buf=buf $0 "\n"; next }
    /^[[:space:]]*$/ || /^[[:space:]]*[0-9]+\/[0-9]+:select/ { next }
    { buf="" }
    END { printf "%s", buf }'
}
_grok_row() { # extended regex for the row text, block; prints the digit if exactly one row matches
  local rows
  rows=$(printf '%s\n' "$2" | grep -E "^[[:space:]]*┃[[:space:]]+[0-9] \([^)]*\) $1" | sed -E 's/^[[:space:]]*┃[[:space:]]+([0-9]).*/\1/')
  [ "$(printf '%s' "$rows" | wc -w | tr -d ' ')" = 1 ] && printf '%s' "$rows"
}
cli_choice_key() { # approve|deny screen
  local block; block=$(_grok_block "$2")
  [ -n "$(_grok_row '.*always-approve' "$block")" ] || return 0
  case "$1" in
    approve) _grok_row 'Yes(, proceed)?[[:space:]]*$' "$block" ;;
    deny) _grok_row 'No, reject' "$block" ;;
  esac
}
cli_dialog_code() { local t; t=$(_grok_block "$1"); [ -z "$t" ] || printf '%s\n' "$t" | dialog_code; }
# --allow path rules do not match on 1.0.77, so the bookkeeping write is answered here, only
# when the active dialog is exactly the Edit menu for this run's result file.
cli_result_write_key() { # screen out_dir
  local block title
  block=$(_grok_block "$1")
  title=$(printf '%s\n' "$block" | grep -E '^[[:space:]]*┃[[:space:]]+›[[:space:]]+Allow ')
  [ "$(printf '%s\n' "$title" | grep -c .)" = 1 ] || return 0
  title=$(printf '%s\n' "$title" | sed -E 's/^[[:space:]]*┃[[:space:]]+›[[:space:]]+//' | trim)
  [ "$title" = "Allow Edit to $2/result.md?" ] || return 0
  [ -n "$(_grok_row 'Yes, allow all edits during this session' "$block")" ] || return 0
  cli_choice_key approve "$1"
}
