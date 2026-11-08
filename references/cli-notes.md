# CLI 实测差异

2026-11-06 实测版本：claude 2.1.319、codex 0.167.0、grok 1.0.77。CLI 变化很快，行为不符时以实际屏幕为准，并告诉用户。

| 项目 | claude | codex | grok |
|---|---|---|---|
| 启动权限 | `--permission-mode auto`（人工模式为 `manual`） | `-a on-request -s workspace-write` | `--permission-mode default --minimal` |
| 批准 | `enter`（光标须在一次性 Yes 上） | `enter`（同左） | 读屏幕，按一次性 Yes 那一行的序号 |
| 拒绝 | `esc` | `esc` | 读屏幕，按 `No, reject` 那一行的序号 |
| 结果文件 | `--add-dir <run>/out` 加单文件放行 | `--add-dir <run>/out` | 脚本回答那一次写入审批 |
| 不会弹审批的操作 | auto 模式自动放行的操作 | 沙箱内的读写，包括 `rm` | `touch`、`mkdir` 等视为只读的命令 |
| 后台任务判断 | 读屏幕上的 `N shells still running` | 未验证 | 未验证 |

## 需要记住的坑

- **人工模式对 codex 不完全有效。** 沙箱内的操作不会逐条询问。需要逐项把关时，用 claude 或 grok，并告诉用户这个差异。
- **grok 的菜单编号随工具变化。** Bash 菜单的 3 是 No，Edit 菜单的 3 是 Yes；选项 1 总是“以后全部放行”；`esc` 不是拒绝，只切到回滚视图。所以不要手动按键。
- **grok 的结果文件写入。** 它的 `--allow` 路径规则实测不匹配。脚本只在对话框标题正好指向本次运行的 `result.md` 时自动批准一次，并记入 `<run>/log`。读屏只看菜单页脚正上方的对话框块。其他 Edit 审批仍会交给你。
- **codex 被沙箱挡住时。** 是否申请提权由模型决定，脚本已在任务说明里要求申请。如果它直接放弃，结果里会写明，这不等于任务完成。
- **目录信任框：** 三种 CLI 都有，且按目录记录；codex 明确提示决定会被保存。Claude 的默认光标在 “No, exit” 上。grok 在 Git worktree 里把信任记在主仓库路径上（已实测）。脚本一律停下报告 `trust_dialog=yes`，子代理开始工作后不再识别这类文字，防止被输出内容冒充。
- **`needs_attention` 常见原因：** 拒绝审批后子代理停下了；登录页显示为 `idle`。
- **崩溃证据。** 子代理非零退出时，脚本保存最后屏幕到 `<run>/last-output`，并在 `--- crash ---` 中显示。只有屏幕上留下的内容才能找回。
- **登录检查：** claude `auth status`、codex `login status`、grok `models`，已封装在 `tower-config.sh check`。

- **运行目录。** 子代理只应写 `<run>/out/`，控制文件在它外面；pane 的 Herdr 环境变量也已清除。但这不是硬隔离：`claude` 和 `grok` 可以经审批写别处，如果状态目录放在 `/tmp` 下，codex 沙箱也能写。默认状态目录不受这一点影响。

Linux 已实测。macOS 尚未实测，脚本已避开 bash 4 专有语法，但不能算验证过。
