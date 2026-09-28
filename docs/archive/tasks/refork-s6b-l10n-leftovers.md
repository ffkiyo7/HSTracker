# REFORK S6b-3：翻译余项

计划见 `docs/REFORK.md` S2 行余项与「S6b 待办」；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`。改动只落在这里。
- 主仓库（分支 `dev`）只读：`git show dev:<path>`。

## 目标

新线界面上还会显示英文的地方补齐 zh-Hans，并统一术语。**本任务是 `_common.md` 第 4 条的例外：允许改 `.xcstrings`，仍不许改 `.xib` / `.strings`。**

1. `Translations/macOS/Localizable.xcstrings` 无 zh-Hans 的 8 个 key：`ArenaPreDraft_Panel_Title`、`CardTile_Drawn_By`、`Enum_DeckPanel_Graveyard`、`No minions on board`、`Overlay_Layout`、`Overlay_Layout_Section_Order`、`Secret_Helper`、`aberration`。`Secret_Helper` 参考 dev 的 `tracker_secret_helper`（`git show dev:Translations/macOS/Localizable.xcstrings`）。
2. `HSTracker/UIs/Preferences/mul.lproj/TrackersPreferences.xcstrings` 无 zh-Hans 的 5 个 key（`aO1-IW-r7y.ibShadowedToolTip`、`bku-WW-nZc.title`、`gV2-en-Cel.title`、`OaC-wC-z3b.title`、`UXw-QE-lUP.title`）。留牌指南相关词汇与 `Localizable` 里已有的 `Mulligan*` 译法一致。
3. 术语统一：全仓 zh-Hans 里「套牌」9 处、「卡组」60 处（含上游原有译文与菜单），**统一成「卡组」**，只改那 9 处（`ArenaPreferences` 1、`PlayerTrackersPreferences` 1、`TheOutfinderPreferences` 1、`Localizable` 6）。
4. dev 有译文而新线缺的 key：只补新线代码里**实际引用**的（已知 `DeckManager.swift:826` 用 `Archive` / `Unarchive`；再 grep 一遍 `Free`、`Tier 7 Mode`）。dev 的 `tracker_*` / `trackers_*` 是已撤的旧设置页文案，不补；`session_recap_*` 由 S6b-2 带。
5. 校验器 `check_xcstrings.py` 的 E2：现在四种分隔符风格任一即过，改成按 baseline 该 key 的风格比，风格被换才报。加一条自测用例。

## 约束

- 只增改 zh-Hans；不增删 key、不改其它语言。
- 每个 catalog 的 zh-Hans 分隔符风格跟该文件已有译文走（校验器会查）。
- 校验器只在主仓库（分支 `dev`）里：`<主仓库>/docs/tasks/tools/check_xcstrings.py`，主仓库路径 = `git worktree list` 第一行。第 5 项就改那个文件（本任务唯一允许改主仓库的地方，同样不 commit）。
- 验收命令在 worktree 根目录跑：`python3 <主仓库>/docs/tasks/tools/check_xcstrings.py --baseline HEAD --allow-zh-edit`，报告输出原文。

## 验收

- 上面五项各自的清单（key → 译文）；校验器输出；受限环境 `clean build` 过（`.xcstrings` 编进包）；`test` 里 `LocalizationFormatTests` 若因桌面权限失败单独说明。
- 🖥️（由人做）：设置 → 记牌器页、Overlay layout 页中文各看一遍。

## 执行结果

09-28 Opus 子代理完成，`dev0923` `2618be4b`（与 S6b-2 同一提交）；校验器改动在主仓库 `dev`。脚本比对：5 个 catalog 0 删 key、其它语言 0 变动。待 🖥️。
1. Localizable 8 条：Arenasmith（品牌名照旧）/ 由 %@ 抽到 / 墓地 / 场上没有随从 / 悬浮窗布局 / 分区顺序： / 奥秘助手 / 畸变怪（取卡牌数据 zhCN）。
2. TrackersPreferences 5 条：留牌指南统一「起手留牌指南」（沿 `Mulligan*` 已有译法，不用旧设置页的「起手换牌指南」）。
3. 「套牌」→「卡组」9 处 + `session_recap_unknown_deck`。
4. 补 `Archive` / `Unarchive`（`DeckManager.swift:826` 在用）；`Free` / `Tier 7 Mode` 新线无引用，不补。
5. 校验器 E2 改按 baseline 该文件风格比，`--self-test` 5 条过；`--baseline HEAD --allow-zh-edit` + 13 个 `--allow-new-key` 通过，1066 / 1078。
- 剩 12 条无 zh：11 条符号 key + `BE`，不补。`gV2-en-Cel.title`「启用起手留牌指南G-V2」是上游占位文案照译。
- 09-28 🖥️ 通过（用户）：记牌器页 / Overlay layout 页中文。
