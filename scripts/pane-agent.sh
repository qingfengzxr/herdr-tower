#!/usr/bin/env bash
# Run one subagent in its own labelled Herdr pane; the pane lives exactly as long as the agent.
#   pane-agent.sh start --task TEXT --prompt-file F [--role R] [--cli C] [--model M] [--name N]
#                       [--cwd DIR] [--approval auto|manual] [--state-dir DIR] [--timeout SECONDS]
#   pane-agent.sh watch <run> | trust <run> | approve <run> <dialog> | deny <run> <dialog>
# Exit status: 0 done · 10 blocked · 11 needs_attention · 12 aborted · 13 timeout · 2 usage/setup
set -u
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
. "$here/lib.sh"

# Only Herdr's own "not found" means gone; a brief outage must not look like a closed pane.
exists() {
  local o; o=$(herdr pane get "$1" 2>&1) && return 0
  case "$o" in *pane_not_found*) return 1 ;; esac
  return 0
}
result_file() { printf '%s/out/result.md' "$run"; }
has_result() { local f; f=$(result_file); [ -f "$f" ] && [ -s "$f" ] && [ ! -L "$f" ]; }
agent_status() { herdr pane get "$1" 2>/dev/null | field agent_status; }
visible() { herdr pane read "$1" --source visible 2>/dev/null; }
unwrapped() { herdr pane read "$1" --source recent-unwrapped --lines 40 2>/dev/null; }

report() { # status, exit code
  echo "status=$1"
  echo "pane=$pane"
  echo "run=$run"
  echo "result=$(result_file)"
  [ -f "$run/exit" ] && echo "exit_code=$(cat "$run/exit")"
  [ "${trust_dialog:-}" = yes ] && echo "trust_dialog=yes"
  grep -q 'startup dialog answered' "$run/log" 2>/dev/null && echo "hooks_skipped=yes"
  if [ "$1" = blocked ] || [ "$1" = needs_attention ]; then
    date +%s > "$run/paused_at" # time waiting for a person is not the agent's time
    local screen code
    screen=$(visible "$pane")
    if [ "$1" = blocked ] && [ "${trust_dialog:-}" != yes ]; then
      code=$(cli_dialog_code "$screen")
      [ -z "$code" ] || echo "dialog=$code"
    fi
    echo '--- screen ---'
    printf '%s\n' "$screen" | grep -v '^[[:space:]]*$' | tail -25
    if has_result; then
      echo '--- result (not final: the agent has not finished) ---'
      cat "$(result_file)"
    fi
  elif has_result; then
    echo '--- result ---'
    cat "$(result_file)"
  elif [ -s "$run/last-output" ]; then
    echo '--- crash ---'
    grep -v 'exec bash ' "$run/last-output" | grep -v '^[[:space:]]*$' | tail -20
  fi
  exit "$2"
}

load_run() {
  run=$1
  [ -f "$run/pane" ] && [ -f "$run/cli" ] || die "not a run directory: $run"
  local cli; cli=$(cat "$run/cli")
  case "$cli" in claude|codex|grok) ;; *) die "bad CLI name in $run" ;; esac
  pane=$(cat "$run/pane")
  case "$pane" in ''|*[!A-Za-z0-9:_-]*) die "bad pane id in $run" ;; esac
  . "$here/cli/$cli.sh"
}

take_watch_lock() {
  if ! mkdir "$run/watch.lock" 2>/dev/null; then
    local pid; pid=$(cat "$run/watch.lock/pid" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && die "this run is already being watched"
    rm -rf "$run/watch.lock"
    mkdir "$run/watch.lock" || die "could not lock $run"
  fi
  echo $$ > "$run/watch.lock/pid"
  trap 'rm -rf "$run/watch.lock"' EXIT
}

watch_pane() {
  load_run "$1"
  local deadline started=$SECONDS seen_working=0 settled=0 key screen
  take_watch_lock
  deadline=$(cat "$run/deadline")
  if [ -f "$run/paused_at" ]; then
    deadline=$(( deadline + $(date +%s) - $(cat "$run/paused_at") ))
    echo "$deadline" > "$run/deadline"
    rm -f "$run/paused_at"
  fi
  sleep 2 # let a just-answered dialog clear before reading state

  while :; do
    if ! exists "$pane"; then
      # Gone with a result is only success if the agent itself exited cleanly.
      if has_result && [ "$(cat "$run/exit" 2>/dev/null)" = 0 ]; then report done 0; fi
      report aborted 12
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      herdr pane close "$pane" >/dev/null 2>&1
      report timeout 13
    fi

    screen=$(visible "$pane")
    # Startup dialogs only count before the agent works: after that it could print the same text.
    if [ ! -f "$run/started" ]; then
      if [ -n "$(cli_trust_keys "$screen")" ]; then trust_dialog=yes; report blocked 10; fi
      key=$(cli_startup_key "$screen")
      if [ -n "$key" ]; then
        # The same words in echoed text must not keep interrupting the agent.
        [ "$(grep -c 'startup dialog answered' "$run/log" 2>/dev/null)" -ge 3 ] 2>/dev/null && report needs_attention 11
        herdr pane send-keys "$pane" "$key" >/dev/null
        echo "startup dialog answered with: $key" >> "$run/log"
        settled=0; sleep 2; continue
      fi
    fi

    case "$(agent_status "$pane")" in
      blocked)
        : > "$run/started"
        key=$(cli_result_write_key "$(unwrapped "$pane")" "$run/out")
        if [ -n "$key" ]; then
          herdr pane send-keys "$pane" "$key" >/dev/null
          echo "result file write approved with: $key" >> "$run/log"
          settled=0; sleep 2; continue
        fi
        report blocked 10 ;;
      working) seen_working=1 settled=0; : > "$run/started" ;;
      idle|done)
        # Before the first turn starts an agent can look idle; don't count that as settled.
        if [ "$seen_working" = 1 ] || [ $(( SECONDS - started )) -ge 30 ]; then
          settled=$(( settled + 1 ))
        fi ;;
      *) settled=0 ;;
    esac

    if [ "$settled" -ge 5 ]; then
      # Idle with background work is not stopped; the deadline still bounds the wait.
      if cli_background_busy "$screen"; then settled=0; sleep 1; continue; fi
      has_result || report needs_attention 11
      herdr agent prompt "$pane" "$CLI_EXIT_TEXT" >/dev/null 2>&1
      for _ in 1 2 3 4 5 6 7 8 9 10; do exists "$pane" || break; sleep 1; done
      exists "$pane" && herdr pane close "$pane" >/dev/null 2>&1
      report done 0
    fi
    sleep 1
  done
}

answer() { # approve|deny, run, dialog code from the blocked report
  load_run "$2"
  exists "$pane" || die "pane is gone: $pane"
  [ "$(agent_status "$pane")" = blocked ] || die "pane is not waiting for an approval: $pane"
  local screen key
  screen=$(visible "$pane")
  # The tower decided about one specific dialog; never answer a different one.
  [ "$(cli_dialog_code "$screen")" = "$3" ] || die "the dialog has changed; run watch again and re-read it"
  key=$(cli_choice_key "$1" "$screen")
  [ -n "$key" ] || die "unrecognised approval dialog; ask the user to answer it in pane $pane"
  herdr pane send-keys "$pane" "$key" >/dev/null || die "could not send the key"
  echo "$1 sent: $key" | tee -a "$run/log"
}

trust() { # only after the user agreed to trust this folder
  load_run "$1"
  exists "$pane" || die "pane is gone: $pane"
  [ ! -f "$run/started" ] || die "the agent has already started; not a startup dialog"
  local keys k; keys=$(cli_trust_keys "$(visible "$pane")")
  [ -n "$keys" ] || die "no folder trust dialog on screen in pane $pane"
  for k in $keys; do
    if [ "$k" = enter ] && ! cli_trust_cursor_ok "$(visible "$pane")"; then die "cursor is not on the trust option"; fi
    herdr pane send-keys "$pane" "$k" >/dev/null || die "could not send the key"
    sleep 0.5
  done
  echo "folder trust answered: $keys" | tee -a "$run/log"
}

write_launch() {
  local q=() a
  for a in "${CLI_ARGV[@]}"; do q+=("$(printf '%q' "$a")"); done
  {
    echo '#!/usr/bin/env bash'
    printf 'export PATH=%q\n' "$PATH"
    # The agent has no business driving Herdr. Not a hard barrier: the default socket may still work.
    echo 'unset HERDR_SOCKET_PATH HERDR_BIN_PATH HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID'
    printf 'exec %s "$(cat %q)"\n' "${q[*]}" "$run/prompt"
  } > "$run/inner.sh"
  # The agent runs as a plain foreground child: Herdr cannot recognise it under `script`, and
  # redirecting stderr blanks some TUIs. So the last screen is read back once it has exited.
  {
    echo '#!/usr/bin/env bash'
    printf 'bash %q\n' "$run/inner.sh"
    echo 'rc=$?'
    printf 'echo "$rc" > %q\n' "$run/exit"
    printf '[ "$rc" -eq 0 ] || herdr pane read "$HERDR_PANE_ID" --source recent-unwrapped --lines 40 > %q 2>/dev/null\n' "$run/last-output"
    echo 'exit "$rc"'
  } > "$run/launch.sh"
}

start_pane() {
  local name='' task='' role='' cli='' model='' prompt_file='' cwd=$PWD approval=auto state='' timeout=1800 line
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "missing value for $1"
    case "$1" in
      --name) name=$2 ;; --task) task=$2 ;; --role) role=$2 ;; --cli) cli=$2 ;; --model) model=$2 ;;
      --prompt-file) prompt_file=$2 ;; --cwd) cwd=$2 ;; --approval) approval=$2 ;;
      --state-dir) state=$2 ;; --timeout) timeout=$2 ;;
      *) die "unknown option: $1" ;;
    esac
    shift 2
  done

  [ "${HERDR_ENV:-}" = 1 ] || die "not running inside a Herdr pane (HERDR_ENV != 1)"
  [ -n "$task" ] && [ -n "$prompt_file" ] || die "--task and --prompt-file are required"
  [ -f "$prompt_file" ] || die "prompt file not found: $prompt_file"
  [ -d "$cwd" ] || die "cwd not found: $cwd"
  case "$approval" in auto|manual) ;; *) die "--approval must be auto or manual" ;; esac
  case "$timeout" in ''|*[!0-9]*) die "--timeout must be whole seconds" ;; esac

  if [ -n "$role" ]; then
    if line=$(bash "$here/tower-config.sh" get "$role"); then
      [ -n "$cli" ] || cli=${line%%$'\t'*}
      [ -n "$model" ] || model=${line#*$'\t'}
    elif [ -z "$cli" ]; then
      die "role '$role' is not configured; run the setup in references/setup.md"
    fi
  fi
  [ -n "$cli" ] || die "give --role or --cli"
  [ -f "$here/cli/$cli.sh" ] || die "unsupported CLI: $cli"
  [ -n "$model" ] || model=-
  [ -n "$name" ] || name=${role:-$cli}
  . "$here/cli/$cli.sh"

  [ -n "$state" ] || state="$(tower_state_root)/adhoc"
  mkdir -p "$state/runs" || die "cannot create $state/runs"
  run=$(mktemp -d "$state/runs/${name//[\/[:space:]]/_}.XXXXXX") || die "mktemp failed"
  run=$(cd "$run" && pwd -P)
  mkdir "$run/out" || die "cannot create $run/out" # the only part of the run the agent may write

  printf '%s' "$cli" > "$run/cli"
  echo $(( $(date +%s) + timeout )) > "$run/deadline"
  {
    echo 'Task:'
    cat "$prompt_file"
    echo
    echo "If a sandbox or permission check blocks something the task needs, request approval and wait; never work around it."
    echo "When the whole task is finished, write your final report to $run/out/result.md as your very last action, then stop. Do not create that file earlier."
  } > "$run/prompt"
  cli_args "$model" "$approval" "$run/out" "$name"
  write_launch

  local shown=$model label
  [ "$shown" = - ] && shown=默认
  label="🐝 $name · 📝 $task · 🧠 $shown · 🧰 $cli"
  printf '%s' "$label" > "$run/label"

  pane=$(bash "$here/layout.sh" place --cwd "$cwd") || die "could not place a pane"
  printf '%s' "$pane" > "$run/pane"
  echo "run=$run"; echo "pane=$pane" # known from the start, for recovery after an interruption
  herdr pane rename "$pane" "$label" >/dev/null || die "could not label pane $pane"
  herdr pane run "$pane" "exec bash $(printf %q "$run/launch.sh")" >/dev/null || die "could not start the agent in $pane"
  watch_pane "$run"
}

command=${1:-}; [ $# -gt 0 ] && shift
case "$command" in
  start) start_pane "$@" ;;
  watch) [ $# -eq 1 ] || die "usage: watch <run>"; watch_pane "$1" ;;
  trust) [ $# -eq 1 ] || die "usage: trust <run>"; trust "$1" ;;
  approve|deny) [ $# -eq 2 ] || die "usage: $command <run> <dialog>"; answer "$command" "$1" "$2" ;;
  *) die "usage: pane-agent.sh start|watch|approve|deny|trust ..." ;;
esac
