# Bug T4 — 不在对局里的时候，记牌器该不该显示

先读 `docs/tasks/_common.md` 里的通用约束。

## 症状

一局打完回到炉石主菜单，**两个记牌器都还挂在屏幕上**，显示的是刚结束那一局的终局状态。
2026-08-31 22:20 用户截图：左侧对手记牌器（对手是牧师，`opponent_tracker_frame = {0,0}`）
和右侧我方记牌器（牌组「地沟油」）在主菜单页面同时可见。

用户原话（这已经是第二次提了，第一次在 2026-08-30）：
> 「这盘打完左侧依旧出现了对手的记牌器，回到主页面也是。」

## 这次**不是**上次那个病，别往那边查

2026-08-30 那次「残留」的根因是主线程死锁（overlay 冻在最后一帧、没人执行 `orderOut`），
已由 `ac116be0` 修好。**本次已排除同一根因**，证据：

- 无新的 `.hang` 报告（`/Library/Logs/DiagnosticReports/` 最新一份仍是 8-30 17:33 那份）。
- 延迟探针到 22:20:09 仍在正常产出（D 的 `n` 从 135 涨到 139），主队列是活的。
- `QueueEvents` 本局 `Now in queue`(22:10:59) / `No longer in queue`(22:11:12) 正常配对，
  `isInQueue` 没有卡住 —— `docs/PROGRESS.md` 里那条"`isDeckTrackerQueue` 没有 `isInMenu` 门"
  的隐患本次也没被触发。

**所以这是显示条件本身的问题，不是线程、不是陈旧状态。**

## 期望行为

| 用户在哪 | 我方记牌器 | 对手记牌器 |
|---|---|---|
| 对局中 | 显示 | 显示 |
| 排队中（已选牌组，非战棋） | **显示** | 不显示 |
| 主菜单 / 收藏 / 其它非对局界面 | 不显示 | 不显示 |

第二行是 `phase6-t1-queue-residue` 刚做出来的功能（`Game.isDeckTrackerQueue`），
**这次修完它必须还在**。第三行是本次要修的。

## 硬约束

- **不许靠让用户去偏好设置里打开某个开关来"解决"。** 现有开关表达不了上面那张表；
  如果你发现某个开关看起来能解决，先验证它对第二行（排队时显示我方牌组）有没有副作用，
  并把结论写进报告。
- **上游默认值不要改。** 这个 fork 的用户没有改过相关的 `defaults`，
  修完要让默认行为就是上面那张表，而不是依赖用户去配。
- 不要动 `ac116be0` 修好的线程归属（watcher 回调必须回主线程写 view model），
  也不要动 `eb52832e` 的 Tier7 显示路径。
- ⚠️ **`docs/tasks/phase0-t6b-shrink-refresh-cost.md` 第 2 步正在并行进行。**
  那本只加延迟埋点，不碰显示条件；**本任务只碰显示条件，不要改刷新路径的结构、
  投递顺序或防抖参数** —— 一动就污染它正在采的数。两边各守各的。
- 不要 `git add` 或 commit，不要动 `.xib`，不要动 `project.pbxproj`。

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`：

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. 报告里逐格论证上面那张表的九个格子各由哪条判定负责，特别是：
   **"排队中"和"主菜单"这两行凭什么被区分开** —— 它们都不在对局里。

3. 说清楚这个判定在**状态没有按预期推进**时会怎样（比如上一局结束了但下一局的重置还没跑、
   或者某个状态位卡住）。这个仓库在"某个标志位卡住导致记牌器整局不出现"上已经栽过一次，
   不要修出第二次。

4. 报告里标出：哪些格子静态就能证明，哪些必须用户实战才能确认。
   **用户不玩战棋**，战棋相关的格子只能静态论证，不要排"打一局战棋"这种验收项。

## 背景资料

- 上次「残留」的完整定案：`docs/PROGRESS.md` 的「③ 的余留已查明」一节
- 排队显示我方牌组是怎么做出来的：`docs/archive/tasks/phase6-t1-queue-residue.md`
- 上次的死锁根因：`docs/archive/tasks/bug-t1-viewmodel-offmain-writes.md`

## 执行结果（2026-08-31）

根因就是显示门：`hide_all_trackers_when_not_in_game` 默认 `false`，旧条件因此允许 `gameEnded == true`
时继续显示。`gameEnd()` 的 `hideGameTrackers()` 本来就不包含两个主记牌器，随后 `updateTrackers()`
又按旧门让它们保持显示；进入主菜单不会再触发一次记牌器刷新来纠正。

修复把显示上下文拆成两个互不混用的正向入口：

- **对局入口**：`!gameEnded && !isInMenu`，再叠加传统模式、非观战、前后台和各自总开关。
- **排队入口**：只给我方，要求 `isInMenu`、`isInQueue`、已有牌组、`currentMode` 在队列白名单内且不是
  `.bacon`。对手没有这个入口。

逐格对账：

| 用户在哪 | 场景判定 | 我方 | 对手 | 证明方式 |
|---|---|---|---|---|
| 对局中 | `gameEnded=false` 且 `isInMenu=false`；传统模式门为真 | 对局入口放行 | 对局入口放行 | 条件可静态证明；真实状态翻转需标准实战 |
| 排队中 | `isInMenu=true`、队列位为真、有牌组、模式白名单命中 | 排队入口放行 | 没有排队入口，拒绝 | 条件可静态证明；队列事件需标准实战 |
| 主菜单 / 收藏 / 其它 | 对局入口为假；队列位或模式白名单至少一项为假 | 拒绝 | 拒绝 | 常规模式静态可证，实际窗口隐藏需实战 |

排队和主菜单虽然都不在对局里，但前者必须同时拿到**队列事件 + 已选牌组 + 受支持的具体模式**；
主菜单 `.hub`、收藏 `.collectionmanager` 等不在白名单，即使有旧牌组也不能放行。

现有偏好开关不能作为修复：把 `hide_all_trackers_when_not_in_game` 打开后，排队期间
`gameEnded` 仍为 true，会把我方牌组也挡掉。此次没有改任何 defaults；默认值下直接得到上表行为。

状态异常时：

- 上一局结束但下一局 `reset()` 还没跑，`gameEnded` 已经挡住对局入口；只有收到一条完整合法的排队状态
  才能打开我方入口，旧 `currentGameType` 或旧实体单独不能让窗口出现。
- `isInQueue` 卡在 true 也不能污染下一局：排队入口新增 `isInMenu`，一进对局它就关闭；对局入口完全不读
  `isInQueue`，不会重演“排队位没清导致整局记牌器不出现”。
- 如果 `gameEnded` 或 `isInMenu` 只有一个在结束时成功推进，对局入口仍会关闭；开始新局时两者由
  `gameStart()` 在同一段同步设为 false 后才请求刷新。若整条 `gameStart()` 都丢失，记牌器会保持隐藏并
  暴露故障，不会拿上一局终局状态伪装成功。
- 仍有一个诚实边界：如果 `isInQueue` 卡在 true、`currentMode` 也一直卡在同一个受支持的大厅模式，
  且牌组仍在，就没有第二份独立事实能区分“仍在排队”和“已取消”，我方可能继续显示；对手仍不显示。

战棋对局/排队均只做静态论证：传统模式门会挡战棋对局，`.bacon` 会挡战棋排队。用户无需打一局战棋。
受限环境 Debug build 输出 `BUILD SUCCEEDED`；标准模式的“排队 → 对局 → 回主菜单”窗口实效仍需用户实战。

## review（2026-08-31）：门本身成立，但带出四条副作用

独立复跑受限环境 Debug build：`BUILD SUCCEEDED`。九格判定逐条核过，成立。
**顺带确认这次修复关掉了一个挂了两轮的隐患**：`isDeckTrackerQueue` 补上 `isInMenu` 之后，
PROGRESS 里那条"`isInQueue` 卡住会让我方记牌器整局强制显示"从结构上不可能再发生了。

下面四条是执行报告没提的，按影响排序。**第 1 条用户这一局就会看到。**

### 1. 🔴 记牌器现在在「打完的那一瞬间」消失，不是回主菜单才消失

任务书那张表写的是"主菜单不显示"，实现出来的是"`gameEnded` 一为真就不显示"。
正常结束路径是 `TagChangeActions.stateChange`（`:541-546`）：先 `gameEnd()`，
而 `gameEnd()` 末尾就有 `updateTrackers(reset: true)`（`Game.swift:2208`）。
所以**还停在结算画面、牌桌还在的时候，两个记牌器就已经消失了**。

这不是 bug，是比需求更激进的一档。**要用户在验收局里看一眼再定。**

> 顺带说清楚为什么不能简单改成只看 `isInMenu`：`inMenu()`（`Game.swift:2211`）
> 只置位、**不请求刷新**，`isInMenu` 翻 true 之后没人去重算显示。
> 现在是 `gameEnded` 同时充当了判定和触发点。要改成"离开牌桌才消失"，
> 得在 `inMenu()` 里补一次 `updateTrackers()`，不是把条件删掉就行。

### 2. 🟡 法力水晶上限 overlay 不跟着消失，会在结算画面上单独挂着

`updateMaxResourcesWidget`（`Game.swift:685` / `:692`）走的还是旧的
`shouldShowTracker`（`:250`），那条**没有跟着改**，仍然由
`hideAllTrackersWhenNotInGame`（默认 false）决定。
而 `updatePlayerResorucesWidgetVisibility`（`:5264`）只挡 `isInMenu`。
结算画面上 `isInMenu` 仍是 false，`showPlayerMaxResources` / `showOpponentMaxResources`
默认都是 `true`（`Settings.swift:425` / `:431`，用户没改过）——
**两个记牌器消失、水晶上限还在**。回到主菜单后它才会被 `isInMenu` 挡掉。

### 3. 🟡 「不在对局时隐藏全部记牌器」这个偏好开关现在半死

两个主记牌器已经不读它了，但 `shouldShowTracker` 还读（即上面第 2 条那条路径）。
用户去设置里勾它，会得到"水晶上限受影响、记牌器不受影响"的部分效果。
要么让它也走新场景门，要么从设置界面撤掉。**本轮不改，记着。**

### ✅ 实战验收结果（2026-08-31 23:17–23:26，Release，标准模式一局）

用户走完「标准排队 → 完整一局 → 回主菜单」，**四项行为全部与描述一致**：

1. 排队时只有我方记牌器，对手的不出现 ✅
2. 对局中两个都在 ✅
3. 打完的瞬间（还停在结算画面）两个记牌器消失 ✅ ——
   **用户已决定保留这个行为**，不改回"离开牌桌才消失"。
4. 同一时刻法力水晶上限 overlay 单独留着 ✅ ——
   **用户已决定修掉**，连同下面第 3 条的半死开关，一起进
   `docs/tasks/bug-t5-tracker-visibility-consistency.md`。

回主菜单后两个记牌器都不显示。同一局顺带完成了 T6b 第 2 步取数。

**本任务书到此结案。** 下面第 2 / 3 / 4 条的处置：第 2、3 条 → Bug T5；
第 4 条第二小点（`clearTrackersOnGameEnd` 的形状）也一并进 Bug T5；
第 4 条第一小点（`selfAppActive` 逃生口）用户未提出异议，暂不处理，留档。

### 4. 🟢 两条低优先级

- **`selfAppActive` 逃生口没了。** 旧条件里的 `|| self.selfAppActive` 意思是
  "HSTracker 自己在前台时无条件显示"，那是非对局状态下把记牌器拖到别处的唯一办法。
  用户 defaults 里有自定义的 `opponent_tracker_frame` / `player_tracker_frame`，
  说明拖过。现在只能在对局中拖。
- **`clearTrackersOnGameEnd` 那块被移出了 `if shouldShow`**，于是只要 `gameEnded`
  就**每一轮刷新**都往一个已经隐藏的 tracker 写空数组。用户默认是 `false`
  （`Settings.swift:413`）所以当前是死代码；开了也只是白做功，不影响正确性。
  但 T6b 正在削刷新成本，这种"给隐藏窗口反复写 `@Published`"的形状不该留。
