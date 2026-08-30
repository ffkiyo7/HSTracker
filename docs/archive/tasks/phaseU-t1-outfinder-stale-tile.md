# Phase U / T1 — 卡池浮窗串卡（上游 3.6.7 的回归）

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
背景见 `docs/PLAN.md` 的 **Phase U** 一节和 `docs/PROGRESS.md` 的「已知问题」。

## 现象

卡点 ① 实战（2026-08-30）发现：**悬停不同的卡，卡池浮窗里会混进上一次悬停留下的卡图。**

用户实测的形态是「误炸」（Misfire，`WW_348`）这一张反复出现在好几张不相干的卡的相关牌里；
同一张备牌拥有者在牌库里悬停显示错的、抽到手上再悬停就对了 —— 后者只是因为两次的
网格行列数不同、视图被迫重建了。

**不是数据算错**：`getRelatedCards()` 返回的卡是对的，错的是画出来的图。

## 根因（已定位到行）

`HSTracker/UIs/Tooltips/RelatedCardsTooltipPanel.swift`：

| 行 | 内容 |
|---|---|
| `:113` | `RelatedCardImageView` 用 `@SwiftUI.State private var image: NSImage?` 自己存图 |
| `:138` | 只有 `.onAppear(perform: loadImage)` 触发加载，没有任何"卡变了"的通道 |
| `:178` / `:180` | `ForEach(0..<layout.rows, id: \.self)` / `ForEach(0..<layout.columns, id: \.self)` —— **格子的 SwiftUI 身份是行列下标，不是卡** |
| `:428` | `hide()` 只是 `orderOut(nil)`，`NSPanel` 和它那棵 `NSHostingView` 视图树一直活着 |

四条合起来：两次悬停只要网格形状相同，SwiftUI 就复用同一批 `RelatedCardImageView` 实例，
`onAppear` 不再触发，`@State image` 还挂着**上一张卡的图**。形状变了也只是部分格子重建，
活下来的格子照样串。

**这是上游的代码，不是我们改出来的。** `git diff 534ee2d8 -- <该文件>` 是空的；
它来自上游 commit `643ca6d1 The OutFinder`。3.6.5 用的是 AppKit 的 `GridCardImages.swift`
（`NSCollectionView`，每次 reload 重新绑定 item），所以这个问题是 3.6.7 换 SwiftUI 时引入的。

## 要做出什么

**换卡必换图。** 任何一次 `setCardIdsFromCards()` 之后显示出来的每一格，画的都必须是当前这批卡。

## 关键约束

- **不许用"隐藏时清空 `viewModel.cards`"来绕。** 那会让浮窗在 `hide()` 到下一次 `show()`
  之间闪一下空网格，而且 `gridWidth` / `gridHeight` 是从 `viewModel.layout` 算的
  （`:414` / `:419`），清空会让调用方拿到 0 尺寸。
- **同一张卡在池子里出现多次是合法的**，身份方案要能区分重复项，不能只用 `card.id`。
- **不许动 `RelatedCardsGridLayout`**（`:39-100`）。它算出来的 `gridWidth` / `gridHeight`
  被三处调用方拿去算浮窗位置：`Tracker.swift:762` / `:809`、`Game.swift` 的悬停路径、
  `CounterChipView`。改布局等于改位置。
- **不许放宽 `@available(macOS 10.15, *)`**。部署目标虽然已经是 14.0，但清理那 97 处守卫
  是独立的收尾项，不在本任务范围。注意这也意味着 **`onChange(of:) { _, _ in }`（双参版本）
  是 macOS 14 API，在这个文件里不能直接用**；单参版本是 macOS 11。你选的方案要在
  10.15 守卫下能编译。
- **不做动效。** 换图就是硬切换，与浮窗现有形态一致。
- **加载失败仍要显示占位图**（`loadingImageName`，`:117-124`）。现在失败时 `image` 保持 nil、
  画占位；修完之后"上一张的图"不能变成新的兜底。

## 范围边界

- **只改这一个文件。** 悬停路径（`Tracker.swift` / `Game.swift`）、`RelatedCardsManager`、
  `ImageUtils` 一律不动 —— 数据是对的。
- 同一文件里 `PoolSummaryPanelView` 的关键词 chips（`:365` 起）和 `StatBarColumnView`
  的柱子（`:311`）也是 `id: \.self` 的下标 `ForEach`。**先确认它们有没有同类问题再决定动不动** ——
  它们内部没有 `@State`，纯值渲染，大概率不需要改。**动了要在报告里给理由。**
- `RelatedCardsBrowserPanel.swift`（右键开的池浏览器）不在范围内，但**它是同一个作者同一轮加的、
  很可能同构**。看一眼，把结论写进报告，不要顺手改。

## 允许修改的文件

`HSTracker/UIs/Tooltips/RelatedCardsTooltipPanel.swift`。

## 验收

1. Debug 构建通过。
2. `git diff --stat` 里只有这一个文件。
3. 人肉验（我来做）：**连着悬停两张相关牌数量相同的卡**，第二张不能带出第一张的图；
   悬停 → 移开 → 再悬停另一张，同样不能串。备牌浮窗（ETC / 下水道之王）和 OutFinder
   的卡池浮窗各试一遍 —— 它们共用这同一扇窗。

## 报告里请回答

- 你给格子选的身份是什么，重复卡怎么区分。
- 为什么这个方案在 `@available(macOS 10.15, *)` 下能编译（用到的 API 及其可用版本）。
- `PoolSummaryPanelView` / `StatBarColumnView` / `RelatedCardsBrowserPanel` 各自有没有同类问题，
  依据是什么。
- 范围边界之外你注意到、但按规则没有动的问题。
