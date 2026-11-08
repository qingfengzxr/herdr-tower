# Claude Code adapter. Verified on 2.1.319: start, result file, /exit, approve, deny, background shell.
CLI_EXIT_TEXT=/exit
. "${BASH_SOURCE[0]%/*}/../lib.sh"

cli_args() { # model|- auto|manual run_dir name
  CLI_ARGV=(claude)
  [ "$1" = - ] || CLI_ARGV+=(--model "$1")
  # --allowedTools is variadic, so it must be followed by another option, never the prompt.
  CLI_ARGV+=(--permission-mode "$2" --add-dir "$3" --allowedTools "Edit(/$3/result.md)" -n "$4")
}
cli_startup_key() { :; }
cli_background_busy() { printf '%s' "$1" | grep -Eq '[0-9]+ shells? still running'; }
cli_choice_key() { # approve|deny screen
  local m; m=$(menu_tail ❯ "$2")
  [ "$(menu_line 1 "$m")" = "❯ 1. Yes" ] || return 0
  case "$(menu_line 2 "$m")" in "2. "*) ;; *) return 0 ;; esac
  case "$1" in approve) printf enter ;; deny) printf esc ;; esac
}
cli_dialog_code() { local t; t=$(menu_context ❯ "$1"); [ -z "$t" ] || printf '%s\n' "$t" | dialog_code; }
cli_result_write_key() { :; }
# The cursor starts on "No, exit".
cli_trust_keys() {
  case "$1" in *"Is this a project you created or one you trust"*) ;; *) return 0 ;; esac
  local m; m=$(menu_tail ❯ "$1")
  [ "$(menu_line 1 "$m")" = "❯ No, exit" ] && [ "$(menu_line 2 "$m")" = "Yes, I trust this folder" ] && printf 'down enter'
}
cli_trust_cursor_ok() { [ "$(menu_line 1 "$(menu_tail ❯ "$1")")" = "❯ Yes, I trust this folder" ]; }
