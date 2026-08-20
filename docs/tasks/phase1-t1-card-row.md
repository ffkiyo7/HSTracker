# Phase 1 / T1 — SwiftUI 卡行 + 主题图片缓存

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。

Phase 1 要把记牌器渲染从即时模式 `NSView.draw()` 换成 SwiftUI。这是第一块，
**只做一行卡，不接进现有记牌器**，两套渲染并存。

## 要做出什么

放在新目录 `HSTracker/UIs/Trackers/SwiftUI/`：

1. **一个 SwiftUI 视图**，渲染单张卡的卡条。同一张卡 + 同一主题下，与现有 `CardBar`
   **视觉上不可区分**。
2. **主题图片的进程内缓存。**
3. **一个并排比对入口**，把同一张卡的新旧两种渲染画在一起，供人肉逐元素比对。
   Phase 1 后续每一块都要靠它验收，所以它是产物不是脚手架。

参照实现：`HSTracker/UIs/Cards/CardBar.swift`（`draw()` 在 `:295`）与 4 个主题子类
（`ClassicBar` / `DarkBar` / `FrostBar` / `MinimalBar`）。主题资源在 bundle 的
`Resources/Themes/Bars/<themeDir>/`，元素清单见 `ThemeElement.swift`。

## 范围边界

**只做常规对战那条路径**：底图、卡图 tile、fade、countBox + 数量、created 图标、
legendary 图标、frame、gem、费用、卡名、darken 蒙版。

**不做**：战棋相关（battlecry / deathrattle 标签、`battleground_spell`、`coinCost`）、
`editDeck` 与 `hero` 两种 `playerType`、`highlightColor` 闪烁、调度胜率条。
范围外的输入画出范围内的部分即可，不要崩、不要报错。

## 硬性要求

- **行高沿用 `CardSize.swift` 的 5 档常量**，不要自己定义尺寸。
- **每个主题 PNG 整个进程只解码一次。** 现状是 `CardBar.add(themeElement:)`（`:796`）
  每次 draw 都 `NSImage(contentsOfFile:)`，一次记牌器重绘 150~500 次解码 ——
  这是本任务要消灭的具体开销，不是可选的优化。
- **不要移植 `fitFontForSize`（`:697`）那套二分查找试字号**，它每次迭代都跑一遍完整文本排版。
  字号自适应交给框架能力。
- **不要修改任何既有文件**，`CardBar.swift` 和 4 个主题子类一行都不许动 —— 两套渲染必须并存，
  这样才能比对。唯一的例外见下一条。
- **比对入口的挂载点自己选，但不许改 `.xib`**（`_common.md` 第 4 条）。仓库里有两套现成做法：
  `AppDelegate.swift:655` 那个 `#if DEBUG` 调试窗口，或 `LatencyProbe` 那种环境变量开关
  （`HSTracker/Utility/LatencyProbe.swift:18`）。选一个，在报告里说明理由。
  为此修改 `AppDelegate.swift` 是允许的，改动要尽量小。
- **新增的 `.swift` 必须手工登记进 `project.pbxproj`**（`PBXBuildFile` + `PBXFileReference` +
  所属 group + Sources build phase，共 4 处）。**漏登记不会报编译错误**，文件会被静默忽略。
  详见 `AGENTS.md` 的「构建」一节。

## 验收

1. 构建通过。
2. 每个新增文件 `grep -c "<文件名>.swift" HSTracker.xcodeproj/project.pbxproj` 都 ≥ 3。
3. `git diff --stat` 里被修改的既有文件只有 `project.pbxproj` 和（如果你选了它）`AppDelegate.swift`。
4. 比对入口能打开，同一张卡的新旧两版并排显示。

## 报告里请回答

- 缓存在什么时机加载、什么时机失效，用户在设置里切换主题时会发生什么。
- `CardBar` 的哪些行为你决定不复刻，为什么。
- 范围边界之外你注意到、但按规则没有动的问题。
