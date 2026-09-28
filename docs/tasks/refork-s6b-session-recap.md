# REFORK S6b-2：局末小结窗搬到新线

计划见 `docs/REFORK.md` S6 / 「S6b 待办」；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`。改动只落在这里。
- 主仓库（分支 `dev`）只读：`git show dev:<path>`、`git show <commit>`、`git log dev -- <path>`。

## 目标

dev 的 Phase 7 局末小结（炉石退出时弹独立小窗，列本次会话的构筑对局）原样搬到新线，行为与 dev 一致。
来源提交 `0af024d7`（`git log dev -- HSTracker/UIs/SessionRecap` 看有没有后续修补，一并带上）。
设计与已决事项在 `git show dev:docs/archive/tasks/phase7-t1-session-recap-window.md`，先读。

搬的东西：`HSTracker/UIs/SessionRecap/` 三个文件；`Settings.showConstructedSessionRecap`（键 `show_constructed_session_recap`，默认 true，放 `Fork/Settings+Fork.swift` 或与 dev 同位置，二选一说明理由）；`RealmHelper.getStatistics(since:)`；`CoreManager` 的三处钩子（init 里炉石已在跑、`appLaunched`、`appTerminated`）；`project.pbxproj` 4 处登记。
`TrackerHeaderView.swift` 的 `HeaderStyle` S4 已随目录带来，确认是 internal 即可。

## 约束

- `.xcstrings` 例外：只允许往 `Translations/macOS/Localizable.xcstrings` 加 dev 里的 11 个 `session_recap_*` key（en + zh-Hans 原样拷），不动其它 key。改完跑 `python3 docs/tasks/tools/check_xcstrings.py --baseline HEAD`，报告输出。
- 3.6.12 的 `CoreManager.appTerminated` 与 dev 基座同形（`quitWhenHearthstoneCloses` 分支），照 dev 的做法改；若发现上游这段已变，以新线现状为准重新落地，不 apply 旧 diff。
- 小结窗是普通 `NSWindow`，不挂 overlay 画布，不受 `RootOverlayWindow` 的 `alwaysLocked` / 点击穿透影响。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（及若因桌面权限失败的 `LocalizationFormatTests`）外全绿，报告总条数。
- 报告：文件清单与行数；与 dev 的差异（若有）；`pbxproj` 登记的 `grep -c` 结果。
- 🎮（由人做）：打一局后退出炉石，弹小结窗，局数 / 胜负 / 套牌行正确，「打开统计」能开；0 局退出不弹。
