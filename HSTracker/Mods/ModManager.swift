//
//  ModManager.swift
//  HSTracker
//
//  Fork：app 里的 mod 管理器。上游文件里的挂点只调它（5 处：`LogReaderManager` 两处、`RootOverlayViewModel`、
//  `RootOverlayView`、`AppDelegate` 的设置页分组；外加 `AppDelegate` 启动 / 退出各一行），
//  它再把 ModKit 的 5 个口子接到已启用的 mod 上。上游改宿主类型时改的是 HSTracker/Mods/ 这一层，mod 不动。
//
//  mod 的来源：
//  - 编进 app 的（`builtInRegistrations`），启动时直接登记；
//  - `~/Library/Application Support/HSTracker/Mods/` 里的动态库，由 ModHost 扫描、判版本、dlopen、判安全模式。
//  两种 mod 走同一套宿主服务和口子。设置里关掉某个 mod 下次启动生效（Swift 库加载后卸不掉）。
//
//  线程：`start` / `shutdown` / 读口子在主线程；对局事件在解析线程（`LogReaderManager` 的串行队列）上同步派发，
//  回调列表启动后不再变，派发时在锁里拷一份。
//

import AppKit
import Foundation
import ModHost
import ModKit

final class ModManager {

    static let shared = ModManager()

    /// 编进 app 的 mod（排在 Mods 目录里的前面）。红龙辅助搬成 Mods/RedDragon/ 的动态库之前先编在这里
    static var builtInRegistrations: [() -> ModRegistration] = [RedDragonMod.registration]

    /// 宿主老版本存过的设置键 → mod 的设置键（mod id → [(老键, 新键)]）。启动时抄一次，老键留着给旧版用
    static let legacySettings: [String: [(legacy: String, key: String)]] = [
        // 红龙辅助编在 app 里时（Settings+Fork.swift）的三个键
        "red-dragon": [("red_dragon_assist", "assist"),
                       ("red_dragon_reveal_level", "revealLevel"),
                       ("red_dragon_quiz_mode", "quizMode")]
    ]

    static let disabled_mods = "disabled_mods"

    /// 一个 mod 在设置页列表里的一行
    struct Entry {
        enum Source {
            case builtIn
            case file(URL)
        }
        var id: String?
        var name: String
        var version: String?
        var source: Source
        var status: String
        var isActive: Bool
    }

    // —— 主线程 ——

    private(set) var host: ModHost?
    private(set) var entries: [Entry] = []
    private(set) var overlayProviders: [(id: String, provider: any ModOverlayProvider)] = []
    private(set) var preferencePanes: [(manifest: ModManifest, pane: ModPreferencePane)] = []
    private var builtInMods: [(manifest: ModManifest, mod: any HSTrackerMod)] = []
    private var started = false

    // —— 解析线程（`handlers` 启动时写一次，之后只读；都在 `lock` 下）——

    private let lock = NSLock()
    private var handlers: [(id: String, handler: any ModGameEventHandler)] = []
    /// 只在解析线程读写：上一次派发时的对局身份、本局是否已发过 gameEnded
    private var lastMatch: Date?
    private var endedMatch: Date?

    /// 一次回调超过这个时长就记日志点名（每批日志都会调，慢了整个解析跟着慢）
    static let slowCallback: TimeInterval = 0.05

    static var disabledModIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: disabled_mods) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: disabled_mods) }
    }

    // MARK: - 启动 / 退出（主线程）

    /// `applicationDidFinishLaunching` 里调一次，在建 overlay 和设置窗之前。启动时按住 ⇧ 进安全模式（不加载 Mods 目录）
    @MainActor
    func start() {
        guard !started else { return }
        started = true
        let disabled = Self.disabledModIDs
        var contributions: [(manifest: ModManifest, contributions: ModContributions)] = []

        var builtInIDs = Set<String>()
        for make in Self.builtInRegistrations {
            let registration = make()
            let manifest = registration.manifest
            var entry = Entry(id: manifest.id, name: manifest.name, version: manifest.version, source: .builtIn,
                              status: "", isActive: false)
            defer { entries.append(entry) }
            guard ModManifest.isValidID(manifest.id), !builtInIDs.contains(manifest.id) else {
                entry.status = ModStatus.invalidID.summary
                continue
            }
            builtInIDs.insert(manifest.id)
            guard !disabled.contains(manifest.id) else {
                entry.status = ModStatus.disabledByUser.summary
                continue
            }
            let mod = registration.makeMod()
            do {
                let c = try mod.activate(services(for: manifest))
                builtInMods.append((manifest, mod))
                contributions.append((manifest, c))
                entry.status = ModStatus.active.summary
                entry.isActive = true
                logger.info("mods: 已启用内置 mod \(manifest.id) \(manifest.version)")
            } catch {
                entry.status = ModStatus.activationFailed(String(describing: error)).summary
                logger.error("mods: 内置 mod \(manifest.id) 启用失败：\(error)")
            }
        }

        // 跑测试时不扫 Mods 目录：测试宿主结束时不走 applicationWillTerminate，会被 ModHost 当成崩溃，下次启动进安全模式
        if !AppDelegate.isRunningTests {
            let forceSafeMode = NSEvent.modifierFlags.contains(.shift)
            let configuration = ModHostConfiguration.standard(disabledModIDs: disabled, forceSafeMode: forceSafeMode) { level, message in
                Self.log(level, "mods: \(message)")
            }
            let host = ModHost(configuration: configuration)
            self.host = host
            host.loadMods()
            host.activateMods { [unowned self] manifest in self.services(for: manifest) }
            for record in host.records {
                let duplicate = record.modID.map(builtInIDs.contains) ?? false
                entries.append(Entry(id: record.modID, name: record.manifest?.name ?? record.label,
                                     version: record.manifest?.version, source: .file(record.candidate.url),
                                     status: duplicate ? "id 和内置 mod 重复，未接入" : record.status.summary,
                                     isActive: !duplicate && { if case .active = record.status { return true }; return false }()))
            }
            contributions += host.activeContributions.filter { !builtInIDs.contains($0.manifest.id) }
        }

        lock.lock()
        handlers = contributions.compactMap { item in item.contributions.gameEvents.map { (item.manifest.id, $0) } }
        lock.unlock()
        overlayProviders = contributions.compactMap { item in item.contributions.overlay.map { (item.manifest.id, $0) } }
        preferencePanes = contributions.compactMap { item in item.contributions.preferencePane.map { (item.manifest, $0) } }
    }

    /// `applicationWillTerminate`：逐个 `deactivate`，告诉 ModHost 正常退出
    @MainActor
    func shutdown() {
        for item in builtInMods { item.mod.deactivate() }
        builtInMods = []
        host?.shutdown()
    }

    private func services(for manifest: ModManifest) -> ModServices {
        let store = ModSettingsStore(modID: manifest.id)
        for item in Self.legacySettings[manifest.id] ?? [] {
            store.migrate(from: item.legacy, to: item.key)
        }
        return ModServices(manifest: manifest, settings: store)
    }

    private static func log(_ level: ModLogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug(message)
        case .info: logger.info(message)
        case .warning: logger.warning(message)
        case .error: logger.error(message)
        @unknown default: logger.info(message)
        }
    }

    // MARK: - 对局事件（解析线程）

    /// `LogReaderManager` 每处理完一批日志行调一次（包括没有新行的空批）。`idle`：解析器没有未闭合的 BLOCK
    func parserBatchDidEnd(_ game: Game, linesProcessed: Bool, idle: Bool) {
        dispatch(game, .batchEnded(linesProcessed: linesProcessed, idle: idle))
    }

    /// `LogReaderManager` 在一行把最外层 BLOCK 闭合时调
    func parserTopBlockDidClose(_ game: Game) {
        dispatch(game, .topBlockClosed)
    }

    private func dispatch(_ game: Game, _ event: ModGameEvent) {
        lock.lock()
        let targets = handlers
        lock.unlock()
        guard !targets.isEmpty else { return }
        let state = ModGameAdapter(game)
        // 开局 / 终局由对局身份和胜负推出来，排在这一批的事件前面
        let match = state.matchStartTime
        if let match, match != lastMatch {
            lastMatch = match
            deliver(.gameStarted, state, targets)
        }
        if let match, state.isGameOver, endedMatch != match {
            endedMatch = match
            deliver(.gameEnded, state, targets)
        }
        deliver(event, state, targets)
    }

    private func deliver(_ event: ModGameEvent, _ state: ModGameAdapter,
                         _ targets: [(id: String, handler: any ModGameEventHandler)]) {
        for target in targets {
            let start = DispatchTime.now().uptimeNanoseconds
            target.handler.handle(event, game: state)
            let spent = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
            if spent > Self.slowCallback {
                logger.warning("mods: \(target.id) 处理 \(event) 用了 \(Int(spent * 1000)) ms")
            }
        }
    }
}
