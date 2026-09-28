# Phase 2 / V2b — 原画铺满卡条，左暗右亮（D3-b）

先读 `docs/tasks/_common.md`、`docs/tasks/phase2-v1-vector-card-bars.md`（原画区 / 渐隐现状与 `TrackerFade`），
对照页 <https://claude.ai/artifact/M9QKUWFUAEF3H5RQ7kiRey> 顶部「D3-b 渐变到 75%」那一栏（2× 渲染；源码里 `.D` / `.D.fe75` 两条 CSS 是精确数值）。
**用户 2026-09-16 定稿 D3-b。** 本片只动卡条的原画几何和渐变；三行头 / 段头 / 卡名颜色是 V2a，别越界。

## 现状

- V1：原画区 = 行宽 × `artFraction`（100/171），贴右；上面盖 `TrackerFade`（底色实心 0–35%，35–100% 线性到透明）。
  实机里肉眼只剩约 65 u 原画（38% 行宽），用户嫌少。
- 瓦片仍是 `tiles/<id>.jpg`（256×59）。

## 要做出什么

1. 原画区从**费用格右缘（22 u）铺到卡条右端**（1920×1080 下 149 u），cover 裁切居中：149:21 比 256:59 更扁，纵向多裁、横向铺满，**不放大**。
2. 渐变改为：从原画区左缘起，底色 `#1B1410` **实心 0–10%**，线性到 **75% 处全透**，其后原画全亮。
   渐变的 alpha 随 `Settings.trackerOpacity` 的语义走：底色乘 `TrackerMetrics.baseOpacity`（已有），渐变层跟面板底同一套不透明度，不能出现「面板半透、渐变全实」的两层色。
3. 卡名投影加重：`0 1u 2u @.95` + `0 0 4u @.8`（对照页 `.D .row .name`），因为后半段可能压在原画上。
4. 计数框（20 u，黑 50%）、费用格、created 角标、协同高亮描边、暗条、`.dim` 45% 全部不动；计数框仍盖在原画上。
5. `TrackerBarStyle.artFraction` / `artFadeFraction` / `TrackerFade.startFraction` / `opaqueFraction` 四个常量：
   改名或改值都行，但 V1 测试里引用它们的地方要一起改，**不留一个名字和实际含义相反的常量**。

## 硬约束

- 旧路径一行不动。
- 会话回顾窗复用 `TrackerFade`（V1 注释写明），改完它也要对（不挤爆、渐变方向不反）。
- 一次刷新不重建视图树；瓦片异步加载 + LRU 沿用。
- **不动 `HSTracker/Logging/Entity.swift`、`Player.swift`、`Parsers/TagChangeActions.swift`、
  `HSTrackerTests/CardZoneGroupsTests.swift`、`ZoneGroupsReplayTests.swift`**（Bug T8 未提交改动，另一条线）。
- 若 V2a 已先落地，在它之上改，不要回退它任何一行。

## 允许修改的文件

- `HSTracker/UIs/Trackers/SwiftUI/CardRowView.swift`、`TrackerBarStyle.swift`
- `HSTrackerTests/TrackerMetricsTests.swift`

## 验收

1. Debug build `BUILD SUCCEEDED`；测试全绿。
2. 报告里给出：1920×1080 / 2560×1440 / 1280×720 下原画区起点 / 宽度、实心段与全透点的绝对 u 值；
   瓦片 cover 后的缩放比与纵向裁掉的像素数；`trackerOpacity` = 0 / 60 / 100 三档下面板底与渐变层各自的 alpha。
3. 🎮 用户看：原画从费用格右边一路到底，左暗右亮，「公诉人梅尔特拉尼克斯」这种长名仍可读。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`。**

## 执行结果（2026-09-17，在 V2a 之上）

### 改动清单

| 文件 | 做了什么 |
|---|---|
| `SwiftUI/TrackerBarStyle.swift` | **删掉** `artFraction`（100/171）和 `artFadeFraction`（0.35）；换成 `artSolidFraction = 0.10` / `artClearFraction = 0.75`（注释写明这两个是**原画区**的比例，不是卡条的）；新增 `nameShadowNear = 2` / `nameShadowFar = 4`。`TrackerFade.startFraction` / `opaqueFraction` 不再从卡条常量推导，改成会话回顾窗自己的字面值，注释写明「卡条已经不用它了」 |
| `SwiftUI/CardRowView.swift` | `artWidth` 从 `barWidth × 100/171` 改成 `barWidth − costWidth`（= 149 u）；渐变四停改成 D3-b；新增 `baseOpacity` 属性与 `shade` 计算属性，渐变底色跟着面板不透明度走；卡名投影从单层 `0 1u 2u @.9` 改成 `0 1u 2u @.95` + `0 0 4u @.8` |
| `HSTrackerTests/TrackerMetricsTests.swift` | 新增 4 条测试 |

费用格、计数框、created 角标、协同高亮、暗条、`.dim` 45% / 55%：**一个字节没动**。计数框仍盖在原画上（`ZStack` 顺序没变）。

### 验收

- Debug build（`-derivedDataPath …/scratchpad/DerivedData-v2`）：**BUILD SUCCEEDED**
- test：**执行 122 条，121 过 1 败**（V2a 之后的 118 + 本片 4）。新增的是
  `testArtStripSpansEverythingRightOfTheCostCell` / `testD3bFadeStopsMatchTheSheet` /
  `testSessionRecapFadeIsIndependentOfTheCardRow` / `testArtShadeCarriesThePanelOpacity`，四条全过。
- **那一败是 `SecretTests.testSingleSecret_OneMinionDied`，与本片无关的 flaky。**
  报错是 `Asynchronous wait failed: Exceeded timeout of 2.05 seconds`（`SecretTests.swift:196`），
  不是断言不成立。证据两条：① V2a 那轮同一份代码路径下 118 / 118 全绿，`SecretTests` 那 33 条当时也全过；
  ② 单独重跑 `-only-testing:HSTrackerTests/SecretTests` → **33 / 33 全绿，TEST SUCCEEDED**。
  奥秘判定和记牌器绘制没有任何调用关系，本片也没碰过它涉及的任何文件。

### 原画区几何（`.big` 档，未压缩；单位 pt，括号里是参考像素 u）

| 窗口 | 面板宽 | 行高 | 原画起点（费用格右缘） | 原画宽 | 实心段到 | 全透点 |
|---|---|---|---|---|---|---|
| 1920×1080 | 170.61 | 20.95 | **21.95**（22 u） | **148.66**（149 u） | 36.82（36.9 u） | **133.44**（133.75 u） |
| 2560×1440 | 227.48 | 27.94 | **29.27**（22 u） | **198.21**（149 u） | 49.09（36.9 u） | **177.93**（133.75 u） |
| 1280×720 | 113.74 | 13.97 | **14.63**（22 u） | **99.11**（149 u） | 24.54（36.9 u） | **88.96**（133.75 u） |

绝对 u 值（三档一致，因为几何全按 u 定义）：原画区 `[22, 171]`，实心段 `[22, 36.9]`，
`36.9 → 133.75` 线性到全透，`[133.75, 171]` 原画全亮 —— 也就是**卡条右端 37.25 u（21.8%）完全不盖底色**。
对照 D2：原画区 `[71, 171]`，实心 `[71, 106]`，肉眼可见原画只有 `[106, 171]` = 65 u（38% 行宽）。
D3-b 的可见原画是 `36.9 → 171` 共 **134.1 u（78% 行宽）**，其中 37.25 u 全亮。

### 瓦片 cover：缩放比与纵向裁掉的像素

瓦片 256 × 59。目标 149 : 21 比 256 : 59 扁，所以 `contentMode: .fill` 取的是**宽度**这一边：

| 窗口 | 缩放比 | 缩放后高 | 纵向裁掉（pt） | 纵向裁掉（源像素） |
|---|---|---|---|---|
| 1920×1080 | 0.5807 | 34.26 | 13.31 | **22.92** |
| 2560×1440 | 0.7743 | 45.68 | 17.75 | **22.92** |
| 1280×720 | 0.3871 | 22.84 | 8.87 | **22.92** |

源像素裁掉的量三档相同，因为目标比例恒为 149 : 21：`59 − 256 × 21 / 149 = 22.92`，
即**上下各裁 11.46 px，用掉 59 行里的 36.08 行（61%）**。
对照 D2（原画区 100 u）：缩放比 0.3897，只裁 5.24 源像素。D3-b 纵向裁得多是任务书预告过的代价。

**三档缩放比都 < 1，不放大。** 上限出现在 `huge` 档 + 2560×1440：面板 284.3、原画 247.7、缩放比 0.968，仍不到 1。
真要放大得面板宽超过 256 / (149/171) ≈ 294 pt，那要 3440 宽以上的窗口配 `huge`；
代码用的是 `.fill`（标准 cover），到那一步会照 cover 的规矩放大，没有额外的封顶 —— 见「待用户确认」。

### `trackerOpacity` 三档下两层的 alpha

`TrackerMetrics.baseOpacity(setting:)` 把「0 = 未设置 = 画满」这条既有语义原样保留：

| `tracker_opacity` | 面板底 alpha（`TrackerView`） | 渐变实心段 alpha（`CardRowView.shade`） | 两层是否同值 |
|---|---|---|---|
| 0（默认 / 未设置） | 1.00 | 1.00 | ✅ |
| 60 | 0.60 | 0.60 | ✅ |
| 100 | 1.00 | 1.00 | ✅ |

两边都走同一个函数、同一个 `Settings.trackerOpacity`，所以「面板半透、渐变全实」的两层色不可能出现。
V1 里渐变用的是 alpha 恒为 1 的 `TrackerBarStyle.base`，在 60 那一档就是两层色，本片修掉了。

### 关键决定

1. **`artFraction` / `artFadeFraction` 删掉而不是改值。** 新几何里「原画占卡条的比例」这个概念本身没了
   （起点由费用格决定，终点是卡条右端），留着这个名字必然词不达意。两个新常量的注释里点明
   「是原画区的比例，不是卡条的」，因为 0.10 / 0.75 和旧的 0.35 分母不同，最容易读错的就是这里。
2. **`TrackerFade` 的两个常量改成字面值，名字不动。** 它们现在只有 `SessionRecapView` 在用，
   而那个文件不在允许清单里 —— 改名会编译不过。好在 `startFraction`（阴影带从哪开始）和
   `opaqueFraction`（渐变里还平的那一段占多少）对**会话回顾窗**仍然字字属实，不构成「名字和实际含义相反」。
   V2a 已经把三行头从 `TrackerFade` 上摘下来了，所以现在它的唯一消费者就是回顾窗，方向、宽度、挤爆风险都没变。
3. **`baseOpacity` 做成 `CardRowView` 的属性、默认值读 `Settings`。** 和它旁边的
   `showRarityColors: Bool = Settings.showRarityColors` 是同一个写法。走属性而不是在 `body` 里直接读 `Settings`，
   是为了让它参与 `CardRowView` 的结构比较：`Tracker.setOpacity()` 触发重排 → `TrackerView` body 重跑 →
   行被重建时默认值重新求值 → 新旧 `CardRowView` 不相等 → 重绘。直接在 `body` 里读的话，
   SwiftUI 可能因为「行的存储属性一个没变」而跳过重绘。`TrackerCardListView` / `TrackerCardListViewModel`
   不在本片允许清单里，所以没走「view model 加一个 `@Published opacity`」那条更正统的路 —— 见「待用户确认」。
4. **投影用两层 `.shadow`，radius 直接照 CSS 的 blur 取值。** 沿用 V1 的换算惯例（V1 把 `0 1 2 @.9`
   写成 `radius: 2 * u, y: u`），本片只是把它升成 `0 1u 2u @.95` + `0 0 4u @.8` 两层，没有另起一套换算。
5. **原画仍用 `.frame(width: barWidth, alignment: .trailing)` 定位。** `artWidth = barWidth − costWidth`，
   贴右等价于「左缘正好落在费用格右缘」，比再算一次 offset 少一处可以对不上的地方。

### 待用户确认

1. **超大面板下 cover 会放大瓦片。** 见上表下方那段：面板宽超过约 294 pt（3440 宽窗口 + `huge` 档）时
   256 px 的瓦片不够铺，`.fill` 会按 cover 放大，糊一点。任务书写的是「不放大」，
   但那是对 149:21 与 256:59 两个比例的描述，不是一条要写进代码的封顶规则，所以我没加封顶
   （加了的话超宽面板右侧会露出面板底色，更难看）。要封的话说一声。
2. **`baseOpacity` 走的是默认参数而不是 view model。** 见「关键决定 3」。
   如果你更想要「`TrackerCardListViewModel` 加一个 `@Published var opacity`、由 `updateLayout` 灌进来」，
   那是两行的事，但要动 `TrackerCardListViewModel.swift` / `TrackerCardListView.swift`，两个都不在本片清单里。

### 发现但按规则没动

1. **`CardRowView` 现在直接读 `Settings.trackerOpacity`，这是它第二处直接读 `Settings`**（第一处是 `showRarityColors`，
   但那一处实际上被 `TrackerCardListView` 用 view model 的值覆盖了，默认值只在预览 / 测试里生效）。
   见「待用户确认 2」。
2. V2a 报过的几条（`TrackerCardListViewModel.sectionHeaderHeight` 默认值 40、`HeaderStyle` 里只剩回顾窗在用的两个常量）
   本片同样没碰。
3. **`SecretTests.testSingleSecret_OneMinionDied` 的 2.05 s 异步等待偏紧**，整包跑时会偶发超时（见「验收」）。
   属于测试自身的稳定性问题，不在本片范围内。
