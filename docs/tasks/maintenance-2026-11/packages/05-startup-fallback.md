# 包 5　启动侧兜底和 Debug 失效开关（W2a、W2d），以及 W2 的整体实机验收

> 总 spec：`../spec.md`。顺序第 5，依赖包 4。

## W2a　日志目录兜底

### 现状【核实】

- `CoreManager.swift:316-334`：在后台线程调用 `MirrorHelper.getLogSessionDir()`，结果回到主线程交给 `finishStartTracking`。
- 拿到空串就 `retryStartTracking`，每秒重试一次，没有上限。
- 如果 `HearthMirror(pid:blocking:true)` 本身卡住，回调永远不会来。

### 要做的事

1. **启用条件**：`getLogSessionDir()` 连续失败 N 次（建议 5 次），或者从 `startTracking` 起超过 T 秒（建议 15 秒）还没返回，就启用兜底。
2. **选目录**：在 `<Settings.hearthstonePath>/Logs/Hearthstone_YYYY_MM_DD_HH_MM_SS` 中，选目录名时间**不早于** `CoreManager.hearthstoneApp?.launchDate`（容差几秒）的最新一个。没有符合条件的目录就继续等。
3. **计时**：超时由 `CoreManager` 自己的计时器负责。闭源的 `HearthMirror(pid:blocking:)` 没法加超时。
4. **只启动一次**：兜底启动之后，要忽略迟到的 HearthMirror 回调。路径相同就静默忽略，不同就记 warning。不允许第二次重建 `LogReaderManager`。现有的 `trackingGeneration` 机制要一起考虑。
5. **线程**：计时器、选目录、启动读取都在主线程执行，和现在的 `finishStartTracking` 一致。
6. **日志**：写明「日志目录来自兜底」和所选的路径。

## W2d　Debug 专用的「模拟 HearthMirror 失效」开关

- **要做**：只在 `#if DEBUG` 下生效，新增 UserDefaults 开关 `fork.debug.simulateMirrorFailure`。打开后 `MirrorHelper` 的所有读取都返回 nil 或空串。
- **启动方式**：先从菜单栏完全退出正在运行的 HSTracker，否则 `open` 只会把已有窗口调到前台，`--args` 不生效。

  ```bash
  open ~/Library/Developer/Xcode/DerivedData/HSTracker-batppbchpubuefehmmfbulefeevu/Build/Products/Debug/HSTracker.app --args -fork.debug.simulateMirrorFailure YES
  ```

- **限制**：这个开关只能模拟「HearthMirror 立刻返回失败」。「调用卡住、一直不返回」的情况要靠下面的单元测试覆盖。

## 验收

- **单元测试**：
  - 选目录的函数单独可测。用临时目录造几个会话目录，覆盖「有新目录」「只有旧目录」「目录名无法解析」三种情况。
  - 把获取日志目录的函数做成可以注入：注入一个永远不返回的实现，确认 T 秒后走了兜底；之后再让它返回，确认迟到的回调被忽略，`LogReaderManager` 只建了一次。
  - Release 配置下没有这个开关（编译期确认）。
- 全套测试通过。
- **实机：第二轮**（你操作，一个 Debug 包）：
  1. 退出 HSTracker 后带开关启动，进第一局前先看日志里有没有「日志目录来自兜底」，确认开关生效。然后打一到两局天梯。期望：
     - T 秒内开始读日志，日志里写着「日志目录来自兜底」；
     - 牌表随抽牌、出牌更新，计数器照常显示；
     - 手动选卡组后，红龙面板正常工作；
     - 自动识别卡组、留牌指南不工作，这是预期的。
  2. 去掉开关重启，再打一局。期望行为和平时完全一致，日志里没有兜底的字样。

## 记录

W2a、W2d 各一个 `feat:` 提交；`docs/PLAN.md` 记提交，实机结果记到构建 / 测试记录里。
