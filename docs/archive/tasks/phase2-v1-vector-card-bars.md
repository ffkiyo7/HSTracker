# Phase 2 / V1 — 矢量卡条 + 尺寸按窗口比例 + 主题退役

先读 `docs/tasks/_common.md`，再读 `docs/tasks/phase2-v-visual-redesign.md`（总纲，含 D2 定稿参数与对照页链接）、
`docs/PLAN.md` 2.8 一节、`docs/research/firestone-overlay.md` 第七节（目标尺寸的实测来源）。
本片只做**卡条本身和尺寸**；段头 / 折叠 / 三行头压行高 / 拖拽吸附是 V2，别越界。

## 现状

- SwiftUI 路径的卡条 `CardRowView`（T1）是按主题 PNG（`Themes/Bars/<theme>/*.png`，217×34 的 1x 图）逐像素复刻 `CardBar` 的：
  框、费用宝石、计数框、渐隐层都是贴图，字号 / 名字区宽度由 `ThemeBarLayout` 从贴图尺寸推出。
- 尺寸：`CardSize.swift` 五档预设，宽度从行高推出、宽高比锁死 6.38 : 1；`SizeHelper.trackerFrame()` 用绝对点值，不随炉石窗口缩放；
  行高压缩（`TrackerViewModel.updateLayout` 的公式）时宽度不跟着收，贴图纵向压扁，`CardBar.ratioHeight` 是给这种情况打的补丁。
- 用户实战结论（09-14）：整体太大、长卡名被遮、视觉不成一套。

## 要做出什么

1. **卡条改矢量绘制**，按 D2 定稿（对照页里 `.panel.C` 那一栏就是规格，2× 渲染）：
   - 行内从左到右：费用格（宽 22 / 行高 21 的比例，整格按稀有度着色）→ 卡名（主题字体 `TrackerTextFont.name`，白字带投影，**超长省略号截断**，不缩字）→ 右侧原画（占行宽约 58%，用现有 `tiles/<id>.jpg`，左缘 35% 用底色渐隐）→ 计数框（张数 > 1 显示数字；传说单张显示 ★）。
   - 费用格色板：普通 `#5A5650` · 稀有 `#3B6B8F` · 史诗 `#9A5F8C` · 传说 `#A8762C`。数字 Belwe 白字。
   - 底色：整块面板一个底 `#1B1410`，乘现有 `Settings.trackerOpacity`；行间细线金 `#D6B26E` 10%。
   - 保住的语义（形态由你定，报告里说明）：`isCreated` 礼物角标、`count <= 0` 的暗条（已打出段用负数 count）、`highlightInHand` 绿名、`highlightDraw` / `highlightDiscarded` 的抽牌 / 弃牌信号、协同高亮 `HighlightColor`（teal / orange / green）。这些都在 `CardRowView` 现有代码里，一个都不能丢，但可以换画法。
2. **尺寸按炉石窗口比例**：面板宽 8.9% 窗口宽、行高 1.94% 窗口高（1920×1080 下 171 × 21），宽高比 8.14 : 1；`SizeHelper.trackerFrame()` 改为按比例；
   行高被压缩时**宽度同步收**，比例不变（PLAN 2.8 第 3 条）；`CardSize` 五档改成对上述基准的倍率（默认档 = Firestone 尺寸），本机现值 `small` 应对应比默认略小。
3. **主题退役**：SwiftUI 路径不再读任何主题 PNG；设置页的主题选择器去掉。**PNG 资源和 `CardBar` 旧路径先留着**（`useSwiftUITracker = false` 仍要能跑，「收尾」阶段再删），只是新路径不碰它们。

## 硬约束

- 旧路径（`CardBar` / `AnimatedCardList` / `updateLegacyFrames`）一行不动；`useSwiftUITracker` 为 false 时逐字回现状。
- 排版仍由 `TrackerViewModel.updateLayout` 一处算，压缩公式保留，`bottomY` 与渲染高度同源，无 `GeometryReader`。宽度同步收缩的实现要写清楚它和 `bottomY` / tracking area 的关系。
- 一次刷新不重建视图树；`TrackerCardRow` 的 id / Equatable 语义不变。
- 卡图异步加载 + LRU（T7）沿用，`ThemeImageCache` 要么改名复用要么删，不留死代码。
- 三行头（T5）本片不动外观，只跟着新的行高 / 面板宽缩放，别让它挤爆；压到 21 行高是 V2 的事。
- `CardRowCompareWindow`（Phase 1 的并排比对窗）随主题一起退役，删干净并解除 pbxproj 登记。
- 所有 view model 写入在主线程。不动 `Player.swift` / `Game.swift`。

## 允许修改的文件

- `HSTracker/UIs/Trackers/SwiftUI/` 全部；新增 / 删除文件同步 pbxproj（新增 4 处，删除也要摘干净）
- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/Core/SizeHelper.swift`、`HSTracker/UIs/Cards/CardSize.swift`
- `HSTracker/Core/Settings.swift`（`theme` 的声明保留，老 defaults 可读；只是不再有 UI）
- `HSTracker/UIs/Preferences/TrackersPreferences.swift`（去主题选择器）
- `Translations/macOS/Localizable.xcstrings` 只准删本片撤掉的 UI 文案 key、加本片新 key，过校验器
- `HSTrackerTests/` 新增尺寸 / 布局测试

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；测试全绿（基线 90 + 本片新增）。
2. 报告里给出：
   - 三种窗口下的尺寸表（2560×1440 全屏、1920×1080 全屏、1280×720 窗口）：面板宽、行高、费用格、名字区宽、原画区宽，各档 `CardSize` 倍率；
   - 压缩场景（30 张 + 三段头）下宽高怎么一起收，`bottomY` 怎么算；
   - 每个保住的语义现在怎么画（礼物 / 暗条 / 绿名 / 抽弃信号 / 协同高亮）；
   - 删了哪些文件、哪些 key。
3. 🎮 用户看：整体大小、卡名「公诉人梅尔特拉尼克斯」完整可读、费用格四色、原画渐隐。

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/archive/tasks/phase1-t6-tracker-root-layout.md`。
**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-15）

### 改动清单

| 文件 | 做了什么 |
|---|---|
| **新增** `SwiftUI/TrackerBarStyle.swift` | D2 色板与行内几何（全部以「1920×1080 下的 1 逻辑像素」为单位）；`TrackerMetrics`（按窗口比例的面板宽 / 行高 / 五档倍率 / 三行头行高）；`TrackerTextFont`（去主题，只按语言选字体）；`TrackerFade`（原 `fade.png` 改成程序画的渐变 `NSImage`） |
| `SwiftUI/CardRowView.swift` | **整文件重写**成矢量卡条。`ThemeBarLayout`（四套主题的 20 个 rect 常量）、`CardRowStrokedText`、`pixelSize` / `ratios` / `ratio` 全删 |
| `SwiftUI/TrackerViewModel.swift` | `TrackerLayout` 加 `barWidth` / `opacity`；`updateLayout` 收 `panelWidth`，基准行高由它推出；段的压缩预算补上 5pt 段尾留白（见下）；删 `baseCardHeight`（原来读 `kRowHeight` 五档） |
| `SwiftUI/TrackerView.swift` | 面板整体一个底色 × 不透明度，宽度取 `layout.barWidth`，按我方 / 对手贴靠窗口右 / 左缘 |
| `SwiftUI/TrackerCardListViewModel.swift` | 删 `theme` / `cardSize` 两个 `@Published` 和 `ThemeImageCache.prepare`，加 `barWidth` |
| `SwiftUI/TrackerCardListView.swift` | 传参跟着改 |
| `SwiftUI/TrackerSectionView.swift` | 去掉段自己的不透明底 `#23272A`（与「整块面板一个底」直接冲突）；图标 / 字号从写死 17pt 改成跟行高收，防止压缩时挤爆。**外观重做仍归 V2** |
| **删除** `SwiftUI/ThemeImageCache.swift` | 主题 PNG 缓存，SwiftUI 路径唯一的消费者没了 |
| **删除** `SwiftUI/CardRowCompareWindow.swift` | Phase 1 的并排比对窗，随主题退役 |
| `Trackers/Tracker.swift` | `updateSwiftUIFrames` 不再用 `ratio`，行高 / 三行头行高由窗口宽推出；`setOpacity()` 在 SwiftUI 路径把窗口底改成透明（底色改由面板自己画）并触发一次重排 |
| `Core/SizeHelper.swift` | `trackerWidth` 在 SwiftUI 路径改成按炉石窗口算；**旧路径逐字保留绝对点值** |
| `UIs/Cards/CardSize.swift` | 只加了一段注释说明 `k*` 常量从此只服务旧路径 |
| `UIs/Preferences/TrackersPreferences.swift` | 删主题选择器 |
| `AppDelegate.swift` | 删 `CardRowCompareWindowController.openIfRequested()`（那个类已删，不删这行编译不过） |
| `Translations/macOS/Localizable.xcstrings` | 删 5 个 key，无新增 |
| **新增** `HSTrackerTests/TrackerMetricsTests.swift` | 10 条尺寸 / 布局测试 |

`project.pbxproj`：`TrackerBarStyle.swift`、`TrackerMetricsTests.swift` 各登记 4 处；
`ThemeImageCache.swift`、`CardRowCompareWindow.swift` 各摘掉 4 处。`TrackerHeaderView.swift` **一行没动** ——
`TrackerTextFont` / `TrackerFade` 挪进新文件时接口保持不变，所以三行头和 `SessionRecapView`（不在允许清单里）都不用改。

删掉的 key：`tracker_theme`、`tracker_theme_classic`、`tracker_theme_dark`、`tracker_theme_frost`、`tracker_theme_minimal`。

### 验收

- 受限环境 `clean build`：**BUILD SUCCEEDED**
- 受限环境 `test`：**100 / 100 全绿**（基线 90 + 本片 10）
- `python3 docs/tasks/tools/check_xcstrings.py --baseline HEAD`：**5 条 E3「删除了 baseline 里存在的 key」**，
  正是上面那 5 个主题 key；其余全过（只剩 4 条与本片无关的既有 W1）。
  **校验器没有 `--allow-removed-key` 这类开关**（`--allow-new-key` 只放行新增），而本任务书第 43 行明确允许「删本片撤掉的 UI 文案 key」，
  所以没有改校验器，按预期失败报上来。

### 尺寸表

基准：面板宽 = `min(窗口宽 × 8.9%, 窗口高 × 1.94% × 8.1429)`，行高 = 面板宽 ÷ 8.1429。
16:9 下两条规则结果一致（差 < 0.2%），取 min 只是为了超宽窗口不至于给出一条荒唐宽的面板（有测试覆盖）。
**宽高比 8.142857 : 1 由构造保证**，不是调出来的。

倍率：`tiny 0.70 / small 0.85 / medium 0.92 / big 1.00 / huge 1.25`。
`big` 是 `Settings.cardSize` 的 `defaultValue`，所以让它承载 Firestone 尺寸；本机现值 `small` 落在默认的 85%，符合「比默认略小」。
**没有改 `Settings` 的默认值**。

单位：pt。「卡名区」= 无计数框 / 有计数框两种；原画区含渐隐段（其左 35% 被底色盖住）。

**2560×1440 全屏**（基准面板 227.5）

| 档 | 面板宽 | 行高 | 费用格 | 卡名区 | 原画区 |
|---|---|---|---|---|---|
| tiny | 159.2 | 19.56 | 20.5 | 125.7 / 110.8 | 93.1 |
| small | 193.4 | 23.75 | 24.9 | 152.7 / 134.6 | 113.1 |
| medium | 209.3 | 25.70 | 26.9 | 165.2 / 145.6 | 122.4 |
| **big** | **227.5** | **27.94** | **29.3** | **179.6 / 158.3** | **133.0** |
| huge | 284.3 | 34.92 | 36.6 | 224.5 / 197.9 | 166.3 |

**1920×1080 全屏**（基准面板 170.6 —— 实测目标 171 × 21）

| 档 | 面板宽 | 行高 | 费用格 | 卡名区 | 原画区 |
|---|---|---|---|---|---|
| tiny | 119.4 | 14.67 | 15.4 | 94.3 / 83.1 | 69.8 |
| small | 145.0 | 17.81 | 18.7 | 114.5 / 100.9 | 84.8 |
| medium | 157.0 | 19.28 | 20.2 | 123.9 / 109.2 | 91.8 |
| **big** | **170.6** | **20.95** | **21.9** | **134.7 / 118.7** | **99.8** |
| huge | 213.3 | 26.19 | 27.4 | 168.4 / 148.4 | 124.7 |

对照现状（`.big` 旧值 217 × 34、卡名区被贴图锁死约 145）：**面板窄 21%、行高矮 38%**，卡名区反而没变窄。

**1280×720 窗口**（基准面板 113.7）

| 档 | 面板宽 | 行高 | 费用格 | 卡名区 | 原画区 |
|---|---|---|---|---|---|
| tiny | 79.6 | 9.78 | 10.2 | 62.9 / 55.4 | 46.6 |
| small | 96.7 | 11.87 | 12.4 | 76.3 / 67.3 | 56.5 |
| medium | 104.6 | 12.85 | 13.5 | 82.6 / 72.8 | 61.2 |
| **big** | **113.7** | **13.97** | **14.6** | **89.8 / 79.2** | **66.5** |
| huge | 142.2 | 17.46 | 18.3 | 112.2 / 98.9 | 83.1 |

### 压缩：宽高怎么一起收，`bottomY` 怎么算

一处算，仍在 `TrackerViewModel.updateLayout`，**无 `GeometryReader`**：

```
basePanelWidth = SizeHelper.trackerWidth      // = 记牌器窗口自己的宽度
baseRowHeight  = basePanelWidth / 8.1429
frameHeight    = round(baseRowHeight * 40 / 34)          // 三行头 / 段头一行
offset         = headerHeight + Σ每个可见段(frameHeight + 5)  [+ frameHeight 若预留墓地行]
cardHeight     = min(baseRowHeight, (availableHeight - offset) / totalCards)
barWidth       = cardHeight * 8.1429                      // ← 宽度跟着行高收
```

**三条关系**：

1. **和渲染高度同源**：`contentHeight` 仍由 `TrackerLayout` 的各段高度相加，`bottomY = availableHeight - contentHeight`，
   两边都从这一次算出的 `cardHeight` 来，不存在两套账。
2. **`barWidth` 不参与 `bottomY`**。它只是绘制宽度：`TrackerRootHost` 的 frame 仍是整个窗口宽，
   面板在里面按贴靠边对齐（我方贴右、对手贴左），收缩时缺口开在**内侧**，不会离开屏幕边缘。
   所以压缩只改面板的可见宽度，不改窗口、不改 `bottomY`、不改排序。
3. **tracking area 仍按窗口宽**（`Tracker.getTrackingArea()` 用 `window.frame.width`）。
   压缩时它比可见面板宽出 `窗口宽 − barWidth`，等于对手侧的「链接对手卡组」悬停区在面板左侧多出一条透明带 ——
   **与压缩前的行为一致**（以前窗口宽 = 面板宽，现在多出来的那条是新增的），判定用的是 `y >= bottomY`，横向本来就不设限。
   要收窄得连 `bottomY` 的语义一起改，属于 V2 的鼠标模型那一片，本片没动。

**顺手修了一个既有缺陷**：段的 5pt 段尾留白原来不在 `offset` 预算里，而 `sectionHeight` 里有，
所以只要压缩生效，`contentHeight` 恒比 `availableHeight` 多 `5 × 段数`，**`bottomY` 会变成负数**（分区模式下 −15）。
把 `frameHeight + 5` 一起计入 `offset` 后等式严格成立，新测试 `testZoneSectionsStayInsideTheWindowWhenCompressed` 覆盖。

**算例**（`.big`、我方、三行头 1 行、分区模式牌库 30 / 手牌 10 / 已打出 20）：

| 场景 | 面板宽 | 基准行高 | `frameHeight` | `availableHeight` | `offset` | `cardHeight` | `barWidth` | `contentHeight` | `bottomY` |
|---|---|---|---|---|---|---|---|---|---|
| 1920×1080 全屏，30 张一段 | 170.6 | 20.95 | 25 | 1080 | 55 | **20.95（不压缩）** | **170.6** | 683.6 | 396.4 |
| 1920×1080 全屏，60 张三段 | 170.6 | 20.95 | 25 | 1080 | 115 | 16.08 | 131.0 | 1080.0 | 0.00 |
| 1280×720 窗口，60 张三段 | 113.7 | 13.97 | 16 | 670 | 79 | 9.85 | 80.2 | 670.0 | 0.00 |

第 1 行是重点：**1080p 全屏一整副 30 张牌根本触发不了压缩**，而现状（行高 34）在同样条件下必压。

### 保住的语义现在怎么画

`Card.textColor()` 一行没动，抽 / 在手 / 弃牌的优先级和它们背后的四个 Settings 开关仍归它管；
卡条只把它的「默认白」换成 D2 的羊皮纸白 `#F4EAD4`，其余颜色原样用。

| 语义 | 旧画法 | 现在 |
|---|---|---|
| `isCreated` 礼物 | `icon_created.png`，并把计数框和卡名区一起往左推 | 费用格左上角一枚 6u 金色三角切角。**不占卡名宽度**，所以礼物牌不会因为多个角标就被截断 |
| `count <= 0` / `jousted` 暗条 | 整条盖 `dark.png` | D2 的 `.dim`：原画与卡名 45% 不透明、费用格 55%。（已打出段用负 count，走的就是这条） |
| `highlightInHand` 绿名 | `textColor()` → 绿 | 不变，`textColor()` 直接出色 |
| `highlightDraw` 抽牌 | `textColor()` → 橙 | 不变 |
| `highlightDiscarded` 弃牌 | `textColor()` → 暗红 | 不变 |
| 协同高亮 teal / orange / green | 整条盖 `highlight_*.png` 发光贴图 | 该色 14% 填充 + 1.5u 内描边。**不遮稀有度色和原画**，这是换画法的理由：发光贴图在 21pt 行高上会把整条糊掉 |
| 传说单张 | `icon_legendary.png` | 计数框里一枚 `★`（`#FFB641`），与 ≥2 张时的数字同一个框，位置不跳 |
| 张数 ≥ 2 | `countbox*.png` + ChunkFive 数字 | 20u 黑 50% 框 + 左缘金线 + Belwe 白字；有框时卡名右留白从 8u 变 24u |
| 稀有度 | 框 / 宝石 / 计数框三套 PNG 各 4 张 | 整格费用格着色：普通 `#5A5650` / 稀有 `#3B6B8F` / 史诗 `#9A5F8C` / 传说 `#A8762C`。`Settings.showRarityColors` 关掉时一律普通色（这个开关留着了） |

### 关键决定

1. **面板宽用 `min(宽规则, 高规则)`。** Firestone 实测同时给了 8.9%W 和 1.94%H，16:9 下两者一致。
   取 min 而不是二选一：16:9 结果不变，超宽屏（21:9）不会给出一条 306pt 宽的面板。
2. **行高由面板宽推，不独立取。** 窗口宽度就是面板宽度，行高 = 面板宽 ÷ 8.1429 —— 宽高比因此**无法**被压缩公式破坏，
   这正是 PLAN 2.8 第 3 条要的，`CardBar.ratioHeight` 那个补丁在新路径上没有对应物。
3. **`big` = Firestone 尺寸，不动 `Settings` 默认值。** 见「尺寸表」。
4. **底色改在 SwiftUI 里画，窗口底改透明。** 否则窗口的黑色 × opacity 会在面板下面再垫一层，
   而且它铺满整个窗口高度 —— D2 的「一个底」是指跟着内容高度走的那块。旧路径的 `setOpacity()` 逐字保留。
5. **`TrackerFade` 保住接口、换掉实现。** `SessionRecapView.swift` 不在允许清单里且在用它，
   所以没有删，而是把 `fade.png` 换成程序画的同形状渐变（底色 → 35% 处仍不透明 → 右缘全透）。
   这样「SwiftUI 路径不读任何主题 PNG」和「不碰不许碰的文件」同时成立，也不留死代码。
6. **文字用 SwiftUI `Text` + 投影，不用描边。** 旧的 `CardRowStrokedText` 走 `NSStringDrawingContext.minimumScaleFactor` 缩字保命 ——
   而本片要求「超长省略号截断，不缩字」，两者不能共存。改成 `lineLimit(1) + truncationMode(.tail)`，
   投影用 D2 的 `text-shadow`（黑 90%、2u 模糊、1u 下移）替掉 `strokeWidth`。
7. **段头只做了减法。** 去掉它自己的不透明底是「一个底」的直接要求；字号跟行高收是防挤爆。
   居中、张数、折叠箭头、金字——全是 V2，没碰。

### 发现但按规则没动

1. **战棋随从卡条仍读主题 PNG。** `BattlegroundsCardsGroupView.swift:492-507` 用 `Settings.theme` 拼路径、
   按 `theme == "classic"` 选字体。主题选择器删掉之后它**被冻在 defaults 里的当前值**（本机 `dark`）。
   `Settings.theme` 的声明按任务书保留了，所以不会崩，但「主题退役」在战棋那侧没有落实。
   用户不玩战棋，优先级自定；真要收尾得连 `Themes/Bars/` 资源一起删，那是「收尾」阶段的事。
   同样情况：`UIs/Trackers/TrackerFrame.swift:57`（旧路径，本来就要留）。
2. **`Settings.theme` 的 `theme_token` 通知仍有三个订阅者**（`EditDeck.swift:138`、`DeckManager.swift:111`、`Game.swift:1691`）。
   没有 UI 能再改它，所以这三处从此不会触发。清理归「收尾」。
3. **三行头（T5）的固定列宽没跟着面板变窄重算。** `TrackerHeaderRow` 的中 / 右两列是 `62 * scale` / `76 * scale`，
   `scale = lineHeight / 40`，而 `lineHeight` 走的是**未压缩**的基准行高。
   面板重度压缩时（上表第 3 行 `barWidth` 80.2）两列合计 85pt 会顶满，套牌名那格被挤成 0。
   本片「三行头不动外观」，且这一格的省略号 / 悬停浮层已经排进 V2，所以没动 —— **V2 做三行头时要把列宽改成按 `barWidth` 取比例**。
4. **校验器缺「允许删 key」的开关**，见「验收」。
