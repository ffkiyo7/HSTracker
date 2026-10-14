# 红龙 T2c —— overlay 与设置页

先读 `docs/tasks/_common.md`。前置：T2a、T2b 已提交，展示模型和开关都在 `HSTracker/RedDragon/`。背景：`docs/research/red-dragon-rogue-spike.md`
第二节（三档揭示、答题模式、兜底三件套、重编号）、第六节（已决：纯文字不行，手牌序号 + 场上标记 + 一行文字三样都要）、第七节（落点：SwiftUI `RootOverlayView` 画布 —— **行号和「1080 画布在哪」以现码为准**，3.6.13 的 `RootOverlayView` 已分成随游戏缩放的一层和固定像素的一层，放哪层由你按各元素的性质定并说明）。

## 用户的验收原话（10-04）

> 实现在设置内新增可热开启红龙辅助选项；Overlay 内 UI 不卡顿、符合整体设计语言，不与其他已有组件冲突。
> UI 样式可以参考现有项目组件的样式；实现后用 artifact 画给我看效果，我来验收。

## 要做出什么

1. **overlay**：把 T2b 展示模型的全部信息画出来 —— 角标（能否斩杀 / 差值 / 难度档 / 正在算·过时·截断）、L1 参与牌高亮（必打与可选能区分）、L2 前 3 步序号、场面目标标记、一行「下一步」、抽牌分叉与缺件、危险提示、答题模式的对 / 错反馈。悬停手牌时游戏会放大那张牌，标记不能挡住它。
2. **热键**：升档 / 降档、答题模式开关。不能要求用户授予辅助功能权限；只在炉石在前台时响应；报告里写清默认键位以及为什么不和炉石 / HSTracker 已有快捷键冲突。
3. **设置页**：在上游 3.6.13 的设置窗里放「红龙辅助」总开关和 T2b 的偏好，开关切换后 overlay 立即出现 / 消失，不重启。放在哪一页、要不要新开一页由你定并说明。
4. **效果图**：写一个可重复运行的渲染入口（测试或 Debug 专用），把 overlay 在若干代表局面下离屏渲染成 1920×1080 PNG，背景用能体现手牌 / 场面位置的示意（真游戏截图没有，别去 `~/Movies` / `~/Pictures` 找），输出到环境变量指定的目录，**不入库**。局面至少覆盖：L0 可斩、L0 不可斩 + 缺件、L1、L2 中途重编号、答题对 / 错、抽牌分叉、危险提示、正在算；再加设置页截图（亮 / 暗各一）。

## 设计语言与不冲突

- 视觉从现有 overlay 组件取：字体、描边文字、圆角、配色、阴影、动效时长（`TrackerBarStyle` / `TrackerMotion` / 计数器 / 留牌指南 / 入场序号徽章等，自己找全）。报告里列出你借用了哪些现成样式。
- 先盘点现有组件在手牌区、场面区、屏幕中下部占了哪些位置（入场序号、对手手牌标记、场面攻击图标、留牌指南、卡牌 HUD、悬停卡图、记牌器面板、计数器……），**给出一张占位表**，证明红龙的元素在所有局面下不与它们重叠；确实重叠的给出让位规则。
- 标记都不接鼠标，窗口保持点击穿透；不报交互 / 悬停区域。

## 硬约束

- 上游文件（`RootOverlayView` / `RootOverlayViewModel` / 设置窗相关）每个只加挂载所需的极少行，其余在 `HSTracker/RedDragon/` 下的新文件。
- 不卡顿：overlay 只在展示模型变化时重绘；无关的记牌器刷新不能引起红龙视图重算，反之亦然。给出可复现的测量（例如视图 body 求值次数、主线程耗时），用数据说明。
- 文案：`AGENTS.md` 禁止给 `.xcstrings` 增 key，所以红龙自有的界面文案直接用中文字面量，集中放一个文件；不动任何 `.xcstrings` / `.strings` / `.xib`。
- 视觉动效遵守系统「减弱动态效果」。

## 构建节奏（10-05 用户定）

- 改动过程中只跑相关测试（`-only-testing:` 红龙 / 本书新增的测试类），全套 `test` 只在交付前跑一次。
- 不切换 `SWIFT_OPTIMIZATION_LEVEL` / configuration 做测量（会整包重编）；性能数据在 Debug 下取相对值，或用 scratchpad 里的独立 `swiftc -O` 基准。

## 允许修改的文件

`HSTracker/RedDragon/`（新增 / 修改）、`RootOverlayView.swift` / `RootOverlayViewModel.swift`（挂载）、设置窗里放开关所需的文件、`HSTrackerTests/` 红龙相关、`project.pbxproj`（只登记）。还要碰别的，先在报告里论证。

## 验收

1. 受限环境 `clean build` 成功；`test` 条数与失败数如实报告。
2. 效果图按上面清单全部产出，报告给出生成命令和输出路径。
3. 占位表、借用样式表、热键说明、性能数据。
4. 能自测的行为写成测试：热切换后视图出现 / 消失、档位规则、重编号后序号落在正确的 entity 上。

## 执行结果

2026-10-05，实现者（Opus 子代理），基于 HEAD 61fbcbd3，未提交。

### 改动文件

- 新：`HSTracker/RedDragon/RedDragonStrings.swift`（全部中文文案）、`RedDragonOverlayModel.swift`（hint → 显示模型的规则 + 几何）、`RedDragonOverlayView.swift`（view model + 视图）、`RedDragonHotkeys.swift`（Carbon 热键）、`RedDragonPreferences.swift`（设置页）；`HSTrackerTests/RedDragonOverlayTests.swift`（18 条）。
- 改：`RedDragonGameSnapshot.swift` / `RedDragonSnapshot.swift`（加 `boardSlots` / `opponentBoardSlots`：按 ZONE_POSITION 的占格实体，含地标）、`RedDragonHint.swift`（`RDAnalysis` 加 `handOrder` / `boardSlots` / `opponentBoardSlots`，供标记按 entity 定位）。
- 上游挂载：`RootOverlayView.swift` +2 行（`RedDragonOverlayView`，放在 MercenariesAbilityHoverView 后、FlavorTextView 前）、`RootOverlayViewModel.swift` +3 行（`let redDragon = RedDragonOverlayViewModel()`）、`AppDelegate.swift` +3/-1（偏好窗 pane 列表只在这里构造，Overlay 组末尾加 `RedDragonPreferences()`）、`project.pbxproj` +24（5 个 app 文件 + 1 个测试文件，各 4 处）。
- 层：挂在固定像素层（与 BoardOverlayView 同层），手牌 / 场面坐标直接复用 `BoardOverlayView.handCardPosition/handCardAngle/minionWidth/playerTop/opponentTop`，避免缩放层再换算。
- 设置页：现有偏好页都是 nib，不能动 .xib，故在 Overlay 组新增 SwiftUI 页「红龙辅助」（SF Symbol flame），只放控件，复用已有键 `redDragonAssist` / `redDragonRevealLevel` / `redDragonQuizMode`。

### 线程（onChange 到显示）

上游 T2b：解析线程 → `main.async` submit → 后台搜索 → `main.async` commit。本书：assistant 在主线程 publish（commit / submit / markStale 的 main block、设置通知、热键回调）→ `onChange` → `RedDragonOverlayViewModel.receive` 只存 pending → **一次 `main.async`** flush：`RDOverlayModel.make` 后与旧值比较，不同才写 `@Published model` → SwiftUI 下一帧求值 `RedDragonOverlayView.body`。同一 run loop 内多次 receive 合并成一次提交（有测试）。无 `main.sync`。

### 占位表

| 现有元素 | 位置 | 红龙的处理 |
|---|---|---|
| 判定面板（自有） | 4:3 区左下：左 0.025×4:3 宽，底 0.985H，宽 200–320u 且不越过 1~10 张手牌转角后的最左边 | — |
| 我方 / 对方场攻图标 | (25.5%, 67.62%) 75px 等 | 面板与标记均不相交（测试） |
| 计数器 / 生效中 / 法力 (75.2%, 95.6%) | 右下 | 面板在左，不相交（测试） |
| 对手手牌标记 | 顶部 | 不放东西 |
| 对手记牌器 | letterbox 左侧 | 窄屏纵向交叠时面板挪到记牌器右侧 +8u（测试） |
| 入场序号 | 格上沿 | 红龙场面标记放格下沿，英雄目标在对方头像左下，均不重叠（测试） |
| 悬停放大牌 | — | 红龙视图在 opacity mask 的 ZStack 内，被 mask 挖掉 |
| FlavorText | — | 仍在红龙之上 |

### 借用样式

| 用途 | 借自 |
|---|---|
| 面板底色 / 描边 / 文字 | `TrackerBarStyle` base(0.9) / line / text / gold |
| 步骤徽章、必打实线发光 | `TrackerBarStyle.star` |
| 目标圈、敌方目标 | `TrackerBarStyle.flame` |
| 判定色（可斩 / 抽到才斩 / 不能） | `TrackerBarStyle` highlight green / orange，skull |
| 可选虚线 | highlight teal |
| 字体 | "AR LisuGB Medium" + Belwe 数字，×1.2 |
| 步骤徽章形状 | 入场序号同款胶囊 |
| 动画 | easeOut(`TrackerMotion.duration`)；减弱动态效果时为 nil |

### 热键

⌃⌥W 升一档、⌃⌥S 降一档、⌃⌥Q 开 / 关答题。Carbon `RegisterEventHotKey`，不需辅助功能权限；只在开关开 + 炉石（`unity.Blizzard Entertainment.Hearthstone`）前台时注册，切走即注销，回调里再核一次。冲突：HSTracker 自身快捷键都是 ⌘ 组合；炉石用 Esc / Enter / ⌘；macOS 默认 ⌃ 组合不带 ⌥；Rectangle 常用 ⌃⌥ 方向键 / Enter / UIJK / DFGET / C，不含 WSQ。被占时返回 `eventHotKeyExistsErr`，不抢，只记 warning。

### 性能（Debug，全套测试那次）

无关 RootOverlayViewModel 刷新 50 次：红龙视图重建 50 次、body 求值 0 次；红龙状态变化 40 次：红龙 body 40 次、RootOverlayViewModel.objectWillChange 0 次；receive→提交→布局+绘制 avg 1.09 ms / median 0.73 ms / max 10.40 ms（多次运行 avg 0.93–1.57、max 8–14 ms）；`RDOverlayModel.make` ≈ 8 µs。Release 未测。

### 效果图

命令（仓库根，目录不入库）：

```
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com.proxy \
  GIT_CONFIG_VALUE_0=<https_proxy> TEST_RUNNER_RD_RENDER_DIR=<输出目录> \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug -destination 'platform=macOS' \
  test -only-testing:HSTrackerTests/RedDragonOverlayTests -skip-testing:HSTrackerTests/LocalizationFormatTests
```

本次输出在会话 scratchpad `t2c-renders/`：01-L0-lethal（L0 可斩杀）、02-L0-not-lethal-missing（不能斩杀 + 缺件）、03-L1-cards（参与牌实线 / 虚线）、04-L2-renumbered（L2 前 3 步，场面重编号后序号落在 entity 上）、05-quiz-correct、06-quiz-wrong（答题判卷）、07-draw-branches（需抽到才斩杀 + 3 条分叉）、08-danger（单回合不够 + 场面危险）、09-computing（正在算）、10-opponent-secrets（⚠ 对方有奥秘）、11-settings-light、12-settings-dark（设置页）。背景是示意图（虚线占位现有组件），不是游戏截图。

### 测试

- clean build 成功，红龙文件无新增警告。
- 过程中 `-only-testing` 红龙各类 + 本书新类：113 条，1 跳过，0 失败。
- 交付前全套（`-skip-testing:HSTrackerTests/LocalizationFormatTests`）：437 条，1 跳过（`RedDragonFormulaTests.testProductionConfigCostRelease`），1 失败（既有的 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`，签名相关，与本书无关）。

### 遗留风险

1. 坐标是公式估计（英雄目标点、面板位置、手牌转角外接框），需 🎮 实测；面板高度用估计值参与记牌器让位。
2. 不挡悬停放大牌依赖 opacity mask，时序未实测。
3. 分叉 / 缺件卡名跟随应用语言，非中文时与中文文案混排。
4. `RedDragonAssistant.onChange` 是单回调，先接者得（overlay 只在为 nil 时接）。
5. T2b 下一步文本里的 ⚔ 字形在 overlay 字体下显示近似 x（攻击方徽章已改 SF Symbol，文本未动）。
6. 热键注册失败只记日志，设置页无提示。
7. 热切换测试会临时改真实 Settings 再恢复；异常中断可能残留。

## 第二轮（Codex review 2 条 P2 + 2 条小项）

2026-10-05，未提交。第一轮遗留风险 4、5 已在本轮解决。

### P2-1 面板压手牌 → 障碍让位 + 降级规则

- `RDOverlayGeometry.panelLayout(canvas:badge:lines:trackers:)` 取代 `panelFrame`。面板矩形不和任何障碍相交（含 4 u 余量），不出画布：
  - 手牌：1~10 张转角外接框的并集 `handBox`；
  - 固定组件 `fixedObstacles`：双方场面一行、双方场攻图标、我方计数器、双方英雄区、法力、对方手牌标记；
  - 两个记牌器：`trackerBox`，照 `TrackerPanelView` 的摆法（对手左沿挂 left%、我方右沿挂 left%，高 = height% H），宽取区域分组 / 老布局两种宽度的大者。
- 面板只在我方英雄区左边找位置（右半边有法力水晶、牌库、我方记牌器）。降级顺序，第一个放得下的就用：
  1. 行数：全部 → 2 → 1 → 0。按重要度保留：危险 > 下一步 > 单回合不够 > 分叉 > 缺件；角标末尾写「收起 N 条」。最后一档去掉「伤害 / 血量」，只留标题、差值和标签行（「⚠ 对方有奥秘」始终保留）。
  2. 底边：0.985 H → 手牌上沿之上 → 各记牌器上沿之上。
  3. 缩放：×1 → ×0.85 → ×0.72。
  4. 左沿：4:3 内缩 → 画布左边 8 u → 各障碍右沿 + 8 u；宽度到右边第一个障碍为止。
  5. 都放不下：不画面板，手牌 / 场面标记照画。
- 尺寸估计 `RDPanelMetrics`：常数与 `RDPanelContent` 一一对应。文字宽按偏大估（汉字 / 符号 1 em、其余 0.62 em、Belwe 数字 0.7 em）；每行超宽按两行计（`lineLimit(2)`），所以估计只会偏大。`testPanelMetricsAreUpperBounds` 用 NSHostingView 实测核对：高最多多估 25%，最小宽最多多估 9%。
- 测试：
  - `testPanelYieldsToWideOpponentTracker`：Codex 复现的 1440×1080、150% / 85%、10 张，查面板整矩形（含右缘）。
  - `testPanelSweepNeverOverlaps`：8 种画布（16:9 / 21:9 / 4:3 / 5:4 / 16:10）× 对手记牌器缩放 50–200% × 高 40–100% × 左 0–15% × 上 0–30% × 我方记牌器 2 种 × 卡牌尺寸 3 种 × 面板内容 3 种，共 27 648 组。每组查面板和每张手牌、两个记牌器、固定组件都不相交。各档次数：默认 10 536、默认缩小 88、挪到障碍右边 3 032、画布左边 6 970、手牌上方 1 756、记牌器上方 2 900、收行 38、去数字 1 728、不画 600。其中常见配置 1 152 组（缩放 ≤ 100%、记牌器在左沿、上沿 12.5%）：0 组不画。
  - `testPanelClearOfHandAndWidgets`：没有记牌器挡路时，最高的面板也在默认那一行、不收行；常见 L2 面板 16:9 下 ×1 放在默认位置。

### P2-2 让位不跟记牌器拖动 → 订阅记牌器 view model

- `RDTrackerObstacles`（ObservableObject，由 `RedDragonOverlayViewModel` 持有）订阅两个 `TrackerPanelViewModel` 的 `$isShown/$left/$top/$height/$scaling` 和 `card_size` 通知，`removeDuplicates` 后攒着，下一跳 `main.async` 一次提交。拖动一步先后改 left、top，只提交一次。
- 拖动时这些 @Published 每步都变，松手才存设置；红龙不再读 Settings。
- `RootOverlayViewModel` 挂载改为 `lazy var redDragon = RedDragonOverlayViewModel(trackers: [playerTracker, opponentTracker])`（仍是 +3 行）。
- 数据来自 `testPanelFollowsTrackerDragWithoutUnrelatedRedraws`，真 RootOverlayView 离屏：
  - 记牌器无关刷新 ×50（`update` 卡牌列表 + `updateCardCounter` + 同值 `reloadSettings`）：红龙 body 0 次，obstacles 提交 0 次。
  - 拖动 20 步：obstacles 提交 20 次，红龙 body 20 次；设置没被写。
  - 面板 (276, 935, 284×129) → (8, 954, 208×109) ×0.85，不再和拖过来的记牌器相交。
- 线程跳数增加一条：记牌器 @Published（主线程，拖动手势 / reloadSettings）→ sink 攒 → **main.async** flush 写 `state` → SwiftUI 重算红龙 body。assistant 那条不变：publish → subscriber → `receive` → **main.async** flush。

### 小项 3 单回调

`RedDragonAssistant` 加多订阅：`subscribe(_:) -> token`、`unsubscribe(_:)`、`subscriberCount`。`onChange` 原样保留，publish 先调它再调各订阅者。overlay view model 改用 `subscribe`，不再占 `onChange`；`deinit` 时退订（非主线程则 `main.async` 退订）。测试 `testSubscriptionsCoexistAndUnsubscribeOnRelease` 覆盖：`onChange` 被占时两个 VM 都收到，释放一个后订阅数从 2 变 1。

### 小项 4 ⚔ 字形

overlay 不再用 T2b 的 `nextStepText`，改由 `RDText.step(_:cardName:)` 按结构化 `RDStep` 拼：
- 攻击：「A 攻击 B」；
- 打牌：「卡名 → 目标（选 X）/（抽到 X）」；
- 对方英雄：「对方英雄」。

文案都在 `RedDragonStrings.swift`。`testStepTextAvoidsMissingGlyphs` 断言全部效果图局面的文字行不含 ⚔ / ▸。T2b 的 `nextStepText` 本身没动。

### 测试

- 过程中只跑 `RedDragonOverlayTests`：23 条，0 失败。
- 交付前全套（`-skip-testing:HSTrackerTests/LocalizationFormatTests`）：442 条，1 跳过（`RedDragonFormulaTests.testProductionConfigCostRelease`），1 失败（既有 `OfficialBuildTests.testHostAppIsRecognizedAsOfficial`）。
- 性能（Debug）：无关 Root 刷新 50 次，红龙 body 0 次；红龙状态变 40 次，红龙 body 40 次、Root 0 次。receive→提交→布局+绘制 avg 1.25 ms、median 0.93 ms、max 6.28 ms。`make` 9.3 µs。
- 两个挂真 RootOverlayView 的测试先等宿主 app 的 `coreManager` 建好（上游 `AnomalyGuideMulliganTriggerView` 直接隐式解包它，跑得早会崩），60 秒内没建好就 skip。

### 效果图（同一目录覆盖，命令同第一轮）

01–12 同第一轮；04 的下一步改为「狐人老千 攻击 森金持盾卫士」。新增：
- 13-yield-tracker-150：1440×1080、对手记牌器 150% / 85%、10 张手牌。左下没地方，面板贴到记牌器头顶，收起 4 条、去掉伤害数字。
- 14-yield-tracker-dragged：1920×1080，记牌器被拖进 4:3 区域左下，面板退到左边黑边里，×0.72、内容不减。

### 本轮遗留风险

1. 固定障碍是按各组件默认百分比估的矩形（场攻 75 px、计数器 400 u 宽、英雄区 ±0.2 H、法力 160 u），没有读这些组件的实际设置；用户挪过这些组件时不跟随。
2. 极端配置（缩放 ≥ 150% 且高度 ≥ 85%、或 1024×768 这类小 4:3）仍有 2% 的组合不画面板；「记牌器上方」一档会把面板放到左上角，离棋盘远。
3. 高度估计最多偏大 25%：面板可能比必要的更早挪位 / 缩小。
4. 我方记牌器默认 `isShown` 由上游控制；没显示时不算障碍。
