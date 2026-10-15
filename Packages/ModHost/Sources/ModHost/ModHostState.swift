//
//  ModHostState.swift
//  ModHost
//
//  加载器自己落盘的状态（一个 JSON 文件），跨启动用：
//  - `launch`：本次启动的记录，加载 mod 前写下，启动稳定（撑过崩溃窗口）或正常退出时清掉。
//    下次启动还看得到它 = 上次启动后很快崩了（或被强退）。
//  - `safeMode`：进了安全模式就一直留着，直到要加载的 mod 变了（换了文件、关掉了某个）或用户手动退出。
//  - `knownModIDs`：可执行文件路径 → mod id。被用户关掉的 mod 按 id 记，有了这张表才能不 dlopen 就认出它。
//

import Foundation

struct ModHostState: Codable, Equatable {
    var launch: LaunchRecord?
    var safeMode: SafeModeRecord?
    var knownModIDs: [String: String] = [:]

    struct LaunchRecord: Codable, Equatable {
        var startedAt: Date
        /// 这次要 dlopen 的 mod（显示用：已知 id 写 id，否则写文件名）。空 = 这次没加载 mod，崩了也不怪 mod
        var attemptedMods: [String]
        /// 这次要 dlopen 的那批文件的指纹
        var fingerprint: [String]
        /// 这次实际加载成功的 mod id
        var loadedModIDs: [String]
    }

    struct SafeModeRecord: Codable, Equatable {
        var enteredAt: Date
        /// 崩掉的那次启动的开始时间
        var crashedLaunchStartedAt: Date
        /// 崩掉的那次启动加载了哪些 mod
        var suspectMods: [String]
        /// 崩掉的那次启动要加载的文件指纹；当前指纹和它不同就自动退出安全模式
        var fingerprint: [String]
    }
}

/// 状态文件的读写。读不到、解不开都当空状态；写失败只记日志
struct ModHostStateStore {
    let fileURL: URL
    let log: (String) -> Void

    func load() -> ModHostState {
        guard let data = try? Data(contentsOf: fileURL) else { return ModHostState() }
        do {
            return try Self.decoder.decode(ModHostState.self, from: data)
        } catch {
            log("状态文件解不开，按空状态处理：\(error)")
            return ModHostState()
        }
    }

    func save(_ state: ModHostState) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            log("状态文件写不进去，安全模式这次不起作用：\(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
