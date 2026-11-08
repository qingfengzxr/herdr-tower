# 首次设置

配置全局生效，保存在 `~/.config/herdr-tower/roles.conf`。只在首次使用或用户要求更新时运行。下文 `S=~/.claude/skills/herdr-tower/scripts`。

1. **检测：** `bash $S/tower-config.sh detect` 列出已安装的 CLI。没装的不要替用户安装。
2. **预检：** 对每个已安装的 CLI 运行 `bash $S/tower-config.sh check <cli>`。失败时请用户自己登录，建议用户输入 `! <cli> login`。
3. **询问：** 按角色询问 CLI 和模型，并给出推荐。默认角色是开发、测试、验证、文档，用户可以增减。模型留空表示 CLI 的默认值，标签显示 `🧠 默认`。可用模型由各 CLI 提供，比如 `codex debug models`、`grok models`，不要凭记忆填写。
4. **实测：** 每种选中的 CLI 和模型组合跑一个小任务（比如回复一个单词），确认能真正走完。CLI 默认模型可能不适用于用户的账号，只做预检发现不了。
5. **保存：** `bash $S/tower-config.sh set <角色> <cli> <模型或->`。

查看配置用 `list`，删除角色用 `remove <角色>`。单次任务可以用 `--cli`、`--model` 临时覆盖，不会改动配置。

## 用户需要决定的事

- **codex hooks：** 启动时如果出现 “Hooks need review”，脚本会按 `esc` 跳过，钩子不运行。是否信任由用户决定，要告诉用户这件事。
- **目录信任：** 三种 CLI 第一次进入目录时都可能询问是否信任。脚本不会自己回答，处理方式见 `SKILL.md`。

## 尚未支持的 CLI

第一版只支持 claude、codex、grok。pi、hermes 等未经验证：标明“未验证”，不要配置。用户明确要求时，要先写适配文件并实测通过才能加入。
