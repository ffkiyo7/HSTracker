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

- pbxproj 里另有一处 `MACOSX_DEPLOYMENT_TARGET = 10.12;`，**属于另一个 target，不要动它**。
  改之前先 `grep -n "MACOSX_DEPLOYMENT_TARGET" HSTracker.xcodeproj/project.pbxproj` 看清楚每一处属于谁。
- **不要清理那 97 处 `@available(macOS 10.15, *)` 守卫。** 提升部署目标之后它们只是恒真，
  仍然完全合法。清理是可选的后续收尾，不在本任务范围，动了会把 diff 撑爆、掩盖真正的改动。
- 不要改 `SWIFT_VERSION`、`ARCHS`、`ONLY_ACTIVE_ARCH` 或任何其它构建设置。
- 不要用 Xcode GUI 去改（会顺带重排整个 pbxproj）。用文本编辑精确改那两行。

## 验收

1. `grep -n "MACOSX_DEPLOYMENT_TARGET" HSTracker.xcodeproj/project.pbxproj` 的输出里，
   原来两处 `10.14` 变成 `14.0`，那处 `10.12` 原封不动。
2. 构建通过。
3. `git diff --stat` 只显示 `project.pbxproj` 一个文件、改动行数很少（个位数）。
   如果 diff 很大，说明文件被重排了，请还原重做。
