# Phase 0 / T4 — 部署目标提升到 macOS 14.0

先读 `docs/tasks/_common.md` 里的通用约束，再读本文件。

**这个任务要等 T1–T3 完成并且人工做过一轮游戏内实测之后再执行。** 它本身不改善性能，
只是为后续的 SwiftUI 重写（Phase 1）铺路。

## 目标文件

`HSTracker.xcodeproj/project.pbxproj`

**本任务只允许修改这一个文件。**

## 要做的改动

把 `MACOSX_DEPLOYMENT_TARGET = 10.14;` 改为 `MACOSX_DEPLOYMENT_TARGET = 14.0;`。
Debug 和 Release 两处配置**都要改**。

## 明确不要动

- pbxproj 里一共有 **6 处** `MACOSX_DEPLOYMENT_TARGET`，只动其中 2 处：

  | 值 | 归属 | 动不动 |
  |---|---|---|
  | `10.12` ×2 | PBXProject "HSTracker"（工程级默认，配置列表 `439C7E431C7772C000D29859`） | **不动** |
  | `10.14` ×2 | PBXNativeTarget "HSTracker"（`439C7E711C7772C100D29859` Debug / `439C7E721C7772C100D29859` Release） | **改成 `14.0`** |
  | `11.0` ×2 | PBXNativeTarget "HSTrackerTests"（`439C7E741C7772C100D29859` / `439C7E751C7772C100D29859`） | **不动** |

  动手前先 `grep -n "MACOSX_DEPLOYMENT_TARGET" HSTracker.xcodeproj/project.pbxproj` 核对一遍，
  确认待改的两行确实落在上表说的那两个配置块里 —— app target 的两块紧跟着
  `PRODUCT_NAME = "$(TARGET_NAME)";`，工程级那两块没有。
- **不要清理那 97 处 `@available(macOS 10.15, *)` 守卫。** 提升部署目标之后它们只是恒真，
  仍然完全合法。清理是可选的后续收尾，不在本任务范围，动了会把 diff 撑爆、掩盖真正的改动。
- 不要改 `SWIFT_VERSION`、`ARCHS`、`ONLY_ACTIVE_ARCH` 或任何其它构建设置。
- 不要用 Xcode GUI 去改（会顺带重排整个 pbxproj）。用文本编辑精确改那两行。

## 验收

1. `grep -n "MACOSX_DEPLOYMENT_TARGET" HSTracker.xcodeproj/project.pbxproj` 的输出里，
   原来两处 `10.14` 变成 `14.0`，两处 `10.12` 和两处 `11.0` 原封不动 —— 仍是 6 行。
2. 构建通过。本任务改的是**构建设置**，所以验收构建要在**受限环境**下跑（Xcode 由 launchd 拉起，
   既没有 homebrew 的 PATH 也没有代理，命令行两样都继承，不剥掉就测不出真实情况）：

   ```
   cd /Users/wadorudi/Desktop/dev/HSTracker
   env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin \
     xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
     -configuration Debug -destination 'platform=macOS' build
   ```

   改部署目标会让模块缓存整体失效，这一次实际上是全量重编，耗时较长，属正常现象。
3. 提升部署目标后新冒出来的**警告**（deprecated API、恒真的 `@available` 等）**一律不要修**，
   数一数有多少、挑几条有代表性的写进报告即可。
4. `git diff --stat` 只显示 `project.pbxproj` 一个文件、改动行数很少（个位数）。
   如果 diff 很大，说明文件被重排了，请还原重做。
