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
