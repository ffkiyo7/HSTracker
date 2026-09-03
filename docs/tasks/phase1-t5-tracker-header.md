# Phase 1 / T5 — 顶部信息区重做（Firestone 三行头）

先读 `docs/tasks/_common.md`，再读 `docs/PLAN.md` Phase 1 一节和 **2.4**。
本片是 Phase 1 切片表的 **T5**，对应实测卡点 ②。

## 要做出什么

`Settings.useSwiftUITracker` 为 true 时，记牌器顶部换成一个 SwiftUI 视图 `TrackerHeaderView`
（文件名沿用 PLAN「目录结构」表），取代现有的四个顶部面板：

| 现有组件 | outlet（`Tracker.swift:17-23`） |
|---|---|
| 手牌数 / 牌库数 | `cardCounter` |
| 抽卡概率 | `playerDrawChance` / `opponentDrawChance` |
| 胜负比 | `recordTracker` |
| 坟场计数 | `graveyardCounter` |

我方侧三行（PLAN 2.4 的样式）：

```
第 1 行   套牌名称          手牌数  牌库数
第 2 行   套牌胜率     58.7%      27 / 19
第 3 行   对阵 <对方职业>  62.5%   10 / 6
```

对手侧只保留第 1 行的手牌数 / 牌库数；hero 卡条（`playerClass`）不动。

## 数据来源

- 手牌数 / 牌库数：沿用现在喂给 `cardCounter` 的 `deckCount` / `handCount`，只换呈现。
- 第 2 / 3 行：`StatsHelper.getDeckRecord(deck:againstClass:mode:)`（`StatsHelper.swift:228`），
  第 2 行传 `.neutral`，第 3 行传对手职业。
- 套牌名称受 `Settings.showDeckNameInTracker` 控制。
- 第 3 行依赖已知对手职业：开局前整行隐藏或显示占位，两者选一并在报告里说明。

## 硬约束

- **开关为 false 时逐字回到现状。** 旧面板的删除留到「收尾」阶段，本片只让它们在开关打开时不显示、不参与排版。
- **挂载方式沿用 T2 / T4 的套路**（`NSHostingView` 作为兄弟视图加进 `contentView`，按开关互相让位），不要另发明一种。
- **高度由 `Tracker.updateFrames()` 传入**，新视图不许自己决定高度，也不许让 SwiftUI 自适应布局改动它。
  被替换的四个面板在 `updateFrames()` 里各占一段高度，新视图占的高度要和实际画出来的行数一致，差一行下面所有段全串位。
- **一次刷新不许重建视图树**（PLAN 1.3）。胜率查询走 Realm，**不许每帧查**，只在套牌 / 对手职业 / 对局结束变化时刷新，报告里论证。
- 新视图必须透明；整体不透明度涂在 window 背景上（`Tracker.swift:113`）。
- 现有开关继续生效：`showPlayerCardCount` / `showOpponentCardCount` / `showWinLossRatio` / `showDeckNameInTracker`。
  `showPlayerDrawChance` / `showOpponentDrawChance` / `showPlayerGraveyard` / `showOpponentGraveyard` / `fatigueIndicator`
  在新路径下不再有对应 UI，**设置项本身不动**，Phase 4 做设置界面时统一处理。
- 不做动效；不许改 `.xib`、`CardCounter.swift`、`PlayerDrawChance.swift`、`StringTracker.swift`、`GraveyardCounter.swift`。
- 不许动刷新路径的结构、投递顺序、防抖参数（T6b 已结案，「合并 18 次投递」另有立项）。
- 不许动 `Player.swift` / `Game.swift`。

## 允许修改的文件

- `HSTracker/UIs/Trackers/Tracker.swift`
- `HSTracker/UIs/Trackers/SwiftUI/` 下已有文件（仅在为复用而必须重构时，报告里说明）
- 新增 `.swift` 文件，**必须手工登记进 `project.pbxproj`**（4 处，见 `AGENTS.md`「构建」）；只允许这一类 pbxproj 改动

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令见 `docs/archive/tasks/bug-t5-tracker-visibility-consistency.md`「验收」）。
2. 测试 target 仍 50 / 50 全绿：同一命令把 `build` 换成 `test`。
3. 报告里给出：新视图在 `updateFrames()` 里占的高度怎么算、与旧四面板之和的差异；胜率何时刷新；开关关掉后哪些代码路径被走到。
4. 🎮 卡点 ② 由用户实战看：手牌数 / 牌库数 / 总胜率 / 对阵职业胜率四个数对不对，开局前第 3 行的状态。**不排在本次验收里，与 Phase 4 一起验。**

## 执行结果（2026-09-03）

- 新头部高度是 `smallFrameHeight × 行数`：对手在 `showOpponentCardCount` 打开时为一行；我方为一行计数、两行（加总胜率）或三行（已知对手职业后再加对阵胜率）。旧路径仍按原来各面板的条件高度计算；关闭 `useSwiftUITracker` 时，SwiftUI host 清零隐藏，`cardCounter`、抽卡概率、胜负比和坟场计数恢复原来路径和排版。
- 胜率缓存键为卡组 ID 与对手职业；只在这两项变化、对局结束状态翻转或带 `reset` 的刷新时重新从 Realm 取卡组并查询。普通 `updateFrames()` 只提交已有 view model 数据，不做 Realm 查询。
- 我方卡组名继续由未改动的 hero 卡条显示，三行头不重复它；`showDeckNameInTracker` 在 SwiftUI 路径也仍控制该卡条。
- 受限环境 Debug build：`BUILD SUCCEEDED`；测试：50 / 50 通过。实际数字和开局前第三行仍按任务书留待实战验收。

## 定稿（2026-09-04，用户实机看过第一版后重新设计）

第一版是裸文字，用户否掉。经三轮比稿（对照页：https://claude.ai/code/artifact/17cd53de-24f0-45fc-9350-a20856ceae3b）定为 **D2**：

- **排版照 Firestone**：三行 × 三列表格。左列标签、中列百分比、右列胜 / 负；列宽 `1fr / 62 / 76`（按 `smallFrameHeight / 40` 缩放），格线 `white 18%`。
  - 行 1：职业图标 + 套牌名 ｜ 手牌数 ｜ 牌库数
  - 行 2：套牌胜率 ｜ 58.7% ｜ 27 / 19（胜绿 `#62D97A`、负红 `#FF6B5E`）
  - 行 3：vs 〔对手职业图标〕职业名 ｜ 62.5% ｜ 10 / 6（图标放在 vs 之后，放前面有歧义）
- **底是英雄皮肤原画**：`ImageUtils.art`（256×256 方图，`v1/256x/<id>.jpg`），左深右浅压暗 `rgba(12,11,9) 0.95 → 0.9 → 0.4`，和卡条 `fade.png` 同向。皮肤 ID 两条路径都现成：开局前 `Deck.heroId`（HearthMirror 读的收藏皮肤），对局中 `player.hero.cardId`。
- **去掉我方 hero 卡条**：面板行 1 已承担套牌名和英雄身份，`playerClass` 在 SwiftUI 路径下我方恒隐藏（对手侧不动）。
- **字体**：中文走 `TrackerTextFont.name`（= 卡条同款，简中为文鼎中隶）；数字用 **Belwe Bd BT**（炉石卡牌字体，仓库已打包）。ChunkFive 与隶书不搭，被否。
- **职业图标**：仓库自带 `Classes.xcassets/<class>.png`，22px。
- 对手侧暂不重做，仍只有手牌 / 牌库一行。

## 执行结果（2026-09-04，Claude 实现定稿）

- `TrackerHeaderView.swift` 重写为上面的三行表格 + 原画底；原画只在 hero id 变化时拉一次，过期回调按 id 丢弃。
- `CardRowView.swift` 暴露 `TrackerTextFont.name`（`ThemeBarLayout` 是 private，加一个只读入口）。
- `Tracker.swift`：给 header 传套牌名 / 职业 / 皮肤 id；SwiftUI 路径下我方 `playerClass` 恒隐藏。
- `Localizable.xcstrings` 新增 `Deck win rate`（套牌胜率）、`vs`。
- 受限环境 Debug build `BUILD SUCCEEDED`；测试见 PROGRESS。
- 🎮 仍待实战：四个数字、开局前第 3 行、原画压暗后右侧数字是否可读、隶书 + Belwe 的实际观感。
