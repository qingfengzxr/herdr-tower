#!/usr/bin/env bash
# Layout tests: plain shells in temporary workspaces; no model usage.
set -u
[ "${HERDR_ENV:-}" = 1 ] || { echo "not inside herdr"; exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/lib.sh"
LAYOUT=$ROOT/scripts/layout.sh
tmp=$(mktemp -d); export HERDR_TOWER_STATE=$tmp/state
pass=0 fail=0 spaces=()
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ $# -gt 1 ] && echo "      $2"; }
eq() { if [ "$2" = "$3" ]; then ok; else bad "$1" "got [$2] want [$3]"; fi; }
cleanup() { for w in "${spaces[@]:-}"; do [ -n "$w" ] && herdr workspace close "$w" >/dev/null 2>&1; done; rm -rf "$tmp"; }
trap cleanup EXIT

new_space() { # sets WS, TOWER
  local j; j=$(herdr workspace create --label "🧪 布局测试" --cwd /tmp --no-focus)
  WS=$(printf '%s' "$j" | field workspace_id); TOWER=$(printf '%s' "$j" | field pane_id); spaces+=("$WS")
}
place() { HERDR_PANE_ID=$TOWER bash "$LAYOUT" place --cwd /tmp; }
rects() { herdr pane layout --pane "$1" | grep -o '"pane_id":"[^"]*","rect":{"height":[0-9]*,"width":[0-9]*'; }
height() { herdr pane layout --pane "$1" | grep -o "\"pane_id\":\"$1\",\"rect\":{\"height\":[0-9]*" | grep -o '[0-9]*$'; }
width() { herdr pane layout --pane "$1" | grep -o "\"pane_id\":\"$1\",\"rect\":{\"height\":[0-9]*,\"width\":[0-9]*" | grep -o '[0-9]*$'; }
area() { herdr pane layout --pane "$1" | grep -o '"area":{"height":[0-9]*,"width":[0-9]*' | grep -o '[0-9]*$'; }
tab_of() { herdr pane get "$1" | field tab_id; }
tab_label() { herdr tab get "$1" | field label; }
count_in_tab() { rects "$1" | wc -l | tr -d ' '; }
focus_before=$(herdr workspace list | grep -o '"focused":true,"label":"[^"]*"')

# --- growth and overflow
new_space; tab1=$(tab_of "$TOWER")
p1=$(place); eq "place rc" "$?" 0
eq "first pane stays in tower tab" "$(tab_of "$p1")" "$tab1"
tw=$(width "$TOWER"); a=$(area "$TOWER"); eq "tower column is 40%" "$(( tw * 100 / a ))" 40
eq "new pane is labelled as owned" "$(herdr pane get "$p1" | field label)" "🚀 启动中"
p2=$(place); p3=$(place); p4=$(place)
eq "four in right column plus tower" "$(count_in_tab "$TOWER")" 5
hs=$(for p in "$p1" "$p2" "$p3" "$p4"; do height "$p"; done | sort -n)
lo=$(printf '%s\n' "$hs" | head -1); hi=$(printf '%s\n' "$hs" | tail -1)
[ $(( hi - lo )) -le 1 ] && ok || bad "four panes near equal height" "$hs"
p5=$(place); t2=$(tab_of "$p5")
[ "$t2" != "$tab1" ] && ok || bad "fifth pane must overflow"
eq "overflow tab name" "$(tab_label "$t2")" "🚀 调度 2"
p6=$(place); p7=$(place); p8=$(place)
eq "overflow tab holds four" "$(count_in_tab "$p5")" 4
p9=$(place); eq "ninth goes to third tab" "$(tab_label "$(tab_of "$p9")")" "🚀 调度 3"

# --- freed slot is reused, tower tab first
herdr pane close "$p2" >/dev/null; p10=$(place)
eq "freed slot reused in tower tab" "$(tab_of "$p10")" "$tab1"

# --- right column rebuilt after it empties
for p in "$p1" "$p3" "$p4" "$p10"; do herdr pane close "$p" >/dev/null; done
eq "tower alone" "$(count_in_tab "$TOWER")" 1
p11=$(place); eq "rebuild stays in tower tab" "$(tab_of "$p11")" "$tab1"
tw=$(width "$TOWER"); eq "rebuilt tower column is 40%" "$(( tw * 100 / a ))" 40

# --- emptied overflow tab goes away and its number is reused
for p in "$p9"; do herdr pane close "$p" >/dev/null; done
herdr tab get "$(tab_of "$p5")" >/dev/null 2>&1; eq "other overflow tab remains" "$?" 0

# --- foreign pane in tower tab is left alone
new_space; tab1=$(tab_of "$TOWER")
foreign=$(herdr pane split "$TOWER" --direction down --cwd /tmp --no-focus | field pane_id)
fh=$(height "$foreign")
q=$(place); [ "$(tab_of "$q")" != "$tab1" ] && ok || bad "must not split a tab holding a foreign pane"
eq "foreign pane height unchanged" "$(height "$foreign")" "$fh"
eq "foreign pane label unchanged" "$(herdr pane get "$foreign" | field label)" ""
eq "overflow named from 2" "$(tab_label "$(tab_of "$q")")" "🚀 调度 2"

# --- a foreign pane in an overflow-named tab is not split
new_space
j=$(herdr tab create --workspace "$WS" --label "🚀 调度 2" --cwd /tmp --no-focus); up=$(printf '%s' "$j" | field pane_id)
herdr pane split "$TOWER" --direction down --cwd /tmp --no-focus >/dev/null
q=$(place); [ "$(tab_of "$q")" != "$(tab_of "$up")" ] && ok || bad "must not split a user pane in a tab named like an overflow tab"
eq "next free name used" "$(tab_label "$(tab_of "$q")")" "🚀 调度 3"

# --- parallel placement
new_space; tab1=$(tab_of "$TOWER"); out=$tmp/par; mkdir -p "$out"
for i in 1 2 3 4 5 6; do ( place > "$out/$i" 2>&1 ) & done; wait
eq "parallel ids unique" "$(cat "$out"/* | sort -u | wc -l | tr -d ' ')" 6
eq "parallel never exceeds four" "$(count_in_tab "$TOWER")" 5
for f in "$out"/*; do case "$(cat "$f")" in *:p*) ok ;; *) bad "parallel place output" "$(cat "$f")" ;; esac; done

# --- guards and focus
HERDR_PANE_ID=no:such bash "$LAYOUT" place --cwd /tmp >/dev/null 2>&1; eq "bad tower pane rc" "$?" 2
eq "user focus unchanged" "$(herdr workspace list | grep -o '"focused":true,"label":"[^"]*"')" "$focus_before"

echo "layout: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
