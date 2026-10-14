# 红龙 T6：判定面板放大

先读 `docs/tasks/_common.md`，再读 `docs/tasks/rdr-t2c-overlay.md`（面板摆位规则、效果图命令）和
`HSTracker/RedDragon/RedDragonOverlayModel.swift` 里 `RDOverlayGeometry` 的注释。

## 要什么（用户，2026-10-07）

公式浮窗太小，看不清。用户看过放大示意图后要求落地：示意图在
`/private/tmp/claude-501/-Users-wadorudi-Desktop-dev-HSTracker/8ffbc823-1c71-44a9-b9f1-6cf394a34785/scratchpad/big/`
（`18-formula-locked-169-x16.png`、`15-danger-heal16-169-x16.png`、`15-danger-heal16-43-x16.png`，红色虚线是手牌禁区）。

- 16:9 默认布局下，面板的字号 / 间距 / 宽度上限是现在的 **1.6 倍**（现状宽 ≤ 320 u；1920×1080 下锁定公式面板约 282 px 宽 → 约 512 px）。
- 面板**右沿贴手牌禁区左边**（留现有的间隙），变大时向左、向上长；左边可以长进 16:9 的黑边，到画布左边为止。
- 放不下 1.6 倍时逐级缩小，直到现在最小的那一档为止；行的收起、换底边、让记牌器这些现有降级规则照旧生效，顺序怎么和缩放档交织由你定，报告里写清。

## 硬约束

- **任何情况下不遮手牌**：1~10 张手牌、任何画布比例（16:9 / 16:10 / 4:3 / 超宽）、任何行数的面板，都不与手牌外接框相交。这条要有测试覆盖，不能只靠看图。
- 现有的其它障碍（记牌器、场面、场攻图标、计数器、英雄区、法力、对方手牌标记）照旧不相交；记牌器被拖动 / 改高度 / 改缩放时照旧让位。
- 公式行不能被收掉（现有规则）。
- 只动面板的摆位和尺寸，不动面板内容、判定、引擎、设置项。
- 尺寸估计（`RDPanelMetrics`）和实际绘制仍要一一对应，现有「估计 ≥ 实测」的核对测试继续成立。

## 可改的文件

`HSTracker/RedDragon/RedDragonOverlayModel.swift`、`HSTracker/RedDragon/RedDragonOverlayView.swift`、`HSTrackerTests/RedDragonOverlayTests.swift`。
几何测试里写死的旧尺寸期望可以改，逐条在报告里说明为什么变。

## 验收

- 受限环境 `build` 过；改动中只跑 `-only-testing:HSTrackerTests/RedDragonOverlayTests`，交付前跑一次全套（`-skip-testing:HSTrackerTests/LocalizationFormatTests`），报告条数。
- 按 `rdr-t2c-overlay.md` 的效果图命令重渲染一套到你的 scratchpad，报告里给目录；场景里要有 10 张手牌和 4:3 画布的图。
- 报告：缩放档和降级顺序；16:9 / 4:3 下锁定公式面板和奶 16 面板的实际像素尺寸；手牌不相交的测试怎么覆盖的。
- 🎮（由人做）：打一局红龙贼看面板大小、手牌满 10 张时不被挡。

## 执行结果

10-07 第一轮（Opus 子代理），我读 diff 通过（本书不跑 Codex，用户定）。改 `RedDragonOverlayModel.swift`（缩放档 `[1.6, 1.36, 1.15, 1, 0.85, 0.72]`；每档先找「右边第一个障碍是手牌」的空当、右沿贴手牌，再走原左对齐）、`RedDragonOverlayView.swift`（`RDFlowLayout` 摆位宽度 +1 pt）、`RedDragonOverlayTests.swift`。

- 降级顺序没变：行数 → 底边 → 缩放（六档）→ 左右位置。
- 测试：`RedDragonOverlayTests` 25 条 0 失败；全套 479 条，4 跳过，只挂签名 1 条。新 `testPanelNeverCoversHand`（12 画布 × 6 记牌器配置 × 25 面板，1785 个布局逐张手牌查）、`testFormulaRowsStayInsidePanel`；`testPanelSweepNeverOverlaps` 27 648 → 46 080 组。
- 改的旧期望：`testPanelClearOfHandAndWidgets`（×1 内缩 → ×1.6 贴手牌）；`testPanelYieldsToWideOpponentTracker`「不挡面板的记牌器」72% → 60% 高（72% 的现在会挡）；sweep 的统计分类。
- 顺带修：`RDFlowLayout` 算高度和摆位置用的宽度差零点几像素，非整数缩放档下行尾的词掉出面板底边（旧 ×0.85 / ×0.72 理论上也有）。
- 效果图：会话 scratchpad `t6/renders/`，新增 21–27（10 张手牌 / 4:3 / 默认记牌器）。

**实际大小取决于对手记牌器**（障碍是记牌器分配的盒子 `height% × H`，不是实际内容高度；示意图里画的是 60% 高，够不着面板）：

| 1920×1080 | 无记牌器挡路 | 默认记牌器（0.5 / 12.5 / 72） | 本机当前（−0.83 / 10.09 / 72） |
|---|---|---|---|
| 锁定公式 | ×1.60，512×256 | ×1.15，325×184 | ×1.36，351×218 |
| 奶 16 | ×1.60，512×288 | ×1.60，325×324 | ×1.60，351×324 |

4:3 无记牌器：锁定公式 ×1.15 312×184、奶 16 ×1.36 312×245；默认记牌器下 4:3 / 16:10 基本没比 T6 前变大。记牌器障碍口径 10-08 用户定：按分配的盒子（`height% × H`）算，不按实际内容高；`RDOverlayGeometry.trackerBox` 现状即如此，不改。
