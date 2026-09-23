# REFORK S4：我们的记牌器面板上画布

计划见 `docs/REFORK.md` S4；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（上游 `3.6.12` + 已提交的 S1–S3）。改动只落在这里。
- 主仓库（分支 `dev`）只读，是旧实现的来源；它的记牌器画在自己的 `NSPanel`（`Tracker.swift` / `TrackerRootHost`）里，3.6.12 已没有这套窗口。

## 目标

对局中，双方记牌器的**内容和外观与 dev 一致**：三行头、按牌库 / 手牌 / 已打出分区（数据来自 S3 的 `HSTracker/Fork/`）、V1 / V2 卡条、位图缓存、T8 进出场动效。同时**保住上游画布给面板的一切**：位置 / 大小设置、解锁后的拖拽与缩放、悬停卡图与协同高亮（`TrackerCardHoverHandler`）、`InteractiveRegion` / `HoverRegion` 上报、坟场详情、`TrackerDeckLensView`、对手栈上的 link-deck 提示。

## 已定的方案（09-23 用户定 A）

保留上游 `TrackerPanelView` / `TrackerPanelViewModel` 当外壳，只把卡牌列表部分换成我们的。框的位置和大小走上游设置；框内行高压缩沿用我们的算法。dev 有而上游没有的开关（如分区开关）照旧可关，关掉时退回上游原生列表。上游有、dev 没有的区块（坟场计数、sideboards、lens 等）保留；两边重复的信息只留一份，以 dev 外观为准。

## 来源

dev 的 `HSTracker/UIs/Trackers/SwiftUI/` 整目录与 `HSTrackerTests/TrackerMetricsTests.swift`；相关提交 `e0f7d42c` 起到 `2e9713b5`（`git log master..dev -- HSTracker/UIs/Trackers/SwiftUI`），含 `780f2e1d` 的面板底色修复、`143db6f3` 的 Perf P2 位图与 `Game.updateTrackers` 单次取数、`04dae47a`（T10）、`f8fa4c86`（T11 护栏中的面板部分）。`Game` 里 3 处 `tracker.update(cards:…)`（3.6.12 约 `:303/341/406`）是接入点。

## 约束

- `UIs/Trackers/SwiftUI/` 是 fork 自有目录，可按新外壳改写；上游文件（`RootOverlayView`、`TrackerPanelView(Model)`、`Game`、`Settings` 等）的改动越少越好，能在 fork 目录里用扩展或包装解决的不改上游。
- 上游 `Settings` 已有的键不重复造；fork 自有键（`group_cards_by_zone`、`tracker_motion`、`tracker_perf_*` 等）照 dev 默认值。默认值差异见 dev 的 `docs/PLAN.md`「与上游的默认值差异」。
- 线程与时序遵守 `AGENTS.md`「线程与时序」：写 view model 先回主线程，同一份状态同一个 main block 提交。
- 本任务允许改 `project.pbxproj`（文件登记）；允许在 `Translations/macOS/Localizable.xcstrings` **新增面板实际用到的 fork key**，英文与 zh-Hans 取自 dev 同名 key，不改已有 key。
- 设置页不在本任务（S6）；刷新合并与埋点不在本任务（S5）。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全绿，`TrackerMetricsTests` 在内，报告总条数。
- 报告：外壳里哪些是上游原样、哪些换成了我们的；上游文件改动清单与行数；dev 面板功能逐项的去向（搬了 / 由上游替代 / 未搬 + 原因）；需要 🎮 实机看的点。
- 🎮（由人做）：一局构筑，外观与 dev 一致、分区正确、不掉帧、解锁拖拽 / 缩放可用、悬停卡图与协同高亮。

## 执行结果

（执行者追加）
