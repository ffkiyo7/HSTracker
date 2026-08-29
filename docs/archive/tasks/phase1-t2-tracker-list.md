# Phase 1 / T2 — 把 SwiftUI 卡行接进记牌器

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
T1 的产物 `HSTracker/UIs/Trackers/SwiftUI/`（`CardRowView` / `ThemeImageCache` / 比对窗）是本任务的输入，
它已经与 `CardBar` 逐元素比对过。这一块把它接到**真的记牌器主牌表**上，新旧两条渲染路径由一个开关切换。

## 要做出什么

1. **`Settings.useSwiftUITracker`** —— 属性照 `removeCardsFromDeck`（`Settings.swift:352`）的写法，
   key 常量放在 `Settings.swift:652` 那一片。**默认 `false`**：Phase 1 还没验收完，这台机器每天在打游戏，
   默认值不能是没验收过的那条路径。（`docs/PLAN.md` 第 3 节写的 default true 是**全部验收通过后**的终态，现在不是。）
   不许改 `.xib`，所以没有 Preferences UI，靠 `defaults write` 切。
2. **一个 SwiftUI 卡表视图**，取代 `Tracker.swift:17` 的 `cardsView`（`AnimatedCardList`）。
   开关为 true 时由它渲染主牌表，为 false 时逐字回到现状。玩家和对手记牌器共用 `Tracker` 这一个类，两边一起生效。

## 范围边界

**只接主牌表这一条列表。** `DeckLens`（置顶 / 置底 / 相关牌）、`DeckSideboards`、
`BattlegroundsCardsGroups` 继续用 `AnimatedCardList`；`playerClass` 里那个 hero `CardBar` 不动。

**不做动效。** 淡入 / 淡出 / 抽卡闪光 / 位置动画留给后续切片，本切片增删卡就是直接出现和消失。
但**不许照搬 `AnimatedCardList.remove(card:fadeOut:)`（`:164`）那个 600ms `asyncAfter`** ——
它在 count == 0 的路径上是纯死等（`docs/PROGRESS.md` 2026-08-22 那节量过），搬过来等于复制一份已知的卡顿。

战棋、`editDeck` / `hero` 两种 `playerType` 都不做，与 T1 的边界一致。

## 硬性要求

- **不许改任何 `.xib`。** `cardsView` 是 `Tracker.xib` 里的 outlet，类型写死是 `AnimatedCardList`，挂载方式你自己解决。
- **不许改 `CardBar.swift`、4 个主题子类、`AnimatedCardList.swift`。** 两条路径必须都还能跑，否则没法比对。
- **行的身份判定必须与 `AnimatedCardList.areEqualForList`（`:180`）一致** —— 自己去读那个函数。
  拿 `card.id` 当 `ForEach` 的 id 是不够的，同一张卡的两行会互相吞掉。
- **行高由 `Tracker.updateFrames()` 算好后传进来**（`Tracker.swift:290-323`，卡多时会压缩）。
  新视图不许自己决定行高，也不许让 SwiftUI 的自适应布局改动它 —— `cardViewHeight = count * cardHeight`
  是 Tracker 拿去排它下面所有段的，差一像素下面全串。
- **`count` 语义。** `Tracker.updateFrames()` 读 `cardsView.count` 参与 `totalCards` 和整体高度计算。
  新路径要提供同样意义的值，且在同一次 `updateFrames()` 里与实际画出来的行数一致。
- **一次 `update(cards:)` 不许重建整个视图树。** `AnimatedCardList.updateFrames()`（`:186-201`）
  每帧把 subview 全拆了重加，把上面刚做完的增量 diff 全部作废 —— 这正是 `docs/PLAN.md` 1.3 点名要消灭的东西。
  每次刷新新建 `NSHostingView`、或整棵 rootView 全量重算，是同一个错误换了层皮。**在报告里论证你没踩。**
- **悬停要继续工作**：出卡图、相关牌 tooltip、玩家侧协同高亮（`Tracker.swift:527-611`）。
  现有的 `CardCellHover` 以 `CardBar` 为参数，`getHoverComponent()`（`:474`）靠向上遍历 superview 猜自己属于哪一段。
  新路径这两条都不许依赖 —— 分段身份直接传参（`docs/PLAN.md` 1.5）。出卡图需要该行在屏幕上的矩形。
- **协同高亮的边框要画出来。** `cardsView.shouldHighlightCard`（`AnimatedCardList.swift:33-57`）是玩家侧独有的，
  T1 的 `CardRowView` 把这一层排除在范围外了，对应 `CardBar.addHighlightColor`（`:491`）。闪光动画仍然不做。
- **新视图必须透明。** 记牌器的整体不透明度是 `Settings.trackerOpacity` 涂在 window 背景上的（`Tracker.swift:110`），
  自带背景色会把它盖掉。
- **主题 / 卡牌尺寸在设置里改完要生效。** 旧路径靠 `CardBar.factory()` 下次重建时换子类；
  新路径的缓存和视图身份是你自己设计的，在报告里说明它何时失效。
- **新增 `.swift` 必须手工登记进 `project.pbxproj`**（`PBXBuildFile` + `PBXFileReference` + group + Sources，共 4 处）。
  **漏登记不会报编译错误**，文件被静默忽略，详见 `AGENTS.md`「构建」一节。
- 仓库里已有两处 SwiftUI 窗口的现成做法（`PlayerResourcesWindow` / `RootOverlayWindow`），
  视图模型的写法与它们保持一致，不一致就说明理由。

## 验收

1. 构建通过。
2. 每个新增文件 `grep -c "<文件名>.swift" HSTracker.xcodeproj/project.pbxproj` 都 ≥ 3。
3. `git diff --stat` 里被修改的既有文件只有 `project.pbxproj`、`Tracker.swift`、`Settings.swift`。
   多一个都要在报告里给理由。
4. 开关关闭时 `Tracker` 的行为与改动前完全一致 —— 说明你是怎么确认的。
5. app 能启动；`HSTRACKER_CARD_ROW_COMPARE=1` 那个比对窗仍然打得开，没被你破坏。
   实战里的逐元素比对由人来做。

## 报告里请回答

- 挂载方式：outlet 的类型改不了，你怎么让两条路径共存的。
- 一次刷新里新路径重算了什么、复用了什么。
- `AnimatedCardList` 里你**没有**复刻的行为，逐条给理由。
- 范围边界之外你注意到、但按规则没有动的问题。
