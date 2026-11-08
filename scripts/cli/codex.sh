# Codex adapter. Verified on 0.167.0: start, result file, /exit, deny.
# Inside the workspace sandbox nothing prompts; manual approval cannot tighten that.
CLI_EXIT_TEXT=/exit
. "${BASH_SOURCE[0]%/*}/../lib.sh"

cli_args() { # model|- auto|manual run_dir name
  CLI_ARGV=(codex)
  [ "$1" = - ] || CLI_ARGV+=(-m "$1")
  CLI_ARGV+=(-a on-request -s workspace-write --add-dir "$3")
}
# Esc skips the hook-trust dialog: hooks stay off. Trusting them is the user's decision.
cli_startup_key() { printf '%s\n' "$1" | grep -Eq '^[^[:alnum:]]*Hooks need review[^[:alnum:]]*$' && printf esc; return 0; }
cli_background_busy() { return 1; }
cli_choice_key() { # approve|deny screen
  local m; m=$(menu_tail › "$2")
  case "$(menu_line 1 "$m")" in "› 1. Yes, proceed"|"› 1. Yes, proceed (y)") ;; *) return 0 ;; esac
  case "$(menu_line 2 "$m")" in "2. "*) ;; *) return 0 ;; esac
  case "$1" in approve) printf enter ;; deny) printf esc ;; esac
}
cli_dialog_code() { local t; t=$(menu_context › "$1"); [ -z "$t" ] || printf '%s\n' "$t" | dialog_code; }
cli_result_write_key() { :; }
cli_trust_keys() {
  case "$1" in *"Trust this folder?"*) ;; *) return 0 ;; esac
  local m; m=$(menu_tail › "$1")
  [ "$(menu_line 1 "$m")" = "› 1. Trust and continue" ] && printf enter
}
cli_trust_cursor_ok() { :; }
