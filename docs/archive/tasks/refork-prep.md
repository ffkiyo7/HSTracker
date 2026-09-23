# 重建 fork 前的减负（三片）

先读 `AGENTS.md`。背景：上游把 overlay 重写成单一画布，我们要在其下个 tag 上重建 fork。
本书三片的目的都是**把 fork 对上游文件的改动面压到最小**，行为一律不变。
三片互相独立，各自报告。对照基线：上次合并点 `8ea0eaea`。

工作区里两个 `.xcstrings` 的未提交改动不是你的，不要还原、不要提交、不要动。
`Game.swift` / `Tracker.swift` 里带 `[T11]` 的诊断日志原样保留。

## A. 分区逻辑搬出 `Player.swift`

- `CardZoneGroups`、`PlayerTrackerSnapshot` 以及只为分区服务的成员，搬到 `HSTracker/Fork/` 下的新文件（`extension Player`）。
- 目标是 `git diff 8ea0eaea -- HSTracker/Logging/Player.swift` 尽可能小。搬不走的（改了上游已有函数体的、必须放宽访问级别的）留下，报告里逐条列出为什么。
- 行为不变：不改任何测试的期望，不改分区结果。
- 新文件登记 pbxproj 4 处。

## B. `LatencyProbe` 埋点收到 ≤3 处

- 上游文件（`Game.swift`、`Watchers.swift`、`LogReaderManager.swift`、`SceneHandler.swift`）里对 `LatencyProbe` 的调用合计 ≤3 处。留哪几处你定，要求是仍能得到「日志行 → 面板提交」的端到端延迟。
- 刷新合并（`scheduleGuiUpdate` / `runGuiUpdate` 及其时序）不许变。这是卡顿相关路径，动了要在报告里论证等价。
- `Utility/LatencyProbe.swift` 里因此变成死代码的部分删掉。
- 报告给出 `git diff 8ea0eaea --stat` 在这四个文件上的前后对比。

## C. zh-Hans 注入脚本

- 新增 `scripts/inject-zh-hans.py`：输入「上游版 catalog」和「我们的 catalog」，按 key 把我们的 zh-Hans 译文注入上游版，输出合并结果。
- 输出与上游版的差异**只能是新增的 zh-Hans 块**：不增删 key、不动其他语言、不改格式（分隔符、缩进、key 顺序、转义与 Xcode 写出的一致）。
- 上游已有 zh-Hans 的 key：默认保留我们的，并在报告里列出两边不同的条目。
- 我们有、上游已无的 key 或整个 catalog：不注入，列进报告。
- 幂等：对输出再跑一次，结果不变。
- 验收用干跑：对 `git show upstream/master:<path>` 取出的全部 catalog 跑一遍，输出写到临时目录，**不写进仓库**。报告每个 catalog 的注入数 / 跳过数，以及上面两类清单的条数。
- 只依赖 Python 3 标准库。

## 允许修改的文件

- A：`HSTracker/Logging/Player.swift`、`HSTracker/Fork/` 下新文件、`project.pbxproj`（仅登记新文件）
- B：上述四个上游文件、`HSTracker/Utility/LatencyProbe.swift`
- C：`scripts/inject-zh-hans.py`

## 验收

1. A、B：受限环境 Debug `clean build` → `BUILD SUCCEEDED`；`test` 全绿（基线 165 条，`SecretTests` 有既有 flake，出现时单独说明）。
2. C：干跑结果 + 幂等验证。
3. 不 `git add`、不 commit、不动 `docs/PLAN.md` / `docs/PROGRESS.md`。

## 汇报

结果写进本文件末尾「执行结果」，A / B / C 各一小节，每节 ≤15 行：改了什么、前后数字、没做成的和你怀疑但没证实的。

## 执行结果

### A. 分区逻辑搬出 `Player.swift`

新文件 `HSTracker/Fork/PlayerCardZones.swift`（300 行），pbxproj 登记 4 处（新建 `Fork` group）。
`git diff 8ea0eaea -- HSTracker/Logging/Player.swift`：**+336/-14 → +47/-14**。测试未改，165 条全绿。

搬走：`CardZoneGroups`、`PlayerTrackerSnapshot`、`playerCardListWithoutDeck`、`cardsInHandByCardId`、
`zoneCardId`、`knownCardsInDeckZone`、`entitiesThatLeftTheDeck`、`shuffledIntoDeckByCardId`、
`shuffledCopiesThatLeftTheDeck`、`cardsThatLeftTheDeck`、`cardsInHandFromDeck`、`zoneGroups`、
`var playerCardGroups`、`opponentCardGroups`。

搬不走，逐条：
1. `playerTrackerSnapshot`、`playerCardList(deckState:sideboards:)`、`playerCardGroups(sideboards:)`
   —— 要读 `private let game` 和 `fileprivate getDeckState()`，别的文件里的 `extension` 拿不到。
2. `playerCardList`、`playerSideboardsDict`、`annotateCards`、`playerSideboards(from:)` —— 改的是上游已有
   函数体（把一次 `getDeckState()` 的 sideboards 穿下去），整体搬出反而要把上游函数删掉，diff 更大。
3. `deckStateEvaluations` —— Swift 的 extension 放不了存储属性，自增也在 `getDeckState()` 体内。

约束存疑：把 `private let game: Game` 放宽成 internal 只要 1 行，第 1 条约 40 行新增就能一起搬走。
任务书写明「必须放宽访问级别的留下」，所以没做，数字摆在这里由你定。

怀疑未证实：`var playerCardGroups` 搬出后去掉了外层 `guard game.currentDeck != nil`（内层 guard 仍在），
无牌组时多跑一次 `getDeckState()`，返回值不变，只影响没人断言的 `deckStateEvaluations`。未做 overlay 实测。

### B. `LatencyProbe` 埋点收到 ≤3 处

上游文件里只剩 3 条调用，是端到端链的三个必需点：
1. `LogReaderManager.processLine` → `logLineStarted(time:)`：日志行时间戳入口（A 段仍在）。
2. `Game.updateTrackers` → `updateRequested()`：放在 `_queue.async` 之前，跑在解析线程上才认得出本行。
3. `Game.runGuiUpdate` 双层 `main.async` 里 → `updateCommitted()`：面板提交点，E2E 在这里落账。

合并与删除：`captureUpdateRequest()` + `updateRequested(request:)` 并成一个自取线程上下文的
`updateRequested()`；`logLineFinished()` 删掉，改成「认领即消费」，旧时间戳不会被记到后来的刷新上。
丢掉 C（debounce）和 D（渲染分项 / runloop gap）两段分解，连带 22 处 `renderBlock*`、7 处 `mainQueueWork*`。
`Utility/LatencyProbe.swift` 425 → 149 行。

刷新合并等价：`_queue.async` 闭包只少一条探针语句；`runGuiUpdate` 只少 `updateStarted()` 一条，位置在
`guiUpdateInFlight = true` 与 `updateAllTrackers()` 之间；双层 `main.async`、debounce 常量、
`guiUpdateScheduled` / `guiUpdateInFlight` 一律未动。探针默认关闭时每次调用只做一次静态 Bool 判断。
与探针同批加的 `DispatchQueue.main.async` 跳转保留 —— 那是 AGENTS.md 的回调写 view model 规则，不是探针。

`git diff 8ea0eaea --stat` 前 → 后：`Watchers.swift` 8/2 → 4/2；`Game.swift` 249/87 → 195/87；
`LogReaderManager.swift` 2/0 → 1/0；`SceneHandler.swift` 5/1 → 3/1。

怀疑未证实：E2E 样本数会变少 —— 刷新在途时到达的请求，其行时间戳被丢弃（旧版由 `updateStarted()` 接手能采到）。
指标定义没变，但分位数可能偏乐观。没开 `HSTRACKER_LATENCY_PROBE=1` 实跑验证过。
