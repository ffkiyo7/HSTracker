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

## 执行结果（2026-09-13）

- `Player.swift`：新增 `struct CardZoneGroups`（`deck` / `hand` / `played` 三个 `[Card]` + 纯函数 `make`）、`Player.cardsInHandByCardId`、`Player.playerCardGroups`、`Player.opponentCardGroups`。已有函数一行没动，`playerCardList` / `opponentCardList` / `getDeckState()` 原样。
- `Settings.swift`：`groupCardsByZone`（key `group_cards_by_zone`，默认 **true**）。
- `Game.swift`：新增 `useZoneGroups`（`useSwiftUITracker && groupCardsByZone`），我方 / 对手两处喂数按它选择分组或平铺；`group_cards_by_zone` 进 `playerTrackerUpdateEvents` 和 `opponentTrackerUpdateEvents`。
- `Tracker.swift`：`update(...)` 加 `groups: CardZoneGroups? = nil`；`ensureSwiftUIRoot()` 一次性把三段的悬停身份绑成主牌表的身份（`.playerCardView` / `.opponentCardView`），仍是绑定时传参；`highlightPlayerDeckCards` 的四次 `setHighlight` 收成 `setSwiftUIHighlight`，覆盖主牌表和三段。
- `TrackerViewModel.swift` / `TrackerView.swift`：三个常驻的 `TrackerCardListViewModel`（`deck` / `hand` / `played`，不是每帧 new），`TrackerLayout` 加三个高度字段，段头复用 `TrackerSectionView`，标题走新 key。
- `TrackersPreferences.swift`：`tracker_group_cards_by_zone` 开关，紧挨 `tracker_remove_zero_count_cards`。
- `Localizable.xcstrings`：新增 4 个 key（`Zone_Deck` / `Zone_Hand` / `Zone_Played` / `tracker_group_cards_by_zone`），中英文齐。
- `HSTrackerTests/CardZoneGroupsTests.swift`：8 条新测试，已按 4 处登记进 `project.pbxproj`（本次 pbxproj 只有这一类改动）。

### 分组接口与三段的数据来源

```swift
struct CardZoneGroups {
    let deck: [Card], hand: [Card], played: [Card]
    static func make(remainingInDeck: [Card], predictedInDeck: [Card], removedFromDeck: [Card],
                     cardsInHand: [Card], originalDeck: [Card]) -> CardZoneGroups
}
var Player.playerCardGroups: CardZoneGroups?     // game.currentDeck == nil → nil（平铺）
var Player.opponentCardGroups: CardZoneGroups?   // Player.knownOpponentDeck == nil → nil（平铺）
```

| 段 | 数据来源（PLAN 2.1 表的对应行） |
|---|---|
| 牌库 | `getDeckState().remainingInDeck` + `getPredictedCardsInDeck(hidden: false)`，再滤掉 `count <= 0`（第 1 行） |
| 手牌 | `hand` 实体里非 created / stolen 的按 cardId 分组计数，并上 `createdCardsInHand`（受 `Settings.showPlayerGet` 控制）（第 2 行） |
| 已打出 | `getDeckState().removedFromDeck`，每行的张数按补集算：`总张数 − 牌库剩余 − 手上张数`，≤0 就不出行（第 3 行） |

`make` 是纯函数（不读任何 `Settings`），所以测试不需要造 `Game` / 实体。我方侧三段各自再过一遍 `annotateCards`（Zilliax 3000 + 起手胜率）和 `sortCardList(sorting)`，与平铺逐字同源；对手侧只 `sortCardList()`，同 `opponentCardList`。

**不变式 1 的实际形态，和任务书字面的差别（重要）**：任务书写「三段之和恒等于 `playerCardList`，按 cardId 汇总 count」。**这条字面上不可能成立**，原因在平铺表本身有损：

1. `getDeckState()` 把离开牌库的每一行强制写成 `count = 0`（`toRemovedCard`），打出 2 张和打出 1 张在平铺表里长得一样；
2. 一张牌「牌库剩 1、手上 1」时，平铺表只有那条 `count = 1` 的牌库行，手上那张根本没有计数（`removeCardsFromDeck` 为 true 时它变成 `count = 0` 的绿名行，仍然是 0）。

所以我实现并测的是**更强的那条**（也是 PLAN 原文「三段之和恒等于原始牌表」的意思）：**对每个 cardId，`牌库 + 手牌 + |已打出| == 该牌的已知总张数`**（牌表里的张数；牌表外的 created / stolen 按「至少这一张」算）。它直接保证了「没有牌消失或重复」这个目的，而且能写成算术断言。与平铺表的行对应关系：平铺表的每一行都在三段里出现且只出现一次（`count > 0` 的进牌库段；`count == 0` 的按是否在手上分进手牌段 / 已打出段），三段**多出来**的只有平铺表表达不了的那些副本（上面第 2 条）。

不变式 2（牌库段不出现 `count == 0`）由 `make` 里的 `.filter { $0.count > 0 }` 保证，有断言 helper 逐条覆盖。

### `highlightCardsInHand` 在分区模式下的语义

**分区模式下它完全失效**：`playerCardGroups` / `make` 一行都不读它，手牌段无条件按 `hand` 实体构建。理由：

- 它的作用（把手上的牌以 `count = 0` + 绿名塞回牌库段）与分区的目的直接冲突，正是反馈 ① 抱怨的现象；位置本身已经说明状态，不需要"塞回去再染个色"。
- 绿名样式没有删，只是换了地方：手牌段的行仍然带 `highlightInHand = true`（`CardRowView` 照旧画绿名），所以"这张在手上"的视觉线索还在，只是现在出现在手牌段而不是牌库段。牌库段里凡是仍有剩余副本的牌，`remainingInDeck` 那边本来就会带 `highlightInHand`，我没有去掉——那是**上游给「牌库里还有、手上也有一张」的行**打的标，含义仍然成立。

顺带两个同类决定：

- **`removeCardsFromDeck` 在分区模式下也不参与**。如果照它的字面（打出的牌不显示）就得把已打出段清空，不变式 1 立刻破。它原本是给单表去杂的，分区已经用段完成了这件事。
- **已打出段的卡条暂时形态**：`count` 写成**负数**（`-已打出张数`）。`CardRowView` 对 `count <= 0` 画 `dark.png`、计数框用 `abs(count)`，所以单张时与现状的暗条逐像素一致，打出 2 张时多一个 "2" 计数框，同时让不变式 1 成为可测的算术等式。状态图标（骷髅 / 火焰）是 2.7 的事，没做。

### 每段高度：开关关 vs 开关开

算法从代码推。共同前提同 T6：我方记牌器、`cardSize = .big`（`ratio = 1`、`smallFrameHeight = 40`、`kRowHeight = 34`）、`contentView` 高 700、hero 卡条隐藏、三行头只有第 1 行（40）、`showGraveyard = false`、无置顶 / 置底 / 相关牌。牌组按 30 张各 1 张算。

**配置 A：30 张全在牌库**

| 项 | 关（平铺） | 开（分区） |
|---|---|---|
| `offsetFrames` | 40 | 40 + 40（牌库段头）= 80 |
| `totalCards` | 30 | 30 |
| 行高 | `min(34, (700−40)/30)` = 22 | `min(34, (700−80)/30)` = 20.667 |
| 主牌表 / 牌库段 | 660 | 30×20.667 + 40 + 5 = 665 |
| 手牌 / 已打出段 | — | 0 / 0（空段零高） |
| 内容合计 | 700 | 705 |
| `bottomY` | 0 | −5 |

**配置 B：抽了 5 张、打出 3 张（三段都有）**

平铺侧按默认 `removeCardsFromDeck = false`：25 条牌库行 + 5 条 `count = 0` 行 = 30 行。

| 项 | 关（平铺） | 开（分区） |
|---|---|---|
| `offsetFrames` | 40 | 40 + 3×40 = 160 |
| `totalCards` | 30 | 25 + 2 + 3 = 30 |
| 行高 | 22 | `min(34, (700−160)/30)` = 18 |
| 牌库段 | —（主牌表 660） | 25×18 + 45 = 495 |
| 手牌段 | — | 2×18 + 45 = 81 |
| 已打出段 | — | 3×18 + 45 = 99 |
| 内容合计 | 700 | 715 |
| `bottomY` | 0 | −15 |

两处沿用 T6 的既有口径，不是本片新引入的：段间那个 `+5` 不进 `offsetFrames`（所以满压缩时 `bottomY` 为负，`−5 × 段数`），段头高度仍是 `smallFrameHeight`。压缩公式仍然只有 `TrackerViewModel.updateLayout` 一处，没有 `GeometryReader`，`Tracker.bottomY` 仍读 `layout.contentHeight`。

### 开关关掉后走到的路径

`Game.useZoneGroups` 为 false → `playerCardGroups` / `opponentCardGroups` **根本不求值**（`getDeckState()` 不会多跑一遍）→ `tracker.update(cards: playerCardList, …, groups: nil)` → `TrackerViewModel.update` 走 else 分支，喂 `cards`、把 `deck` / `hand` / `played` 清空 → `showDeck/showHand/showPlayed` 全 false → `offset` / `totalCards` / `listHeight` 与 T6 收口后逐字相同，`TrackerLayout` 新增的三个字段恒为 0，`contentHeight` 的加数不变 → `TrackerView` 只渲染 `TrackerCardListView(viewModel.cards)`，三个 `if` 都不成立。`Settings.useSwiftUITracker` 为 false 时同理（`useZoneGroups` 直接 false），旧路径一行没碰。

### 验收

- `xcodebuild … build`（受限环境）：`** BUILD SUCCEEDED **`
- `xcodebuild … test`（受限环境）：`** TEST SUCCEEDED **`，`Executed 82 tests, with 0 failures`（原 74 + 新增 8）
- `python3 docs/tasks/tools/check_xcstrings.py --baseline HEAD --allow-new-key Zone_Deck --allow-new-key Zone_Hand --allow-new-key Zone_Played --allow-new-key tracker_group_cards_by_zone`：`✓ 校验通过`（新增 key 必须用 `--allow-new-key` 放行，否则撞 E3）
- 🎮 实战（抽牌 / 打出 / 弃牌 / 对手已链接牌表）按任务书不排在本次验收里。

## review（Claude，2026-09-13）通过

逐行核对了 `Player.swift` 新增段、`Game.swift` 两处喂数、`Tracker.swift` / `TrackerViewModel` / `TrackerView` 的 diff 和 8 条新测试，另跑了一遍受限环境 `test`：82 / 82 全绿。

- 不变式 1 改成「每个 cardId：牌库 + 手牌 + |已打出| == 已知总张数」是对的：平铺表把离开牌库的行强制 `count = 0`，任务书字面那条本来就不可测；新形态更强且能断言。
- `playerCardList` / `opponentCardList` / `getDeckState()` 确认一行没动；`useZoneGroups` 为 false 时分组根本不求值，旧路径与 T6 收口后逐字一致。
- 三段常驻 view model、悬停身份绑定时传参、压缩公式仍在 `updateLayout` 一处、无 `GeometryReader`，T6 的约束全部保住。
- 已打出段用负 `count` 复用 `CardRowView` 的暗条 + `abs()` 计数，是临时形态，2.7 做图标时再定。
- pbxproj 只多了测试文件的 4 处登记。

顺带记两点，不返工：牌库段里「还有剩余、手上也有」的行仍带绿名，来自 `getDeckState()` 第 664 行 `hand.any`，**不受 `highlightCardsInHand` 控制**，实现报告的说法准确；分区打开后段头多占 3 × 45，30 张牌时行高从 22 压到 18，觉得挤属 2.8 范围。
