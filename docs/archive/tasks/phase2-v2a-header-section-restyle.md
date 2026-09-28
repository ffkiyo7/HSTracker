# Phase 2 / V2a — 三行头压行高 + 段头重画 + 手牌不绿名

先读 `docs/tasks/_common.md`，再读 `docs/tasks/phase2-v-visual-redesign.md`（总纲）、
`docs/tasks/phase2-v1-vector-card-bars.md`（V1 已落地的色板 / 几何 / 执行结果），
对照页 <https://claude.ai/artifact/M9QKUWFUAEF3H5RQ7kiRey>（**D3-b 那一栏的三行头和段头就是本片的规格**，2× 渲染；
页面源码里 `.hdr` / `.sec` 两组 CSS 是精确数值）。
本片只做**三行头、段头、卡名颜色**三件事；原画铺满是 V2b，折叠手势 / 拖拽吸附不在本轮，别越界。

## 现状（2026-09-16 实机）

- 三行头 `TrackerHeaderView`：行高走 `TrackerMetrics.headerLineHeight` = 卡条行高 × 40/34（1920×1080 下 ≈ 25 pt），
  标签 13 pt × scale、数字 15–16 pt × scale；第一行是职业图标 + SF Symbol ✋ / ▭ + 数字；分隔线白 18%、外框 `#141617`。
  用户看到的是「字又大又粗、和卡条不是一套」。
- 段头 `TrackerSectionView`：左对齐、`.system` 字体、放大镜图标、行高同三行头。**用户明确要求：一处系统字体都不留。**
- 手牌段：`CardRowView.nameColor` 对所有段都走 `Card.textColor()`，`highlightCardsInHand` 的绿名在手牌段也亮着；
  D2 定稿是「手牌段不再绿名，绿名只在牌库段保留」。
- 计数框 ★ 用的 `.system`。

## 要做出什么

1. **三行头压到卡条网格**：每行 = 卡条行高（1920×1080 下 21）；三行 63 + 底边 1 线。
   标签用 `TrackerTextFont.name`（中文 = 文鼎中隶）9.5 u，数字 Belwe 10 u（u = 卡条行高 / 21，V1 的定义）。
   列宽：第二列 40 u、第三列 46 u，列间线和行间线都是金 `#D6B26E` 28%（`TrackerBarStyle.line`），外框也换金线；
   底图暗化渐变 0.95 / 0.9 / 0.4 @ 0 / 0.48 / 1 保留，胜负色 `#62D97A` / `#FF6B5E` 保留。
   第一行：职业图标 + 套牌名 | 手牌数 | 牌库数，**去掉两个 SF Symbol 图标**（对照页第一行就是「● 地沟油 | 6 | 13」）。
   套牌名超长省略号截断。
2. **段头重画**：高 22 u，居中「牌库 (20)」——段名中隶金字 `TrackerBarStyle.gold`，张数 Belwe 白字 `(n)`；
   右侧 22 u 格内一个 6 u 的 ˅ 折叠箭头（金，80%），**只画不响应**（折叠手势是后续片）；顶边金线 28%；去掉放大镜。
   张数按副本计（与 V1 计数一致）。
3. **手牌段不绿名**：手牌段卡名恒为 `TrackerBarStyle.text`；牌库段保留 `highlightInHand` 绿；抽牌 / 弃牌 / 暗条语义全部不动。
   实现位置由你定，但 `Card.textColor()` 本身不能改（旧路径共用）。
4. **★ 换字体**：计数框的传说 ★ 不再 `.system`。用 Belwe 画不出星就用矢量 / SF Symbol 的 `star.fill` 描形，但**不能是系统字体的文字 ★**。
5. 对手侧三行头仍只有一行（手牌 / 牌库数），同一套样式。

## 硬约束

- 旧路径（`CardBar` / `updateLegacyFrames` / `useSwiftUITracker == false`）一行不动。
- 排版仍由 `TrackerViewModel.updateLayout` 一处算：`headerHeight` / 段头高的变化要同步到 `bottomY` 与 tracking area，
  报告里写清新旧公式。`TrackerMetrics.headerLineHeight` 要么改成 21 u 要么删掉，不留「40/34」的注释误导后人。
- 会话回顾窗（`HeaderStyle` 注释里提到的复用方）跟着新常量走，不能编译不过、不能挤爆。
- 一次刷新不重建视图树；`TrackerCardRow` 的 id / Equatable 不变。
- 所有 view model 写入在主线程。不动 `Player.swift` / `Game.swift` / `Card.swift`。
- **不动 `HSTracker/Logging/Entity.swift`、`Player.swift`、`Parsers/TagChangeActions.swift`、
  `HSTrackerTests/CardZoneGroupsTests.swift`、`ZoneGroupsReplayTests.swift`**——工作区里这几个文件是另一条线（Bug T8）的未提交改动，
  碰了会混线。

## 允许修改的文件

- `HSTracker/UIs/Trackers/SwiftUI/TrackerHeaderView.swift`、`TrackerSectionView.swift`、`CardRowView.swift`、
  `TrackerBarStyle.swift`、`TrackerViewModel.swift`、`TrackerView.swift`
- `HSTracker/UIs/Trackers/Tracker.swift`（只准动 `updateSwiftUIFrames` 里三行头 / 段头高度的取法）
- `HSTrackerTests/TrackerMetricsTests.swift` 加测试；如需新测试文件同步 pbxproj
- `Translations/macOS/Localizable.xcstrings` 只准加本片新 key，过校验器

## 验收

1. Debug build `BUILD SUCCEEDED`；测试全绿（基线 = 现有全部 + 本片新增）。
2. 报告里给出：
   - 1920×1080 / 2560×1440 / 1280×720 三种窗口下：三行头每行高、标签 / 数字字号、段头高、箭头尺寸；
   - `headerHeight` / 段头高 / `bottomY` 的新公式，以及 30 张 + 三段头压缩场景下总高怎么收；
   - 手牌不绿名的实现点，以及牌库段绿名 / 抽牌橙 / 弃牌红 / 暗条四个语义各自现在在哪一行代码决定；
   - `rg -n "\.system\(|systemName|systemFont" HSTracker/UIs/Trackers/SwiftUI/` 的输出（预期：0 行，或仅剩 ★ 的 `star.fill` 一处并说明）。
3. 🎮 用户看：三行头与卡条同网格、字是中隶 + Belwe、金线；段头居中金字 + 箭头；手牌段白名；★ 不再是系统字。

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/archive/tasks/phase1-t6-tracker-root-layout.md`。
**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`。**

## 执行结果（2026-09-17）

### 改动清单

| 文件 | 做了什么 |
|---|---|
| `SwiftUI/TrackerBarStyle.swift` | 新增 `.hdr` / `.sec` 的参考像素常量（段头 22、列宽 40 / 46、内边距 6、标签 9.5、数字 10、职业图标 11、箭头 6 / 描边 1.5 / 不透明 0.8、字距 .04em、★ 10）；新增字体工厂 `label(_:size:)` / `digits(_:size:)`；新增 `TrackerStar`（矢量五角星）、`TrackerChevron`（`.sec .chev` 的直角折线）两个 `Shape`；新增环境键 `trackerHandSection`。`TrackerMetrics.headerLineHeight` **删除**，换成 `sectionHeaderHeight(rowHeight:) = rowHeight × 22 / 21`，「40 / 34」的注释一并删干净 |
| `SwiftUI/TrackerHeaderView.swift` | 三行头重画：`scale = lineHeight / 40` → `u = lineHeight / 21`；列宽改成跟 `barWidth` 取比例；分隔线 / 行线 / 外框全换金线 `TrackerBarStyle.line`（白 18% 的 `divider` 和 `#141617` 的 `border` 只剩会话回顾窗在用，`innerBorder` 已删）；第一行去掉两个 SF Symbol，改成 职业图标 + 套牌名（省略号截断）｜手牌数｜牌库数；hero 原画上的 `TrackerFade` 层去掉，统一走 `.hdr .shade` 那条 0.95 / 0.9 / 0.4 @ 0 / 0.48 / 1；view model 加 `deckName` / `barWidth` |
| `SwiftUI/TrackerSectionView.swift` | 段头整块重画：`[22u][1fr][22u]` 三列，中间「段名（中隶金字）+ (n)（Belwe 白字）」，右列 6u 折叠箭头（金、80%、只画不响应），顶边金线；**放大镜图标和 `.system` 字体全部删除**（连 `#if HSTTEST` 那个 `systemSymbolName` 一起）；张数按副本计 |
| `SwiftUI/CardRowView.swift` | ★ 从 `Text("★").font(.system(...))` 换成 `TrackerStar` 矢量填充；`nameColor` 读环境 `trackerHandSection`，手牌段恒为 `TrackerBarStyle.text` |
| `SwiftUI/TrackerView.swift` | 手牌段挂 `.environment(\.trackerHandSection, true)` |
| `SwiftUI/TrackerViewModel.swift` | `updateLayout` 末尾把这一帧的 `barWidth` 同步给 `header`（列宽跟着压缩收） |
| `Trackers/Tracker.swift` | `updateSwiftUIFrames` 里一个 `smallFrameHeight` 拆成两个：`headerLineHeight = baseRowHeight`、`sectionHeaderHeight = TrackerMetrics.sectionHeaderHeight(...)`。对手侧 AppKit hero bar 跟三行头一行同高。**其余一行没动** |
| `HSTrackerTests/TrackerMetricsTests.swift` | 两处 `headerLineHeight` 调用改名；新增 4 条测试 |

`Localizable.xcstrings` **没动**：本片没有新文案（段名走已有的 `Zone_Deck` / `Zone_Hand` / `Zone_Played`，`(n)` 不需要 key）。pbxproj 没动（无新增 / 删除文件）。

### 验收

- Debug build：**BUILD SUCCEEDED**（00:19:21）
- test：**118 / 118 全绿**（基线 114 + 本片 4）（00:20:19 ~ 00:23:47）。新增的是
  `testHeaderKindsSitOnTheCardRowGrid` / `testSectionHeaderKeepsItsRatioToTheRow` /
  `testHeaderColumnsLeaveRoomForTheDeckName` / `testCompressedPanelNarrowsTheHeaderColumns`
- `rg -n "\.system\(|systemName|systemFont" HSTracker/UIs/Trackers/SwiftUI/` → **0 行**（exit 1）。
  ★ 也不是 SF Symbol，是 `TrackerStar` 这个自己画的 `Shape`，所以连 `star.fill` 那一处豁免都没用上。
- ⚠️ 本片这两次跑用的是**默认 DerivedData**（`~/Library/Developer/Xcode/DerivedData/HSTracker-cgfkyd…`），
  因此 00:20:19 覆盖过那里的 `Debug/HSTracker.app`。V2b 起全部改用
  `-derivedDataPath /private/tmp/claude-501/-Users-wadorudi-Desktop-dev-HSTracker/e8739b8e-9fed-4951-84c1-6c3f7ac7434c/scratchpad/DerivedData-v2`。

### 尺寸表（`.big` 档，未压缩；单位 pt，u = 行高 / 21）

| 窗口 | 面板宽 | 三行头每行 | u | 标签 9.5u | 数字 10u | 段头 22u | 箭头 6u | 箭头描边 1.5u | 第二列 40u | 第三列 46u | （旧）40/34 行高 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1920×1080 | 170.61 | **20.95** | 0.998 | 9.48 | 9.98 | **21.95** | 5.99 | 1.50 | 39.91 | 45.89 | 25 |
| 2560×1440 | 227.48 | **27.94** | 1.330 | 12.64 | 13.30 | **29.27** | 7.98 | 2.00 | 53.21 | 61.19 | 33 |
| 1280×720 | 113.74 | **13.97** | 0.665 | 6.32 | 6.65 | **14.63** | 3.99 | 1.00 | 26.61 | 30.60 | 16 |

三行头一行从 25 → 20.95（1080p），三行合计 **75 → 62.86**；段头 25 → 21.95。
箭头描边和金线都有 `max(…, 1)` / `max(…, 0.5)` 的下限，1280×720 下描边正好落在 1.0。

### 新旧公式

```
旧： frameHeight = round(baseRowHeight × 40 / 34)          // 三行头一行 == 段头，同一个值
    headerHeight = lineCount × frameHeight
    offset       = headerHeight + Σ可见段(frameHeight + 5) [+ frameHeight 若预留墓地行]

新： headerLine   = baseRowHeight                           // 三行头一行 = 一条卡条
    sectionH     = baseRowHeight × 22 / 21
    headerHeight = lineCount × headerLine
    offset       = headerHeight + Σ可见段(sectionH + 5)   [+ sectionH 若预留墓地行]

两者共有：
    cardHeight   = min(baseRowHeight, (availableHeight − offset) / totalCards)
    barWidth     = cardHeight × 8.142857
    contentHeight= headerHeight + Σ段(count × cardHeight + sectionH + 5) + count×cardHeight
    bottomY      = availableHeight − contentHeight
```

`bottomY` 的来源没变（仍是 `availableHeight − contentHeight`，`Tracker.updateSwiftUIFrames` 一处赋值），
变的只是 `offset` / `contentHeight` 里段头那一项的数值。tracking area 仍按窗口宽（`Tracker.getTrackingArea()`），本片没碰。

**30 张 + 三段头怎么收**（`.big`、三行头 3 行、30 张分在三段里）：

| 窗口 | availableHeight | headerHeight | 段头 ×3 + 留白 | offset | cardHeight | barWidth | contentHeight | bottomY |
|---|---|---|---|---|---|---|---|---|
| 1920×1080 | 1080 | 62.86 | 80.85 | 143.71 | **20.95（不压缩）** | 170.61 | 772.27 | 307.73 |
| 2560×1440 | 1440 | 83.81 | 102.80 | 186.61 | **27.94（不压缩）** | 227.48 | 1024.69 | 415.31 |
| 1280×720 | 720 | 41.90 | 58.90 | 100.80 | **13.97（不压缩）** | 113.74 | 519.84 | 200.16 |

三档都触发不了压缩，`bottomY` 全为正。对照 V1 的同场景（三行头 3 行时 offset 是 75 + 90 = 165），
新公式把 offset 压到 143.71，**预算宽出 21 pt**，压缩只会来得更晚。
真正压缩的边界（60 张三段、1080p）由 `testCompressedPanelNarrowsTheHeaderColumns` 与既有的
`testZoneSectionsStayInsideTheWindowWhenCompressed` 覆盖，`contentHeight ≤ availableHeight` 仍成立。

### 四个语义现在在哪一行决定

| 语义 | 决定它的代码 |
|---|---|
| 手牌段不绿名 | `CardRowView.swift` `nameColor`：`if playerType == .cardList \|\| playerType == .editDeck \|\| isHandSection { return TrackerBarStyle.text }`。`isHandSection` 来自 `@Environment(\.trackerHandSection)`，唯一的写入点是 `TrackerView.swift` 手牌段上的 `.environment(\.trackerHandSection, true)` |
| 牌库段绿名 | 仍是 `Card.textColor()`（`Card.swift:330`，`highlightInHand && Settings.highlightCardsInHand` → `Settings.playerInHandColor`），经 `CardRowView.nameColor` 末两行透传 |
| 抽牌橙 | `Card.swift:328`（`highlightDraw && Settings.highlightLastDrawn`），同样经 `nameColor` 透传 |
| 弃牌红 | `Card.swift:334`（`wasDiscarded && Settings.highlightDiscarded`），同上 |
| 暗条 | 两处，都没动：颜色走 `Card.swift:332`（`count <= 0 \|\| jousted` → 灰）；整条的 45% / 55% 走 `CardRowView.isDimmed` + `TrackerBarStyle.dimContent` / `dimCost` |

`Card.textColor()` 一个字节没改。

### 关键决定

1. **`headerLineHeight` 删掉而不是改值。** 改成「返回 `rowHeight`」就是个恒等函数，留着只会让人以为还有转换。
   段头那 22 : 21 的比例才需要一个命名常量，于是只留 `sectionHeaderHeight(rowHeight:)`。
2. **对手侧 AppKit hero bar 用三行头的行高（= 卡条行高），不是段头高。** 它是「一行」，不是「一个段头」，
   放在同一条行网格上才符合总纲的「整个面板一个行网格」。它比以前矮了 4 pt（1080p：25 → 20.95）。
3. **列宽按 `barWidth` 取比例，不按 `lineHeight`。** V1「发现但按规则没动」第 3 条就是这个：
   `62 * scale` / `76 * scale` 里的 `scale` 走未压缩行高，重度压缩时两列合计会顶满、套牌名被挤成 0。
   现在 `columnUnit = barWidth / 171`，未压缩时与 `u` 逐位相等（两者都是 `rowHeight / 21`），压缩时两列同步收。
4. **三行头的暗化层统一成 `.hdr .shade` 那条渐变，不再叠 `TrackerFade`。** 对照页 `.hdr .shade` 就是
   0.95 / 0.9 / 0.4 三停的线性渐变，任务书也写「保留」；原来「有原画走 fade.png、没原画走渐变」的双路径
   在 D3 里没有对应物，而且 `TrackerFade` 在 V2b 要改几何，留着会把两件事绑死。
   `HeaderStyle.fadeOpacity` 因此只剩 `SessionRecapView` 在用，注释已改。
5. **套牌名在 view model 里自取，没经过 `Tracker.swift`。** 任务书只准动 `updateSwiftUIFrames` 里的高度取法，
   而 `TrackerHeaderViewModel.update(...)` 的参数表要加一项就得改 `updateSwiftUIHeader`。
   取的是 `AppDelegate.instance().coreManager.game.currentDeck?.name` —— 和 `Game.swift:442` 给
   `tracker.playerName` 的**同一个源**，调用点（`updateSwiftUIHeader` → `header.update`）也是同一处、同一个主线程。
6. **★ 用自己画的五角星，不用 `star.fill`。** 任务书允许 SF Symbol 兜底，但 `Shape` 更省事也更干净，
   验收那条 rg 因此是干净的 0 行。内外半径比取 1/φ² = 0.382，是正五角星。
7. **箭头逐字复刻 CSS。** `.sec .chev` 是「6u 方块的右边 + 下边，1.5u 描边，旋转 45°，再上移 25%」，
   所以 `TrackerChevron` 画的是那条直角折线，`.rotationEffect(.degrees(45))` 之后 `.offset(y: -chevron/4)`
   （CSS 的 `translateY(-25%) rotate(45deg)` 是先转后移，SwiftUI 的修饰符顺序正好对应）。
8. **段头字距用 `.tracking(0.04 × 字号)`。** SwiftUI 的 `tracking` 是绝对值，CSS 的 `.04em` 是相对字号，换算了一次。
9. **三行头文字色从纯白改成 `TrackerBarStyle.text`（#F4EAD4）。** 对照页 `.hdr` 继承的就是 `--t`，
   而且「和卡条是一套」是本片的出发点。胜负色 `#62D97A` / `#FF6B5E` 原样保留。

### 待用户确认

1. **手牌段「恒为 `TrackerBarStyle.text`」会连抽牌橙一起吃掉。** 任务书第 30 行同一句里既说「手牌段卡名恒为
   `TrackerBarStyle.text`」，又说「抽牌 / 弃牌 / 暗条语义全部不动」——这两条在手牌段是互斥的：
   `highlightDraw`（刚抽到的那张）标记的牌就在手上。我按**字面**做了（恒为 text），依据是对照页的
   `.inhand .name { color: var(--hand) }` 也是这么写的。
   如果你要的是「只吞绿名、抽牌橙留着」，改法是 `nameColor` 里把 `isHandSection` 那条从「直接返回 text」
   换成「只在 `highlightInHand` 命中时返回 text」，一行的事。
2. **套牌名的悬停浮层没做。** 总纲第 8 行提到「悬停第 1 行时以浮层显示完整套牌名」，但 V2a 的「要做出什么」
   只写了「省略号截断」，而且记牌器现在仍是 `ignoresMouseEvents` 的锁定浮窗（鼠标模型是折叠那一片的事），
   浮层现在做也收不到 hover。留到折叠 / 拖拽吸附那一片。
3. **对手侧 hero bar 矮了 4 pt。** 见「关键决定 2」。它还是旧的 `CardBar` 贴图，按新高度画会略扁；
   实机看着别扭的话可以让它单独保留 22 : 21 甚至更高。

### 发现但按规则没动

1. **`TrackerCardListViewModel.sectionHeaderHeight` 的默认值还是 `40`。** 它每帧都被 `updateLayout` 覆盖，
   所以不影响实机，但这个 40 是旧网格的遗物。该文件不在本片的允许清单里，没改。
2. **`HeaderStyle.divider` / `.border` 现在只服务 `SessionRecapView`。** 名字还叫 `HeaderStyle` 但记牌器三行头
   已经不用它们了。`SessionRecapView.swift` 不在允许清单里，所以没有把这两个常量搬过去。
3. V1 报的战棋卡条仍读主题 PNG、`Settings.theme` 的三个死订阅者，本片同样没碰。

### 复核（Claude，2026-09-17）

- 待确认 1 **已裁决并改掉**：手牌段只吞绿名，抽牌橙保留。`CardRowView.nameColor` 里 `isHandSection` 那条改成
  「`highlightDraw && Settings.highlightLastDrawn` 不命中时才返回 text」。理由：手牌段每张都在手上，去掉绿名后
  抽牌橙是这一段唯一还能表达的状态。
- 待确认 2（套牌名悬停浮层）、3（对手侧 hero bar 21 pt）：留到 🎮 看。
- 其余 diff 通过：`TrackerHeaderViewModel.update` 读 `game.currentDeck` 与它原本读 `playerName` 同一线程；
  `updateLayout` 写 `header.barWidth` 在主线程；`TrackerFade` 两常量改字面值后只剩回顾窗消费，含义未反。
