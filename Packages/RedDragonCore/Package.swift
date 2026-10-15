// swift-tools-version:5.9
//
// 红龙引擎（卡表 / 局面 / 规则 / 搜索 / 读取 / 展示模型）单独成一个本地包，只为一件事：
// Debug 下也用 -O 编它。用户日常跑 Debug，app 整体 -Onone 时搜索比 -O 慢约 11 倍，线上 3 s CPU 兜底下会漏斩杀
// （T2b 任务书「第二轮」C13）。项目的优化级别不动，只有这个包的源文件带 -O。
//
// 源文件在标准目录 Sources/RedDragonCore/，加引擎文件不用改这里，也不用碰 project.pbxproj。
// 依赖 `Game` / `Entity` / `Settings` 的调度、拷快照、面板、设置页仍编进 app（HSTracker/RedDragon/）。
// -enable-testing：app 和测试都用 `@testable import RedDragonCore` 访问 internal 符号，引擎不必为此改成 public。
//
import PackageDescription

let package = Package(
    name: "RedDragonCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RedDragonCore", targets: ["RedDragonCore"])
    ],
    targets: [
        .target(
            name: "RedDragonCore",
            swiftSettings: [
                .unsafeFlags(["-O", "-enable-testing"])
            ]
        )
    ]
)
