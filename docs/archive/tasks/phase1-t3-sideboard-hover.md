# Phase 1 / T3 — 备牌段改为悬停浮出

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
本任务对应 `docs/PLAN.md` 的 **2.5**（执行时机被提前到 Phase 1 的 T3），动手前把那一节读完。

## 背景

「备牌」是牛头人酋长（ETC）和下水道之王这类卡携带的额外卡组。现在它们在记牌器里占一整块独立区域，
把携带的卡**完整铺开成卡条**（`Tracker.swift:26` 的 `playerSideboards` outlet → `DeckSideboards.swift`），
高度是 `count * cardHeight + smallFrameHeight * sideboardCount`（`Tracker.swift:404`）。
一张 ETC 就吃掉三行加一个段头，很占竖向空间。

**这一段要整个消失**，改成：光标移到牌表里的 ETC / 下水道之王**本体那一行**上时，
把它携带的卡浮出来显示。本体那一行本来就在主牌表里（它是牌组里的一张牌），不需要新画。

## 要做出什么

1. **备牌段不再占任何竖向空间**，也不再渲染卡条。
2. **悬停牌表里的备牌拥有者时，浮出它携带的卡。** 载体用现成的
   `windowManager.tooltipGridCards` —— `Tracker.setRelatedCardsTooltip`（`Tracker.swift:563`）
   已经在用它做「相关牌」提示，浮窗定位、屏幕边界处理、显示/隐藏都是现成的，照它的形态做。
3. **`Settings.hidePlayerSideboards` 继续有效**：为 true 时连浮出也不做，等于完全关闭这个功能。

## 关键约束

- **不许改任何 `.xib`。** `playerSideboards` 是 `Tracker.xib` 里的 outlet，类型写死是 `DeckSideboards`，
  这个 outlet 必须继续存在且不能崩。让它不占空间、不渲染即可。
- **按 `Sideboard.ownerCardId` 通用匹配，不要硬编码那两个卡 ID。** `DeckSideboards.update(sideboards:)`
  现在是按 `CardIds.Collectible.Neutral.ETCBandManager` 和
  `CardIds.Collectible.Hunter.KingOfTheUnderbelly` 分别取的 —— **不要复刻这个写法**。
  数据源 `[Sideboard]` 每项自带 `ownerCardId`，按它匹配悬停的那张卡，将来多一种备牌卡也不用再改代码。
- **备牌数据 `Tracker.update(...)` 已经收到了**（`Tracker.swift:121` 的 `sideboards:` 参数，
  来自 `Game.swift:394` 的 `player.playerSideboardsDict`）。悬停时要能查到它，
  怎么持有由你决定，但**不要在悬停路径里去反查 `Game` 或 `AppDelegate` 拿一份新的** ——
  悬停发生在主线程，`Game` 的状态是后台队列在写。
- **两条渲染路径都要正确。** `Settings.useSwiftUITracker` 开和关时行为必须一致 ——
  旧路径的悬停走 `hover(cell:card:)` + `getHoverComponent()`（`Tracker.swift:543`），
  新路径走 `TrackerCardListHost.onHover` 闭包（`Tracker.swift:154`）。
  **`getHoverComponent()` 不许删**，旧路径还在用它。
- **`.playerSideboards` 这个 `HoveredComponent` 枚举值的去留由你决定并说明理由。**
  它在 `getHoverComponent()` 和 `tooltipDisplay()`（`:680`）两处出现。
- **相关牌提示不能被顶掉。** `tooltipDisplay()` 现在对 `.playerCardView` 会调
  `setRelatedCardsTooltip`。一张卡同时有备牌和相关牌时的优先级由你定，
  但**必须给出结论并在报告里说明**，不许两个浮窗同时抢 `tooltipGridCards`。
- **浮窗标题**用现成的本地化 key，不要新增 `.xcstrings` 条目（通用约束第 4 条禁止改它们）。
  `DeckSideboards` 用的是 `DeckSideboard_Label_ETCBand` 和卡牌自身的 `name`，
  `setRelatedCardsTooltip` 用的是 `Related_Cards`。选哪个、为什么，写进报告。
- **不做动效**，与前两片一致。

## 范围边界

- **只做玩家侧。** 对手侧没有备牌数据。
- **不要动 `AnimatedCardList.swift` / `CardBar.swift` / 4 个主题子类。**
- **不要动 `Player.swift` / `Game.swift`。** 数据已经送到 `Tracker` 了。
- `DeckSideboards.swift` 这个类**可以不动**。它不再被布局使用之后是死代码，
  留到收尾阶段统一删（`docs/PLAN.md` 的「收尾」一节）。如果你认为必须动它，先在报告里说明理由。

## 允许修改的文件

`HSTracker/UIs/Trackers/Tracker.swift`。

新增 `.swift` 文件是允许的，但**必须手工登记进 `project.pbxproj`**（`PBXBuildFile` +
`PBXFileReference` + group + Sources，共 4 处）。**漏登记不会报编译错误**，文件被静默忽略，
详见 `AGENTS.md`「构建」一节。

## 验收

1. 构建通过（`Debug`）。
2. `git diff --stat` 里被修改的既有文件只有 `Tracker.swift`（以及新增文件带来的 `project.pbxproj`）。
   多一个都要在报告里给理由。
3. 新增文件（如果有）`grep -c "<文件名>.swift" HSTracker.xcodeproj/project.pbxproj` ≥ 3。
4. **`updateFrames()` 的高度账要对。** 备牌段不占空间之后，
   `totalCards`（`:321` 起）和 `offsetFrames` 里与 `playerSideboards` 相关的项必须一并处理干净 ——
   算多了下面所有段的行高会被无谓压缩。说明你改了哪几处。
5. app 能启动；`HSTRACKER_CARD_ROW_COMPARE=1` 比对窗仍打得开。
6. 实战验证由人来做（需要一副带 ETC 或下水道之王的牌）。

## 报告里请回答

- 备牌数据你存在哪、什么时候更新、悬停时怎么查。
- 同一张卡既有备牌又有相关牌时的优先级，以及理由。
- `updateFrames()` 里与备牌相关的高度计算你改了哪几处，为什么那样改。
- 新旧两条渲染路径你各自是怎么接上悬停的，怎么确认两边行为一致。
- 范围边界之外你注意到、但按规则没有动的问题。
