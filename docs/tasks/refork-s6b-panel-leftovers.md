# REFORK S6b-1：分区面板的三处遗留

计划见 `docs/REFORK.md`「S6b 待办」与「不搬的东西」勘误；通用约束见 `docs/tasks/_common.md`，以下为本任务的差异。

## 在哪干

- 分支 `dev0923`，worktree `.claude/worktrees/refork`（HEAD `5ff7f87c`）。改动只落在这里。
- 主仓库（分支 `dev`）只读，是旧实现的来源：`git show dev:<path>`、`git show <commit>`。

## 现状

S4 把我们的分区列表接进上游 `TrackerPanelView`（接入点 `UIs/Trackers/SwiftUI/TrackerPanelZone.swift`，
上游外壳保留位置 / 拖拽 / 悬停 / 坟场详情）。09-26 实测发现三处与 dev 不一致，全部只在分区模式
（`Settings.groupCardsByZone` 为真）下改，分区关闭时上游行为一律不动。

| 项 | 要做成什么 | dev 来源 |
|---|---|---|
| 备牌 | 不画备牌段；悬停本体行时把备牌卡浮出到相关牌同一个浮窗；匹配用 `card.deckbuildingCard.id == sideboard.ownerCardId` 通用规则，不硬编码 ETC / 深邃之王（基里亚斯的外观组件副本要能匹配上）；同一张卡既有备牌又有相关牌时备牌优先；`Settings.hidePlayerSideboards` 为真整条短路 | `8dcf2f47`（改的是已删的 `Tracker.swift`，只看行为，不 apply） |
| 抽牌概率 / 坟场计数 | 两行都不画，设置值不改（用户 09-26 定）。坟场计数行同时是上游坟场详情的悬停区，隐藏后详情随之没有，这是预期 | dev 的 SwiftUI 路径无条件不画 |
| 对手英雄条 | 高度 = 行高，落在行网格上（现在是 `width * 34 / 217`） | `1745adfa` |

新线的悬停链路在 `UIs/Overlay/Trackers/TrackerCardHoverHandler.swift`（每侧一个 handler，相关牌走 `tooltipDisplay` → `setRelatedCardsTooltip`）。
上游 `TrackerPanelViewModel.sideboardBoxes` 硬编码两个 ID，只服务上游自己的备牌段，不用改它。

## 约束

- 先在 `UIs/Trackers/SwiftUI/` 里做；上游文件（`TrackerCardHoverHandler` / `TrackerPanelViewModel` / `TrackerPanelView`）改动越少越好，报告里列每个上游文件的改动行数。
- 线程规则见 `AGENTS.md`；备牌数据在哪一跳进 view model、悬停在哪一跳读，报告里写清。
- 分区测试：给备牌匹配（含基里亚斯副本、`hidePlayerSideboards`、备牌优先于相关牌）和分区模式下段规划（无抽牌概率 / 坟场行、英雄条高度 = 行高）各加测试，放在现有 `TrackerMetricsTests` 或同目录新文件；新 `.swift` 按 `AGENTS.md` 登记 4 处。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`（及若因桌面权限失败的 `LocalizationFormatTests`）外全绿，报告总条数；`RedDragonTests.testSearchReachesTableDamage` 负载下会超时，挂了单独说明。
- 报告：三项各自的落点与上游文件改动行数；分区关闭时哪些代码路径证明没变。
- 🎮（由人做）：一局带 ETC 或深邃之王的构筑：备牌段不出现，悬停本体浮出备牌；面板底部没有抽牌概率 / 坟场两行；对手英雄条与卡条同高。
