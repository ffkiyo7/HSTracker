# REFORK 第二批 review 修复（S3–S5）

`dev0923` 的 `687aa134` / `8c2a4081` / `cc0fa753` 经我、Fable、Codex 三方 review 后要修的问题。通用约束见 `docs/tasks/_common.md`；在哪干同 `refork-s5-refresh-perf.md`。

每条只写现象和证据，怎么修由执行者定；修法若要动上游文件，改动越少越好，能放 `HSTracker/Fork/` 的放 Fork。

## 必修

1. **LRU 淘汰后卡图永久缺失。** `ImageUtils` 的缓存有了上限，但上游 `CardTileArtCache.tile(for:)`（`UIs/Overlay/Trackers/CardTileView.swift` ~:427）把请求过的 cardId 记进 `requested` 且从不移除：图被淘汰后再显示时既不命中缓存、也不再去读。要检查其他同类「请求过就不再取」的调用方。
2. **协同高亮按分区错用。** `TrackerViewModel.setHighlight`（`UIs/Trackers/SwiftUI/TrackerViewModel.swift` ~:106）把同一个 `deckHighlight` 发给 `cards / deck / hand / played` 四个列表，`TrackerCardListViewModel` 以各自列表的 `live` 作为高亮函数的第二参（上游语义是「牌库里剩的牌」，如 `TaelanFordringCore.swift:19` 用它挑最高费随从）。分区模式下手牌、已打出也被高亮，且牌库口径错。以上游平铺列表的行为为准。
3. **画布点击穿透被高频刷新反复重置。** 每次刷新 `WindowManager.show` → `OverWindowController.updateFrames()`（`UIs/Trackers/OverWindowController.swift:33`）写 `ignoresMouseEvents = Settings.windowsLocked`，覆盖 `RootOverlayWindow.updateMouseThrough()` 按鼠标位置设的值。S5 把刷新从最多 2 次/秒提到最多约 60 次/秒，光标停在可交互区（解锁的面板、按钮）上时点击可能漏进炉石，只靠 0.15s 兜底计时器纠正。`LinkOpponentDeckPanelView.swift:74` 的注释记载上游以前处理过同类问题。

## 顺手修

4. **战绩缓存不随统计删除失效，且头部两份缓存不同步。** `Fork/DeckRecordLabelCache` 只在写完统计时失效（`Game.swift` ~:2353），删除统计（`Statistics.swift:107` → `RealmHelper.removeAllGameStats`）不失效；分区头部的 `TrackerHeaderStats`（`UIs/Trackers/SwiftUI/TrackerPanelZone.swift:81-118`）又是另一份，只在 `gameEnded` 翻转和 `reset` 时重取，对局结束画面可能显示上一局的胜率。两份在同样的时机失效。
5. **调度器未设 `refresh` 时吞掉一次刷新。** `Fork/OverlayRefreshScheduler.run()` 先清 `needsUpdate` 再 `refresh?(reset)`。
6. **负缓存 key 不含语言。** `ImageUtils` 的 `missing`（~:165）按 cardId 记，而 `.cardArt` / `.cardArtBG` 的 URL 带客户端语言。
7. **测试专用计数器进了生产代码。** `Player.deckStateEvaluations`（`Logging/Player.swift` ~:627）只给 `CardZoneGroupsTests` 用。`Player.swift` 相对 `3.6.12` 仍须 ≤15 行。
8. **缺测试**：第 1 条（淘汰后能重新取到图）、第 2 条（分区模式下高亮只落在该落的列表、口径正确）、`OverlayRefreshScheduler` 的合并 / inFlight、`SynchronizedLRUCache` 的淘汰顺序。

## 不修（记录在案）

- 运行中关分区开关没有完整切换路径（`group_cards_by_zone` 不在刷新通知列表；分区模式下平铺 `cards` 为空）→ 归 S6 做设置页时一起接。
- 延迟探针多批共用 `pendingLineClock`、只测到入队不测到绘制；scheme 里探针常开 → 与 dev 相同，探针只看趋势。
- `PlayerCardZones.playerCardList(deckState:sideboards:)` 与上游 `Player.playerCardList` 重复 → 已注明同步，接受。
- AX 轮询 0.25s（上游约 2s、dev 0.1s）→ 折中，🎮 看 CPU。

## 验收

- 受限环境 `clean build` 过；`test` 除 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial` 外全绿，报告总条数与新增条数。
- 报告：逐条修法与依据；上游文件改动清单与行数（相对 `cc0fa753`）；第 3 条的修法对「锁定 / 解锁」两种状态各自的点击行为。

## 执行结果

09-24 Opus 子代理完成，`dev0923` `d589ff8a`；测试 265 条只挂 `OfficialBuildTests`（新增 8 条）。09-26 实测锁定 / 解锁点击正常、高亮只落牌库区。
1. `CardTileArtCache` 取到图后从 `requested` 移除（取失败的仍不重试）。
2. `TrackerViewModel.setHighlight` 只发给 `cards` + `deck`；分区模式下手里生成的牌不亮（与平铺开 `showPlayerGet` 时略异）。
3. `RootOverlayWindow` 覆写 `updateFrames()`，按光标与 `interactiveRegions` 重算点击穿透。
4. `DeckRecordLabelCache` 加失效计数 + `statisticsChanged()`，写 / 删统计都走它；`TrackerHeaderStats` 改看同一计数。
5. 调度器 `refresh` 未设时保留待办，`didSet` 补排。
6. 负缓存 key 带客户端语言。
7. 删 `Player.deckStateEvaluations`，3 条测试改为比对快照与旧入口（「一次刷新只算一次 deck state」不再有测试守护）。
- 未修（上游）：卡图磁盘缓存路径不分语言。
