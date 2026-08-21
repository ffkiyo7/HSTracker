## 通用约束（所有 Phase 0 任务共用）

项目：HSTracker，macOS 上的炉石传说记牌器，Swift + AppKit。这是个人自用 fork，不需要考虑回合并 upstream。

**仓库根目录就是你当前的工作目录**（`git rev-parse --show-toplevel`）。它可能是一个 git worktree，
路径不固定 —— 任何地方都不要写死绝对路径，更不要 `cd` 到别的 HSTracker 副本去。

完整计划见 `docs/PLAN.md`，动手前先读你的任务所属那个 Phase 的小节建立上下文。

### 硬性规则

1. **只修改本任务书明确指定的文件。** 发现其它地方也有问题，写进最后的报告里，不要顺手改。
2. **不要 commit，不要 `git add`。** 改完留在工作区，由人 review 后统一提交。
3. **不要动 `Config.xcconfig`。** 它已被设为本地签名并标记 `skip-worktree`。
4. **不要改动任何 `.xcstrings` / `.strings` / `.xib`。**
5. 保持与周围代码一致的风格（缩进、命名、注释密度）。这个仓库注释偏少，不要加大段注释；只在改动的原因不明显时写一两行说明**为什么**。
6. 改完必须自己跑一遍验收构建，确认通过：

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker \
  -configuration Debug -destination 'platform=macOS' build
```

构建产物较大、日志很长，只需确认最后是 `BUILD SUCCEEDED`。若失败，读错误自行修复后重跑，直到通过。

### 最后请输出

- 改了哪些文件、每处改动的一句话说明
- 验收构建的结果
- 任何你认为有风险、或发现但按规则没有动的问题

### 工作区已有的改动（不是你造成的，不要还原、不要"顺手修复"）

1. `Config.xcconfig` —— 已改为本地签名，并已 `git update-index --skip-worktree`，`git status` 里看不到它。
2. `HSTracker.xcodeproj/project.pbxproj` —— "Embed Mono" build phase 里的 `NET_VERSION=net7.0` 已改为 `net8.0`。
   这是修 upstream 的一个真实 bug：commit `d70efe05` 把 `HSTracker/mono-version.txt` 从 `7.0.20` 升到 `8.0.29`，
   但没同步更新脚本里的 `NET_VERSION`，导致全新 clone 必然构建失败（下载到的 8.0.29 只有 `net8.0` 目录）。
   **除非你的任务书明确指定要改 pbxproj，否则不要动这个文件。**

基线状态：上述两处改动到位后，Debug 构建 `BUILD SUCCEEDED`，`downloaded-frameworks/` 已暖好。
