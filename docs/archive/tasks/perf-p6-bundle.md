# Perf P6 — 包体：去掉没人读的 `HearthDb.xml`，只嵌本机架构的 .NET 库

先读 `docs/tasks/_common.md`。实现分支：从最新 `dev0923` 切 `perf/bundle`。
本书只动 `project.pbxproj` 的构建阶段，和滚动那本没有共同文件，可以并行；按项目目标排在滚动之后。
`AGENTS.md` 规定「`project.pbxproj` 任务没要求就不动」，本书就是这个要求，范围以下面列的为限。

## 为什么

包里有两块用不到的东西，大小取自仓库和构建脚本的注释，没量过成品包：

- `HearthDb.xml`，9.6 MB，是编译器生成的文档注释，运行时没人读。
- Intel 那一半：「Embed Mono」把两套 .NET 基础库都拷进包里，每套约 17 MB（脚本注释原话「~17MB per arch」）。
  用户的机器是 M4，只用 arm64。Debug 包虽然只编本机架构（`ONLY_ACTIVE_ARCH = YES`），这一步照样拷两套。

## 现状（`origin/dev0923` `35a783f6`）

- 「Embed BobsBuddy and HearthDb」（`project.pbxproj:7253-7275`）：`for file in BobsBuddy.dll BobsBuddy.Common.dll HearthDb.dll HearthDb.xml` 拷进包；`inputPaths` 里也有 `HearthDb.xml`（`:7265`）。
- 解包校验阶段（`:7297` / `:7301`）从 `Vendor/Managed/HearthDb.zip` 解出 `HearthDb.xml` 并校验它存在。这一步只写 `downloaded-frameworks/managed`，不进包。
- 「Embed Mono」（`:7159` 起）：`EMBED_ARCHES="osx-arm64 osx-x64"` 写死，两套都拷进 `Contents/Resources/Managed/{arm64,x64}`；`outputPaths` 两套都列着；`libcoreclr.dylib` / `libSystem.Native.dylib` 是 universal。
- 运行时按架构挑目录：`Mono/MonoHelper.swift:409-413`。

## 要做出什么

1. 「Embed BobsBuddy and HearthDb」不再拷 `HearthDb.xml`，`inputPaths` 同步去掉。解包校验阶段不动：它只管 vendored 包是否完整，`AGENTS.md` 也规定这两个库只走 `Vendor/Managed/` + `scripts/update-managed-deps.sh`。
2. 「Embed Mono」按本次构建的 `$ARCHS` 决定拷哪几套（`arm64` → `osx-arm64`，`x86_64` → `osx-x64`），`outputPaths` 跟着改成只覆盖实际产物。在 M4 上 Debug 和 Release 都应该只剩 arm64 一套。
3. Release 构建只出 arm64：在 HSTracker target 的 Release 配置里限定 `ARCHS = arm64`，或用其他等效设置，写进报告。
4. 两个 universal dylib 要不要 `lipo -thin`，你量完再定：省得多就做，省得少就在报告里写数字、不做。

## 不在本片

- 整个去掉 Mono / Bob's Buddy：要给 `HSTracker/Mono/` 下约 50 个文件加条件编译，还要摘掉运行时的链接。P3 之后不玩战棋就不会加载 Mono，剩下的只是磁盘。
- `NanumGothic.ttf`（4.3 MB，只有韩文用）、`grid.db`（4.3 MB，天梯统计格）：都在 `HSTracker/Resources/` 里，`AGENTS.md` 不许改写这个目录，用户也没定。
- `CardDefs.bin` 的 14 种语言：内存映射，只占磁盘。

## 硬约束

- `NET_VERSION` 保持 `net8.0`；`MACOSX_DEPLOYMENT_TARGET` 不动（PLAN「合并还要保住」）。
- 不改写 `HSTracker/Resources/`；不动 `Vendor/Managed/`、`*-version.txt`、`scripts/update-managed-deps.sh`。
- 只有 github.com 走代理（`AGENTS.md`「构建」）。
- FF 本机有未提交改动的文件一律不碰：`Fork/PlayerCardZones.swift`、`TagChangeActions+ZoneLatches.swift`、`Logging/Entity.swift`、分区相关测试、`RedDragonOverlayModel` / `RedDragonOverlayView` 及其测试、`docs/PLAN.md`。

## 允许修改的文件

- `HSTracker.xcodeproj/project.pbxproj`：只动上面点名的两个构建阶段和 Release 的架构设置

## 验收

1. Debug `clean build` `BUILD SUCCEEDED`；全套测试只允许 PLAN 里记着的两条老失败。
2. Release `clean build` 成功（只编 app，Release 测试 target 编不过是已知问题，见 PLAN「等你定」）。
3. 报告给出，改前改后各一组：
   - `du -sh` 整个 `.app`，以及 `Contents/Resources/Managed`、`Contents/Resources/Resources/Managed`；
   - `lipo -archs` 主可执行文件和两个 dylib；
   - 包里没有 `HearthDb.xml`，`Managed/` 下只有 `arm64`。
4. 启动正常，构筑对局正常。Bob's Buddy 只做静态确认：`MonoHelper.load()` 找的 `Managed/arm64` 还在、内容完整。
   想顺手看就进一次战棋大厅（P3 合入后），看日志出现 `Bob's Buddy is ready`。

## 汇报

结果写进本文件末尾「执行结果」一节：改动清单、两次构建结果、测试条数、改前改后的大小表。
**不要 commit，不要动 `docs/PLAN.md`。**
