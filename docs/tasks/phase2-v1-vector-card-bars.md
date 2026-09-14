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
