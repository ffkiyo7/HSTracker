# Phase 2 / T2 — 分段视觉统一：段头 + 计数 + 折叠 + 长卡名

先读 `docs/tasks/_common.md`，再读 `docs/tasks/phase2-t1-zone-groups.md`（含执行结果 / review）和
`docs/tasks/bug-t6-zone-sections-stale.md`（**本片排在它之后**，以它落地后的 `TrackerViewModel` 为基线）。
参考：用户 2026-09-15 给的 Firestone 截图（若已存为 `docs/research/assets/firestone-zones-2026-09-15.png` 就看图；否则按下面的文字描述）——
整个面板一个深色半透明底；三段标题「In deck (8)」「In hand (8)」「Other (19)」居中、与卡条同色系字体、右侧一个 ˅ 折叠箭头，**段头没有自己的方块或边框**；
每段张数按副本计；「Other」段的卡条整体压暗并在右侧带状态图标（图标是 2.7，本片不做）。
Firestone 的实测尺寸在 `docs/research/firestone-overlay.md`。

## 现状与用户的判断（2026-09-14 实战反馈 ⑧ ⑩）

- 三段的段头是 T4 按上游 `DeckLens` 逐像素复刻的：`#23272A` 底色独立方块、`#141617` 边框、17×17 放大镜图标、**系统字体**白字左对齐（`TrackerSectionView.swift`）。
  三行头（T5）和卡条用的是主题字体（`TrackerTextFont.name`，classic 为 Belwe），段头和它们不是一套，用户原话「字体和当前整体视觉不符合」。
- 用户要的是 **Firestone 那种统一视觉语言**：整个浮窗一个底色，段头只是底色上的一行居中文字「牌库 (8)」+ 右侧折叠箭头，没有自己的方块；每段带张数；可折叠。
- 我们的底色现状：窗口背景是黑色 × `Settings.trackerOpacity`（`Tracker.setOpacity()`），卡条是主题 PNG 各自带框。**「统一」在我们这边的含义是：段头不再有自己的底色和边框，直接坐在窗口底色上**；卡条本身不动。
- ⑩ 长卡名右侧被遮（例：恶魔猎手「公诉人梅尔特拉尼克斯」）。名字区宽度由 `CardRowView.cardNameRect` 按主题 `frameRect` 减计数框算，缩字靠 `minimumScaleFactor = 0.001`。这是 T1 照 `CardBar` 复刻来的上游行为，但中文长名下不可接受。

## 要做出什么

1. **段头**：所有带段头的段（牌库 / 手牌 / 已打出 / 置顶 / 置底 / 相关牌）用同一个新段头：透明底、标题居中、文字用 `TrackerTextFont.name`、右侧折叠箭头；高度与卡条行高同一量级（Firestone 段头 ≈ 卡条高，见 `firestone-overlay.md` 第七节）。旧 `DeckLens` 视觉在 SwiftUI 路径下不再出现。
2. **计数**：标题带该段张数，按 **副本数**算（`abs(count)` 求和，不是行数），与 T1 的不变式同一口径。
3. **折叠**：每段可折叠，折叠后只剩段头；状态按段持久化（重启后保持）。**已知坑**：锁定时浮窗 `ignoresMouseEvents = true`（`OverWindowController.swift:50`），点不到箭头。折叠手势在锁定态下怎么触发（解锁才可点 / 悬停 + 键 / 别的）由你定，报告里给结论和理由，**不许为此把锁定态的窗口改成接收鼠标事件**——那会挡住游戏里的点击。
4. **长卡名**：名字必须完整可读或以省略号截断，不能被右侧计数框 / 原画遮住。缩字下限、省略策略由你定，但 T1 的「与 `CardBar` 逐像素一致」在**这一点上放开**，其它外观仍不变。

## 硬约束

- 排版仍由 `TrackerViewModel.updateLayout` 一处算，折叠段的高度进 `TrackerLayout`，`Tracker.bottomY` 与渲染高度同源，无 `GeometryReader`；压缩公式里折叠段的卡不计入 `totalCards`。
- 一次刷新不重建视图树；折叠 / 展开用条件视图。
- 平铺路径、旧路径一行不动；`useSwiftUITracker` 为 false 时逐字回现状。
- 三行头（T5）的字体 / 底图不动，本片只让段头向它靠。
- 新文案走 `Localizable.xcstrings`（只加新 key，过校验器 `--allow-new-key`）；折叠状态的 Settings key 照 `group_cards_by_zone` 的写法。
- 不做动效（T8）、不做 2.7 状态图标、不做 2.8 尺寸 / 贴图矢量化。

## 允许修改的文件

- `HSTracker/UIs/Trackers/SwiftUI/` 下已有文件；新增文件登记 pbxproj 4 处
- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/Core/Settings.swift`
- `Translations/macOS/Localizable.xcstrings`（只加新 key）
- `HSTrackerTests/`（新增或扩展布局测试：折叠段高度、计数口径）

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；测试全绿（基线以 Bug T6 落地后的条数为准）+ 本片新增。
2. 报告里：段头的最终参数（高度、字号、箭头样式）、折叠手势方案与理由、长卡名的截断策略、每段高度对照表（含一段折叠时）。
3. 🎮 由用户看：段头与三行头 / 卡条是否一套、计数对不对、折叠、「公诉人梅尔特拉尼克斯」完整可读。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。
