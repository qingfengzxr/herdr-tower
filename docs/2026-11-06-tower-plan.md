# herdr-tower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `herdr-pane-agent` 重构成 `herdr-tower`：主代理作为塔台，调度不同 CLI 和模型的子代理，herdr 展示现场；同时保留轻量的单子代理用法。

**Architecture:** `SKILL.md` 负责判断和流程；Bash 脚本负责机械部分：角色配置、CLI 适配、布局分配、子代理生命周期、验证副本。布局状态不另存，从 herdr 的 pane 标签推导（`🐝` 开头的 pane 属于塔台）。

**Tech Stack:** Bash、herdr 0.9.5 CLI、`script`（util-linux 或 BSD）、Git。不依赖 jq 和 python。

**Spec:** `docs/2026-11-06-tower-design.md`

## Global Constraints

- 技能目录最终为 `~/.claude/skills/herdr-tower/`。这个目录不是 Git 仓库，计划中没有提交步骤。
- 标签格式：`🐝 名字 · 📝 任务 · 🧠 模型 · 🧰 CLI`；未指定模型时写 `🧠 默认`。塔台标签：`🗼 塔台`。溢出 tab：`🐝 调度 N`。
- 配置：`~/.config/herdr-tower/roles.conf`。状态：`~/.local/state/herdr-tower/<任务>/`；轻量用法用 `adhoc`。
- 退出码：0 `done`、10 `blocked`、11 `needs_attention`、12 `aborted`、13 `timeout`、2 用法或环境错误。
- 第一版只支持 claude、codex、grok。
- 绝不使用 `bypassPermissions`、`--always-approve`、`--yolo`、`--dangerously-*`，也不选择“以后都放行”类选项。
- 不修改任何 agent CLI 的配置。
- 测试只操作自己创建的 workspace、tab 和 pane。

## Review Focus

1. **并行启动多个子代理：** 布局不能竞态，每个 pane 只分配一次。→ Task 3 测试。
2. **塔台所在 tab 已有其他 pane：** 不能拆分或关闭它们，子代理放进溢出 tab。→ Task 3 测试。
3. **任务名、提示词含空格、引号或中文：** 启动和标签都不能出错。→ Task 4 测试。
4. **CLI 崩溃或未登录：** pane 消失后仍能报告退出码和报错；不能静默。→ Task 4 测试。
5. **验证副本：** 未提交、未跟踪和已删除的文件都要反映到副本；验证者写入不影响原目录；非 Git 目录也能用。→ Task 5 测试。

---

## 文件结构

```
~/.claude/skills/herdr-tower/
  SKILL.md                     触发条件、两种用法、判断规则
  references/tower-workflow.md 塔台完整流程、进度文件模板、任务说明模板
  references/setup.md          设置向导步骤
  references/cli-notes.md      各 CLI 实测行为
  scripts/lib.sh               公共函数（JSON 字段、锁）
  scripts/tower-config.sh      角色配置和 CLI 检查
  scripts/cli/{claude,codex,grok}.sh  CLI 适配
  scripts/layout.sh            pane 分配
  scripts/pane-agent.sh        start/watch/approve/deny
  scripts/verify-copy.sh       验证副本
  scripts/tower.sh             init/finish
  tests/run-unit.sh            不消耗模型额度
  tests/run-layout.sh          临时 workspace，普通 shell
  tests/run-e2e.sh             真实 CLI，小任务
  docs/                        设计和计划
```

### Task 1: 配置和 CLI 适配

**Files:** Create `scripts/lib.sh`, `scripts/tower-config.sh`, `scripts/cli/{claude,codex,grok}.sh`, `tests/run-unit.sh`

**Interfaces:**
- Produces:
  - `tower-config.sh set <role> <cli> <model|->`、`get <role>`（输出 `cli<TAB>model`，未配置时退出码 1）、`list`、`remove <role>`、`detect`（每行 `cli<TAB>路径或 missing`）、`check <cli>`（登录检查，失败退出码 1）
  - 适配函数（source 后调用）：`cli_args <model|-> <auto|manual> <run_dir> <name> <prompt_file>` 把 argv 写入数组 `CLI_ARGV`；`cli_startup_key <screen_text>` 输出要发送的按键，无则为空；`cli_background_busy <screen_text>`，返回 0 表示还有后台工作；变量 `CLI_APPROVE_KEY`、`CLI_DENY_KEY`、`CLI_EXIT_TEXT`

- [ ] **Step 1: 写失败测试** `tests/run-unit.sh`：config set/get/覆盖/remove、拒绝非法 CLI 和角色名；三个适配生成的 argv 精确比对；模型为 `-` 时不含模型参数；三个适配都不含任何禁用参数；grok `CLI_DENY_KEY=3`、`CLI_APPROVE_KEY=2`；`cli_startup_key` 对 “Hooks need review” 返回 `esc`，对 “Do you trust the contents” 返回 `y`；claude 适配对 `1 shell still running` 判定忙。
- [ ] **Step 2:** 运行，确认失败。
- [ ] **Step 3: 实现。** 权限映射：claude `auto|manual`；codex 两种都是 `-a on-request -s workspace-write --add-dir <run>`；grok 两种都是 `--permission-mode default --add-dir <run>`。argv 中放行结果文件：claude `--allowedTools Edit(/<run>/result.md)`；grok 的放行规则由 Task 4 实测确定。`check`：claude `claude auth status`；codex `codex login status`；grok `grok models`。
- [ ] **Step 4:** 运行，确认全部通过。

### Task 2: 验证副本

**Files:** Create `scripts/verify-copy.sh`; Modify `tests/run-unit.sh`

**Interfaces:** Produces `verify-copy.sh create <src> <state_dir>`（输出副本路径）、`remove <copy_path>`（只接受 `<state_dir>/copies/` 下的路径）

- [ ] **Step 1: 写失败测试：** Git 目录中有已修改、已暂存、未跟踪、已删除的文件，副本内容一致；`.gitignore` 忽略的文件不复制；在副本里写文件后，原目录 `git status --porcelain` 不变；remove 后 `git worktree list` 无残留；非 Git 目录走目录副本；remove 拒绝范围外路径。
- [ ] **Step 2:** 运行，确认失败。
- [ ] **Step 3: 实现。** Git：`git worktree add --detach`，再 `git diff HEAD --binary` 应用到副本，并复制 `git ls-files -o --exclude-standard` 列出的文件。非 Git：`cp -a`。
- [ ] **Step 4:** 运行，确认全部通过。

### Task 3: 布局分配

**Files:** Create `scripts/layout.sh`, `tests/run-layout.sh`

**Interfaces:** Produces `layout.sh place --cwd DIR`：以 `$HERDR_PANE_ID` 为塔台，输出新 pane ID。

**规则：** 取得 `mkdir` 锁（等待上限 30 秒）。塔台所在 tab 中，非塔台 pane 全部以 `🐝` 开头时才可用：没有子代理则以 0.4 向右拆分；不足 4 个则从最高的 `🐝` pane 以 0.5 向下拆分。否则按序检查 `🐝 调度 N` tab，不足 4 个 pane 就拆分最高的；都满则新建下一个编号的 tab，并使用它的根 pane。新 pane 必须在释放锁之前写上临时标签 `🐝 启动中`，这样下一个分配能算到它。全程 `--no-focus`。

- [ ] **Step 1: 写失败测试** `tests/run-layout.sh`，在临时 workspace 中运行，用临时根 pane 作为 `HERDR_PANE_ID`：1～4 个 pane 的位置（左列宽约 40%，第 4 个时高度差不超过 1）；第 5 个进入 `🐝 调度 2`；第 9 个进入 `🐝 调度 3`；关闭中间 pane 后再放置，回到第 1 个 tab；全部关闭后重建右列；已有非 `🐝` pane 时不动它，直接进溢出 tab；并行 6 个 place，ID 全部唯一，第 1 个 tab 不超过 4 个子代理；用户焦点不变。
- [ ] **Step 2:** 运行，确认失败。
- [ ] **Step 3: 实现。**
- [ ] **Step 4:** 运行，确认全部通过，临时 workspace 已清理。

### Task 4: 子代理生命周期

**Files:** Create `scripts/pane-agent.sh`, `scripts/tower.sh`, `tests/run-e2e.sh`; Modify `scripts/cli/grok.sh`, `tests/run-unit.sh`

**Interfaces:**
- Consumes: Task 1 适配函数、`tower-config.sh get`、`layout.sh place`
- Produces:
  - `pane-agent.sh start --task TEXT --prompt-file F [--role R] [--cli C] [--model M] [--name N] [--cwd D] [--approval auto|manual] [--state-dir D] [--timeout S]`
  - `pane-agent.sh watch <run>`、`approve <run>`、`deny <run>`
  - `tower.sh init <slug>`（给塔台 pane 加标签，输出状态目录）、`finish`（清除塔台标签）
  - 输出字段：`status=`、`pane=`、`run=`、`result=`、`exit_code=`，以及 `--- result ---` 或 `--- screen ---` 或 `--- crash ---`

**运行方式：** pane 执行 `exec bash <run>/launch.sh`。launch.sh 用 `script` 运行 CLI（Linux：`script -qefc`；macOS：`script -q <file> cmd`；没有 `script` 时直接运行），把退出码写入 `<run>/exit`。成功时删除录制文件；失败时保留，去掉 ANSI 控制符后，`aborted` 报告显示最后 20 行。

**watch 改动：** 每轮用 `cli_startup_key` 处理启动确认框并写日志；用 `cli_background_busy` 判断后台工作；`approve`/`deny` 只发送该 CLI 的 `CLI_APPROVE_KEY`/`CLI_DENY_KEY`，发送前要确认状态确实是 `blocked`，否则退出码 2。

- [ ] **Step 1: 实测 grok 放行结果文件：** 用 `--permission-mode default --add-dir <run>` 分别试 `--allow 'Edit(/<run>/result.md)'` 和 `--allow 'Write(<run>/*)'`，选能免审批写入且不放行其他写操作的规则；都不行时，在 `cli-notes.md` 记录，让塔台批准这一次写入。
- [ ] **Step 2: 写失败测试：** 单元部分：缺角色配置时退出码 2 且提示设置；非法 `--approval` 被拒绝；标签含 `🧠 默认`；`--cli` 和 `--model` 可以覆盖角色；任务名含引号和中文不破坏启动脚本（用假 CLI）；假 CLI 以退出码 7 崩溃时报告 `aborted`、`exit_code=7` 和报错文字。
- [ ] **Step 3: 写 e2e：** claude、codex、grok 各跑：正常完成；批准（`grok` 确认按 `2` 后命令执行，且没有进入 always-approve）；拒绝；外部关闭；超时。claude 再测后台 shell。标签包含 `🧰 <cli>`。模型用小模型：`haiku`、`gpt-5.6-luna`、`grok-4.7-build-fast`。
- [ ] **Step 4:** 运行，确认失败。
- [ ] **Step 5: 实现，** 以现有 `scripts/pane-agent.sh` 为基础。
- [ ] **Step 6:** 单元和 e2e 全部通过。有 CLI 行为和设计不符时，写进 `cli-notes.md` 并在交付时说明。

### Task 5: 技能文档和改名

**Files:** Create `~/.claude/skills/herdr-tower/SKILL.md`, `references/*`; Remove `~/.claude/skills/herdr-pane-agent/`（内容移入新目录）

- [ ] **Step 1:** 把目录改名为 `herdr-tower`，修正脚本和测试中的路径，重跑单元和布局测试。
- [ ] **Step 2: 写 `SKILL.md`：** description 只写触发条件：用户明确要求塔台、调度子代理，或要求在 herdr pane 里跑子代理；不因任务大而触发。正文：确认 `HERDR_ENV=1`、两种用法的入口、塔台不做什么、审批规则、退出码表、按键禁令、指向 references。控制在 500 词左右。
- [ ] **Step 3: 写 `references/tower-workflow.md`：** 第 4 节九步流程、验收标准规则、任务说明模板（目标、范围、项目规则摘录、危险操作须停下报告、被沙箱挡住时申请提权、结果写法）、修复循环（新子代理、3 轮上限）、并行写入规则、验证副本用法、进度文件模板、中断恢复步骤。
- [ ] **Step 4: 写 `references/setup.md` 和 `cli-notes.md`：** 向导步骤（detect → check → 询问 → 小任务实测 → set）、hooks 信任由用户决定、未验证 CLI 的提示。
- [ ] **Step 5:** 确认旧技能目录已不存在，文档里的命令路径都能运行。

### Task 6: 端到端验收

- [ ] **Step 1: 真实塔台演练。** 用一个新会话，在临时 Git 项目里明确要求塔台完成一个小功能，至少包含开发、测试、验证、文档四个角色，且使用不止一种 CLI。验证者在独立副本里运行。确认：塔台没有亲自改项目文件；用户确认过验收标准；进度文件完整；交付时逐项给出证据。
- [ ] **Step 2: 高危路径。** 任务中包含一个删除操作，确认塔台先问用户，而不是自行批准。
- [ ] **Step 3: 全新子代理审查** 整个技能。修复确认的问题，并重跑相关测试。
- [ ] **Step 4: 用户肉眼确认** 布局和标签。
