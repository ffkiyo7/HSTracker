# Perf P1：overlay 开着时炉石掉帧（面板刷新路径的四处无谓开销）

先读 `docs/tasks/_common.md`。本书是 Codex 2026-09-17 排查报告（`/private/tmp/hstracker-performance-findings.md`，
临时文件、可能已不在；要点已全部抄进下文）的落地。

## 症状（用户，2026-09-17）

overlay 开启时炉石整体帧数不稳、明显卡顿；退出 HSTracker 恢复；**只关掉玩家 / 对手两个面板也恢复**；
抽牌、出牌、悬停时最明显。环境：3840×2160 165Hz，炉石 3840×1874 / 165FPS，Debug 包，`HSTRACKER_LATENCY_PROBE=1`。
退出 HSTracker 后 GPU 仍到过 92%，所以 GPU 占用不能单独归罪面板。

Codex 报告没能用修前后帧时间对照锁定唯一根因；Claude 已逐条核对代码，下面四条**都是真的**，
按报告建议的顺序修，**每改一条就单独测一次**，别一口气全改再说「好了」。

## 已核实的四处（按修的顺序）

1. **窗口每次刷新都同步提交 WindowServer 事务。** `WindowManager.show(controller:show:frame:title:overlay:)`
   每次调用无条件 `setFrame(_:display:true)` 和 `orderFront`，没有「位置 / 可见性没变就跳过」的检查。
   `Game.updatePlayerTracker` / `updateOpponentTracker` 每次 GUI tick（16ms 去抖）都走到它。
   采样里主线程 254 个样本卡在 CA 事务提交 → `SLSConnectionSetLastSLSCATransaction` → unfair lock。
   这是首要嫌疑：它直接和游戏的合成路径抢 WindowServer。
2. **一次分区刷新算四遍 `getDeckState()`。** `Player.playerCardGroups` 三个分区各自 `annotateCards`，
   `annotateCards` 又读 `playerSideboardsDict`（`getDeckState()` 一次）；`Game.swift` 传 `sideboards:` 时再读一次。
   平铺模式是三遍。`getDeckState()` 遍历全部 revealed entities 做分组，不便宜。
3. **每次刷新都读一次 Realm 并开一个空写事务。** `Game.swift` 刷新里 `RealmHelper.getDeck(with:)` 只为算
   战绩标签；`getDeck` 无条件调 `validateCardCounts`，后者**没有 `count > 30` 的卡也照样 `realm.write {}`**。
   Realm 空事务仍要拿文件锁、提交。dense 和 lag-now 两份采样都抓到这条路径。
4. **同值 `playerType` 每次刷新触发 7 个 `@Published` 通知。** `Tracker.update` 每次给 `viewModel.playerType` 赋值，
   `TrackerViewModel.playerType.didSet` 无条件转发给 7 个列表的 `@Published var playerType`，
   SwiftUI 因此每次刷新都收到 7 次 `objectWillChange`，即使值根本没变。`rows` / `showRarityColors` 都做了同值跳过，就它没做。

## 方向

- 第 1 条：**只在帧 / 可见性 / 层级 / collectionBehavior / styleMask 真变了才提交**。但 `orderFront` 不能简单换成
  `!isVisible`：Space 切换、炉石前后台切换（`Events.space_changed` / `hearthstone_active` / `hearthstone_deactived`）
  后窗口要保持在游戏之上的正确层级。这些事件本来就走 `updateAllTrackers`，怎么区分「日常刷新」和「必须重新置前」你定，报告里给理由。
  `controller.updateFrames()` 是否也该受同样的门控，一并判断。
- 第 2 条：一次刷新只算一次 `getDeckState()`，算出来的东西在 `playerCardGroups` / `playerCardList` / `playerSideboardsDict`
  之间怎么传你定。**不许**改 `getDeckState()` 的语义、不许缓存跨刷新（T6 / T7 / T8 的账都靠它每次现算）。
- 第 3 条：读之前先判断有没有要修的卡，没有就不开写事务；战绩标签要不要按 `currentDeck.id` 缓存到 `reload_decks` / 局结束再失效，你定。
- 第 4 条：`Tracker` 和 `TrackerViewModel` 两层都加同值跳过。

## 硬约束

- **不要先删阴影、改画质、把锅推给 Debug。** 报告明说了，这次也不许。
- 视觉、内容、分区行为、悬停高亮、tooltip 一律不变。Phase 2 / V1 / V2 已落地的样式一像素不动。
- 每条改完跑一次同场景对照：`HSTRACKER_LATENCY_PROBE=1` 下「D tick → UI committed」和 `player tracker` 块的 p50 / p95，
  修前修后各记一次写进报告（改前基线：玩家面板 p50 9.9ms / p95 28.4ms / max 95.1ms；D p50 40.1ms / p95 172.4ms）。
  探针只量 HSTracker 自己的提交耗时，**不等于炉石帧耗时**，报告里别混着说。
- 现有 112 条测试全绿；分区 / 回放测试（`CardZoneGroupsTests` / `ZoneGroupsReplayTests` / `TrackerMetricsTests`）不许改期望。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/UIs/Trackers/WindowManager.swift`
- `HSTracker/Logging/Game.swift`（仅 `updatePlayerTracker` / `updateOpponentTracker` 及其直接辅助）
- `HSTracker/Logging/Player.swift`（仅 `playerCardList` / `playerCardGroups` / `annotateCards` / `playerSideboardsDict` 一族）
- `HSTracker/Database/RealmHelper.swift`（仅 `getDeck` / `validateCardCounts`）
- `HSTracker/UIs/Trackers/Tracker.swift`、`HSTracker/UIs/Trackers/SwiftUI/TrackerViewModel.swift`、
  `HSTracker/UIs/Trackers/SwiftUI/TrackerCardListViewModel.swift`
- 测试：可新增，`HSTrackerTests/` 下现有文件只加不改

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；112 条 + 新增全绿。
2. 报告里按 1→4 分别给：改了什么、为什么这样区分「要不要提交」、修前修后的探针数字、哪条没效果直说。
3. 报告末尾列出**你没动但怀疑的**下一批候选，Claude 已知的两条先写这里，实现者补充或反驳：
   - `Game.housekeepingTick` 每 250ms 做 `CGWindowListCopyWindowInfo` + 4 次跨进程 AX 调用打进炉石主线程
     （`SizeHelper.hearthstoneWindow.reload()`），165FPS 下一帧只有 6ms，AX 请求会让游戏主线程停下来应答。
     用户「只关面板也恢复」的证据不指向它，所以本书不修；但若 1→4 修完仍卡，它是第一候选。
   - 悬停 → `highlightPlayerDeckCards` → 4 个列表各自 `setHighlight` 重算 rows，再加 400ms 后 tooltip 窗口走一遍
     `WindowManager.show`。第 1 条修好后它自然受益，单独不动。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。
🎮 实测由用户做：报告里给启动命令 `open <DerivedData>/Build/Products/Debug/HSTracker.app`，并说明要用
`HSTRACKER_LATENCY_PROBE=1` 环境变量启动才有探针数字。
