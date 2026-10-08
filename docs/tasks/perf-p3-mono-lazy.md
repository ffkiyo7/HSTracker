# Perf P3 — Bob's Buddy 运行时只在战棋时启动

先读 `docs/tasks/_common.md`。实现分支：从最新 `dev0923` 切 `perf/mono-lazy`。
本书和滚动那本（`phase2-scroll-collapse.md`）没有共同文件，可以并行；按项目目标排在滚动之后。

## 为什么

用户不玩战棋（PLAN「战棋不作为验收手段」，10-08 再次确认）。但每次启动都会在后台起 Mono 并加载 `BobsBuddy.dll`。
`BobsBuddy.dll` 引用 HearthDb 的卡表（`Cards.All` / `GetFromDbfId`），而 `HearthDb.dll`（37 MB）内嵌全量卡牌 XML，
所以只要模拟一次，整张表就进了 Mono 堆。Debug 包每次启动还跑一次 1000 次 × 4 线程的冒烟模拟。
**能省多少内存是从代码推断的，没量过，本片要量。**

## 现状（`origin/dev0923` `35a783f6`）

- `AppDelegate.swift:481-496`：启动后在 global 队列 `MonoHelper.start()`；`#if DEBUG` 下接着 `MonoHelper.testSimulation()`。
- `Mono/MonoHelper.swift:373-393`：`isReady` 带锁（`load()` 在 `:395`）；`start()` = `load()` + `initialize()`，成功后置 `isReady`。
- `BobsBuddy/BobsBuddyInvoker.swift:142-147`：唯一入口 `instance(...)` 在 `!isReady` 时返回 `nil`，所有调用方本来就接受 `nil`。
- 调用方**不全**限定战棋（例如 `Game.swift:3956` 的攻击事件），所以不能在 `instance()` 里触发启动，否则构筑对局也会把 Mono 拉起来。
- 战棋入口：`Logging/SceneHandler.swift:101` 的 `to == .bacon`（进战棋大厅）。

## 要做出什么

1. 删掉启动时的 `MonoHelper.start()`。新增一个幂等的「需要时启动」（名字你定，例如 `MonoHelper.startIfNeeded()`）：第一次调用在后台队列起 Mono，之后的调用什么都不做，并发调用也只起一次。
2. 只在两个战棋触发点调用它：
   - 进战棋大厅：`SceneHandler.swift:101` 的 `to == .bacon` 分支；
   - 兜底：没经过大厅直接进了战棋对局（炉石开着时才启动 HSTracker、断线重连）。在最早能可靠判定 `isBattlegroundsMatch()` 的那一刻触发，位置写进报告。赶不上第一场战斗可以接受。
3. DEBUG 冒烟模拟默认不跑，只在设了环境变量（例如 `HSTRACKER_BOBS_BUDDY_SMOKE=1`）时，在启动完成后跑。
4. `BobsBuddyInvoker` 的调用方和 `isReady` 的语义都不改。

## 硬约束

- 不动 `HSTracker/Mono/` 下的代理文件、构建阶段、`project.pbxproj`。
- `#if !HSTTEST` / `HSTTEST` 下现有行为保留：测试宿主不起 Mono。
- 起 Mono 仍在后台队列；`SceneHandler` 回调在哪个队列上，确认后写进报告。
- FF 本机有未提交改动的文件一律不碰：`Fork/PlayerCardZones.swift`、`TagChangeActions+ZoneLatches.swift`、`Logging/Entity.swift`、分区相关测试、`RedDragonOverlayModel` / `RedDragonOverlayView` 及其测试、`docs/PLAN.md`。

## 允许修改的文件

- `HSTracker/AppDelegate.swift`：只动 `:481-496` 这一段
- `HSTracker/Mono/MonoHelper.swift`：只加启动入口
- `HSTracker/Logging/SceneHandler.swift`：只加触发
- `HSTracker/Logging/Game.swift`：只加兜底触发一处

## 测试

能在不真正加载 Mono 的前提下测「只触发一次」就加一条（例如把一次性开关抽成可注入的闭包）；做不到就在报告里说明，靠下面的测量。

## 验收

1. Debug `BUILD SUCCEEDED`；全套测试只允许 PLAN 里记着的两条老失败。
2. 测量，Release 包，改前改后同一流程：启动 → 主菜单停 30 秒 → 打一局构筑 → 回主菜单。
   - 在主菜单和局后两个点，各记一次 `footprint -p HSTracker`（或活动监视器「内存」列）。
   - 构筑流程中 `~/Library/Logs/HSTracker/hstracker.log` 不再出现 `Bob's Buddy is ready`。
3. 战棋只做静态确认：说明两个触发点为什么覆盖了进大厅和直接进局两种情况。想顺手看一眼的话，进一次战棋大厅（不用开局）看日志出现 `Bob's Buddy is ready`。

## 汇报

结果写进本文件末尾「执行结果」一节：改动清单、测试条数、两组内存数字（主菜单 / 局后，改前 / 改后）。
**不要 commit，不要动 `docs/PLAN.md`。**
