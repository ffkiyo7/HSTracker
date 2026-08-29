# Phase 0 / T6 — 修埋点量程，再打 p50

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。
背景见 `docs/PROGRESS.md` 的「延迟实测」整节 —— **那一节列的两个 🔴 就是本任务的前半。**

**这是一本 spike + 修复合一的任务书，但顺序是死的：**

> **口径没修好之前不许调任何参数、不许做任何优化。**
> 这个坑这个仓库已经踩过两次（Debug 当 Release 用了一次，D 段量程错了一次）。
> 第 1 步做完要**停下来交给人跑一局取数**，拿到数据再进第 2 步。

## 这一轮的实测数据（2026-08-30，卡点 ①）

```
A 日志行 -> 解析完   p50=85   p95=200   p99=272   max=635
C 请求   -> tick    p50=17    p95=116   p99=284   max=481
D tick   -> UI 提交  p50=57    p95=224   p99=401   max=10946
E2E 日志行 -> 画面    p50=171   p95=450   p99=5044  max=9293
```

**两个口径警告，先记住再看数：**

1. **这是 Debug 包**（从 `Build/Products/Debug/HSTracker.app` 起的）。
   `docs/PROGRESS.md` 的「Debug 数据不算数」那条在这里同样成立 —— D 段里有一大块是 `-Onone`。
   **不能和 8-21 / 8-22 那两列 Release 数并排比。**
2. **D 段的量程还是错的**（下面第 1 步就是修它）。所以 `D p50=57` 不是"一轮刷新的耗时"，
   是"第一个 block 的耗时"。

**这组数唯一确定的结论**：p50 层面没有"1-2 回合"那个量级的延迟，用户报的记牌器滞后另有原因
（已定位为 `highlight_cards_in_hand` 的行为，不在本任务范围）。**尾巴是真的**：
E2E p99 5.0s / max 9.3s，且 >10s 的样本被 `outlierCutoff` 直接丢掉、只记进 `dropped` 计数。

## 第 1 步：修口径（三件事，做完就停）

### 1.1 D 段量程

`LatencyProbe.shared.updateCommitted()` 现在在 `Game.updatePlayerTracker()` 那个主队列 block 的
末尾（`Game.swift:455`）。而 `updateAllTrackers()`（`:218`）会往主队列排**约 20 个** block，
`updatePlayerTracker` 只是**第一个**。

`runGuiUpdate()`（`:273`）尾部已经有一个专门为"整轮刷新真的做完了"设计的 marker block
（`:283-290`，注释写着「a block queued behind them runs once the refresh is really done」）。
**把 `updateCommitted()` 挪到那里。**

注意副作用：`updateCommitted()` 同时结算 D 和 E2E（`LatencyProbe.swift:107-120`），
挪了之后**两个数都会变大**，那是修正不是回归。

### 1.2 补 B 段埋点

`docs/PROGRESS.md`：「**B 段至今没有埋点**，而 E2E 的长尾恰恰落在这里。」
口径见该文件末尾的「埋点分段口径」表：**B = `processLine` 开始 → `updateTrackers()` 置位**。

落点：`LogReaderManager.processLine`（`LogReaderManager.swift:129` 调用它）与
`Game.updateTrackers()`（`Game.swift:254`）。B 段要能和 A / C / D 一起出现在 `dump()` 里。

### 1.3 E2E 的归因

`updateRequested()`（`LatencyProbe.swift:83`）把**所有**刷新请求都按「最后一行日志的时间戳」
（`lastLineClock`）归因，包括根本不是日志触发的那些（窗口位置变化 `applyWindowChange`、
设置变更、`setSelfActivated`、延迟重试）。这就是 PROGRESS 说「E2E 的 p99 / max 不可信」的原因。

**两条路选一条并说明理由**：让非日志触发的请求不参与 E2E 统计；或者在 `dump()` 里把两类分开报。
**不要**用"调大 `outlierCutoff`"来掩盖。

### 做完停下

修完这三件，构建通过，**报告写清楚每个数的口径变了什么**，然后停。
人会跑一局 **Release** 取新基线。**不要自己下"变快了/变慢了"的结论** —— 你手上没有可比的数据。

## 第 2 步：拿到新数据之后（等人给数据再开始）

按新数据定位 p50 的构成，然后做优化。**候选清单在 `docs/PROGRESS.md` 的
「Phase 0 剩下的优化候选」**，两条都已定位到行：

| 候选 | 落点 | 预计 |
|---|---|---|
| 两个日志轮询串起来 | `LogReader.swift:144` 和 `LogReaderManager.swift:139` 是**两个互不相干的 50ms `Thread.sleep`** —— 读文件的那圈刚把行放进队列，收集那圈可能刚睡下，期望等待是两段之和 | ~50ms（A 段里属于我们的那部分） |
| 文件轮询换 `DispatchSource` | `LogReader.swift` 的 tail 循环 | ~25ms，完全取决于炉石的 flush 行为 |

**A 段包含炉石自己的 flush 延迟，那是不可优化的地板。** 本轮实测 A p50=85ms，
上面第一条候选如果成立，能拿走的就是这 85ms 里属于我们的那部分 —— 动手前先用新埋点
把"炉石的 flush"和"我们的轮询"分开，**不要拿 A 段的总数当优化目标**。

尾巴（p99 / max）等 1.3 修完归因之后再看是不是真的。

## 关键约束

- **不许动 `Game.guiUpdateDebounce` 的值**（`Game.swift:46`）。PROGRESS 明写「阻塞 Phase 0
  剩下的优化和 `guiUpdateDebounce` 调参 —— 那几项动手前必须先修好量程」。
- **不许动 T5 的两个设计点**（`docs/PLAN.md` Phase 0 / T5 那一节）：不是 trailing-edge debounce；
  `guiUpdateInFlight` 是必需的。改坏任何一条都会让 overlay 在日志密集时饿死或堆积。
- **不许动渲染层。** `Tracker.swift` / `UIs/Trackers/SwiftUI/` / `CardBar.swift` 一律不碰 ——
  那是 Phase 1 的地盘，混进来就没法归因了。
- **埋点本身必须保持零成本。** `LatencyProbe.enabled` 是一次原子读（`LatencyProbe.swift:18`），
  新加的埋点也要走同一个 guard，不能在关闭时还去取时间戳。
- **不要改 `dump()` 的输出格式**到无法和历史数据对照的程度。加新行可以（B 段就要加一行），
  改已有行的含义必须在报告里写清楚。

## 范围边界

- 不做 PROGRESS 里那条「掉帧不是 HSTracker 造成的」的复验，那要换测量手段，是另一件事。
- 不动 `frame_gaps.py` 和录屏分析。

## 允许修改的文件

- `HSTracker/Utility/LatencyProbe.swift`
- `HSTracker/Logging/Game.swift`
- `HSTracker/Logging/LogReaderManager.swift`（第 1.2 步埋点；第 2 步优化时才动逻辑）
- `HSTracker/Logging/LogReader.swift`（**只在第 2 步**）

## 验收

1. Debug 构建通过。
2. `HSTRACKER_LATENCY_PROBE=1` 起 app，`dump()` 能打出 A / B / C / D / E2E 五行。
3. **不开探针时**这些路径不产生额外开销（说明你怎么保证的）。
4. 第 1 步交付后停下等数据；第 2 步的验收是 Release 探针的前后对比，由人跑。

## 报告里请回答

- 1.1 挪了之后 D 和 E2E 的含义各自变成什么。
- 1.2 的 B 段起点终点具体埋在哪两行，为什么是那两行。
- 1.3 你选了哪条路，理由；改完之后 E2E 的 n 会不会变小、变多少。
- 你有没有发现别的口径问题（`outlierCutoff` 丢样本、`maxSamples` 的 `removeFirst`
  会让百分位偏向近期，等等）—— 写进报告，**不要顺手改**。
