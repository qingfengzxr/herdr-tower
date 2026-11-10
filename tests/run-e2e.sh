#!/usr/bin/env bash
# End-to-end tests against the real agent CLIs, with small models and tiny tasks.
#   run-e2e.sh [cli ...]     default: claude codex grok
# Consumes a small amount of usage. Approvals are only given to the exact test command.
set -u
[ "${HERDR_ENV:-}" = 1 ] || { echo "not inside herdr"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
PA=$ROOT/scripts/pane-agent.sh
tmp=$(mktemp -d); out_dir=$(mktemp -d /var/tmp/herdr-tower-e2e.XXXXXX)
export HERDR_TOWER_STATE=$tmp/state HERDR_TOWER_CONFIG=$tmp/roles.conf
pass=0 fail=0
ok() { pass=$((pass+1)); echo "  ok: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; [ $# -gt 1 ] && printf '%s\n' "$2" | cut -c1-150 | tail -25 | sed 's/^/        /'; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi; }
get() { printf '%s\n' "$2" | grep -m1 "^$1=" | cut -d= -f2-; }
gone() { herdr pane get "$1" >/dev/null 2>&1 && echo present || echo gone; }
prompt() { f=$(mktemp "$tmp/p.XXXXXX"); printf '%s\n' "$1" > "$f"; printf '%s' "$f"; }
model_of() { case "$1" in claude) echo haiku ;; codex) echo gpt-5.6-luna ;; grok) echo grok-4.7-build-fast ;; esac; }
leftover() { pgrep -f "$1" | wc -l | tr -d ' '; }

j=$(herdr workspace create --label "🧪 e2e" --cwd /tmp --no-focus)
WS=$(printf '%s' "$j" | field workspace_id); TOWER=$(printf '%s' "$j" | field pane_id)
trap 'herdr workspace close "$WS" >/dev/null 2>&1; rm -rf "$tmp" "$out_dir"' EXIT
export HERDR_PANE_ID=$TOWER

# Approval task: a real write outside every sandbox.
# Start or watch, answering folder trust for the test's own temp directories.
st() {
  local o r; o=$(bash "$PA" "$@"); r=$?
  while [ "$r" = 10 ] && [ "$(get trust_dialog "$o")" = yes ]; do
    bash "$PA" trust "$(get run "$o")" >/dev/null
    o=$(bash "$PA" watch "$(get run "$o")"); r=$?
  done
  printf '%s\n' "$o"; return "$r"
}
approval_task() { echo "Run this shell command with your shell tool, exactly as written between the quotes: \"cp /etc/hostname $1\". If the sandbox blocks it, request escalated permissions for it and wait for approval. Do nothing else."; }

trial() { # cli
  local c=$1 m work out rc run pane can n
  m=$(model_of "$c")
  echo; echo "################ $c ($m)"
  local base=(--cli "$c" --model "$m" --timeout 150)

  echo "== normal"
  work=$(mktemp -d "$tmp/w.XXXXXX")
  out=$(st start "${base[@]}" --name n-$c --task "正常完成" --prompt-file "$(prompt 'Your whole task is to write the report described below, containing the single word pong.')" --cwd "$work"); rc=$?
  eq "$c normal rc" "$rc" 0
  [ "$rc" = 0 ] || bad "$c normal output" "$out"
  [ -s "$(get result "$out")" ] && ok "$c result file" || bad "$c result file"
  eq "$c normal pane gone" "$(gone "$(get pane "$out")")" gone
  eq "$c label" "$(cat "$(get run "$out")/label")" "🚀 n-$c · 📝 正常完成 · 🧠 $m · 🧰 $c"

  echo "== approve"
  work=$(mktemp -d "$tmp/w.XXXXXX"); can=$out_dir/approved-$c
  out=$(st start "${base[@]}" --name a-$c --task "批准" --approval manual --prompt-file "$(prompt "$(approval_task "$can")")" --cwd "$work"); rc=$?
  eq "$c asks for approval" "$rc" 10
  run=$(get run "$out"); pane=$(get pane "$out"); n=0
  while [ "$rc" = 10 ] && [ "$n" -lt 4 ]; do
    n=$((n+1))
    case "$out" in
      *"cp /etc/hostname"*) ;;
      *) bad "$c dialog #$n is not the test command" "$out"; break ;;
    esac
    bash "$PA" approve "$run" wrongcode >/dev/null 2>&1; eq "$c wrong dialog code refused" "$?" 2
    bash "$PA" approve "$run" "$(get dialog "$out")" | sed 's/^/  /'
    out=$(st watch "$run"); rc=$?
  done
  eq "$c approve finishes" "$rc" 0
  [ "$rc" = 0 ] || bad "$c approve output" "$out"
  [ -e "$can" ] && ok "$c approved command ran" || bad "$c approved command ran"
  eq "$c approve pane gone" "$(gone "$pane")" gone
  case "$c" in grok) grep -q 'result file write approved' "$run/log" && ok "grok result write answered by exact path" || bad "grok result write log" "$(cat "$run/log" 2>/dev/null)" ;; esac

  echo "== deny"
  work=$(mktemp -d "$tmp/w.XXXXXX"); can=$out_dir/denied-$c
  out=$(st start "${base[@]}" --name d-$c --task "拒绝" --approval manual --prompt-file "$(prompt "$(approval_task "$can")")" --cwd "$work"); rc=$?
  eq "$c asks before deny" "$rc" 10
  run=$(get run "$out"); pane=$(get pane "$out")
  bash "$PA" deny "$run" "$(get dialog "$out")" | sed 's/^/  /'
  out=$(st watch "$run"); rc=$?
  echo "  after deny: status=$(get status "$out") rc=$rc"
  [ ! -e "$can" ] && ok "$c denied command did not run" || bad "$c denied command did not run"
  case "$rc" in
    11) ok "$c deny reports needs_attention"; eq "$c pane kept" "$(gone "$pane")" present ;;
    0) ok "$c agent reported the denial and finished" ;;
    *) bad "$c deny outcome" "$out" ;;
  esac
  herdr pane close "$pane" >/dev/null 2>&1

  echo "== closed from outside"
  work=$(mktemp -d "$tmp/w.XXXXXX")
  st start "${base[@]}" --name c-$c --task "外部关闭" --prompt-file "$(prompt 'Write a 500 word essay about terminals as your reply.')" --cwd "$work" > "$tmp/o-$c" & local bg=$!
  sleep 8; run=$(ls -dt "$tmp"/state/adhoc/runs/c-$c.* | head -1); herdr pane close "$(cat "$run/pane")" >/dev/null 2>&1
  wait "$bg"; rc=$?; sleep 1
  eq "$c closed rc" "$rc" 12
  eq "$c closed leaves no process" "$(leftover "$run")" 0

  echo "== timeout"
  work=$(mktemp -d "$tmp/w.XXXXXX")
  out=$(st start --cli "$c" --model "$m" --timeout 6 --name t-$c --task "超时" --prompt-file "$(prompt 'Write a 2000 word essay about terminals as your reply.')" --cwd "$work"); rc=$?; sleep 1
  eq "$c timeout rc" "$rc" 13
  eq "$c timeout pane gone" "$(gone "$(get pane "$out")")" gone
  eq "$c timeout leaves no process" "$(leftover "$(get run "$out")")" 0
}

background_shell() {
  echo; echo "################ claude background shell"
  local work out rc
  work=$(mktemp -d "$tmp/w.XXXXXX")
  out=$(st start --cli claude --model haiku --timeout 200 --name b-claude --task "后台命令" --prompt-file "$(prompt 'Use the Bash tool with run_in_background set to true to run: sleep 25 . Do not write the report until you receive its completion notification.')" --cwd "$work"); rc=$?
  eq "background shell rc" "$rc" 0
  [ "$rc" = 0 ] || bad "background output" "$out"
}

# The real state directory is outside codex's writable roots, so test with one that is too.
codex_scope() {
  echo; echo "################ codex cannot write the run directory"
  local sd out rc run n=0 work
  sd=$(mktemp -d /var/tmp/herdr-tower-scope.XXXXXX); work=$(mktemp -d "$tmp/w.XXXXXX")
  out=$(st start --cli codex --model gpt-5.6-luna --timeout 150 --state-dir "$sd" --name s-codex --task "范围" --cwd "$work" --prompt-file "$(prompt 'Your report path below ends in /out/result.md. With your shell tool, write the word x to a file named probe.txt in the parent directory of that out directory. If that fails, do not request approval and do not retry; say so in your report.')"); rc=$?
  run=$(get run "$out")
  while [ "$rc" = 10 ] && [ "$n" -lt 3 ]; do n=$((n+1)); bash "$PA" deny "$run" "$(get dialog "$out")" >/dev/null; out=$(st watch "$run"); rc=$?; done
  [ ! -e "$run/probe.txt" ] && ok "control directory stayed unwritable" || bad "codex wrote the control directory"
  echo "  rc=$rc"; herdr pane close "$(get pane "$out")" >/dev/null 2>&1
  case "$sd" in /var/tmp/herdr-tower-scope.*) rm -rf "$sd" ;; esac
}

[ $# -gt 0 ] || set -- claude codex grok
for c; do trial "$c"; done
case " $* " in *" claude "*) background_shell ;; esac
case " $* " in *" codex "*) codex_scope ;; esac

echo; echo "e2e: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
