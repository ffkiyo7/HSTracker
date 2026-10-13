# Perf P5 — 对局中的空转：轮询、无人读的发布、整表过滤

先读 `docs/tasks/_common.md`。实现分支：从最新 `dev0923` 切 `perf/guards`。
**开工条件：滚动那本（`phase2-scroll-collapse.md`）已合入 `dev0923`。** 第 2 条要动 `RootOverlayViewModel` / `RootOverlayWindow`，滚动那本也在这一带加东西。

## 为什么

几处小开销在对局里一直跑：内存轮询、没人读的 `@Published`、同值反复发布、每次调用都过滤整张卡表。
单看都不大，加起来就是对局中的常驻 CPU。**代价都是从代码推断的，没量过，本片要量。**
另外，用户日常打的是 Debug 包（`-Onone`），PLAN 里的实测也都是 Debug。本片的测量一律用 Release 包。

## 要做出什么

### 1. 只在需要的模式里轮询

`Logging/SceneHandler.swift:118-127` 在每次进对局时启动这些 watcher：

| watcher | 周期 | 现状 |
|---|---|---|
| `baconWatcher` | 200 ms | **不是战棋专用**：它还驱动所有模式的好友列表 / 游戏菜单切口（`Hearthstone/Watchers.swift:256-263`），**保持不动** |
| `specialShopChoicesStateWatcher` | 200 ms | 唯一的消费者在非战棋对局里直接返回（`Game.swift:4448-4451`）→ 只在战棋对局里跑 |
| `mulliganTooltipWatcher` | 16 ms | `update()` 永远返回 false，整局都在跑；消费者是选英雄提示的切口和英雄指南触发（`Watchers.swift:291-299`）→ 先核实消费者是否只在战棋 / 留牌阶段有用，再决定只在战棋跑，还是留牌结束就停 |
| `bigCardWatcher` / `choicesWatcher` / `discoverStateWatcher` / `playZoneWatcher` | 16 ms | 构筑也在用，不动 |

每个改动都要在报告里写清：消费者在哪、为什么构筑里用不到、停 / 不启动的时机。
开局时可能还判断不了是不是战棋，那就在能可靠判定的那一刻再启动，位置写进报告。

### 2. 只给 AppKit 读的状态不再 `@Published`

`UIs/Overlay/Root/RootOverlayViewModel.swift` 里的 `interactiveRegions`（`:187`）、`trackerRows`（`:224`）、`boardHoverTargets`（`:242`）只被 AppKit 读：
`RootOverlayWindow`（`:75` / `:141-145` / `:404`）和 `BoardMouseOverDetection.swift:41`。但它们是 `@Published`，每写一次都会让 `RootOverlayView` 整个 body 重算。
T8 行动画期间，行矩形每帧都在变。

- 这三个改成普通属性。
- `interactiveRegions` 在 `RootOverlayWindow.swift:75` 有 Combine 订阅，换成单独的 subject 或回调，行为不变。
- `hoverRegions` 有 SwiftUI 读者（`RootOverlayView.swift:584` / `:589`），保持 `@Published`。
- 滚动那本如果新加了只给 AppKit 读的属性，同样处理。

### 3. 同值不重复发布

- `UIs/Overlay/Board/BoardOverlayViewModel.swift:87-92`：`isMercenariesMatch` / `isMainAction` / `mercsToNominate` / `handCount` 每次都赋值。只在值变时赋。
- `Logging/Game.swift:869`：每次刷新都 `board.isShown = true`。只在变化时赋。

### 4. `Cards.collectible()` 算一次

`Database/Cards.swift:130`：每次调用都过滤整张卡表，全仓库约 240 处调用（`rg -c "Cards.collectible()"`）。

- 结果缓存起来；`Cards.cards` 变化时作废。已知的变化点是 `Database.swift:322` 的 `append`；切换语言的重载路径你找，写进报告。
- `Cards.cards` 是 `SynchronizedArray`，缓存也要线程安全。
- 返回值语义不变：调用方会改返回的 `Card` 吗？逐个核实，必要时照旧返回副本。

## 不在本片

- 图片缓存按张数而不是字节封顶（`UIs/ImageUtils.swift:43`）、本局 Power.log 每行存两份（`LogLine.swift:107`）：先看 P3 / P4 的测量，内存还有明显问题再开。
- 画布遮罩（P4）、Mono（P3）、包体（P6）。

## 硬约束

- 所有 view model 写入在主线程，同一份状态在同一个 main block 里提交（`AGENTS.md`「线程与时序」）。
- 读 `QueueEvents.isInQueue` 的代码不进对局路径（`AGENTS.md`）。
- FF 本机有未提交改动的文件一律不碰：`Fork/PlayerCardZones.swift`、`TagChangeActions+ZoneLatches.swift`、`Logging/Entity.swift`、分区相关测试、`RedDragonOverlayModel` / `RedDragonOverlayView` 及其测试、`docs/PLAN.md`。

## 允许修改的文件

- `HSTracker/Logging/SceneHandler.swift`、`HSTracker/Hearthstone/Watchers.swift`
- `HSTracker/UIs/Overlay/Root/RootOverlayViewModel.swift`、`RootOverlayWindow.swift`、`RootOverlayView.swift`（只动第 2 条涉及的几处）
- `HSTracker/UIs/Overlay/Board/BoardOverlayViewModel.swift`、`BoardMouseOverDetection.swift`
- `HSTracker/Logging/Game.swift`：只动 `:869` 一带和第 1 条需要的启动点
- `HSTracker/Database/Cards.swift`、`Database.swift`（只加作废）
- 测试：加进合适的现有测试文件；要新建就按 `AGENTS.md` 登记 4 处

## 测试

- `collectible()` 缓存：和不缓存时结果相同；`cards` 追加后作废。
- 第 2 条：写 `trackerRows` 不再触发 `RootOverlayViewModel.objectWillChange`；`interactiveRegions` 变化仍能让窗口更新穿透。
- 现有测试的期望一条不改。

## 验收

1. Debug `BUILD SUCCEEDED`；全套测试只允许 PLAN 里记着的两条老失败。
2. 测量，Release 包，改前改后同一流程：启动 → 主菜单 → 一局构筑 → 回主菜单。
   - 对局中活动监视器的 HSTracker CPU %，取 1 分钟平均；
   - Instruments Time Profiler 录 30 秒对局，列前 10 个热点函数。
3. 🎮 用户看：好友列表 / 游戏菜单打开时 overlay 照样被挖空（`baconWatcher` 没被误停）；记牌器悬停、交互区照常。

## 汇报

结果写进本文件末尾「执行结果」一节：改动清单、每个 watcher 的结论表、测试条数、改前改后的 CPU 数字。
**不要 commit，不要动 `docs/PLAN.md`。**
