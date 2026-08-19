# 进度

> 计划全文见 `docs/PLAN.md`。本文件只记录**做到哪了 / 下一步是什么**，每完成一项就更新。

**最后更新**：2026-08-19
**分支**：`perf/phase0-overlay`（基于 `master` = upstream `ecf64cff` / 3.6.4）
**构建状态**：Debug `BUILD SUCCEEDED`
**当前卡在**：等待人工游戏内实测（Phase 0 效果验证）

---

## 状态总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| T0 | 前置环境 | ✅ 完成 |
| T1 | `WindowManager.show()` 去抖 | ✅ 完成并 review |
| T2 | AX 调用移出主线程 | ✅ 完成并 review |
| T3 | 提高 tick 频率 + 跟窗 | ✅ 完成并 review（review 时加了一处设计改动） |
| — | **游戏内实测** | ⏸ **待办 —— 下一步就是这个** |
| T4 | 部署目标 → macOS 14.0 | ⬜ 未开始（**刻意压后到实测之后**） |
| Phase 1 | SwiftUI 记牌器渲染 | ⬜ 未开始 |
| Phase 2 | 记牌器分区（牌库/手牌/已打出） | ⬜ 未开始（依赖 Phase 1） |
| Phase 3 | 补全简体中文 | ⬜ 未开始（与 0–2 独立，可随时并行） |
| Phase 4 | 设置 UI + Dock 菜单 | ⬜ 未开始（与 0–2 独立，可随时并行） |

---

## 已完成的提交

```
a89fce6d  Record the T2/T3 window-polling interaction found on review
330ef0e8  Raise overlay tick to 10Hz and decouple window polling        ← T3
c6bab26f  Keep Hearthstone window Accessibility reads off the main thread ← T2
45d36c47  Only reassign overlay window properties when they change      ← T1
a7c1aaf2  Add Phase 0 plan and grok task books under docs/
1ff31cb1  Fix Embed Mono build phase for mono 8.0.29                    ← T0
```

T1/T2/T3 的代码由本机 grok-4.6（`--effort xhigh`）按 `docs/tasks/` 里的任务书写成，逐个人工 review 后提交。

## 与计划不一致的地方

**T3 在 review 时改了设计。** 任务书原文写「去掉 `counter > 3`，每个 tick 都刷新窗口矩形」，按字面实现会引入一个回归：
T2 已把 `reload()` 从 `updateAllTrackers()` 里摘掉，于是 `reload()` 只剩在 `else` 分支里；日志密集时
`guiNeedsUpdate` 每拍为真，窗口矩形将长时间不刷新，overlay 被钉在旧位置 —— 比改之前更差。
这是 T2 与 T3 组合才出现的问题，单看任一任务都发现不了。

实际实现：把窗口轮询提到分支之外，并用独立的 **250ms** 阈值节流（不跟随 100ms 的 GUI tick）。
除了让两个分支都拿到新鲜矩形，也是因为每次 `reload()` 是 4 次阻塞式 AX 跨进程调用 ——
真按 10Hz 跑就是每秒 40 次打进炉石自己的 run loop，反而拖累我们想保住流畅度的那个进程。
250ms 把 AX 频率维持在接近原先的水平，同时把跟窗延迟从 ~2s 降到 ~250ms。

见 `Game.swift` 的 `windowPollInterval` / `lastWindowPoll`。

---

## 下一步：游戏内实测

Debug 构建产物：
```
~/Library/Developer/Xcode/DerivedData/HSTracker-aqezlgillbghuralonpbmtmljzam/Build/Products/Debug/HSTracker.app
```

**测之前注意：**
1. 先退出已安装的 3.6.2，否则两个实例会同时 tail 炉石日志。
2. 这个构建是 **ad-hoc 签名**，macOS 视其为与 3.6.2 不同的 app —— 辅助功能（Accessibility）和屏幕录制权限**要单独授予**，不会继承。
3. 启动时会弹「移动到「应用程序」」对话框（`AppDelegate.swift:63` 无条件调 `AppMover.moveApp()`）——
   **选否**，否则 DerivedData 里的构建会把自己搬走。

**该看什么：**
- overlay 对游戏状态的反应从 2fps → 10fps
- 拖动/缩放炉石窗口，overlay 跟随从最长 2 秒 → 约 250ms
- 闪烁减少（`styleMask` 不再每 tick 被重写约 20 次）
- 主线程不再因 Accessibility 调用卡住

**该预期什么：**
Phase 0 完全没碰渲染层。主题 PNG 仍每次 draw 从磁盘重新解码，`AnimatedCardList` 仍每帧拆掉整棵视图树。
所以预期是「更跟手、更少抖」，**不是**「像 Firestone 一样顺」。忙碌回合里仍然发沉是**预期结果，不是失败**。

若要留对照数据：Instruments 的 Time Profiler + Core Animation FPS，重点看主线程 CPU 占用，
以及 `AXUIElementCopyAttributeValue` 是否已从主线程调用栈上消失。

---

## 环境备注（换机器或重开时需要）

1. `brew install wget` —— 两个 build phase 依赖它（下载 HearthMirror 和 Mono）。**不装必然构建失败。**
2. `Config.xcconfig` 已改为本地签名（`CODE_SIGN_IDENTITY = -`），并已 `git update-index --skip-worktree`，
   `git status` 里看不到它。换机器要重做这一步。
3. `project.pbxproj` 里 `NET_VERSION` 已由 `net7.0` 修为 `net8.0`（commit `1ff31cb1`）——
   这是修 upstream 的真实 bug，不是本地 hack。
4. SwiftLint **故意没装**。build phase 里未安装只告警、不阻塞；装了反而会给 grok 的验收构建引入无关失败。
5. git 身份是 repo-local 配置的（`ffkiyo7 / ffkiyo7@gmail.com`），没有写进 global。

## 待办清单里还欠的

- `docs/tasks/` 目前只有 Phase 0 的任务书。Phase 1–4 若也要交给 grok，需要按同样颗粒度另写。
- Phase 1 不建议整块丢给 grok —— 它按任务书执行很稳，但不会替你发现任务书本身有问题（T3 就是例子）。
