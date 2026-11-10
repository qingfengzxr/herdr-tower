#!/usr/bin/env bash
# Lifecycle tests with a fake agent in a temporary workspace; no model usage.
set -u
[ "${HERDR_ENV:-}" = 1 ] || { echo "not inside herdr"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
PA=$ROOT/scripts/pane-agent.sh
TW=$ROOT/scripts/tower.sh
tmp=$(mktemp -d)
export HERDR_TOWER_STATE=$tmp/state HERDR_TOWER_CONFIG=$tmp/roles.conf
export REAL_HERDR=${HERDR_BIN_PATH:-$(command -v herdr)} FAKE_HERDR_DOWN=$tmp/herdr-down
export PATH=$ROOT/tests/fake-bin:$PATH
# Never let these tests reach a real agent.
[ "$(command -v codex)" = "$ROOT/tests/fake-bin/codex" ] && [ "$(command -v claude)" = "$ROOT/tests/fake-bin/claude" ] || { echo "abort: claude does not resolve to the fake agent"; exit 1; }
pass=0 fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ $# -gt 1 ] && echo "      $2"; }
eq() { if [ "$2" = "$3" ]; then ok; else bad "$1" "got [$2] want [$3]"; fi; }
has() { case "$2" in *"$3"*) ok ;; *) bad "$1" "[$3] not in [$2]" ;; esac; }
get() { printf '%s\n' "$2" | grep -m1 "^$1=" | cut -d= -f2-; }

j=$(herdr workspace create --label "🧪 生命周期测试" --cwd /tmp --no-focus)
WS=$(printf '%s' "$j" | field workspace_id); TOWER=$(printf '%s' "$j" | field pane_id)
trap 'herdr workspace close "$WS" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
export HERDR_PANE_ID=$TOWER
prompt() { f=$(mktemp "$tmp/p.XXXXXX"); printf '%s\n' "$1" > "$f"; printf '%s' "$f"; }
gone() { herdr pane get "$1" >/dev/null 2>&1 && echo present || echo gone; }
start() { bash "$PA" start "$@"; }

# --- argument guards: a real prompt file, so each guard is what stops the run
p0=$(prompt ok)
start --task t --prompt-file "$p0" >/dev/null 2>&1; eq "no cli or role rc" "$?" 2
msg=$(start --role 开发 --task t --prompt-file "$p0" 2>&1); eq "unset role rc" "$?" 2
has "unset role points at setup" "$msg" "setup"
msg=$(start --cli nope --task t --prompt-file "$p0" 2>&1); eq "unknown cli rc" "$?" 2
has "unknown cli message" "$msg" "unsupported CLI"
msg=$(start --cli claude --task t --prompt-file "$p0" --approval bypassPermissions 2>&1); eq "bad approval rc" "$?" 2
has "bad approval message" "$msg" "auto or manual"
msg=$(start --cli claude --task t --prompt-file /no/such 2>&1); eq "missing prompt rc" "$?" 2
has "missing prompt message" "$msg" "not found"
msg=$(env -u HERDR_ENV bash "$PA" start --cli claude --task t --prompt-file "$p0" 2>&1); eq "outside herdr rc" "$?" 2
has "outside herdr message" "$msg" "inside a Herdr pane"

# --- normal completion, odd text, labels
bash "$ROOT/scripts/tower-config.sh" set 开发 claude fake-model
dir="$tmp/my project"; mkdir -p "$dir"
p=$(prompt 'do "quoted" $HOME `work` 中文')
start --role 开发 --task "审查 \"引号\" 'x' \$y" --prompt-file "$p" --cwd "$dir" --timeout 60 > "$tmp/o" & bg=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  l=$(herdr pane list --workspace "$WS" | grep -o '"label":"[^"]*开发[^"]*"' | head -1); [ -n "$l" ] && break; sleep 0.2
done
wait "$bg"; rc=$?; out=$(cat "$tmp/o")
eq "done rc" "$rc" 0; eq "done status" "$(get status "$out")" done
has "result printed" "$out" "fake report"
eq "pane gone" "$(gone "$(get pane "$out")")" gone
has "label format" "$(herdr tab list --workspace "$WS" >/dev/null; printf '%s' "$(cat "$(get run "$out")/label")")" "🚀 开发 · 📝 审查"
has "label model" "$(cat "$(get run "$out")/label")" "· 🧠 fake-model · 🧰 claude"
R=$(get run "$out")/out
has "prompt text survives quoting" "$(cat "$R/fake-args")" 'do "quoted" $HOME `work` 中文'
eq "cwd with a space" "$(cat "$R/fake-cwd")" "$dir"
has "model passed" "$(cat "$R/fake-args")" "--model fake-model"
has "default approval is auto" "$(cat "$R/fake-args")" "--permission-mode auto"
has "state under root" "$(get run "$out")" "$tmp/state/adhoc/runs/"

# --- overrides and default model label
out=$(start --role 开发 --model other --name 自定义 --task t --prompt-file "$(prompt ok)" --approval manual --timeout 60);
R=$(get run "$out")/out
has "model override" "$(cat "$R/fake-args")" "--model other"
has "approval override" "$(cat "$R/fake-args")" "--permission-mode manual"
has "name override" "$(cat "$(get run "$out")/label")" "🚀 自定义 ·"
out=$(start --cli claude --task t --prompt-file "$(prompt ok)" --state-dir "$tmp/state/job1" --timeout 60)
has "default model label" "$(cat "$(get run "$out")/label")" "🧠 默认 · 🧰 claude"
has "explicit state dir" "$(get run "$out")" "$tmp/state/job1/runs/"

# --- crash keeps evidence, pane still disappears
out=$(start --cli claude --task t --prompt-file "$(prompt CRASH)" --timeout 60); rc=$?
eq "crash rc" "$rc" 12; eq "crash status" "$(get status "$out")" aborted
eq "crash exit code" "$(get exit_code "$out")" 7
has "crash output kept" "$out" "boom: credentials broken"
eq "crash pane gone" "$(gone "$(get pane "$out")")" gone

# --- clean exit without a result is not success
out=$(start --cli claude --task t --prompt-file "$(prompt NORESULT)" --timeout 60); rc=$?
eq "no result rc" "$rc" 12; eq "no result exit code" "$(get exit_code "$out")" 0

# --- timeout closes the pane and leaves no process
out=$(start --cli claude --task t --prompt-file "$(prompt HANG)" --timeout 4); rc=$?
eq "timeout rc" "$rc" 13; eq "timeout pane gone" "$(gone "$(get pane "$out")")" gone

# --- pane closed from outside
start --cli claude --name closeme --task t --prompt-file "$(prompt HANG)" --timeout 60 > "$tmp/o" & bg=$!
sleep 4; run=$(ls -dt "$tmp"/state/adhoc/runs/closeme.* | head -1); herdr pane close "$(cat "$run/pane")" >/dev/null
wait "$bg"; eq "closed rc" "$?" 12

# --- approve and deny refuse without a blocked dialog
start --cli claude --name idle --task t --prompt-file "$(prompt HANG)" --timeout 15 > "$tmp/o" & bg=$!
sleep 4; run=$(ls -dt "$tmp"/state/adhoc/runs/idle.* | head -1)
bash "$PA" approve "$run" >/dev/null 2>&1; eq "approve when not blocked rc" "$?" 2
bash "$PA" deny "$run" >/dev/null 2>&1; eq "deny when not blocked rc" "$?" 2
herdr pane close "$(cat "$run/pane")" >/dev/null; wait "$bg"
bash "$PA" watch /no/such/run >/dev/null 2>&1; eq "watch bad run rc" "$?" 2

# --- folder trust stops and waits for an explicit answer
out=$(start --cli claude --name trust1 --task t --prompt-file "$(prompt TRUSTME)" --timeout 40); rc=$?
eq "trust dialog rc" "$rc" 10; eq "trust dialog flagged" "$(get trust_dialog "$out")" yes
run=$(get run "$out")
bash "$PA" approve "$run" >/dev/null 2>&1; eq "approve does not answer trust" "$?" 2
bash "$PA" approve "$run" x >/dev/null 2>&1; eq "approve with a code does not answer trust" "$?" 2
touch "$run/started"; bash "$PA" trust "$run" >/dev/null 2>&1; eq "no trust after work has started" "$?" 2; rm -f "$run/started"
bash "$PA" trust "$run" >/dev/null; eq "trust rc" "$?" 0
out=$(bash "$PA" watch "$run"); rc=$?
eq "after trust rc" "$rc" 0; has "after trust result" "$out" "fake report"
start --cli claude --name notrust --task t --prompt-file "$(prompt HANG)" --timeout 12 > "$tmp/o" & bg=$!
sleep 4; run=$(ls -dt "$tmp"/state/adhoc/runs/notrust.* | head -1)
bash "$PA" trust "$run" >/dev/null 2>&1; eq "trust without a dialog rc" "$?" 2
herdr pane close "$(cat "$run/pane")" >/dev/null; wait "$bg"

# --- trust dialogs need their real shape, not just the words
start --cli claude --name prose --task t --prompt-file "$(prompt PROSETRUST)" --timeout 6 > "$tmp/o"; rc=$?
eq "words in prose are not a trust dialog" "$rc" 13

# --- waiting for a person does not use up the agent's time
out=$(start --cli claude --name wait --task t --prompt-file "$(prompt TRUSTME)" --timeout 12); eq "waiting run blocks first" "$?" 10; run=$(get run "$out")
sleep 14; bash "$PA" trust "$run" >/dev/null; out=$(bash "$PA" watch "$run"); eq "deadline excludes human wait" "$?" 0

# --- run directory: only out/ is for the agent; control files are validated
out=$(start --cli claude --task t --prompt-file "$(prompt ok)" --timeout 60); run=$(get run "$out")
eq "result under out" "$(get result "$out")" "$run/out/result.md"
has "add-dir is only out" "$(cat "$run/out/fake-args")" "--add-dir $run/out "
eq "herdr control variables removed from the agent" "$(cat "$run/out/fake-env")" ""
printf '../../../evil' > "$run/cli"; bash "$PA" watch "$run" >/dev/null 2>&1; eq "bad cli name rc" "$?" 2
printf 'claude' > "$run/cli"; printf 'x;y z' > "$run/pane"; bash "$PA" watch "$run" >/dev/null 2>&1; eq "bad pane id rc" "$?" 2

# --- a symlink is not a result; a crash after writing one is not success
out=$(start --cli claude --task t --prompt-file "$(prompt SYMLINK)" --timeout 30); rc=$?
eq "symlink result rc" "$rc" 12
case "$out" in *"$(cat /etc/hostname)"*) bad "symlink target leaked" ;; *) ok ;; esac
out=$(start --cli claude --task t --prompt-file "$(prompt CRASHRESULT)" --timeout 30); rc=$?
eq "crash with a result rc" "$rc" 12; eq "crash with a result code" "$(get exit_code "$out")" 7

# --- run id is available while it runs; one watcher per run; a Herdr outage is not a closed pane
start --cli claude --name early --task t --prompt-file "$(prompt HANG)" --timeout 60 > "$tmp/o" & bg=$!
sleep 4; run=$(get run "$(cat "$tmp/o")"); case "$run" in */early.*) ok ;; *) bad "run printed at start" "[$run]" ;; esac
bash "$PA" watch "$run" >/dev/null 2>&1; eq "second watcher refused" "$?" 2
: > "$FAKE_HERDR_DOWN"; sleep 4; kill -0 "$bg" 2>/dev/null && ok || bad "outage treated as a closed pane"; rm -f "$FAKE_HERDR_DOWN"
herdr pane close "$(cat "$run/pane")" >/dev/null; wait "$bg"; eq "still reports the real close" "$?" 12

# --- a blocked report always shows the dialog, even if a result was written early
start --cli claude --name blk --task t --prompt-file "$(prompt EARLY)" --timeout 40 > "$tmp/o" & bg=$!
sleep 3; run=$(get run "$(cat "$tmp/o")"); p=$(cat "$run/pane")
herdr pane report-agent --source test --agent claude --state blocked "$p" >/dev/null 2>&1
wait "$bg"; rc=$?; out=$(cat "$tmp/o"); eq "early result blocked rc" "$rc" 10
has "screen shown when a result exists" "$out" "THE-SCREEN-TEXT"; has "early result marked" "$out" "not final"
herdr pane close "$p" >/dev/null 2>&1
bash "$PA" approve "$run" >/dev/null 2>&1; eq "approve needs the dialog code" "$?" 2

# --- codex hooks: skipped a bounded number of times, and reported
out=$(start --cli codex --name hk --task t --prompt-file "$(prompt HOOKS)" --timeout 40); rc=$?
eq "repeated hooks text stops" "$rc" 11; eq "hooks skip reported" "$(get hooks_skipped "$out")" yes
herdr pane close "$(get pane "$out")" >/dev/null 2>&1

# --- tower label on and off
herdr pane rename "$TOWER" "原标签" >/dev/null
sd=$(bash "$TW" init my-job); eq "init rc" "$?" 0
eq "init state dir" "$sd" "$tmp/state/my-job"
eq "tower label" "$(herdr pane get "$TOWER" | field label)" "🗼 塔台"
bash "$TW" finish "$sd"; eq "finish rc" "$?" 0
eq "label restored" "$(herdr pane get "$TOWER" | field label)" "原标签"
bash "$TW" init 'bad/slug' >/dev/null 2>&1; eq "bad slug rc" "$?" 2

echo "lifecycle: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
