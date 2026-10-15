# ModHost

HSTracker 的 mod 加载器。背景见 `docs/research/red-dragon-mod-eval.md`「让 HSTracker 支持 mod」，接口见 `Packages/ModKit/README.md`。
只依赖 ModKit（本地路径），不依赖 HSTracker；设置窗的 mod 列表、每个 mod 的宿主服务由 app 里的适配层做。

```bash
cd Packages/ModHost && swift test
```

## 用法（主线程）

```swift
let host = ModHost(configuration: .standard(disabledModIDs: 设置里关掉的 id, log: { level, message in … }))
host.loadMods()                                     // 启动时：安全模式判定 → 扫描 → dlopen → 判版本 → makeMod
host.activateMods { manifest in 适配层的宿主服务(manifest) }
host.activeContributions                            // [(manifest, ModContributions)]，接到 5 个口子上
host.records                                        // mod 列表：每个文件的 id、状态（status.summary 是提示文案）
host.safeMode                                       // 非 nil = 这次在安全模式，提示用户
host.leaveSafeMode()                                // 设置里「退出安全模式」，下次启动生效
host.shutdown()                                     // applicationWillTerminate
```

## 扫描

`~/Library/Application Support/HSTracker/Mods/` 第一层的 `.dylib`、`.framework`、`.bundle`，按文件名排序；
`additionalModURLs` 是开发时直接指向构建输出的路径（可以是裸可执行文件），排在后面。同一个可执行文件只加载一次。

## 版本

dlopen 后读 `manifest.modKitVersion`，用 `ModKitVersion.runtime.compatibility(withModBuiltAgainst:)` 判：
主版本不同 → `.incompatible(.majorMismatch)`，按更新的次版本编 → `.incompatible(.hostTooOld)`，都不调 `makeMod()`。
mod 用了宿主 ModKit 没有的符号时 dlopen 本身失败，按 dyld 报错认出来也归 `.hostTooOld`。

## 安全模式

状态文件 `~/Library/Application Support/HSTracker/ModHost/state.json`。

- dlopen 前记下「这次要加载哪些 mod」，撑过 `crashWindow`（默认 30 秒，`loadMods()` 自己排定时器）或 `shutdown()` 时清掉。
- 下次启动还看得到这条记录 = 上次启动后很快崩了：这次一个 mod 都不 dlopen，`safeMode.suspectMods` 列出崩掉那次加载的 mod。
- 一直留在安全模式，直到要加载的 mod 变了（重编了文件、在列表里关掉了某个）或用户 `leaveSafeMode()`。
- 上次没加载 mod 就崩了，不进安全模式。`forceSafeMode` 只管这一次，不落盘。
- 窗口内被强退、在 Xcode 里停掉也算崩溃。

被用户关掉的 mod 按 id 记；加载器记着「可执行文件路径 → id」，认得出的直接不 dlopen，第一次见到的只能 dlopen 读 id 再跳过。
