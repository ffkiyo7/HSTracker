// swift-tools-version:5.9
//
// 红龙辅助 mod：HSTracker 的第一个 mod（docs/research/red-dragon-mod-eval.md 第三阶段）。
// 只通过 ModKit 和 HSTracker 打交道，不依赖 HSTracker 的任何类型；引擎 RedDragonCore 静态链接进来。
//
// - 产物是一个动态库，导出 `hstracker_mod_entry`（RedDragonEntry.swift）。用 `build.sh` 编：
//   它把对 SwiftPM 编出的 libModKit.dylib 的引用改成 HSTracker 里的 ModKit.framework（mod 不得自带 ModKit），
//   去掉指向构建目录的 rpath、补 HSTracker 的 Frameworks 目录，再 ad hoc 签名；`--install` 拷进 HSTracker 的 Mods 目录。
// - 要 HSTracker 在场的红龙测试（日志回放、overlay）留在 HSTrackerTests，直接编这里的源文件跑（入口文件除外）。
//

import PackageDescription

let package = Package(
    name: "RedDragon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RedDragon", type: .dynamic, targets: ["RedDragonMod"])
    ],
    dependencies: [
        .package(path: "../../Packages/ModKit"),
        .package(path: "../../Packages/RedDragonCore")
    ],
    targets: [
        .target(
            name: "RedDragonMod",
            dependencies: [
                .product(name: "ModKit", package: "ModKit"),
                .product(name: "RedDragonCore", package: "RedDragonCore")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
