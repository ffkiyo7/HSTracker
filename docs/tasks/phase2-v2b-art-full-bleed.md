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
