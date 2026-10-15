// swift-tools-version:5.9
//
// ModKit：HSTracker 给 mod 开的接口层（docs/research/red-dragon-mod-eval.md「让 HSTracker 支持 mod」）。
// 只有协议和值类型，不依赖 HSTracker 的任何类型；HSTracker 那边由适配层实现这些协议。
//
// - 动态库：随 HSTracker 编进 app 的 Frameworks，只此一份。mod 只动态链接它，不得自带
//   （自带一份类型就重复了，HSTracker 认不出 mod 返回的东西）。
// - library evolution：ModKit 只加东西（次版本 +1）时，按旧版编的 mod 不用重编。
//   本地包允许 `unsafeFlags`；Xcode 里对应 BUILD_LIBRARY_FOR_DISTRIBUTION。
// - 版本号见 ModKitVersion.swift。
//

import PackageDescription

let package = Package(
    name: "ModKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ModKit", type: .dynamic, targets: ["ModKit"])
    ],
    targets: [
        .target(
            name: "ModKit",
            swiftSettings: [.unsafeFlags(["-enable-library-evolution"])]
        ),
        .testTarget(
            name: "ModKitTests",
            dependencies: ["ModKit"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
