# Phase 1 / T4 — 其余三段卡表接进 SwiftUI

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
本任务对应 `docs/PLAN.md` Phase 1 切片表的 **T4**，动手前把 Phase 1 那一节读完。

T1 的 `CardRowView` 和 T2 的 `TrackerCardListView` / `TrackerCardListViewModel` /
`TrackerCardListHost`（都在 `HSTracker/UIs/Trackers/SwiftUI/`）是本任务的输入。
T2 已经把**主牌表**接上了 SwiftUI，本片把剩下三段带段头的卡表也接上。

## 背景

记牌器里有两种列表形态：主牌表是光秃秃一列卡条；另一种是**带段头的段** ——
上面一条底色 `#23272A` 的横条（左侧 17×17 图标 + 白字标题），下面才是卡条。后者就是 `DeckLens.swift`。

`Tracker.swift:24-27` 挂着三个 `DeckLens` outlet：

| outlet | 段 | 显示条件 |
|---|---|---|
| `playerTop` | 置顶 | `Settings.showPlayerCardsTop` |
| `playerBottom` | 置底 | `Settings.showPlayerCardsBottom` |
| `opponentRelatedCards` | 相关牌 | `Settings.showOpponentRelatedCards` |

## 要做出什么

一个 SwiftUI 的**分段视图**，在 `Settings.useSwiftUITracker` 为 true 时取代这三个 `DeckLens` 的渲染；
为 false 时逐字回到现状。三个 outlet 共用同一个组件的三个实例。

`docs/PLAN.md` 的目录表里这个文件叫 `TrackerSectionView.swift`，沿用这个名字。

## 关键约束

- **不许改任何 `.xib`。** 三个 outlet 的类型写死是 `DeckLens`，挂载方式自己解决 ——
  T2 已经为主牌表趟过一遍（`TrackerCardListHost` 作为 `cardsView` 的兄弟视图加到 `contentView`，
  两者按开关互相让位）。**沿用同一套模式，不要另发明一种。**
- **卡条渲染必须复用 T1 的 `CardRowView`，列表必须复用 T2 的视图模型逻辑。**
  段与段之间、以及与主牌表之间，同一张卡的外观必须完全一致。
  如果 `TrackerCardListViewModel` 需要重构才能被多实例复用，**可以改它**，
  但改完主牌表的行为不许有任何变化，并在报告里说明你动了什么、为什么。
- **段头的视觉必须与 `DeckLens` 不可区分**：底色 `#23272A`、边框色 `#141617`、
  左侧 17×17 的 `icon_magnifying_glass`、白字标题、段头高度是传进来的 `smallFrameHeight`，
  文字基线的算法见 `DeckLens.updateFrames(frameHeight:)`（`DeckLens.swift:58-67`）。
  这是 Phase 1 验收标准第 1 条「视觉不可区分」的范围。
- **空段必须折叠。** `DeckLens` 现在的行为是 `count == 0` 时 `frame = NSRect.zero`
  （`DeckLens.swift:64`），且 `Tracker.updateFrames()` 里还额外判了 `count > 0 && Settings.xxx`
  才给高度（`Tracker.swift:354` / `:391`）。两处语义都要保住。
- **`count` 语义。** `Tracker.updateFrames()` 用 `playerTop.count` 等参与 `totalCards`
  和每一段的高度计算（`:322-330`、`:354-365`、`:391-402`）。新路径要提供同样意义的值，
  且在同一次 `updateFrames()` 里与实际画出来的行数一致。**差一行下面所有段全串位。**
- **行高由 `Tracker.updateFrames()` 传进来**，新视图不许自己决定行高，
  也不许让 SwiftUI 的自适应布局改动它。
- **一次刷新不许重建视图树。** 每次 `update` 新建 `NSHostingView`、或整棵 rootView 全量重算，
  是 `docs/PLAN.md` 1.3 点名要消灭的东西换了层皮。**在报告里论证你没踩。**
- **悬停的分段身份直接传参，不许走 superview 遍历。** `getHoverComponent()`（`Tracker.swift:543`）
  对应的三个枚举值是 `.playerTop` / `.playerBottom` / `.opponentRelatedCards`，
  `tooltipDisplay()`（`:680`）按它决定弹玩家侧还是对手侧的相关牌 —— 这个分支语义必须保住。
  **`getHoverComponent()` 本身不许删**，旧 AppKit 路径还在用它。
- **协同高亮只在主牌表有**（`shouldHighlightCard` 是 `AnimatedCardList` 上的属性，
  `DeckLens` 没有接过）。**这三段不要加高亮**，保持与现状一致。
- **新视图必须透明。** 记牌器的整体不透明度是涂在 window 背景上的（`Tracker.swift:113`），
  自带背景色会把它盖掉。段头那条 `#23272A` 是段头自己的底色，不是这一条说的背景。
- **不做动效**，与前两片一致。
- **不许改 `CardBar.swift`、4 个主题子类、`AnimatedCardList.swift`、`DeckLens.swift`。**
  两条路径必须都还能跑，否则没法比对。`DeckLens` 不再被使用之后是死代码，
  留到收尾阶段统一删。

## 范围边界

- **只做这三段。** `playerSideboards` 已在 T3 处理掉；`BattlegroundsCardsGroups` 不动；
  `playerClass` 里那个 hero `CardBar` 不动。
- **不要动 `Player.swift` / `Game.swift`。** 数据已经送到 `Tracker` 了。
- 战棋、`editDeck` / `hero` 两种 `playerType` 不做，与 T1 / T2 的边界一致。

## 允许修改的文件

- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/UIs/Trackers/SwiftUI/` 下 T1 / T2 的产物（仅在为复用而必须重构时）
- 新增 `.swift` 文件

新增 `.swift` **必须手工登记进 `project.pbxproj`**（`PBXBuildFile` + `PBXFileReference` +
group + Sources，共 4 处）。**漏登记不会报编译错误**，文件被静默忽略，详见 `AGENTS.md`「构建」一节。

## 验收

1. 构建通过（`Debug`）。
2. 每个新增文件 `grep -c "<文件名>.swift" HSTracker.xcodeproj/project.pbxproj` ≥ 3。
3. `git diff --stat` 里被修改的既有文件只有 `project.pbxproj`、`Tracker.swift`，
   以及 SwiftUI 目录下为复用而重构的文件。多一个都要在报告里给理由。
4. **开关关闭时行为与改动前完全一致** —— 说明你是怎么确认的。
5. app 能启动；`HSTRACKER_CARD_ROW_COMPARE=1` 比对窗仍打得开。
6. 实战验证由人来做。注意「置顶 / 置底」要靠特定卡牌效果才会出现，约不出来，
   所以**你不要指望能自己验到它们**，但代码路径必须是对的。

## 报告里请回答

- 挂载方式：三个 outlet 类型改不了，你怎么让两条路径共存的。
- 段头的每一项（底色、边框、图标、字体、基线）你是照 `DeckLens` 的哪一行复刻的。
- 为复用 T2 的视图模型你重构了什么，怎么确认主牌表行为没变。
- 一次刷新里新路径重算了什么、复用了什么。
- 三段的 `count` 与 `updateFrames()` 的高度账是怎么对上的。
- 范围边界之外你注意到、但按规则没有动的问题。
