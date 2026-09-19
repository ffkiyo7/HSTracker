# Perf P2：V1 / V2 矢量卡条上线后炉石掉帧（面板的合成成本）

先读 `docs/tasks/_common.md`，再读 `docs/tasks/perf-p1-overlay-frame-drops.md` 末尾「🎮 实测结果」一节
（P1 四条为什么没命中、日志数字、采样回读）。P1 的改动还在工作区没提交，**不是你造成的，不要还原、不要顺手改**。

## 已知事实

- 用户确认（2026-09-18）：**卡顿是 V1 / V2（09-15 之后）才出现的**。SwiftUI 面板本身更早就在用（Phase 1），那时不卡。
  所以嫌疑收敛到 V1 矢量卡条（`phase2-v1-vector-card-bars.md`）和 V2a / V2b（三行头、段头、原画铺满）引入的画法。
- 关掉双方记牌器立刻恢复；抽牌、出牌、悬停（= 面板内容变化）时最明显。
- HSTracker 自己的 CPU 不是原因：面板刷新闭包只占主线程约 3.6%，关掉记牌器后主线程一样堵但炉石不卡。
  成本在 WindowServer / GPU 侧 —— 4K 165Hz、GPU 已经 92% 的游戏上面叠着一块每次变化都要重新合成的面板。
- 环境：`use_swiftui_tracker = 1`、`card_size = 2`、`tracker_opacity = 50`，双方面板各二三十行。

## 判断（推断，未证实 —— 所以本书要求带开关）

V1 之前一行是一张位图；V1 / V2b 之后一行是：原画 `Image` + 裁切 + `LinearGradient` + 三处带 `.shadow` 的 `Text`
（卡名叠两层模糊阴影）+ 若干组 `.opacity` + `.clipped()` + 描边 overlay。这些在 macOS 上落成一棵 CALayer 树，
由 render server 在 GPU 上画；阴影、组透明度、裁切都是离屏 pass。行数 × 2 个面板，任何一行变了整棵树重提交。

## 方向

让 render server 看到的每一行退回「一张平的贴图」的量级：阴影 / 渐变 / 组透明度 / 裁切在**进程内一次画好并缓存**
（按卡、张数、状态、尺寸、不透明度等决定外观的量做键），内容没变的行不重画、不重提交。
用 `drawingGroup`、`ImageRenderer`、自绘 `NSView` / `CALayer` 还是别的，你定，报告里给理由和取舍。
表头（三行头）和段头同理，但先做卡条 —— 它占了层数的绝大部分。

## 硬约束

- **像素级外观不变。** V1 / V2a / V2b 定稿的样式（酒馆底、方块费用格、原画铺满、卡名阴影、暗化、高亮描边、created 金角）
  一样不许丢。**删阴影 / 降画质不是修复**，只能作为下面的诊断开关存在。
- **必须带运行时诊断开关**，用户一局之内就能二分，不用重新构建。用 `UserDefaults` 键（`defaults write net.hearthsim.hstracker <key>`
  + 重启生效即可，能热切换更好），至少：① 关掉新的平铺 / 缓存路径，退回现在的画法；② 去掉文字阴影；③ 去掉原画；
  ④ 面板强制不透明。默认值 = 新路径开、其余全关。键名、默认值写进报告。开关只读不写 UI，不进设置页。
- **给一个不用开炉石就能跑的代理指标**，修前修后各记一次：例如遍历 hosting view 的 layer 树，数总层数、带阴影的层、
  `opacity < 1` 且有子层的层、带 mask / `masksToBounds` 的层（30 行的面板）。写成测试，断言修后的上限。
  它是代理指标，**不等于炉石帧耗时**，报告里别混着说。
- 悬停高亮、tooltip 命中区域（`TrackerCardRowSensor`）、分区 / 折叠行为、`tracker_opacity` 实时生效、`card_size` 各档缩放，全部照旧。
- 现有测试不改期望（基线：P1 工作区 136 条，其中 `SecretTests` 有既有 flake，见 P1 报告）。
- `_common.md` 规则照旧：不 commit、不动 PLAN / PROGRESS、`.xcstrings` 不动。

## 允许修改的文件

- `HSTracker/UIs/Trackers/SwiftUI/` 下全部文件；可在该目录新增文件（登记 pbxproj）
- `HSTracker/Core/Settings.swift`（仅新增诊断键）
- `HSTrackerTests/TrackerMetricsTests.swift`（只加不改）；可新增测试文件（登记 pbxproj）

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`；现有测试 + 新增全绿（既有 flake 单独说明）。
2. 报告里：选了哪种平铺方式及理由；缓存键是什么、什么时候失效；代理指标修前修后数字；四个诊断键的名字和用法；
   外观不变用什么证明的（快照对比 / 逐像素 diff / 目视，如实说）；哪些没做、哪些你怀疑但没证实。
3. 报告末尾给用户的 🎮 实测步骤：启动命令、按什么顺序切哪几个键、每一步看到什么说明什么。

## 汇报

结果写进本文件末尾「执行结果」一节。**不要 commit、不要动 `docs/PLAN.md` / `docs/PROGRESS.md`**。

## 执行结果（2026-09-19）

一句话：**卡条改成「进程内画一次、按外观做键缓存、一行一张平贴图」**，30 行面板的层数
407 → 121、带阴影的层 90 → 0；**外观逐像素相同（57456 个通道采样 0 个不同）**。
四个诊断键都落了。**这只是代理指标，不是炉石帧耗时** —— 本片没有证实「层树就是根因」，
真正判定要靠下面的 🎮 五步，尤其是第 5 步（把窗口强制不透明）。

### 改动清单

| 文件 | 做了什么 |
|---|---|
| **新增** `SwiftUI/TrackerRowRaster.swift` | `TrackerDiagnostics`（四个诊断开关，直读 `UserDefaults`）；`CardRowRasterKey`（19 个字段的外观键）；`TrackerRowRaster`（`NSCache`，`totalCostLimit` 32 MB，按位图字节计费，附 `renders` / `lookups` 两个测试探针） |
| `SwiftUI/CardRowView.swift` | 拆成两个 struct。`CardRowContentView` = V1 / V2a / V2b 的画法**原样搬过来**（只多了三处诊断条件），无 `@State` / 无环境读取，所以能交给 `ImageRenderer`；`CardRowView` 是外壳，持有 `tile`、读环境、算 `rasterKey`、命中就画一张 `Image(nsImage:)` |
| `SwiftUI/TrackerCardListView.swift` | 行的不透明度和三个诊断标志改为从 list view model 传下去（原来靠默认参数直读 `Settings`） |
| `SwiftUI/TrackerCardListViewModel.swift` | 新增 `baseOpacity` / `flattensRows` / `drawsArt` / `drawsTextShadow` 四个 `@Published`；`syncAppearance()` 每次刷新同值跳过地刷新它们 |
| `SwiftUI/TrackerViewModel.swift` | `layout.opacity` 改走 `TrackerDiagnostics.panelOpacity(setting:)`，让开关 ④ 生效（P1 的 `playerType` 那几行一个字节没动） |
| `SwiftUI/TrackerView.swift` | `TrackerRootHost.viewDidMoveToWindow()`：开关 ④ 打开时把窗口本身置为不透明 |
| `Core/Settings.swift` | 四个诊断键 + 四个 `@UserDefault` 属性，**只新增** |
| `HSTrackerTests/TrackerMetricsTests.swift` | 只加不改，新增 9 条 |
| `HSTracker.xcodeproj/project.pbxproj` | 登记 `TrackerRowRaster.swift`（4 处，`git diff` 就这 4 行） |

`Tracker.swift` / `WindowManager.swift` / `Game.swift` / `Player.swift` / `RealmHelper.swift`
以及 P1 的三个测试文件**一个字节没动**（工作区里它们的改动是 P1 的）。

### 平铺方式：`ImageRenderer` + 按外观做键的 `NSCache`

**选它的理由是「外观不变」这条硬约束。** 被光栅化的就是 V1 / V2 那份 `body` 本身 ——
`CardRowContentView` 是从原文件整段搬过去的，没有重写成 CoreGraphics。所以
「像素级外观不变」不是靠我对齐参数对出来的，是**构造上就成立**，逐像素 diff 只是复核。

两个被否掉的方案：

1. **`drawingGroup()`** —— 一个修饰符就能把子树塌成一层，但它是**每帧**离屏重栅格化，
   没有跨帧缓存；而且 SwiftUI 在 `drawingGroup` 里的文字渲染会变糊，直接顶「像素级外观不变」。
2. **自绘 `NSView` / `CALayer`** —— 控制力最强，但要把费用格、两层文字投影、四停渐变、
   cover 裁切、计数框、金角、协同高亮描边全部手抄一遍。SwiftUI 的 `.shadow(radius:)`
   和 `CGContext.setShadow(blur:)` 不是同一个量纲，手抄必然要靠目测调参 —— 等于用
   「我调得挺像」换掉了「代码就是同一份」。

代价写在下面「代价与风险」。

### 缓存键与失效

`CardRowRasterKey`，19 个字段，就是「能改变这一行长相」的全集：

```
cardId · name（含 extraInfo 后缀） · cost · showsCost · count（带符号，已打出段是负数）
rarity（含 ELITE 推出来的传说） · showRarityColors · dimmed · created · countBox
nameColor（解析后的 sRGB 打包成 UInt32） · highlight · hasTile
rowHeight · barWidth · baseOpacity · scale · drawsArt · drawsTextShadow
```

三个决定：

1. **`nameColor` 存解析后的颜色，不存它背后的开关。** `Card.textColor()` 读四个 Settings
   外加用户自选的 `playerInHandColor`；用输入做键的话，以后多一个输入就悄悄失效了。
   现在是拿最终的 `Color` 转 `NSColor` → sRGB → 打包，**不可能和画出来的颜色脱节**。
2. **不做显式失效。** 键变了就是另一张图，旧图留在 `NSCache` 里由它按成本淘汰。
   `tracker_opacity` 改了 → `baseOpacity` 变 → 新键；窗口缩放 / `card_size` 改了 →
   `rowHeight` / `barWidth` 变 → 新键；诊断开关翻了 → 新键。没有「忘了清缓存」这条路。
3. **容量按字节，不按条数。** 用户那档（3840×2160、`card_size = 2` = `.big`）一行是
   341 × 42 pt，2× 下约 230 KB；双面板活跃集约 60 行 ≈ 16 MB。`totalCostLimit` 设 32 MB，
   内存压力下 `NSCache` 自己会放，miss 的代价只是重画一次。

顺带修掉 V2b「待用户确认 2」：`baseOpacity` 不再由 `CardRowView` 的默认参数直读 `Settings`，
改由 `TrackerCardListViewModel` 灌进来。这样 `tracker_opacity` 改了以后**一定**有 publish，
行一定重画（原来要等行因为别的原因被重建）。`testOpacityReachesEveryList` 锁住。

### 代理指标：修前 / 修后

同一次运行里测的：先把 `tracker_perf_flatten_rows` 强制成 `false` 量一遍（= 修前的画法），
再强制成 `true` 量一遍。统计口径是 `NSHostingView` 底下整棵 `CALayer` 树：总层数、
`shadowOpacity > 0` 的层、`opacity < 1` 且有子层的层、`mask != nil` 且有子层的层、
`masksToBounds` 且有子层的层。

| 场景 | 总层数 | 带阴影 | 组透明度 | 真 mask | 矩形裁切 |
|---|---|---|---|---|---|
| 30 行卡表，**修前** | **407** | **90** | 0 | 0 | 90 |
| 30 行卡表，**修后** | **121** | **0** | 0 | 0 | 30 |
| 整块面板（1 行表头 + 3 个段头 + 38 行），修前 | 505 ~ 543 | 118 | 3 | 0 | 115 |
| 整块面板，修后 | **176** | **4** | 3 | 0 | 39 |
| 单独一行，修前（无原画） | 13 | 3 | 0 | 0 | 2 |
| 单独一行，修前（**有原画**） | 15 | 3 | 0 | 0 | 3 |
| 单独一行，修后 | **2** | **0** | 0 | 0 | 0 |

四点说明，别被数字骗了：

- **任务书要的「带 mask / `masksToBounds` 的层」拆成了两列。** 实测 SwiftUI 这些裁切全是
  `masksToBounds`（矩形），**真 mask 层一个都没有**。矩形裁切合成器一般用 scissor 就能做，
  不是离屏 pass，所以它和阴影不该记在一个账上。真正消失的离屏项是**阴影 90 → 0**。
- **列表那两行的 30 张瓦片没加载成功**（测试里的假 card id 下不到图），所以「修前」被**低估**了：
  单行对照显示有原画时修前是 15 层不是 13，30 行就是 **∼467 而不是 407**；修后不受影响（永远 2 层）。
- **修后剩下的 121 层不全是行。** 每行外面还有 `TrackerCardListView` 的 `ZStack` +
  `TrackerCardRowSensor`（tooltip 命中区那个 `NSView`）+ 一个 `.clipped()`，那 30 个矩形裁切就是它。
  这块没动：它是悬停 / tooltip 的载体，而且是矩形裁切。
- **整块面板修后还剩 4 个带阴影的层和 3 个组透明度层，全在三行头和段头里** —— 见「没做的」。

**这不是炉石的帧耗时。** 它只说明「render server 要合成的东西少了一个数量级」。

### 四个诊断键

域是 `net.hearthsim.hstracker`。**默认值 = 新路径开、其余全关**，四个键出厂都不写进 defaults。

| # | 键 | 默认 | 打开（`-bool true`）之后 |
|---|---|---|---|
| ① | `tracker_perf_flatten_rows` | **true** | `false` = 关掉平铺 / 缓存，逐字退回现在（V1 / V2b）的画法 |
| ② | `tracker_perf_no_text_shadow` | false | 卡名两层投影 + 费用数字投影的 alpha 全给 0 |
| ③ | `tracker_perf_no_card_art` | false | 不画 `tiles/<id>.jpg`，渐变和其余照旧 |
| ④ | `tracker_perf_force_opaque` | false | 面板底 alpha 强制 1，**并且把记牌器窗口本身置为 `isOpaque`** |

```bash
defaults write net.hearthsim.hstracker tracker_perf_no_card_art -bool true
defaults delete net.hearthsim.hstracker tracker_perf_no_card_art     # 还原
defaults read net.hearthsim.hstracker | grep tracker_perf            # 看当前状态
```

- **①②③ 支持热切换**：`TrackerCardListViewModel.syncAppearance()` 每次刷新（16 ms）都重读，
  对局中改完一两秒内就生效，不用重启。切换会换键，所以旧位图不会被误用。
- **④ 必须重启**：窗口的 `isOpaque` 在 `TrackerRootHost` 挂进窗口时施加。
  另外 `Tracker.setOpacity()`（`Tracker.swift` 不在本片允许清单里）在 SwiftUI 路径上会把窗口底设回
  `.clear`，所以**开着 ④ 的时候别动设置页的不透明度滑块**，动了就再重启一次。
- **④ 打开后面板没盖住的那部分窗口会变成一块暗色**。这是预期的，它是测量模式不是外观方案。

四个键的名字、默认值、以及「各自真的关掉了对应的东西」由 `testDiagnosticSwitches` 锁住；
那条测试读回并还原用户自己的值，**跑测试不会打断你正在做的二分**。

### 外观不变用什么证明的

**逐像素 diff，结果是 0。** `testFlattenedRowIsTheSamePicture`：同一张牌
（`公诉人梅尔特拉尼克斯`，7 费、传说、2 张，带计数框和长名截断），在 scale = 2 下

- A = 直接渲染 `CardRowContentView`（= 修前的画法）
- B = 渲染开着平铺的 `CardRowView`（= 先光栅化成位图，再把位图画出来）

两张都是 342 × 42 px，转成 sRGB / premultipliedLast 后逐字节比：
**57456 个通道采样里 0 个不同，最大差 0。**

需要说清楚**它证明了什么、没证明什么**：画法本身是同一份代码（`CardRowContentView` 是整段搬的，
`git diff` 里卡条的绘制只多了三处诊断条件，默认值下逐字等价），所以这条 diff 真正验的是
「光栅化 + 贴回去」这一步有没有偏移、缩放、重采样、scale 取错 —— **没有**。
另外 `rg -n "\.system\(|systemName|systemFont" HSTracker/UIs/Trackers/SwiftUI/` 仍是 **0 行**（V2a 的不变量）。

**没做逐像素 diff 的地方**：三行头、段头（本片没改它们的画法）；协同高亮 / created 金角 /
暗条这些分支只由 `testEveryAppearanceChangeIsANewRasterKey` 保证「换了就是另一张图」，
没有逐个做像素对照。目视由 🎮 补。

### 代价与风险（老实说）

1. **平铺是拿 GPU 合成换主线程 CPU。** `testColdAndWarmRasterCost`（Debug 构建，341 × 42 @2x）：
   **60 行冷启动 24.0 ms（≈ 0.4 ms / 行），60 次命中 0.31 ms（≈ 5 µs / 次）。**
   稳定对局里每个 tick 真正变样的只有一两行 ≈ 0.8 ms；**整块重画只发生在**炉石窗口改尺寸、
   `card_size` 改档、不透明度改值、或压缩档位跳变的那一帧。
   用户这档（1080p 三段 30 张都触发不了压缩，见 V2a 尺寸表）平时不会撞上。
2. **`displayScale`。** 位图按 `@Environment(\.displayScale)` 渲染，取不到（预览 / 测试）时退回
   `NSScreen.main.backingScaleFactor`。如果 SwiftUI 在 Retina 窗口上报了 1，字会发虚 ——
   没观察到，但 🎮 时**顺便看一眼卡名是不是和以前一样锐**，虚了就是这里。
3. **内存** 见「缓存键」：活跃集约 16 MB，上限 32 MB。
4. **没有证实层树就是根因。** P1 的实测日志指向「窗口合成 / GPU 侧」，不是 HSTracker 的 CPU。
   如果根因是「一块半透明大窗口叠在 GPU 已 92% 的游戏上」，那么**层数降一个数量级也不会让帧数回来**，
   而开关 ④ 会立刻告诉你。本片的价值在这种情况下退化为「排除了一个嫌疑 + 留下四个开关」。

### 验收

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug \
  -destination 'platform=macOS' build
→ ** BUILD SUCCEEDED **   （默认 DerivedData，所以下面的启动命令拿到的就是这次的包）

xcodebuild ... test
→ Executed 145 tests, with 0 failures (0 unexpected)   ** TEST SUCCEEDED **
```

**145 / 145 全绿**（P1 的 136 条基线 + 本片新增 9 条），现有测试一条期望没改。
P1 报的 `SecretTests` 既有 flake **这次没有复现**（33 条全过）—— 它是偶发的，不是修好了。

新增的 9 条：`testWholePanelLayerCensus` / `testFlatteningCollapsesTheRowLayerTree` /
`testArtCostsLayersOnlyOnTheVectorRow` / `testFlattenedRowIsTheSamePicture` /
`testUnchangedRowsAreNotRedrawn` / `testEveryAppearanceChangeIsANewRasterKey` /
`testColdAndWarmRasterCost` / `testOpacityReachesEveryList` / `testDiagnosticSwitches`。
其中前三条把「代理指标的上限」写死了：修后 30 行必须 ≤ 130 层、带阴影必须是 0、真 mask 必须是 0。

悬停高亮 / tooltip 命中区（`TrackerCardRowSensor` 在行外面，没碰）、分区 / 折叠、
`card_size` 各档缩放：代码路径未变；`tracker_opacity` 实时生效这条**比以前更硬**了（见上）。

### 🎮 实测怎么跑

```
open /Users/wadorudi/Library/Developer/Xcode/DerivedData/HSTracker-cgfkydaatbcvlygsoujdqwiezsjx/Build/Products/Debug/HSTracker.app
```

（P1 的探针数字这次用不上：那是量 HSTracker 自己的提交耗时，本片要看的是**炉石的游戏内 FPS**。
要一起看也行，那就用 P1 报告里的 `HSTRACKER_LATENCY_PROBE=1 …/HSTracker` 启法。）

每一步都是：**双方记牌器开着，打一局或看重播，盯炉石自己的帧数**；对照基准永远是
「关掉双方记牌器」那个状态。

| 步 | 做什么 | 看到什么说明什么 |
|---|---|---|
| **1** | 什么都不改，直接开（① 默认就是开的） | **帧数回来了** → 就是面板的层树 / 离屏 pass，收工。**没回来** → 继续 |
| **2** | `defaults write net.hearthsim.hstracker tracker_perf_flatten_rows -bool false`，重启 | 和第 1 步**一样卡** → 平铺没影响，成本不在层树，跳到第 5 步。第 1 步明显好一些 → 层树有份，但还有别的 |
| **3** | 键改回 `true`（或 `defaults delete`），再 `tracker_perf_no_card_art -bool true`（这个不用重启，等一两秒） | **帧数回来了** → 成本在原画的像素 / 纹理，不在层数 |
| **4** | 还原 ③，把 ① 关掉（`tracker_perf_flatten_rows -bool false`）再开 `tracker_perf_no_text_shadow -bool true` | **帧数回来了** → 文字投影的离屏 pass 是主因，那第 1 步的平铺方向对、只是还不够。⚠️ 必须在 ① **关掉**的前提下测：① 开着时投影已经烤进位图了，② 不会有任何区别（这本身也是一条自检） |
| **5** | 全部还原，只开 `tracker_perf_force_opaque -bool true`，**重启** | **帧数回来了** → 成本是「半透明窗口叠在游戏上」的逐像素混合本身，跟面板画什么无关 —— 这正是 P1 实测日志指向的那个判断，本片的平铺帮不上忙，下一步该去动窗口而不是画法。**还是卡** → 连不透明都救不回来，嫌疑要移出记牌器窗口（`housekeepingTick` 的 AX 调用、或者根本不是 HSTracker） |

全部还原：

```bash
for k in tracker_perf_flatten_rows tracker_perf_no_text_shadow \
         tracker_perf_no_card_art tracker_perf_force_opaque; do
  defaults delete net.hearthsim.hstracker "$k"
done
```

顺便看一眼外观：**卡名是不是和以前一样锐**（见「代价与风险 2」）、悬停 tooltip 还在不在、
不透明度滑块拖动时面板跟不跟手。

### 没做的 / 怀疑但没证实的

1. **三行头和段头没平铺。** 任务书允许（「先做卡条」），数据也支持：整块面板平铺卡条之后
   总层数已经 505 → 176，**剩下的 4 个阴影层和 3 个组透明度层全在这两处**。
   段头很好办（输入只有段名 / 张数 / 高度）；三行头麻烦一点 —— 它读 `@ObservedObject`、
   里面有 `GeometryReader` 和 hero 原画，要先拆出一个纯 content view，而且手牌数 / 牌库数
   每次抽牌都变，缓存命中率本来就低。**如果 🎮 第 1 步有效果但不够，这是下一刀。**
2. **`TrackerCardListView` 每行那个 `.clipped()` 现在是冗余的**（平铺后行内容不可能溢出），
   修后 30 个矩形裁切层就是它。没删：它同时罩着 tooltip 的 `TrackerCardRowSensor`，
   而且矩形裁切是 scissor 不是离屏 pass，收益接近 0、回归风险不为 0。
3. **战棋随从卡条仍读主题 PNG**（V1「发现但按规则没动 1」），本片同样没碰。
4. **P1 的四条改动仍在工作区未提交**，本片在它们之上做，没有还原任何一行。
5. **怀疑但没证实**：见「代价与风险 4」。本片交付的是「一个被砍掉一个数量级的代理指标」
   加「一套能在一局之内二分的开关」，**不是「炉石不卡了」的结论** —— 那个结论只能由 🎮 给。
