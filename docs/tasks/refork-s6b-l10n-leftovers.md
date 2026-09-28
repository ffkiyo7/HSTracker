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
5. `docs/tasks/tools/check_xcstrings.py` 的 E2：现在四种分隔符风格任一即过，改成按 baseline 该 key 的风格比，风格被换才报。加一条自测用例。

## 约束

- 只增改 zh-Hans；不增删 key、不改其它语言。
- 每个 catalog 的 zh-Hans 分隔符风格跟该文件已有译文走（校验器会查）。
- 验收命令：`python3 docs/tasks/tools/check_xcstrings.py --baseline HEAD --allow-zh-edit`，报告输出原文。

## 验收

- 上面五项各自的清单（key → 译文）；校验器输出；受限环境 `clean build` 过（`.xcstrings` 编进包）；`test` 里 `LocalizationFormatTests` 若因桌面权限失败单独说明。
- 🖥️（由人做）：设置 → 记牌器页、Overlay layout 页中文各看一遍。
