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
  "$release_dir/HSTracker.app/Contents/MacOS/HSTracker" \
  2>&1 | tee /tmp/hstracker-t6b-release.txt
```

完整打一局后回到终端按 `Ctrl-C`，再读最后一份累计分布：

```sh
rg '\[latency\] (D breakdown|D part)' /tmp/hstracker-t6b-release.txt | tail -30
```

先看 `D breakdown` 的 `coverage` 是否约等于 100%；再按随后已经降序排列的 `share` 找最大项。
如果 `unattributed / queue gaps` 最大，现有 block 内埋点还不足以决定优化点，应继续拆这只补集，不能
把它猜成某个 block。拿到这一局的 Release 输出之前，不进入第 3 步优化。
