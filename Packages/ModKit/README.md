# ModKit

HSTracker 给 mod 开的接口层，版本 1.0。背景见 `docs/research/red-dragon-mod-eval.md`「让 HSTracker 支持 mod」。
只有协议和值类型，不依赖 HSTracker；HSTracker 由适配层实现宿主一侧的协议，加载器（ModHost）负责扫描、判版本、调入口。

```bash
cd Packages/ModKit && swift build && swift test
```

## 约定

- 动态库，开 library evolution，在 app 的 Frameworks 里只嵌一份；mod 只动态链接它，不得自带。
- 「主.次」版本（`ModKitVersion`）：次版本只加不改，主版本不同拒绝加载。`compileTime` 编进调用方，`runtime` 读已加载的库，升版本两处一起改。
- 只加不改：加协议要求必须同时给默认实现；枚举加 case 时，mod 侧的 `switch` 要带 `@unknown default`。

## 入口

mod 导出 C 符号 `hstracker_mod_entry`（`ModEntryPoint.symbolName`），返回 `ModRegistration(...).retainedPointer()`。
加载器 `ModRegistration.take(_:)` 取回，先用 `ModKitVersion.runtime.compatibility(withModBuiltAgainst: manifest.modKitVersion)` 判版本，
通过后 `makeMod()`，主线程 `activate(_:)` 拿回 `ModContributions`，退出前 `deactivate()`。

## 5 个口子

| 口子 | 类型 | 谁实现 | 线程 |
| --- | --- | --- | --- |
| 对局事件 | `ModGameEventHandler.handle(_:game:)`，事件 `ModGameEvent`（开始、结束、批尾、最外层 BLOCK 闭合） | mod | 解析线程，同步 |
| 读对局状态 | `ModGameState`、`ModEntity`、`ModDeck`；tag / 区域 / 卡牌类型按原始数值（`ModGameTag`、`ModZone`、`ModCardType`） | 宿主 | 只在回调里读 |
| overlay 图层 | `ModOverlayProvider.overlayView(canvas:)`，画布 `ModOverlayCanvas`（尺寸、记牌器占位、`ModBoardGeometry`）；接鼠标用 `.modInteractiveRegion()` | mod 给视图，宿主给画布 | 主线程 |
| 设置页 | `ModPreferencePane`；存取 `ModSettings`（键由宿主加 mod 前缀，主线程通知观察者） | mod 给页，宿主存取 | 页在主线程，存取任意线程 |
| 宿主服务 | `ModHostServices`：日志、卡名、数据目录、设置、记牌器样式 `ModTrackerStyle` | 宿主 | 任意线程 |
