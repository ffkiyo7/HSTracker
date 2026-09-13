# Phase 2 / T1 — 记牌器分区：牌库 / 手牌 / 已打出

先读 `docs/tasks/_common.md`，再读 `docs/PLAN.md` Phase 2 一节（**2.1 / 2.2 / 2.3 是本片，2.6 / 2.7 / 2.8 不是**），
再读 `docs/PLAN.md` 「本轮（2026-08-30）」表里的反馈 ①。本片是 Phase 2 的第一片，也是反馈 ① 的真修。

## 现状

- SwiftUI 路径（`Settings.useSwiftUITracker`，本机开着）的根视图是 `TrackerView`（T6），从上到下：三行头 → 置顶 → 主牌表 → 置底 → 相关牌。
  段的显示 / 隐藏是条件视图；排版由 `TrackerViewModel.updateLayout` 算一次 `TrackerLayout`，`Tracker.bottomY` 读同一个数。
- 主牌表喂的是 `Player.playerCardList`（`Player.swift:396`），一张平铺：牌库里的、抽过的（暗条）、`highlightCardsInHand` 塞回来的（`count = 0` + 绿名）混在一起。
  反馈 ① 「抽到手上的牌还留在牌库段」就是最后这种。
- `Game.updatePlayerTracker()`（`Game.swift:378`）把 `playerCardList` + 置顶 / 置底（dredge）一起交给 `Tracker.update(cards:top:bottom:sideboards:relatedCards:reset:)`（`Tracker.swift:128`）。

## 要做出什么

新设置 `Settings.groupCardsByZone`，**默认开**。开着且走 SwiftUI 路径时，主牌表拆成三段：**牌库 / 手牌 / 已打出**。
关掉、或走旧路径时，**逐字回到现状**。

段的定义照 PLAN 2.1 那张表，不重述。两条不变式必须成立，并且要有单元测试：

1. **三段之和恒等于 `playerCardList`**：按 cardId 汇总 count，逐张相等。这是 PLAN 写明的关键不变式，靠它保证没有牌"消失"或"重复"。
2. **牌库段里不出现 `count == 0` 的行**。抽走的牌属于手牌段或已打出段，不再在牌库段留暗条。

## 硬约束

- `Player.playerCardList` **一行不动**（`AppDelegate.swift:679` 套牌导出还靠它；PLAN 写的 `Game.swift:2161` 战绩上传那处在上游合并后已不存在）。分组是**新增**接口，形态由你定。
- `highlightCardsInHand` 在分区模式下**不再把手牌塞回牌库段**。它的其它效果（绿名 / `highlightInHand` 样式）留不留、留在哪段，你定，**报告里给结论和理由**（PLAN 2.1 要求"实现时要给出结论"）。
- **对手侧只在 `Player.knownOpponentDeck != nil` 时分区**，否则平铺不变。理由见 PLAN 2.1 末段（未知牌表时分区会泄露"这张在手上"）。
- 段头复用 `TrackerSectionView`，视觉不改（那是 T4 按 `DeckLens` 逐像素复刻的）。三段的标题走 `Localizable.xcstrings`，中英文都要，且要过校验器（见 `AGENTS.md`「本地化」）。
- 空段折叠沿用 `TrackerSectionView` 现有行为（`rows.isEmpty` → 零高）。
- **T6 的排版不变式必须保住**：压缩公式 `cardHeight = min(base, (availableHeight − offset) / totalCards)` 仍在 `TrackerViewModel.updateLayout` 一处；段头高度、段间 `+5`、坟场行预留照旧。新段进 `TrackerLayout`，`Tracker.bottomY` 仍与渲染高度同源，**不得用 `GeometryReader`**（理由见 `docs/archive/tasks/phase1-t6-tracker-root-layout.md`「压缩公式住哪」）。
- **一次刷新不许重建视图树**（PLAN 1.3）。三段是三个 `TrackerCardListViewModel` 实例，不是每帧 new。
- 置顶 / 置底 / 相关牌三段的位置、内容、悬停身份不变。新段的悬停身份照 `Tracker.bindHover` 的方式**作为参数传入**，不许回到 superview 遍历。
- 新 key **必须**加进 `Game.swift:1654` 的 `playerTrackerUpdateEvents`（对手侧同理 `:1664`），否则改设置不实时重绘。设置页开关加在 `TrackersPreferences.swift` 的 SwiftUI 表单里，写法照 `tracker_remove_zero_count_cards` 那一行。
- 所有 view model 写入在主线程；`MainThreadGuard.assertMainThread()` 命中即 trap。
- **不做**：2.6 高亮强度、2.7 已打出段的状态图标与暗条废弃之外的形态、2.8 尺寸、任何动效（T8）、删旧路径（收尾）。已打出段的卡条**暂时**怎么显示（暗 / 不暗）你定，报告里说明；图标是 2.7 的事。
- 不动 `WindowManager` / `SizeHelper` / `.xib`，`.xcstrings` 只许加本片的新 key。

## 允许修改的文件

- `HSTracker/Logging/Player.swift`（只加，不改已有函数）
- `HSTracker/Core/Settings.swift`
- `HSTracker/Logging/Game.swift`（`updatePlayerTracker` / `updateOpponentTracker` 的喂数，和两个 `*TrackerUpdateEvents` 数组）
- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/UIs/Trackers/SwiftUI/` 下已有文件；如需新增文件，**手工登记进 `project.pbxproj`**（4 处，见 `AGENTS.md`「构建」），只允许这一类 pbxproj 改动
- `HSTracker/UIs/Preferences/TrackersPreferences.swift`
- `Translations/macOS/Localizable.xcstrings`（只加新 key，过 `docs/tasks/tools/check_xcstrings.py --baseline HEAD`）
- `HSTrackerTests/` 新增一个测试文件（同样登记 pbxproj）

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令见 `AGENTS.md`「构建」）。
2. 测试：原 74 条全绿 + 本片新增。新增至少覆盖：不变式 1 和 2；`highlightCardsInHand` 开 / 关两种情况下的分组；对手侧 `knownOpponentDeck` 为 nil 时不分区。
   测试怎么构造 `Player` 状态由你定，参考 `HSTrackerTests/` 里现有的做法。
3. `check_xcstrings.py` 通过。
4. 报告里给出：
   - 分组接口的签名，以及三段各自的数据来源（对应 PLAN 2.1 表的哪一行）；
   - `highlightCardsInHand` 在分区模式下的最终语义和理由；
   - 新旧路径每段高度的对照，至少两种配置：只有主牌表 30 张（全在牌库）；抽了 5 张、打出 3 张（三段都有）。算法从代码推；
   - 开关关掉后走到的代码路径，确认与 T6 收口后的现状一致。
5. 🎮 实战由用户看（PROGRESS 标的 ×4：抽牌 / 打出 / 弃牌 / 对手已链接牌表），不排在本次验收里。

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/archive/tasks/phase1-t6-tracker-root-layout.md`。
**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。
