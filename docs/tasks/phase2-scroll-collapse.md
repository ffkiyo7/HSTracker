# Phase 2 — 记牌器固定行高 + 滚动、段头折叠

先读 `docs/tasks/_common.md`，再读 `docs/PLAN.md`（「仍作数的决策」里 T8 那条、「已知问题」）、
`docs/archive/tasks/phase1-t8-tracker-motion.md`（T8 的约束和判定）、`docs/archive/tasks/refork-s4-panel-on-canvas.md`（分区块怎么放进上游面板）。
本片只做两件事：**A 放不下时改成固定行高 + 滚动**，**B 段头折叠**。拖拽吸附、套牌名悬停、平铺模式（`group_cards_by_zone` 关）都不在本片。

## 用户已定（2026-10-08）

| 问题 | 定了什么 |
|---|---|
| 放不下时 | 滚动，不截断 |
| 滚什么 | 三行头固定，下面的卡段一起滚 |
| 抽牌 / 出牌刷新后 | 保持滚动位置，内容变短时夹回合法范围 |
| 哪一侧 | 两侧，同一套代码 |
| 还有内容的提示 | 视口底边淡出 |
| 段头箭头 | 要能点着折叠 / 展开（用户 10-08 报「坏了」，实际从 V2a 起就只画不点，见「现状」） |

规划方另外替你定了三条默认。有理由可以推翻，但要在报告里写清楚：

1. 折叠状态按「哪一侧 × 哪一段」存 UserDefaults，跨局、重启都保留，默认全展开。
2. 解锁（摆位置）时箭头不响应，和解锁时不弹悬停预览一致（`RootOverlayWindow.swift:116`）。
3. 已经向下滚过时，顶边也淡出（「底边淡出」的对称处理）。

## 现状（`origin/dev0923` `35a783f6`）

- **压缩**：`TrackerViewModel.updateLayout` 把所有行挤进盒子（`TrackerViewModel.swift:199-206`，`cardHeight = max(min(base, (availableHeight - offset) / totalCards), 1)`）。V1 让宽度跟着缩（`:206`），三行头列宽也跟着缩（`:244-248`）。
- **盒子**：`TrackerPanelZone.swift:146` 的 `relayoutZonePanel` 排分区块，分区块那一节的高 = `zone.layout.contentHeight`（`:177-182`）；盒高是上游的 `PlayerStackHeight`（`zoneBoxHeight`，`:199`）。面板自上而下：对手英雄条（若有）→ 分区块 → 竞技场包 lens → Godfrey lens（`zonePlan`，`:206-238`），后两者和分区块共用行高。
- **绘制**：`TrackerView.swift` 用一个 `VStack` 叠三行头和各段；`TrackerZonePanelStack`（`TrackerPanelZone.swift:289`）把它放进面板。
- **箭头**：`TrackerSectionView.swift:49-52` 的注释写明「只画，折叠手势是后续片」，`:77-83` 画 `TrackerChevron`。没有点击处理，也没有折叠状态，`dev` 和 `dev0923` 都没有。
- **点击**：画布默认穿透。子视图通过 `InteractiveRegionPreferenceKey`（`RootOverlayView.swift:16`）报矩形，光标进去时 `RootOverlayWindow.updateClickThrough`（`:140`）才关掉穿透。锁定的记牌器一块都不报（`TrackerPanelView.swift:105-122`），所以点箭头直接落到炉石。先例：`ConstructedMulliganPreLobbyWidgetView.swift:55` 用 `GeometryReader` + `.rootOverlayCanvas` 报自己的框。解锁时 `movableBox`（`TrackerPanelView.swift:46-47`、`:165`）整块盖在面板上，拖动手势会先吃掉点击。
- **悬停**：每行的 `TrackerCardRowHitArea`（`TrackerCardListView.swift:87-110`）用 `GeometryReader` 报 `TrackerRowHoverKey`，`RootOverlayWindow.updateTrackerRowHover`（`:394`）取最后一个包含光标的矩形。`.clipped()` 只裁画面，拦不住这个 preference。
- **滚轮**：记牌器代码里没有任何 `scrollWheel` / `ScrollView`。画布穿透，滚轮事件到炉石。
- **T8**：`TrackerMotion.layoutCanAnimate`（`TrackerMotion.swift:121`）要求行高、宽度、三行头高不变，且每段高的变化不超过一行 + 段头。PLAN「仍作数的决策」：行高不动画、压缩态一律瞬切。

## 要做出什么

### A. 固定行高 + 滚动

1. **不再压缩**：分区块的行高恒为 `TrackerMetrics.rowHeight(panelWidth:)`，`barWidth` 恒为面板宽，三行头列宽同理。分区块下方的两个 lens 也用这个行高。上游平铺路径（`TrackerPanelLayout.init` 的非分区分支、`CardTileListView`）一行不动。
2. **视口**：三行头（以及它上面的对手英雄条）不动；其下所有卡段（置顶 / 主列表 / 牌库 / 手牌 / 已打出 / 置底 / 相关）放进一个裁剪视口，整体滚。视口高 = 盒高 − 英雄条 − 三行头 − 分区块下方的 lens；分区块那一节报给面板的高 = 三行头 + 视口高，不再是整个内容高。lens 多到视口不足 3 行时怎么让，由你定，写进报告。内容放得下时和今天未压缩时完全一样：不淡出、不响应滚轮。
3. **位置**：每侧一个滚动位置，放在 `TrackerViewModel`，范围 `[0, 内容高 − 视口高]`。刷新后保持；内容变短、视口变高（拖盒子、改缩放）时夹回范围；新一局（`update(... reset: true)`）归 0。夹位置和 `layout` 在同一个主线程 block 里提交。
4. **滚轮**：在 `RootOverlayWindow` 照 `installMouseMonitors`（`:59`）里 mouseMoved 的两个监视器，加 `.scrollWheel` 的全局 + 本地监视器。光标在哪一侧的视口里才改哪一侧，别处一律不管。全局监视器吞不掉事件；炉石对局里不用滚轮，不必处理。`hasPreciseScrollingDeltas` 为真（触控板）时按点数滚，为假（鼠标滚轮）时一格滚整行，步长写进报告。锁定、解锁都能滚。视口矩形怎么报给窗口由你定，现成的路是 `HoverRegion`（`RootOverlayView.swift:42` / `:67`），每侧一个 id。
5. **淡出**：下面还有内容时，视口底边淡出约一行高；已向下滚时顶边同样淡出（默认 3）。只作用在视口这一小块，用 `.mask` 渐变或底色渐变叠层都行，报告写选了哪个。**不得**新增全画布的 `mask` / `compositingGroup`：画布已经有一层常驻遮罩（`RootOverlayView.swift:630`），之后的 GPU 优化要拿掉它，别再加一层。
6. **悬停**：被滚出视口的行，和只露出一部分的行露在外面的部分，都不能弹预览。命中矩形要裁到视口，在行里裁还是在窗口匹配时裁都行。内容用 `.offset` 移还是改布局由你定，但要用测试证明 `TrackerRowHoverKey` 报出的矩形跟着滚动走。面板本身就是 `.scaleEffect` + `.offset` 摆上去的（`TrackerPanelView.swift:153-154`），行悬停在新线上是对的，说明里面的读数看得到外层的变换；但以测试为准，别凭注释推断。
7. **T8**：行高不再变，刷新照旧走 `layoutCanAnimate`，不改它的判据。滚动本身不加动画。动画中的行不能因为夹位置而飞出或飞进视口；做不到就让夹位置的那次刷新不动画，报告写明。

### B. 段头折叠

1. 点段头右侧的箭头格（`TrackerBarStyle.sectionSideColumn` 那一列，22 u 见方）切换该段折叠。折叠后只剩段头，张数照常显示，箭头从 ˅ 转成 ›。段头下那 5 点留白留不留由你定，写进报告。
2. 两侧所有用 `TrackerSectionView` 的段都能折。
3. **点击路径**：箭头格自己报 `InteractiveRegionPreferenceKey`，坐标取 `.rootOverlayCanvas`，锁定时也报；面板其余像素保持穿透。段头被滚出视口时不报，解锁时不报（默认 2）。
4. 点完炉石仍在前台、键盘照常（🎮 看）。如果抢了焦点，报告写清现象，别为此改窗口层级或 styleMask。
5. 折叠 / 展开瞬切，不走 T8：段高一次变多行，`layoutCanAnimate` 自然判否；用测试锁住切换时 `motionGeneration` 不变。
6. 折叠的段不计入滚动内容高；折叠让内容变短时，位置照 A3 夹回。
7. **持久化**：新键加进 `Settings.swift`，照现有 `@UserDefault` 的写法，键名列进报告（之后进 PLAN「与上游的默认值差异」）。不进设置页。

## 硬约束

- 平铺模式，以及上游 `CardTileListView` / `TrackerDeckLensView` 的内部不动。
- 写 view model 一律在主线程，同一份状态在同一个 main block 里提交（`AGENTS.md`「线程与时序」）；监视器回调也要先确认在主线程。
- `TrackerCardRow` 的 id / `Equatable`、`CardRowView` 的 `.equatable()` 不变；一次刷新不重建视图树；行位图缓存（`TrackerRowRaster`）的键不变。
- 不加全画布遮罩或合成层（A5）。`RootOverlayWindow` 只加滚轮监视器和视口匹配，不动穿透、悬停、棋盘那几段逻辑。
- 最好不新增 `.swift`；要加就按 `AGENTS.md` 手工登记 4 处。不动 `.xcstrings`（本片没有新文案）。

## 允许修改的文件

- `HSTracker/UIs/Trackers/SwiftUI/TrackerViewModel.swift`、`TrackerView.swift`、`TrackerSectionView.swift`、`TrackerCardListView.swift`、`TrackerCardListViewModel.swift`、`TrackerPanelZone.swift`、`TrackerBarStyle.swift`
- `HSTracker/UIs/Overlay/Trackers/TrackerPanelView.swift`：只准动分区面板的交互区 / 悬停区
- `HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift`：只准加滚轮监视器和视口匹配
- `HSTracker/UIs/Overlay/Root/RootOverlayViewModel.swift`、`RootOverlayView.swift`：只在把滚动转给两侧面板确实需要时动，改动最小
- `HSTracker/Core/Settings.swift`：只加折叠状态的键
- `HSTrackerTests/TrackerMetricsTests.swift`

## 测试

`_common.md` 不许为变绿改期望。**本书明确授权**改写下面六条，因为它们锁的正是本片要取消的压缩：

| 测试 | 改成锁什么 |
|---|---|
| `testCompressionKeepsTheAspect` | 放不下时行高 = 基准行高，`barWidth` = 面板宽 |
| `testContentFitsTheAvailableHeight` | 放不下时三行头 + 视口 ≤ 盒高，最大滚动 = 内容高 − 视口高 |
| `testZoneSectionsStayInsideTheWindowWhenCompressed` | 同上，30 / 10 / 20 张三段 + 段头 |
| `testCompressedPanelNarrowsTheHeaderColumns` | 放不下时 `header.barWidth` 仍 = 面板宽 |
| `testACompressedPanelNeverFliesThroughAGridChange` | 放不下的面板上抽一张：栅格不动，照常动画（`motionGeneration` + 1） |
| `testTheRefreshThatCrossesTheCompressionThresholdIsOneFrame` | 从刚好放下到放不下的那次刷新：栅格不动，行不飞 |

其余测试的期望一条不改（`testAnUncompressedPanelStillAnimatesTheSameRefresh` 留着当对照）。新增测试至少覆盖：

- 内容变短后位置夹回；`reset` 归 0；
- 折叠的段高 = 段头（± 留白），切换不加 `motionGeneration`；
- 滚出视口的行不报命中矩形，或报的矩形已裁到视口；
- 锁定时箭头报交互区，解锁或段头滚出视口时不报。

## 验收

1. Debug `BUILD SUCCEEDED`；全套测试只允许 PLAN 里记着的两条老失败（签名、`LocalizationFormatTests`），条数写实。
2. 报告给出：
   - 新的高度公式：视口高、分区块那一节的高、最大滚动；
   - 1920×1080、`.big`、默认盒高下两种情况是否放不下、视口高、最大滚动：开局 30 张分三段（20 / 6 / 4），长局（牌库 10 / 手牌 8 / 已打出 25）；
   - 滚轮步长（鼠标一格、触控板）和方向的取法；
   - 命中矩形裁剪、箭头交互区、淡出各自的实现点（文件:行）；
   - 默认 1–3 有没有推翻、为什么；持久化键名。
3. 🎮 用户看（两侧都看）：长局已打出段变长后行高不变、滚轮能滚、底边淡出；抽牌 / 出牌后位置不跳；点箭头折叠 / 展开，炉石不失焦；滚出视口的行不弹预览；拖盒子变高后位置合理。

## 汇报

结果写进本文件末尾「执行结果」一节，格式照 `docs/archive/tasks/phase2-v2a-header-section-restyle.md`。
**不要 commit，不要动 `docs/PLAN.md`。**
