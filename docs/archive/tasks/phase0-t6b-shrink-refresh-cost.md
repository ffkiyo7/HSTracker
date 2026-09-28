# Phase 0 / T6b — 压一轮 GUI 刷新的成本

先读 `docs/tasks/_common.md` 里的通用约束。

## 目标

E2E（日志行 → 画面）现行 Release 基线 **p50 = 350ms**。要把它压下来。

## 方向（这一条是定死的，别自己改目标）

**打 D 段，不要打 A 段，也不要直接调 C 段的防抖。**

| 段 | p50 | p95 |
|---|---|---|
| A 日志行 → 解析 | 152.1 | 285.3 |
| B 解析 → 置位 | 0.3 | 8.6 |
| C 置位 → tick | 114.5 | 202.4 |
| D tick → UI 提交 | 81.7 | 269.4 |
| **E2E** | **350.0** | **622.2** |

理由：

- **A 段基本是地板。** 152ms 里绝大部分是炉石自己的写盘节奏，我们只占轮询那一小块。
- **C 段是 D 的因变量。** `Game.guiUpdateDebounce` 只有 16ms，解释不了 114.5 —— 其余是
  `guiUpdateInFlight` 闸门在等上一轮刷新提交完。**D 降下来 C 会跟着降**，反过来单独调 C
  只会让刷新更容易堆积。
- 所以 **C + D 合计 196ms 是 350ms 里唯一能动的部分，而入口是 D。**

D 段量程是 T6 第 1 步刚修正过的，覆盖的是**一整轮 UI 提交**（不是某一个 block）。
所以「D = 81.7ms」的意思是：一轮刷新占住主队列 82ms。**这 82ms 花在哪，目前没人知道。**

## 顺序是死的

1. **先 spike**：把这 82ms 的构成测出来，交出一份分布。
2. **停下来**，把结果交给用户跑一局取数确认。
3. **拿到数据再谈优化。** 在第 2 步完成之前不许改任何刷新参数、不许动数据流。

这个仓库在"没数据就动手"上已经栽过两次（Debug 当 Release 用、D 段量程错了一整轮）。

## 硬约束

- **不要动 `ac116be0` 修好的线程归属**（watcher 回调必须回主线程写 view model），
  也不要动 `eb52832e` 的 Tier7 显示路径。
- **不要靠"少刷新"来降 D。** 拉长防抖、跳过某些刷新、降低 tick 频率都是把延迟转嫁给
  正确性，不算数。要降的是**一轮刷新本身的成本**。
- 新加的埋点参照 `LatencyProbe` 现有的做法：`HSTRACKER_LATENCY_PROBE=1` 才开启，
  关闭时开销必须可忽略。
- **取数必须用 Release 包。** Debug 的 `-Onone` 会让 D 段数据完全不可用 —— 这条踩过。
- 不要 `git add` 或 commit，不要动 `.xib`，不要动 `HSTracker.xcodeproj/project.pbxproj`。
- ⚠️ **`docs/tasks/build-t2-fix-test-target.md` 正在并行进行。** 那本只动测试 target 和
  `project.pbxproj` 的测试配置，不碰 `HSTracker/` 下的运行时代码 —— **本任务也不要去碰
  测试 target**，两边各守各的，避免互相污染和冲突。

## 验收（第 1 步）

1. 受限环境 Debug build `BUILD SUCCEEDED`：

   ```sh
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

2. 说清楚新埋点**测的到底是什么**，以及为什么它加起来能覆盖住 D 段的 81.7ms
   —— 有没有覆盖不到的缝隙，有就直说。

3. 给出用户要跑的确切命令，和跑完之后怎么读那份输出。

## 背景资料

- 现行基线原始 dump：`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-30-release-t6.txt`
- 基线怎么读出来的：`docs/PROGRESS.md` 的「延迟实测」整节
- 前一本（T6 第 1、2 步，已完成）：`docs/archive/tasks/phase0-t6-latency-spike.md`
  —— **里面那组 Debug 数据已作废，不要拿它做任何判断。**

## 第 1 步执行结果（2026-08-30）

spike 已完成，到此停止，没有改刷新参数、刷新频率或数据流。

- `Game.updateAllTrackers()` 投递的 18 个一级主队列 block 全部单独计时；计数器和构筑留牌层条件投递的
  4 个二级 block 也单独计时。
- 每轮沿用原 D 的同一对起止点：`updateStarted()` 到双层 marker 中的 `updateCommitted()`。
  分解恒等式是「首次主队列等待 + 22 个命名 block 的实际执行时间 + 未归因间隙 = D」。最后一桶是
  用原 D 减掉前两项算出的补集，包含 block 间被其他主队列工作占用的时间、marker turn，以及目前
  没有单独命名的内层工作。因此**分类仍有一桶未知，但量程没有空洞**。
- 每 30 秒的 dump 先保留原 A / B / C / D / E2E 五行，再按累计耗时占比从高到低打印 `D part`。
  每个 part 同时给出逐轮 p50 / p95 / p99 / max、平均值、累计值和占 D 的比例。
- 探针关闭时，`renderBlockStarted` 在取时间、加锁或分配样本前由静态 `enabled` 返回 nil；配对的
  `renderBlockFinished` 也在 nil 上直接返回。正常运行只多一次静态判断、一次 nil 判断和函数调用。

受限环境 Debug build 输出 `BUILD SUCCEEDED`。另用 Debug 包做了两轮烟雾样本，只验证输出：原 D
`total=73.5ms`、分项 `componentTotal=73.5ms`、`coverage=100.0%`。Debug 数值不用于性能判断。

### Release 取数命令

先确保没有别的 HSTracker 实例，再在仓库根目录运行：

```sh
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Release -destination 'platform=macOS' build

release_dir="$(env PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Release -destination 'platform=macOS' -showBuildSettings \
  | awk -F ' = ' '/TARGET_BUILD_DIR =/ { print $2; exit }')"

HSTRACKER_LATENCY_PROBE=1 \
  "$release_dir/HSTracker.app/Contents/MacOS/HSTracker"
```

⚠️ **首次从 DerivedData 直接启动会卡在 AppMover 的 "Move to Applications folder" 模态框上。**
它在 `applicationWillFinishLaunching` 里阻塞，而日志系统在之后的 `applicationDidFinishLaunching`
才配置 —— 表现为"进程在跑但一个字都不写日志"，极容易误判成没启动。窗口常被炉石盖住，
需要切到 HSTracker 点 **Don't Move**。

完整打一局后**先别关 HSTracker**（探针每 30 秒 dump 一次累计值），再读最后一份累计分布：

```sh
grep '\[latency\]' ~/Library/Logs/HSTracker/hstracker.log | tail -30
```

⚠️ **必须从日志文件读，不能从 stdout 读。** `ConsoleDestination` 在
`AppDelegate.swift:200-203` 被 `#if DEBUG` 包着，`FileDestination` 才是常开的 ——
Release 包的 `[latency]` 一行都不会出现在终端上，`tee` 出来的文件是空的。
（2026-08-31 实际踩到，浪费了一局。）

先看 `D breakdown` 的 `coverage` 是否约等于 100%；再按随后已经降序排列的 `share` 找最大项。
如果 `unattributed / queue gaps` 最大，现有 block 内埋点还不足以决定优化点，应继续拆这只补集，不能
把它猜成某个 block。拿到这一局的 Release 输出之前，不进入第 3 步优化。

## 第 1 步取数结果（2026-08-31 实战一局，Release）

完整 dump 存档：`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-31-release-t6b.txt`。

`coverage = 100.0%`，恒等式闭合。**但补集就是最大项：**

| D part | p50 | avg | share |
|---|---|---|---|
| **unattributed / queue gaps** | **44.0** | 44.2 | **61.8%** |
| player tracker | 6.9 | 9.1 | 12.7% |
| first main-queue wait | 0.1（p95 42.3 / p99 93.3） | 8.0 | 11.2% |
| counters | 3.4 | 3.7 | 5.1% |
| 其余 18 项合计 | — | ~6.6 | 9.2% |

D 中位数 63.8ms，其中 44.0ms 不在任何一个命名 block 里；22 个 block 的代码加起来只有约 19.5ms。

**所以按第 1 步自己写下的判据，现在不进入第 3 步优化。** 先做第 2 步。

## 第 2 步 —— 把补集拆开

### 要回答的问题

那 44ms 是谁的。**只要它还是最大项，任何优化都是猜。**

补集的物理位置是确定的：`Game.updateAllTrackers()` 里 18 个 `updateXxx()` 各自
`DispatchQueue.main.async`，一轮刷新因此被切成 18 个独立的主队列 turn，补集落在这些 turn 之间。

**至少要把下面两类分开** —— 它们对应完全不同的优化，混在一起等于没测：

1. **runloop 自己的工作**：AppKit layout / display、CATransaction 提交、SwiftUI 刷新。
   如果是这一类，成本随 turn 数走，优化方向是**减少 turn**。
2. **别人投进主队列的 block 插队**：`ac116be0` 刚把 7 条 watcher→UI 写路径搬上主队列，
   其中 `DiscoverStateWatcher` 是 16ms 一次。如果是这一类，减少 turn 没用，
   优化方向是**别让它们插在刷新中间**。

怎么测由你定。**别预设答案** —— 上面两类是"至少"，不是"只有"；测出来是第三种更好。

### 硬约束（除了本任务书前面那些）

- **这一步仍然只测量，不优化。** 不要顺手合并 block、不要改投递顺序、不要改防抖。
  第 1 步埋点没改 block 结构，这一步同样不许改 —— 一旦改了，新数据和第 1 步就不可比。
- 新埋点同样只在 `HSTRACKER_LATENCY_PROBE=1` 下生效，关闭时开销可忽略。
- 保住加法恒等式。补集被拆细之后，**新的分项加起来仍要等于原来的补集**，
  `coverage` 仍要约等于 100%；做不到就说清楚哪里漏了，不要让它悄悄不闭合。
- ⚠️ **`docs/tasks/bug-t4-tracker-visibility-out-of-game.md` 正在并行进行。**
  那本改的是记牌器显示条件（`shouldShow` 的门），不碰刷新路径结构和投递顺序；
  **本任务也不要去碰显示条件**。两边各守各的。

### 验收（第 2 步）

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令同第 1 步）。
2. 说清楚新埋点**测的到底是什么**，以及它凭什么能把上面那两类分开 ——
   分不开的部分直说，不要糊。
3. 给出用户要跑的确切命令和读法。**读法必须是从 `~/Library/Logs/HSTracker/hstracker.log` 读**
   （见上面那条 `#if DEBUG` 的坑）。
4. 预先写下判据：拿到数之后，什么样的结果指向"减少 turn"，什么样的结果指向"别让别人插队"，
   什么样的结果说明还得再拆一层。**这条要在取数之前写死，不许看完数再补。**

## 第 2 步执行结果（2026-08-31）

这一步仍然只有测量，没有合并 block、改变投递顺序、调整防抖或跳过刷新。

- 原补集被拆成两层。第一层精确包住 `ac116be0` 搬到主队列的 7 类 UI 写入；它们只有在确实夹在
  两个刷新 block 之间时才计入各自的 `gap: watcher ...` 桶。
- 第二层只在探针开启时给主 RunLoop 安装 observer，把其余间隙按 `source phase`、
  `timer/observer phase`、`wait/outside`、`transitions` 和 `unknown` 分桶。每次 RunLoop phase
  翻转先结算上一段时间；进入命名刷新 block 或已包住的 watcher block 时暂停 gap 计时，退出后再恢复。
- 原 `unattributed / queue gaps` 仍保留为父级总账，但不再重复加入 D 的加法分项。
  新增 `D gaps additive` 单独校验「五个 RunLoop 桶 + 七个已知插队桶 = 原补集」；原
  `D breakdown additive` 则校验「首次等待 + 22 个刷新 block + 全部 gap 子桶 = D」。
- `source phase` **不是纯 AppKit/SwiftUI**：它还会包含没有显式包住的主队列 block、其它 RunLoop source
  与 libdispatch 自身开销。这个桶若最大，现有粒度仍不足，不能把它改名成渲染成本就开始优化。
- 探针关闭时不安装 RunLoop observer；七个新增调用在静态 `enabled` 判断后立即返回 nil，不取时间、不加锁。

受限环境 Debug build 输出 `BUILD SUCCEEDED`。第一次在沙箱内执行因无权写
`~/Library/Caches/org.swift.swiftpm` 而失败；用完全相同的受限环境命令在本机权限下复核通过，
这是沙箱权限假阴性，不是源码或依赖失败。

另短暂启动 Debug 包做输出烟雾检查，启动期一轮样本得到：
`D breakdown total=87.6ms / componentTotal=87.6ms / coverage=100.0%`，
`D gaps total=34.6ms / componentTotal=34.6ms / coverage=100.0%`。这里只证明格式可读和两层恒等式闭合；
`n=1` 且是 Debug，数值不作任何性能判断。

### 第 2 步 Release 取数与读法

构建和启动仍使用上面「Release 取数命令」的三段命令。完整打一局后先别关 HSTracker，从日志文件读：

```sh
grep '\[latency\]' ~/Library/Logs/HSTracker/hstracker.log | tail -40
```

先检查两行：

1. `D breakdown additive ... coverage` 约等于 100%；
2. `D gaps additive ... coverage` 也约等于 100%。

任一不闭合都先修口径，不解释分布。两行都闭合后，按已经降序排列的 `D part` 看 `share`。

### 取数前写死的判据

- `gap: runloop wait/outside`、`timer/observer phase`、`transitions` 合计明显主导补集：说明刷新被拆成多个
  turn 后，主要时间花在 RunLoop 轮转及等待，下一步才有依据试验减少 turn。
- 七个 `gap: watcher ...` 合计明显主导，尤其是 `watcher discover highlight`：说明已知 watcher 主队列
  block 确实在刷新之间插队，下一步应处理这些写入的排队方式，不能靠合并刷新 block 猜着治。
- `gap: runloop source phase` 仍是最大项：该桶混着 AppKit/SwiftUI、未包住的 app/framework 主队列任务和
  source 处理，必须再拆一层或用 Instruments 对同一 D 区间取调用栈，仍不进入优化。
- `gap: unknown runloop phase` 占比不可忽略，或两条 coverage 偏离 100%：说明 observer 安装或阶段映射
  本身不可靠，先修测量。

### review 补的两条读数注意（2026-08-31）

**(1) `wait/outside` 桶里装的是 CoreAnimation 提交，这是判据一能成立的原因。**
observer 用 `order = 0` 注册，而 CA 的提交 observer 是 `beforeWaiting` 上的 order 2000000 ——
我们先于它翻到 `.waiting`，所以 AppKit layout / display / CA commit 的时间会落进
`gap: runloop wait/outside`。**判据一（"wait 主导 ⇒ 试验减少 turn"）依赖这个 order 关系。**
以后谁改了 observer 的 order 或 activity 掩码，桶的含义会静默翻转而不报错。

反过来也要记住：**多个主队列 block 可以在同一次 runloop pass 里连续排空，中间根本不翻阶段**。
所以如果 18 个 block 之间没有 runloop 轮转，整段间隙会落在最后一次观察到的阶段（多半是 `sources`）。
这正是判据三要挡的情况 —— `sources` 最大不等于"AppKit 贵"，等于"还没测到"。

**(2) 第 2 步的 D 绝对值不能和 8-31 那份直接比。** observer 挂在主 runloop 的全部 activity 上，
每次翻转都要取一次时间并抢一次探针锁，这份开销落在 D 窗口**里面**。
按 runloop 轮转频率估算量级在 0.1% 以下，不影响结论，但方向是抬高 D。
**要看的是本轮内部各桶的 share，不是和上一轮的差值。**

## 第 2 步取数结果（2026-08-31 实战一局，Release）

完整 dump 存档：`~/Desktop/dev/HSTracker-ab/logs/probe-2026-08-31-release-t6b-step2.txt`。
两条 coverage 都是 **100.0%**，`gap: unknown runloop phase` 为 0 —— 按判据四，测量本身可靠。
手工复核加法：命名 block 2176.1 + 首次等待 894.2 + 间隙 4779.0 = 7849.3 ≈ D total 7849.4。

D total 7849.4（n=107，p50 66.5 / avg 73.4），补集 4779.0 = **D 的 60.9%**。

| 补集分项 | 占补集 | 占 D | avg | p50 → p95 |
|---|---|---|---|---|
| `gap: runloop source phase` | **51.3%** | 31.2% | 22.9 | 4.2 → 51.9 |
| `gap: runloop wait/outside` | 43.3% | 26.4% | 19.3 | 4.9 → 60.7 |
| `gap: runloop transitions` | 5.3% | 3.2% | 2.4 | 0.3 → 7.7 |
| `gap: runloop timer/observer phase` | 0.1% | 0.1% | 0.1 | 0.0 → 0.3 |
| **`gap: watcher ...` × 7** | **0%** | **0%** | — | — |

### 判据逐条结算

- 🟢 **判据二否定，而且干净。** 七个 watcher 桶全程零样本，包括 16ms 一跳的
  `DiscoverStateWatcher`。`ac116be0` 搬上主队列的 UI 写入**一次都没夹在刷新 block 之间**。
  **"合并 turn 没用、要改 watcher 排队方式"这条路走死了，以后不必再回头看。**
  同时说明那次线程修复没给刷新路径引入插队成本。
- 🟡 **判据一拿到了一半的实证。** `wait/outside` 占补集 43.3%、占 D 的 26.4%，avg 19.3ms/轮。
  按上面 review 补的那条，这个桶装的是 runloop 休眠 + CoreAnimation 提交 + AppKit display。
  **一轮刷新平均 19.3ms 花在"我们的 block 之间、系统在提交画面"上 —— 多 turn 确实在收费，
  这不再是假设。**
- 🔴 **判据三命中，所以仍然不进优化。** `source phase` 是补集里的最大项（51.3%）。
  它按设计就是混的：没被显式包住的主队列 block、其它 RunLoop source、libdispatch 排空开销。
  **一半把握不足以支撑"把 18 个投递合成 1 个"这种爆炸半径的改动** ——
  这个仓库在主队列时序上已经咬过两次（Tier7 时序、`ac116be0` 的排序副作用）。

### 另外两条读数结论

- **两个大桶都是尾部重的**：source p50 4.2 / p95 51.9 / max 278.5，wait p50 4.9 / p95 60.7。
  中位数那一轮刷新其实很便宜，均值被尾部拉起（D p50 66.5 vs avg 73.4）。
  **以后判断优化收益要盯 p95，只看 p50 会低估。**
- **结构在两局之间高度一致**：补集占比 60.9% vs 61.8%，player tracker 13.2% vs 12.7%，
  counters 5.3% vs 5.1%，首次等待 11.4% vs 11.2%。两次独立采样吻合到这个程度，
  说明这个结构是真的，不是单局噪声。

## 🔻 第 3 步已取消，本任务书到此结案（2026-08-31）

**下面第 3 步的内容不再执行，保留只为记录当时的设计。**

第 2 步交出数据后复查了整个 T6 的前提，结论是**主动收在测量阶段，不做延迟优化**。
完整理由写在 `docs/PLAN.md` 的 Phase 0 一节和 `docs/PROGRESS.md`「延迟实测」末尾，
一句话版本：**压延迟这个目标没有用户反馈支撑，而且是这套探针自己证伪的** ——
唯一一条听起来像延迟的反馈①，探针一测就证明不是延迟。
四轮下来没降一毫秒，天花板又只有 E2E 317 → 约 230ms，而 Phase 1 / T6 才是真正的堵点。

**本任务书的实际产出**：D 段的可加总分解、两轮 Release 分布、四条排除法结论
（A 是地板 / C 是 D 的因变量 / 22 个 block 的代码只占 D 的 27% / watcher 插队约等于 0），
以及一个默认关闭、口径自洽的探针。这些都保留。

**唯一延续下去的候选是「合并 18 次主队列投递」，但它换了立项理由** ——
不是为了快，是因为 `wait/outside` 非零证明**一轮刷新中间至少发生过一次 CoreAnimation 提交、
各段不落在同一帧**。它现在归 `docs/PLAN.md` Phase 0 的「唯一留下的候选」一节管，
排在 Phase 1 的 T5 / T6 之后，验收标准是肉眼看各段是否同步，**不是看 p50**。

---

<details>
<summary>以下为已取消的第 3 步原文（存档，不执行）</summary>

### 要回答的问题

**`source phase` 那 22.9ms/轮里，有多少是"合并 turn 就能消掉"的。**

这是唯一还挡在优化前面的问题。已知它混着至少三类：没被显式包住的主队列 block、
其它 RunLoop source、libdispatch 自身的排空开销。**这三类对合并 turn 的响应完全不同** ——
第一类里属于刷新下游的部分会跟着塌掉，第三类会按 turn 数线性减少，第二类纹丝不动。

怎么测由你定。埋点、RunLoop source 归因、对同一 D 区间取调用栈都行。**别预设答案。**

### 这一步有退出条件，不许无限测下去

已经为这件事花掉用户两局了。**第 3 步是最后一轮纯测量。**

- 如果这一轮能把 `source phase` 拆到足以判断合并 turn 的收益 —— 进第 4 步优化。
- **如果这一轮仍然拆不动**（新的最大项依旧是个混桶、或者 coverage 不闭合），
  **就不要再开第 4 轮测量**。改为直接把"合并投递"当作一次**带内建度量的实验**来做：
  探针现有的口径已经能回答它有没有用（D、`wait/outside`、`source phase` 一起看）。
  那时的爆炸半径由 review 和实战验收兜，不再由测量兜。
  **这条现在就写死，省得到时候顺着惯性再测一轮。**

### 硬约束（除了本任务书前面那些）

- **这一步仍然只测量，不优化。** 不合并 block、不改投递顺序、不改防抖。
- 新埋点同样只在 `HSTRACKER_LATENCY_PROBE=1` 下生效，关闭时开销可忽略。
- **保住两层加法恒等式。** `source phase` 被拆细之后，新分项加起来仍要等于原来的
  `source phase`，两条 coverage 都要约等于 100%。
- **不要动 `gap: watcher ...` 那七个桶。** 它们这一轮的零值是一条有价值的否定结论，
  留着当回归哨兵。**但阈值不是"任何非零"** —— 同一次运行在主菜单空转到 n=339 时，
  两个桶蹭出了痕量值（合计 0.1ms / 25373ms）。要看的是 share 有没有到能和
  `source phase` / `wait/outside` 相提并论的量级。
- ⚠️ **`docs/tasks/bug-t5-tracker-visibility-consistency.md` 正在并行进行。**
  那本只碰显示条件，不碰刷新路径结构和投递顺序；**本任务也不要去碰显示条件**。

### 验收（第 3 步）

1. 受限环境 Debug build `BUILD SUCCEEDED`（命令同第 1 步）。
2. 说清楚新埋点凭什么能把上面那三类分开，分不开的部分直说。
3. 给出确切的取数命令和读法（从 `~/Library/Logs/HSTracker/hstracker.log` 读）。
4. **取数之前**写死判据，包括"什么结果算拆不动、该触发上面那条退出条件"。

</details>
