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
