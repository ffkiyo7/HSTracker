// swift-tools-version:5.9
//
// ModHost：HSTracker 的 mod 加载器（docs/research/red-dragon-mod-eval.md「让 HSTracker 支持 mod」）。
// 扫描 Mods 目录、按 ModKit 的版本规则判兼容、调 mod 入口，上次启动后很快崩溃时进安全模式（一个 mod 都不加载）。
// 只依赖 ModKit，不依赖 HSTracker 的任何类型；设置窗的 mod 列表、宿主服务由 app 里的适配层做。
//
// 和 ModKit 一样编进 app；它不给 mod 用，所以不开 library evolution，静态库即可。
//

import PackageDescription

let package = Package(
    name: "ModHost",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ModHost", targets: ["ModHost"])
    ],
    dependencies: [
        .package(path: "../ModKit")
    ],
    targets: [
        .target(
            name: "ModHost",
            dependencies: [.product(name: "ModKit", package: "ModKit")]
        ),
        .testTarget(
            name: "ModHostTests",
            dependencies: ["ModHost", .product(name: "ModKit", package: "ModKit")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
