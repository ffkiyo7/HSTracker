# REFORK S2：简体中文

计划见 `docs/REFORK.md` S2；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 译文落在 worktree `.claude/worktrees/refork`（分支 `dev0923`，上游 `3.6.12` + S1 未提交改动，S1 的改动别动）。
- 校验器 `docs/tasks/tools/check_xcstrings.py` 在主仓库（分支 `dev`），它的改动落在主仓库；除此之外主仓库只读。

## 目标

`dev0923` 的全部 `.xcstrings` 带上我们的 zh-Hans，与 dev 的中文覆盖相当。

## 要做的

- 用 `scripts/inject-zh-hans.py`（主仓库）以 `dev` 为我们这侧、`3.6.12` 为上游侧批量注入。两边都有 zh-Hans 而不同的 179 条：**以我们为准**（09-23 用户定，即脚本默认 `--on-conflict ours`）。其中英文原文已变的条目要对着上游英文判断，我们的译文与新原文不符就报告，不硬套（已知一条：`PlayerTrackersPreferences` `e7g-zd-YkC.title`）。
- 上游删掉的 3 个 catalog（`BattlegroundsSession` 43 / `BobsBuddyPanel` 16 / `LinkOpponentDeckPanel` 6 条 zh）：文案已随界面改 SwiftUI 迁进 `Translations/macOS/Localizable.xcstrings` 的新 key。按英文原文把我们的译文对到新 key 上；对不上的列进报告。已有上游 zh 的新 key 同样以我们为准。
- `check_xcstrings.py` 目前按 Xcode 的 `" : "` 分隔符重写 JSON，上游有的 catalog 用 `": "`。让它像注入脚本那样按文件探测分隔符风格，不再对风格不同的文件误报。
- 不搬：`String.swift` 的 DEBUG 缺 key 警告（09-23 定，上游已有 `LocalizationFormatTests` 兜底）。上游新增的 `ArenaPreferences` 没有我们的译文，不补。

## 约束

- 只增改 zh-Hans：不增删 key、不改其他语言、不改格式，与 `AGENTS.md`「本地化」一致。
- 不改 Swift / xib / pbxproj。

## 验收

- `python3 docs/tasks/tools/check_xcstrings.py --baseline 3.6.12`（在 worktree 跑；校验器取主仓库那份）通过。
- 受限环境 `test`：除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全过（`LocalizationFormatTests` 若因系统「桌面」权限弹窗读不到 catalog 而失败，报告里写明，不算本任务失败）。
- 报告：每个 catalog 注入 / 覆盖 / 跳过数；3 个迁走 catalog 的 65 条对到新 key 的条数与对不上的清单；英文原文已变的冲突清单；zh-Hans 覆盖率（有 zh 的 key / 总 key）对比 dev。

## 执行结果

09-23 Opus 子代理完成；第一批 review（Claude + Fable 独立核对）通过。
- 17 个 catalog 只增改 zh-Hans（key 集合、其他语言、序列化风格深比较无变化）；注入 230 / 覆盖 179（+ 迁移覆盖 17）/ 相同 440 / 跳过 170。
- 验收命令须带 `--allow-zh-edit`：195 条 E5 都是按「以我们为准」有意覆盖上游 zh。
- 迁走的 65 条：对上 33 条；28 条 xib 占位；4 条无对应 key（"Final"、"Latest 10 games…" ×2 上游改成 8、"Error"）。
- 英文原文已变：`e7g-zd-YkC.title` 上游为 "Show deck name"，保留「显示套牌名称」；"Wecome" 拼写修正，译文照用。
- 覆盖率 1035 / 1060（dev 967 / 981）；余项见 `docs/REFORK.md` S2 行。
