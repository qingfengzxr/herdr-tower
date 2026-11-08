# SDD ledger — plan: docs/2026-11-06-tower-plan.md

Pre-flight: Task 4 consumes Task 1 cli_args, tower-config get and Task 3 place; all consistent.
Task 1: Ruling: cli_args drops the plan's prompt_file parameter; launch appends the prompt itself as the last argument — prompt text must be read at launch so quoting stays safe — cost if wrong: one signature change.
Setup: Ruling: no worktree or commits — the skill directory is not a Git repo and the user never asked for one — cost if wrong: no per-task rollback.
Task 1: complete (tests: tests/run-unit.sh; config check run against real CLIs)
Task 2: complete (tests: tests/run-unit.sh 57/57)
Task 3: complete (tests: tests/run-layout.sh 31/31)
Task 4: Ruling: approval keys come from reading the dialog, not fixed values — grok's menu numbering changes per tool, so a fixed "3" denies Bash but approves Edit — cost if wrong: an unrecognised dialog stops and asks the user.
Task 4: Ruling: no --add-dir for grok — with it the initial prompt stays unsubmitted in the composer — cost if wrong: result file needs its allow rule.
Task 4: Ruling: replaced script recording with a bash child wrapper plus pane read after exit — Herdr returns agent_not_found under script, which also breaks blocked detection — cost if wrong: crash text is limited to what stayed on screen.
Task 4: Ruling: grok result.md write is auto-approved only when the dialog names exactly this run's result file — its --allow path rules do not match — cost if wrong: one extra approval reaches the tower.
Task 4: Ruling: grok runs with --minimal — the fullscreen UI hides approval rows in short panes — cost if wrong: a slightly plainer grok display.
Task 4: complete (tests: run-unit 74/74, run-lifecycle 46/46, run-layout 31/31, run-e2e claude 18/18 codex 17/17 grok 18/18)
Task 5: complete (tests: run-unit 74/74, run-layout 31/31; doc paths checked)
Task 6: Ruling: folder trust is never auto-answered, including grok's previous automatic y; the script reports trust_dialog=yes and `trust <run>` answers after the user agrees — trust can let repo config run code and may persist — cost if wrong: one extra question per new project.
Task 6: Ruling: startup dialogs are only recognised before the agent first reaches working — agents can print identical text — cost if wrong: a dialog appearing after work starts falls through to blocked or needs_attention, which ask the user.
Task 6: Step 1-2 drill passed in a fresh session: four roles on codex, claude, grok; verifier in a copy; deletion of untracked data asked before any dispatch; tower edited no product file. Found and fixed: folder trust flow; stale progress file wording (fix not yet re-drilled).
Final: Ruling: I4 dialog code hashes only the dialog, digits removed, not the whole screen — timers change the screen constantly — cost if wrong: a stale code is refused and the tower re-reads, so it fails safe.
Final: Ruling: verification copies always ask about folder trust — a copy contains the developer's changes, which the user never reviewed — cost if wrong: one extra question per verification round. Supersedes the exemption in the Task 6 trust ruling.
Final: Ruling: screen reading is documented as protection against mistakes, not against an agent deliberately forging its screen; agent_status can also be forged by printed text — no parser can fully close this — cost if wrong: a malicious agent could get a tower-approved key; high-risk rules and CLI sandboxes remain.
Final: Ruling: run control files moved out of the agent-writable path into a parent of <run>/out; Herdr variables unset for agents — not a hard barrier against the default socket, whose reachability from codex's sandbox remains untested — cost if wrong: an agent could drive other panes.
Final: fixed C1 C2 I1-I13 — tests in run-unit, run-lifecycle, run-e2e RED→GREEN.
Final: minor (deferred): layout lock var set before acquire: timed-out wait can remove holder's lock
Final: minor (deferred): stale lock takeover race; waiters give up at 30s while staleness is 2m
Final: minor (deferred): unknown agent status waits silently to deadline
Final: minor (deferred): seen_working not restored on re-watch: 30s extra idle wait
Final: minor (deferred): verify copy from empty untracked subdir prints a missing path
Final: minor (deferred): verify copy lacks pipefail on sending tar
Final: minor (deferred): relative state dir in verify-copy lands in repo
Final: minor (deferred): exit 2 table row says no pane, but some failures leave one
Final: minor (deferred): tower label with escaped quotes truncated on restore
Final: minor (deferred): tower finish after pane change labels the old pane
Final: minor (deferred): very long prompts can hit the single-argument limit
Final: minor (deferred): relative --cwd not normalised
Final: minor (deferred): layout label unset path under set -u
Final: minor (deferred): plan doc still mentions script recording
Final: minor (deferred): BRE alternation in layout grep unverified on BSD grep
Task 6: second drill passed after the fixes: asked before deletion; approvals one-time; progress file now updated, though entries landed under the decisions heading.
Final: minor (deferred): tower may file progress entries under the wrong heading of the template.
Task 6: complete except Step 4, the user's visual check.

## 收尾

- 2026-11-06 Task 6 Step 4：用户肉眼确认布局和标签符合预期；演示 workspace 和文件已清理。
