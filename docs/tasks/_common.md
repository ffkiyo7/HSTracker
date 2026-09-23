## 通用约束（所有任务书共用）

项目：HSTracker，macOS 上的炉石传说记牌器，Swift + AppKit / SwiftUI。个人自用 fork，不回合并 upstream。

**仓库根目录就是你当前的工作目录**（`git rev-parse --show-toplevel`）。它可能是一个 git worktree，
路径不固定 —— 不要写死绝对路径，不要 `cd` 到别的 HSTracker 副本。

规则全文在 `AGENTS.md`；计划与进度在 `docs/PLAN.md`，动手前先读与你任务相关的部分和任务书点名的文档。

### 硬性规则

1. **只修改本任务书明确指定的文件。** 发现其它地方也有问题，写进最后的报告里，不要顺手改。
2. **不要 commit，不要 `git add`。** 改完留在工作区，由人 review 后统一提交。
3. **不要动 `Config.xcconfig`。** 它已改为本地签名并 `skip-worktree`，`git status` 里看不到。
4. **不要改动任何 `.xcstrings` / `.strings` / `.xib`。**
5. 保持与周围代码一致的风格。这个仓库注释偏少，不加大段注释；只在原因不明显时写一两行**为什么**。
6. 改完必须跑 `AGENTS.md`「构建」的受限环境命令，确认 `BUILD SUCCEEDED`；再把 `clean build` 换成 `test` 跑测试，全绿是基线。
   失败就读错误自行修复后重跑，直到通过；不为变绿改被测代码。

### 最后请输出

- 改了哪些文件、每处改动的一句话说明
- 构建与测试的真实结果（条数）
- 任何你认为有风险、或发现但按规则没有动的问题
