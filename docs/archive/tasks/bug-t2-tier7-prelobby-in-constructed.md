# Bug T2：构筑对局中弹出「Tier7 Battlegrounds Overlay」浮窗

## 症状

2026-08-30 18:31，标准模式狂野排位对局中（日志 `HSReplayAPI.getConstructedMulliganV2`
明写 `"player_class":"DEMONHUNTER","opponent_class":"WARRIOR"`），炉石窗口左上角出现一个
标题为 **`Tier7 Battlegrounds Overlay`**、内容一直停在 **`Loading...`** 的浮窗，压在对手
记牌器上面。用户明确表示这个浮窗**以前没出现过**，而且不想要它。

这是战棋的 pre-lobby 面板。它不该在构筑对局里出现，更不该停在 Loading 不动。

同一局里 Bug T1（主线程死锁）的验收是通过的：没有新的 hang report，`[trackervis]`
全程正常翻转，协同高亮和卡池浮窗都正常。所以这不是死锁的残留画面。

## 时间线上的关键事实

这个浮窗是在 **`ac116be0`（Bug T1 的线程修复）之后的第一局**里出现的。那个 commit 改动了
`setBaconState` 的执行时序：原来是「后台线程同步写三个 view model 属性 + 单独派一个 main
block 跑 `updateTier7PreLobbyVisibility()`」，现在是「三个写入和 visibility 更新在同一个
main block 里」。

**是否由该 commit 引入，本任务未定论 —— 见「需要你独立判断的地方」。**

## 复现

标准模式打一局即可。不需要进战棋。

## 已经查到的（**当作待验证的说法，不是结论**）

下面是 review 侧读代码得到的路径，**逐条都可能读错，请独立复核并直说哪条不成立**：

1. `Tier7PreLobbyViewModel.swift:46-47`：`visibility` 是计算属性，`return isModalOpen ? false : true`。
2. `Tier7PreLobbyViewModel.swift:36-42`：`isModalOpen` 的 setter 无条件调
   `onPropertyChanged("visibility")`。
3. `Tier7PreLobby.swift:114-117`：收到 `"visibility"` 就 `isVisible = viewModel.visibility`，
   然后调 `updateBattlegroundsOverlays()`。**这一段看不到任何场景 / 模式 / 设置的判断。**
4. `Game.swift:771-779`：`updateBattlegroundsOverlays()` 里按 `tier7PreLobby.isVisible`
   决定显示或隐藏。
5. `Game.swift:1099`：`updateTier7PreLobbyVisibility()` 的 `show` 条件里**有** `SceneHandler.scene == .bacon`
   这一项，所以走这条路的话构筑局应该算出 false。
6. `SceneHandler.swift:103-110`：进入 `.gameplay` 会 `Watchers.baconWatcher.run()`，
   也就是**构筑对局同样在跑战棋 watcher**，于是 `setBaconState` 在构筑局里照样被调用。
7. `Game.swift:753-754`：`updateBattlegroundsOverlays()` 把整个函数体包在**无条件**的
   `DispatchQueue.main.async` 里，即使调用方已经在主线程也会推迟一轮。

`Loading...` 这个内容大概率说明 `viewModel.update()` 从没跑完过 —— 那个调用在
`Game.swift:1101-1107`，只在 `show == true` 的分支里。也就是说浮窗是被**别的**路径显示出来的，
不是正常的 pre-lobby 显示流程。这条推论同样请你自己验。

## 需要你独立判断的地方

review 侧卡在这里，明确说明以免你被误导：

**按上面 4 / 5 / 7 三条推演，旧代码和新代码的最终状态应该都是「隐藏」** ——
`updateTier7PreLobbyVisibility()` 会把 `isVisible` 打回 false，而 `updateBattlegroundsOverlays()`
的函数体是延后执行、执行时重新读 `isVisible`，所以理应自我纠正。

**所以 review 侧无法解释浮窗为什么会留在屏幕上。** 这正是要你独立排查的核心问题：

- 到底是哪一次 `windowManager.show(controller: tier7PreLobby, show: true)` 把它显示出来的？
  如果读代码定不下来，**加临时日志跑一局是允许且推荐的**（照 `[trackervis]` 的样子做：
  只在状态翻转时打、带上判定用到的全部输入项）。
- `isVisible` 和 `viewModel.visibility` 两个状态是否会不一致？谁先谁后？
- `ac116be0` 到底有没有改变这个结果？如果你的结论是「和该 commit 无关、以前也会出现，
  只是用户没注意到」，**那就直说**，并给出支持这个结论的依据。反过来如果确认是回归，
  也要指出是哪一处时序变化造成的。
- review 侧对 3、7 两条的读法如果是错的，直接推翻。

不要为了和上面的说法保持一致而牵强解释。**两边独立得出结论再对齐，才有交叉检验的价值。**

## 允许修改

需要改哪些文件由你的排查结论决定，但改动要**收敛在这个 bug 上**。下面几条是硬约束：

- **不要靠关设置绕过。** `Settings.enableTier7Overlay` / `showBattlegroundsTier7PreLobby`
  之类的开关不是修法 —— 用户要的是「构筑局不该出现战棋浮窗」，不是「把战棋功能关掉」。
- **不要为了消掉这个浮窗而回退 `ac116be0` 的线程修复。** 那个 commit 修的是已被 hang report
  实证的主线程死锁，不能退。如果你的结论是它必须调整，要写清楚调整后为什么死锁不会回来。
- **不要顺手重构战棋 overlay 的显示体系。** 只解决「构筑局不该出现」这一件事。
- **不要删或改 `Game.swift` 里带 `[trackervis]` 标记的临时诊断代码。** 还有别的问题在查。
- 不要 `git add` 或 commit，不要动 `.xib`，不要动 `HSTracker.xcodeproj/project.pbxproj`。

## 验收

1. 受限环境 Debug build `BUILD SUCCEEDED`：

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. 🎮 标准模式一局：**全程不出现 Tier7 浮窗**，从进队列到对局到回菜单都不出现。

3. ⚠️ **战棋不作为验收手段 —— 用户不玩战棋。** 所以「修完之后战棋自己的 pre-lobby
   还能正常显示」这一条**只能静态论证**：写清楚正常路径（`Game.swift:1098-1116`）在
   `SceneHandler.scene == .bacon` 时为什么仍然会把它显示出来，以及你的改动为什么不影响它。
   这一条必须写，不能跳过。

4. 把排查过程和结论写进本任务书：是哪条路径显示的、是不是 `ac116be0` 的回归、
   review 侧上面那七条里哪些成立哪些不成立。加过的临时日志如果没删，说明为什么留着。

## 执行结果（2026-08-30）

### 根因与回归判断

这是 `ac116be0` 改变队列顺序后暴露的确定性回归，不是“以前也会出现、用户没注意到”。
真正显示窗口的是 `Game.updateBattlegroundsOverlays()` 里的
`show(controller: tier7PreLobby, show: true)`，不是 `updateTier7PreLobbyVisibility()` 的正常
pre-lobby 显示分支。

关键在 `Tier7PreLobby.awakeFromNib()`：view model 的每次 property change 都会再
`DispatchQueue.main.async` 一轮。构筑对局进入 `.gameplay` 后，`BaconWatcher` 首次轮询必定回调
（`_prev` 初始为 nil），且通常得到 `isAnyOpen == false`，所以 `viewModel.visibility == true`。

`ac116be0` 之后的顺序是：

1. `setBaconState` 的 main block 写 `isModalOpen`，把 `"visibility"` 回调排到下一轮主队列；
2. 同一个 main block 立即跑 `updateTier7PreLobbyVisibility()`，因
   `SceneHandler.scene == .gameplay` 算出 `show == false`，把 controller 的 `isVisible` 设为 false
   并隐藏窗口；
3. 下一轮才执行 `Tier7PreLobby.update("visibility")`，它绕过全部场景条件，又把 controller 的
   `isVisible` 改成 `viewModel.visibility == true`，再排一轮 `updateBattlegroundsOverlays()`；
4. 最后一轮重新读到 `isVisible == true`，于是把窗口显示出来。之后没有更晚的隐藏操作纠正它。

旧代码的 view model 写发生在 watcher 队列，`"visibility"` 回调先于末尾单独派发的规范可见性
更新进入主队列。无论主线程是否在两次派发之间开始消费，规范更新都会在旁路显示之后执行，或在
旁路排出的 `updateBattlegroundsOverlays()` 之前把 `isVisible` 改回 false，最终都是隐藏。因此本次
线程修复没有写错状态，但确实把原来偶然正确的队列顺序翻了过来。

`Loading...` 也与这条路径吻合：全仓库只有 `updateTier7PreLobbyVisibility()` 的 `show == true`
分支会调用 `viewModel.update()`；构筑场景进不了该分支，旁路却直接显示了默认仍为 `.loading` 的
view model。

### 修复

删除 `Tier7PreLobby.update("visibility")` 中直接改 controller `isVisible` 并调用
`updateBattlegroundsOverlays()` 的旁路。现在 `isVisible` 的正常写入只由
`Game.updateTier7PreLobbyVisibility()` 负责，离开 / 停止时仍可由 `CoreManager` 强制清零。

没有回退或调整 `ac116be0`：Bacon watcher 的三份状态仍在同一个 main block 内提交，死锁修复和
成组状态提交规则都保留。没有加临时日志；调用点、唯一写点和 FIFO 顺序已经能把显示路径唯一确定。

### 对 review 侧七条的复核

七条按字面都成立，但 4 / 5 / 7 推出的“最终应该隐藏”不成立：

1. `visibility` 确实只等于 `!isModalOpen`。
2. setter 确实无条件额外发送一次 `"visibility"` 通知。
3. 旧的 `Tier7PreLobby.update("visibility")` 确实没有场景、模式或设置门，这正是被删除的旁路。
4. `updateBattlegroundsOverlays()` 确实按 controller 的 `isVisible` 显示 / 隐藏。
5. 规范方法确实有 `.bacon` 门，构筑局会先算出 false。
6. `.gameplay` 确实会启动 Bacon watcher；而且 `_prev == nil` 保证首次采样会触发
   `setBaconState`，不只是“理论上在跑”。
7. `updateBattlegroundsOverlays()` 确实总会延后一轮；误判在于假设延后执行时 `isVisible` 仍是
   规范方法写下的 false，实际上更晚的 `"visibility"` 回调已把它重写为 true。

`viewModel.visibility` 和 controller 的 `isVisible` 本来就不应等价：前者只表达“战棋界面是否有
modal”，后者表达综合场景、运行状态、队列、设置、战棋模式及前者之后的最终显示决定。旁路强行让
两者相等，正是构筑局误显示的直接原因。

### 验收状态

- 任务书指定的受限环境 Debug build 已通过：`** BUILD SUCCEEDED **`。
- 标准模式一局仍待人工验收；当前环境不能代替用户操作炉石，不把静态结论冒充实战结果。
- 战棋正常路径未受影响：进入 `.bacon` 时 `SceneHandler` 会调用
  `updateTier7PreLobbyVisibility()`；Bacon watcher 更新模式 / modal 后也会在同一个 main block
  再调用它。条件满足时该方法仍把 controller `isVisible` 设为 true、更新 view model 并直接显示
  窗口；本次只删除了绕过这些条件的第二条显示路径。
