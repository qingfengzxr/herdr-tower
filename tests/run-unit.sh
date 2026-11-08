#!/usr/bin/env bash
# Unit tests: no model usage and no Herdr panes.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS=$ROOT/scripts
pass=0 fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL: $1"; [ $# -gt 1 ] && echo "      $2"; }
eq() { if [ "$2" = "$3" ]; then ok; else bad "$1" "got [$2] want [$3]"; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export HERDR_TOWER_CONFIG=$tmp/roles.conf
cfg() { bash "$SCRIPTS/tower-config.sh" "$@"; }

# --- roles config
cfg get 开发 >/dev/null 2>&1; eq "get missing role rc" "$?" 1
cfg set 开发 claude opus; eq "set rc" "$?" 0
eq "get role" "$(cfg get 开发)" "$(printf 'claude\topus')"
cfg set 开发 codex -; eq "get overwrites" "$(cfg get 开发)" "$(printf 'codex\t-')"
cfg set 测试 grok grok-4.7; eq "list has two" "$(cfg list | wc -l | tr -d ' ')" 2
cfg set 测试 nosuchcli x >/dev/null 2>&1; eq "reject unknown cli" "$?" 2
cfg set 'a	b' claude x >/dev/null 2>&1; eq "reject tab in role" "$?" 2
cfg set 'a/b' claude x >/dev/null 2>&1; eq "reject slash in role" "$?" 2
cfg remove 测试; cfg get 测试 >/dev/null 2>&1; eq "remove" "$?" 1
det=$(PATH=/nonexistent /bin/bash "$SCRIPTS/tower-config.sh" detect 2>/dev/null)
eq "detect marks missing" "$(printf '%s\n' "$det" | grep -c 'missing$')" 3

# --- adapters
load() { ( . "$SCRIPTS/cli/$1.sh"; shift; "$@" ); }
argv() { # cli model approval
  ( . "$SCRIPTS/cli/$1.sh"; cli_args "$2" "$3" /r/d worker; printf '%s\n' "${CLI_ARGV[@]}" | tr '\n' ' ' )
}
eq "claude argv auto" "$(argv claude opus auto)" \
  "claude --model opus --permission-mode auto --add-dir /r/d --allowedTools Edit(//r/d/result.md) -n worker "
eq "claude argv manual default model" "$(argv claude - manual)" \
  "claude --permission-mode manual --add-dir /r/d --allowedTools Edit(//r/d/result.md) -n worker "
eq "codex argv" "$(argv codex gpt-x auto)" \
  "codex -m gpt-x -a on-request -s workspace-write --add-dir /r/d "
eq "codex argv default model" "$(argv codex - manual)" \
  "codex -a on-request -s workspace-write --add-dir /r/d "
case "$(argv grok grok-x auto)" in
  "grok -m grok-x --permission-mode default --minimal ") ok ;;
  *) bad "grok argv" "$(argv grok grok-x auto)" ;;
esac
for c in claude codex grok; do for a in auto manual; do
  case "$(argv "$c" m "$a")" in
    *bypass*|*always-approve*|*yolo*|*dangerous*|*"-a never"*|*danger-full*) bad "$c $a uses a forbidden flag" ;;
    *) ok ;;
  esac
done; done
# Real dialogs captured from each CLI.
CLAUDE_DIALOG=$' Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and always allow access to /tmp\n   3. Yes, and switch to auto mode\n   4. No\n Esc to cancel'
CODEX_DIALOG=$' Would you like to run the following command?\n › 1. Yes, proceed (y)\n   2. Yes, and don\'t ask again for commands that start with `cp` (p)\n   3. No, and tell Codex what to do differently (esc)'
FOOT=$'\n1/4:select  │  Tab:next option  │  Ctrl+o:always-approve  │  Ctrl+c:cancel'
GROK_BASH=$'┃  │ cp /etc/hostname /x\n┃  1 (○) Yes, and don\'t ask again for anything (always-approve mode)\n┃  2 (●) Yes, proceed\n┃  3 (○) No, reject (type to add feedback)\n┃  4 (○) Never allow: cp /etc/hostname'$FOOT
GROK_EDIT=$'┃  ›  Allow Edit to /r/d/result.md?\n┃  1 (○) Yes, and don\'t ask again for anything (always-approve mode)\n┃  2 (○) Yes, allow all edits during this session\n┃  3 (●) Yes\n┃  4 (○) No, reject (type to add feedback)'$FOOT
GROK_STICKY=$'┃  1 (●) Yes, and don\'t ask again for anything (always-approve mode)\n┃  2 (○) Yes, proceed\n┃  3 (○) No, reject (type to add feedback)'$FOOT
CLAUDE_TRUST=$' Quick safety check: Is this a project you created or one you trust?\n ❯ No, exit\n   Yes, I trust this folder'
CODEX_TRUST=$' Trust this folder? Codex can read, edit, and run files here\n› 1. Trust and continue\n  2. Back to Agent Command Center'
GROK_TRUST=$' Do you trust the contents of this directory?'
GROK_REAL=$'我按你的原样执行这条命令。\n◆ Copy hostname… 1.6s\n┃\n┃  ›  Copy hostname file to debug path\n┃  │ cp /etc/hostname /x\n┃  ← → narrow scope\n┃\n┃  1 (○) Yes, and don\'t ask again for anything (always-approve mode)\n┃  2 (●) Yes, proceed\n┃  3 (○) No, reject (type to add feedback)\n┃  4 (○) Never allow: cp /etc/hostname\n┃\n\n'
choice() { load "$1" cli_choice_key "$2" "$3"; }
eq "claude approve" "$(choice claude approve "$CLAUDE_DIALOG")" enter
eq "claude deny" "$(choice claude deny "$CLAUDE_DIALOG")" esc
eq "claude unknown screen" "$(choice claude approve 'something else')" ""
eq "claude cursor off Yes refuses" "$(choice claude approve $'   1. Yes\n ❯ 2. Yes, and always allow')" ""
eq "codex approve" "$(choice codex approve "$CODEX_DIALOG")" enter
eq "codex deny" "$(choice codex deny "$CODEX_DIALOG")" esc
eq "codex unknown screen" "$(choice codex deny 'something else')" ""
eq "grok bash approve picks proceed-once" "$(choice grok approve "$GROK_BASH")" 2
eq "grok real minimal screen approve" "$(choice grok approve "$GROK_REAL")" 2
eq "grok real minimal screen deny" "$(choice grok deny "$GROK_REAL")" 3
eq "grok real bash dialog is not a result write" "$(load grok cli_result_write_key "$GROK_REAL" /r/d)" ""
eq "grok output after a printed menu ends it" "$(choice grok approve "${GROK_REAL}more output")" ""
eq "grok bash deny" "$(choice grok deny "$GROK_BASH")" 3
eq "grok edit approve picks plain Yes" "$(choice grok approve "$GROK_EDIT")" 3
eq "grok edit deny" "$(choice grok deny "$GROK_EDIT")" 4
eq "grok numbers follow the text, not the cursor" "$(choice grok approve "$GROK_STICKY")" 2
eq "grok unknown screen" "$(choice grok approve 'something else')" ""
eq "claude trust keys" "$(load claude cli_trust_keys "$CLAUDE_TRUST")" "down enter"
eq "codex trust keys" "$(load codex cli_trust_keys "$CODEX_TRUST")" "enter"
eq "grok trust keys" "$(load grok cli_trust_keys "$GROK_TRUST")" "y"
eq "no trust dialog" "$(load claude cli_trust_keys 'hello')$(load codex cli_trust_keys 'hello')$(load grok cli_trust_keys 'hello')" ""
eq "grok never answers trust by itself" "$(load grok cli_startup_key "$GROK_TRUST")" ""
for c in claude codex grok; do eq "$c exit" "$( . "$SCRIPTS/cli/$c.sh"; printf %s "$CLI_EXIT_TEXT")" /exit; done
eq "grok result dialog answered" "$(load grok cli_result_write_key "$GROK_EDIT" /r/d)" 3
# An agent can print any text, so only the dialog's own title line counts.
SPOOF=$'┃  ›  Allow Edit to /r/d/result.md?\n┃  2 (○) Yes, allow all edits during this session\n┃  3 (●) Yes\nsome output\n'
eq "grok printed title before a bash dialog" "$(load grok cli_result_write_key "$SPOOF$GROK_BASH" /r/d)" ""
eq "grok printed marked title before another file" "$(load grok cli_result_write_key "$SPOOF${GROK_EDIT//result.md/other.md}" /r/d)" ""
eq "grok spoofed menu without a footer" "$(load grok cli_result_write_key "$SPOOF" /r/d)" ""
eq "grok approve ignores a printed one-time row" "$(choice grok approve $'┃  1 (x) Yes\nprinted\n┃  1 (●) Yes, and don\'t ask again (always-approve mode)'"$FOOT")" ""
eq "claude printed Yes above another menu" "$(choice claude approve $' ❯ 1. Yes\n   2. x\n text\n ❯ 1. Yes, and bypass permissions\n   2. No')" ""
eq "codex printed Yes above another menu" "$(choice codex approve $' › 1. Yes, proceed (y)\n   2. x\n text\n › 1. Do something else\n   2. No')" ""
eq "claude trust in prose above a real approval" "$(load claude cli_trust_keys "Is this a project you created or one you trust?"$'\n'"$CLAUDE_DIALOG")" ""
eq "claude trust cursor checked" "$(load claude cli_trust_cursor_ok "$CLAUDE_TRUST" && echo y)" ""
eq "claude trust cursor ok" "$(load claude cli_trust_cursor_ok $' ❯ Yes, I trust this folder\n   No, exit' && echo y)" y
eq "codex trust without the menu" "$(load codex cli_trust_keys 'Trust this folder? is what it said')" ""
eq "codex hooks phrase inside prose" "$(load codex cli_startup_key 'please look at why Hooks need review appears')" ""
d1=$(load grok cli_dialog_code "working… 2.8s"$'\n'"$GROK_BASH"); d2=$(load grok cli_dialog_code "working… 9.1s"$'\n'"$GROK_BASH")
eq "dialog code ignores timers" "$d1" "$d2"
case "$d1" in '') bad "dialog code present" ;; "$(load grok cli_dialog_code "${GROK_BASH//hostname/shadow}")") bad "dialog code tells commands apart" ;; *) ok ;; esac
eq "no dialog, no code" "$(load grok cli_dialog_code hello)$(load claude cli_dialog_code hello)$(load codex cli_dialog_code hello)" ""
[ -n "$(load claude cli_dialog_code "$CLAUDE_DIALOG")" ] && [ -n "$(load codex cli_dialog_code "$CODEX_DIALOG")" ] && ok || bad "claude and codex dialog code"
eq "grok printed title before another file's dialog" "$(load grok cli_result_write_key "Allow Edit to /r/d/result.md?"$'\n'"${GROK_EDIT//result.md/other.md}" /r/d)" ""
# trust fixtures must exist before the spoof block uses them
eq "grok title without the dialog marker" "$(load grok cli_result_write_key "${GROK_EDIT//┃  ›  /}" /r/d)" ""
eq "grok similar name not answered" "$(load grok cli_result_write_key "${GROK_EDIT//result.md/result.md.bak}" /r/d)" ""
eq "grok other file not answered" "$(load grok cli_result_write_key "${GROK_EDIT//result.md/other.md}" /r/d)" ""
eq "grok other dir not answered" "$(load grok cli_result_write_key "$GROK_EDIT" /elsewhere)" ""
eq "grok bash dialog not answered" "$(load grok cli_result_write_key "$GROK_BASH" /r/d)" ""
eq "claude never auto-answers" "$(load claude cli_result_write_key "$GROK_EDIT" /r/d)" ""
eq "codex never auto-answers" "$(load codex cli_result_write_key "$GROK_EDIT" /r/d)" ""
eq "codex hooks dialog" "$(load codex cli_startup_key 'Hooks need review')" esc
eq "grok other screen" "$(load grok cli_startup_key 'hello')" ""
eq "codex never answers trust" "$(load codex cli_startup_key 'Do you trust the contents')" ""
eq "claude no dialog" "$(load claude cli_startup_key 'Hooks need review')" ""
load claude cli_background_busy '· 1 shell still running'; eq "claude busy 1" "$?" 0
load claude cli_background_busy '3 shells still running'; eq "claude busy 3" "$?" 0
load claude cli_background_busy 'nothing here'; eq "claude not busy" "$?" 1
load codex cli_background_busy '1 shell still running'; eq "codex not detected" "$?" 1

# --- verification copies
vc() { bash "$SCRIPTS/verify-copy.sh" "$@"; }
export HERDR_TOWER_STATE=$tmp/state
repo=$tmp/repo; mkdir -p "$repo"; git -C "$repo" init -q
git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
printf 'old\n' > "$repo/mod.txt"; printf 'gone\n' > "$repo/del.txt"; printf 'staged\n' > "$repo/stg.txt"; printf '*.log\n' > "$repo/.gitignore"
git -C "$repo" add -A; git -C "$repo" commit -qm base
printf 'new\n' > "$repo/mod.txt"; rm "$repo/del.txt"; printf 'staged2\n' > "$repo/stg.txt"; git -C "$repo" add stg.txt
printf 'fresh\n' > "$repo/untracked.txt"; mkdir "$repo/sub"; printf 'deep\n' > "$repo/sub/u2.txt"; printf 'x\n' > "$repo/ignored.log"
before=$(git -C "$repo" status --porcelain)
copy=$(vc create "$repo" "$tmp/state/t1"); eq "copy create rc" "$?" 0
eq "copy keeps modification" "$(cat "$copy/mod.txt" 2>/dev/null)" new
eq "copy keeps staged change" "$(cat "$copy/stg.txt" 2>/dev/null)" staged2
[ -e "$copy/del.txt" ]; eq "copy keeps deletion" "$?" 1
eq "copy has untracked" "$(cat "$copy/untracked.txt" 2>/dev/null)" fresh
eq "copy has nested untracked" "$(cat "$copy/sub/u2.txt" 2>/dev/null)" deep
[ -e "$copy/ignored.log" ]; eq "copy skips ignored" "$?" 1
echo written-by-verifier > "$copy/mod.txt"; echo artefact > "$copy/build.out"
eq "source untouched by copy writes" "$(git -C "$repo" status --porcelain)" "$before"
eq "source content untouched" "$(cat "$repo/mod.txt")" new
vc remove /etc/passwd "$tmp/state/t1" >/dev/null 2>&1; eq "remove refuses outside path" "$?" 2
vc remove "$copy" "$tmp/state/t1"; eq "remove rc" "$?" 0
[ -e "$copy" ]; eq "copy deleted" "$?" 1
eq "no stale worktree" "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" 1
plain=$tmp/plain; mkdir -p "$plain/a"; echo p > "$plain/a/f.txt"
pc=$(vc create "$plain" "$tmp/state/t1"); eq "plain copy rc" "$?" 0
eq "plain copy content" "$(cat "$pc/a/f.txt" 2>/dev/null)" p
echo w > "$pc/a/f.txt"; eq "plain source untouched" "$(cat "$plain/a/f.txt")" p
vc remove "$pc" "$tmp/state/t1"; [ -e "$pc" ]; eq "plain copy deleted" "$?" 1
vc create "$tmp/nope" "$tmp/state/t1" >/dev/null 2>&1; eq "missing source rc" "$?" 2

# --- verify copy under Git settings that change diff output, and cleanup on failure
for cfgopt in diff.noprefix=true color.ui=always diff.external=/bin/false; do
  r=$(mktemp -d "$tmp/g.XXXX"); st=$(mktemp -d "$tmp/s.XXXX")
  git -C "$r" init -q; git -C "$r" config user.name t; git -C "$r" config user.email t@example.invalid
  echo one > "$r/a"; git -C "$r" add a; git -C "$r" commit -qm i; echo two > "$r/a"
  git -C "$r" config "${cfgopt%%=*}" "${cfgopt#*=}"
  c=$(bash "$SCRIPTS/verify-copy.sh" create "$r" "$st" 2>/dev/null); eq "copy under $cfgopt rc" "$?" 0
  eq "copy under $cfgopt content" "$(cat "$c/a" 2>/dev/null)" two
done
sh=$(mktemp -d "$tmp/shim.XXXX"); printf '#!/bin/sh\nexit 1\n' > "$sh/tar"; chmod +x "$sh/tar"
r=$(mktemp -d "$tmp/g.XXXX"); st=$(mktemp -d "$tmp/s.XXXX")
git -C "$r" init -q; git -C "$r" config user.name t; git -C "$r" config user.email t@example.invalid
echo one > "$r/a"; git -C "$r" add a; git -C "$r" commit -qm i
PATH=$sh:$PATH bash "$SCRIPTS/verify-copy.sh" create "$r" "$st" >/dev/null 2>&1; eq "failed copy rc" "$?" 2
eq "failed copy leaves no worktree" "$(git -C "$r" worktree list | wc -l | tr -d ' ')" 1

echo "unit: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
