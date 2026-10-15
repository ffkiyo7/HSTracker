//
//  ModHost.swift
//  ModHost
//
//  加载器主流程。app 里的适配层这样用（都在主线程）：
//
//      let host = ModHost(configuration: .standard(disabledModIDs: 设置里关掉的 id))
//      host.loadMods()                                   // 启动时：判安全模式、扫描、判版本、dlopen、makeMod
//      host.activateMods { manifest in 适配层的宿主服务(manifest) }
//      for (manifest, contributions) in host.activeContributions { 接到 5 个口子上 }
//      …
//      host.shutdown()                                   // applicationWillTerminate：deactivate + 记正常退出
//
//  安全模式：加载 mod 前先在状态文件里记下「这次启动要加载哪些 mod」，撑过 `crashWindow`（`loadMods()` 自己排定时器）
//  或正常退出时清掉。下次启动还看得到这条记录，说明上次启动后很快崩了，这次一个 mod 都不 dlopen，`safeMode` 给出原因，
//  适配层提示用户。之后要加载的 mod 变了（换了文件、关掉了某个），或用户在设置里点了退出（`leaveSafeMode()`），
//  下次启动才重新加载。窗口内被强退、在 Xcode 里停掉也会被当成崩溃。
//

import Foundation
import ModKit

public struct ModHostConfiguration {
    /// 启动时扫的目录（`~/Library/Application Support/HSTracker/Mods/`）
    public var modsDirectory: URL
    /// 开发时额外加载的路径（指向构建输出，省掉拷贝），排在 Mods 目录后面
    public var additionalModURLs: [URL]
    /// 加载器状态文件所在目录
    public var stateDirectory: URL
    /// 用户在设置里关掉的 mod id：不 dlopen（认得出路径时）、不 makeMod
    public var disabledModIDs: Set<String>
    /// 启动后多久内崩溃算「很快崩溃」，下次启动进安全模式
    public var crashWindow: TimeInterval
    /// `loadMods()` 自己排定时器在 `crashWindow` 后记启动稳定。测试里关掉，手动调 `markLaunchStable()`
    public var schedulesStableMark: Bool
    /// 这次启动直接进安全模式（如启动时按住某个键），不改落盘状态
    public var forceSafeMode: Bool
    /// 宿主进程里 ModKit 的版本，拿它判 mod 兼容
    public var hostModKitVersion: ModKitVersion
    public var log: (ModLogLevel, String) -> Void

    public init(modsDirectory: URL,
                additionalModURLs: [URL] = [],
                stateDirectory: URL,
                disabledModIDs: Set<String> = [],
                crashWindow: TimeInterval = 30,
                schedulesStableMark: Bool = true,
                forceSafeMode: Bool = false,
                hostModKitVersion: ModKitVersion = .runtime,
                log: @escaping (ModLogLevel, String) -> Void = { _, _ in }) {
        self.modsDirectory = modsDirectory
        self.additionalModURLs = additionalModURLs
        self.stateDirectory = stateDirectory
        self.disabledModIDs = disabledModIDs
        self.crashWindow = crashWindow
        self.schedulesStableMark = schedulesStableMark
        self.forceSafeMode = forceSafeMode
        self.hostModKitVersion = hostModKitVersion
        self.log = log
    }

    /// `~/Library/Application Support/HSTracker/` 下的 `Mods/` 和 `ModHost/`
    public static func standard(additionalModURLs: [URL] = [],
                                disabledModIDs: Set<String> = [],
                                forceSafeMode: Bool = false,
                                log: @escaping (ModLogLevel, String) -> Void = { _, _ in }) -> ModHostConfiguration {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HSTracker", isDirectory: true)
        return ModHostConfiguration(modsDirectory: support.appendingPathComponent("Mods", isDirectory: true),
                                    additionalModURLs: additionalModURLs,
                                    stateDirectory: support.appendingPathComponent("ModHost", isDirectory: true),
                                    disabledModIDs: disabledModIDs,
                                    forceSafeMode: forceSafeMode,
                                    log: log)
    }
}

/// 为什么这次启动在安全模式
public struct ModSafeModeInfo: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// 上次启动后 `crashWindow` 内崩了（或被强退）
        case crashedShortlyAfterLaunch(launchStartedAt: Date)
        /// `ModHostConfiguration.forceSafeMode`
        case forced
    }

    public let reason: Reason
    /// 崩掉的那次启动加载了哪些 mod（已知 id 写 id，否则写文件名）；`.forced` 时为空
    public let suspectMods: [String]
}

/// 一个 mod 文件的加载结果
public enum ModStatus {
    /// 已 `makeMod()`，等 `activateMods`
    case loaded
    /// `activate` 成功，`contributions` 可用
    case active
    case disabledByUser
    case skippedSafeMode
    /// 版本对不上：`.majorMismatch` 要按宿主的 ModKit 重编 mod，`.hostTooOld` 要更新 HSTracker
    case incompatible(ModCompatibility)
    /// manifest 的 id 不合规（`ModManifest.isValidID`）
    case invalidID
    /// 和前面某个 mod 的 id 重复，只认先加载的那个
    case duplicateID(firstURL: URL)
    case entryPointMissing
    case loadFailed(String)
    /// `activate` 抛错
    case activationFailed(String)

    /// 设置窗 mod 列表里显示的一句话
    public var summary: String {
        switch self {
        case .loaded: return "已加载，未启用"
        case .active: return "已启用"
        case .disabledByUser: return "已关闭"
        case .skippedSafeMode: return "安全模式，未加载"
        case .incompatible(.majorMismatch): return "ModKit 主版本不同，要按当前 HSTracker 重编"
        case .incompatible(.hostTooOld): return "按更新的 ModKit 编的，要先更新 HSTracker"
        // ModCompatibility 开了 library evolution，以后可能加 case
        case .incompatible: return "ModKit 版本不兼容"
        case .invalidID: return "mod id 不合规"
        case .duplicateID(let first): return "id 和 \(first.lastPathComponent) 重复，未加载"
        case .entryPointMissing: return "没有入口 \(ModEntryPoint.symbolName)，不是 HSTracker mod"
        case .loadFailed(let message): return "加载失败：\(message)"
        case .activationFailed(let message): return "启用失败：\(message)"
        }
    }
}

public struct ModRecord {
    public let candidate: ModCandidate
    /// dlopen 过才有；没 dlopen 的（安全模式、被关掉）为 nil
    public internal(set) var manifest: ModManifest?
    /// manifest 的 id，或没 dlopen 时按上次记下的路径 → id 认出来的
    public internal(set) var modID: String?
    public internal(set) var status: ModStatus
    public internal(set) var mod: (any HSTrackerMod)?
    public internal(set) var contributions: ModContributions?

    /// 显示用：有 id 写 id，否则写文件名
    public var label: String { modID ?? candidate.displayName }
}

@MainActor
public final class ModHost {
    public let configuration: ModHostConfiguration
    public private(set) var records: [ModRecord] = []
    public private(set) var scanIssues: [ModScanIssue] = []
    /// 非 nil = 这次启动在安全模式，一个 mod 都没加载
    public private(set) var safeMode: ModSafeModeInfo?

    private let loader: ModLibraryLoading
    private let now: () -> Date
    private let store: ModHostStateStore
    private var state = ModHostState()
    private var didLoad = false
    private var didShutdown = false

    public init(configuration: ModHostConfiguration,
                loader: ModLibraryLoading = DynamicLibraryLoader(),
                now: @escaping () -> Date = Date.init) {
        self.configuration = configuration
        self.loader = loader
        self.now = now
        let log = configuration.log
        self.store = ModHostStateStore(fileURL: configuration.stateDirectory.appendingPathComponent("state.json"),
                                       log: { log(.warning, "[ModHost] \($0)") })
    }

    /// 已启用的 mod 和它们接的口子，按加载顺序
    public var activeContributions: [(manifest: ModManifest, contributions: ModContributions)] {
        records.compactMap { record in
            guard case .active = record.status, let manifest = record.manifest,
                  let contributions = record.contributions else { return nil }
            return (manifest, contributions)
        }
    }

    // MARK: - 启动

    /// 启动时调一次：判安全模式 → 扫描 → 判版本 → dlopen → makeMod。重复调无效
    public func loadMods() {
        guard !didLoad else { return }
        didLoad = true

        state = store.load()
        let scan = ModScanner.scan(directory: configuration.modsDirectory,
                                   additionalURLs: configuration.additionalModURLs)
        scanIssues = scan.issues
        for issue in scan.issues {
            log(.warning, "跳过 \(issue.url.path)：\(issue.reason)")
        }

        // 只保留这次还在的路径，被关掉的 mod 不 dlopen
        let paths = Set(scan.candidates.map { Self.key(for: $0) })
        state.knownModIDs = state.knownModIDs.filter { paths.contains($0.key) }
        records = scan.candidates.map { candidate in
            let knownID = state.knownModIDs[Self.key(for: candidate)]
            let disabled = knownID.map { configuration.disabledModIDs.contains($0) } ?? false
            return ModRecord(candidate: candidate, manifest: nil, modID: knownID,
                             status: disabled ? .disabledByUser : .loaded, mod: nil, contributions: nil)
        }
        let planned = records.indices.filter { if case .disabledByUser = records[$0].status { return false }; return true }
        let fingerprint = planned.map { Self.fingerprint(of: records[$0].candidate) }

        safeMode = decideSafeMode(currentFingerprint: fingerprint)
        if let safeMode {
            for index in planned { records[index].status = .skippedSafeMode }
            log(.warning, "安全模式，这次不加载任何 mod（\(safeMode.reason)，涉及：\(safeMode.suspectMods.joined(separator: "、"))）")
        }

        // dlopen 之前先落盘：mod 的初始化代码崩了，下次启动也看得到
        let attempted = safeMode == nil ? planned : []
        state.launch = ModHostState.LaunchRecord(startedAt: now(),
                                                 attemptedMods: attempted.map { records[$0].label },
                                                 fingerprint: attempted.isEmpty ? [] : fingerprint,
                                                 loadedModIDs: [])
        store.save(state)

        var firstURLByID: [String: URL] = [:]
        for index in attempted {
            load(at: index, firstURLByID: &firstURLByID)
        }

        state.launch?.loadedModIDs = records.compactMap { record in
            if case .loaded = record.status { return record.modID }
            return nil
        }
        store.save(state)

        if configuration.schedulesStableMark && !attempted.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + configuration.crashWindow) { [weak self] in
                MainActor.assumeIsolated { self?.markLaunchStable() }
            }
        }
    }

    /// 主线程，`loadMods()` 之后调：逐个 `activate`。`services` 给每个 mod 一份自己的宿主服务（设置键带 mod 前缀等）
    public func activateMods(services: (ModManifest) -> any ModHostServices) {
        for index in records.indices {
            guard case .loaded = records[index].status,
                  let mod = records[index].mod, let manifest = records[index].manifest else { continue }
            do {
                records[index].contributions = try mod.activate(services(manifest))
                records[index].status = .active
                log(.info, "已启用 \(manifest.id) \(manifest.version)")
            } catch {
                records[index].status = .activationFailed(String(describing: error))
                log(.error, "\(manifest.id) 启用失败：\(error)")
            }
        }
    }

    // MARK: - 启动之后

    /// 启动已经撑过崩溃窗口：清掉启动记录，之后再崩不进安全模式。`schedulesStableMark` 为真时 `loadMods()` 自己会排
    public func markLaunchStable() {
        guard state.launch != nil else { return }
        state.launch = nil
        store.save(state)
    }

    /// `applicationWillTerminate`：逐个 `deactivate`，记正常退出。重复调无效
    public func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        for record in records {
            if case .active = record.status { record.mod?.deactivate() }
        }
        markLaunchStable()
    }

    /// 用户在设置里点「退出安全模式」：下次启动重新加载 mod。这次已经没加载的，这次不补（Swift 库要重启才干净）
    public func leaveSafeMode() {
        guard state.safeMode != nil else { return }
        state.safeMode = nil
        store.save(state)
        log(.info, "已退出安全模式，下次启动加载 mod")
    }

    // MARK: - 内部

    private func decideSafeMode(currentFingerprint: [String]) -> ModSafeModeInfo? {
        // 上次启动没撑过窗口，且加载过 mod：记一笔安全模式
        if let crashed = state.launch, !crashed.attemptedMods.isEmpty {
            log(.warning, "上次启动（\(crashed.startedAt)）后 \(Int(configuration.crashWindow)) 秒内没正常结束")
            state.safeMode = ModHostState.SafeModeRecord(enteredAt: now(),
                                                         crashedLaunchStartedAt: crashed.startedAt,
                                                         suspectMods: crashed.attemptedMods,
                                                         fingerprint: crashed.fingerprint)
        }
        state.launch = nil

        if let record = state.safeMode, record.fingerprint != currentFingerprint {
            // 换了 mod 文件或关掉了某个：再试一次
            log(.info, "要加载的 mod 和崩溃那次不同了，退出安全模式")
            state.safeMode = nil
        }

        if let record = state.safeMode {
            return ModSafeModeInfo(reason: .crashedShortlyAfterLaunch(launchStartedAt: record.crashedLaunchStartedAt),
                                   suspectMods: record.suspectMods)
        }
        if configuration.forceSafeMode {
            return ModSafeModeInfo(reason: .forced, suspectMods: [])
        }
        return nil
    }

    private func load(at index: Int, firstURLByID: inout [String: URL]) {
        let candidate = records[index].candidate
        let registration: ModRegistration
        do {
            registration = try loader.loadRegistration(from: candidate.binaryURL)
        } catch ModLibraryLoadError.openFailed(let message, let missingModKitSymbol) {
            records[index].status = missingModKitSymbol ? .incompatible(.hostTooOld) : .loadFailed(message)
            log(.error, "\(candidate.displayName) 打不开：\(message)")
            return
        } catch ModLibraryLoadError.entryPointMissing {
            records[index].status = .entryPointMissing
            log(.error, "\(candidate.displayName) 没有入口 \(ModEntryPoint.symbolName)")
            return
        } catch {
            records[index].status = .loadFailed(String(describing: error))
            log(.error, "\(candidate.displayName) 加载失败：\(error)")
            return
        }

        let manifest = registration.manifest
        records[index].manifest = manifest
        guard ModManifest.isValidID(manifest.id) else {
            records[index].status = .invalidID
            log(.error, "\(candidate.displayName) 的 id「\(manifest.id)」不合规")
            return
        }
        records[index].modID = manifest.id
        state.knownModIDs[Self.key(for: candidate)] = manifest.id

        if let first = firstURLByID[manifest.id] {
            records[index].status = .duplicateID(firstURL: first)
            log(.error, "\(candidate.displayName) 的 id \(manifest.id) 和 \(first.lastPathComponent) 重复")
            return
        }
        firstURLByID[manifest.id] = candidate.url

        if configuration.disabledModIDs.contains(manifest.id) {
            records[index].status = .disabledByUser
            return
        }

        let compatibility = configuration.hostModKitVersion.compatibility(withModBuiltAgainst: manifest.modKitVersion)
        guard compatibility == .compatible else {
            records[index].status = .incompatible(compatibility)
            log(.error, "\(manifest.id) 按 ModKit \(manifest.modKitVersion) 编，宿主是 \(configuration.hostModKitVersion)：\(compatibility)")
            return
        }

        records[index].mod = registration.makeMod()
        records[index].status = .loaded
        log(.info, "已加载 \(manifest.id) \(manifest.version)（\(candidate.url.path)）")
    }

    private func log(_ level: ModLogLevel, _ message: String) {
        configuration.log(level, "[ModHost] \(message)")
    }

    /// 状态文件里认 mod 用的键：可执行文件的真实路径
    static func key(for candidate: ModCandidate) -> String {
        candidate.binaryURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 文件身份：路径 + 大小 + 修改时间。重编 mod 后会变
    static func fingerprint(of candidate: ModCandidate) -> String {
        let path = key(for: candidate)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(path)|\(size)|\(modified)"
    }
}
