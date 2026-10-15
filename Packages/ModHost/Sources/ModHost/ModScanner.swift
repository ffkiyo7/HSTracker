//
//  ModScanner.swift
//  ModHost
//
//  扫 Mods 目录，找出 mod 动态库。只看文件，不 dlopen。
//
//  认三种形状（目录第一层，不递归）：
//  - `Foo.dylib`：裸动态库
//  - `Foo.framework`：可执行文件取 `Foo.framework/Foo`（或 `Versions/Current/Foo`）
//  - `Foo.bundle`：可执行文件取 Info.plist 的 CFBundleExecutable
//  隐藏文件和其他扩展名跳过。符号链接照常认（开发时把构建输出链进来）。
//

import Foundation

/// 一个待加载的 mod 文件
public struct ModCandidate: Hashable, Sendable {
    /// Mods 目录里的那一项（`.dylib` / `.framework` / `.bundle`），或开发时额外指定的路径
    public let url: URL
    /// 真正要 dlopen 的可执行文件
    public let binaryURL: URL

    public init(url: URL, binaryURL: URL) {
        self.url = url
        self.binaryURL = binaryURL
    }

    /// 日志和提示里用的名字（文件名）
    public var displayName: String { url.lastPathComponent }
}

/// 扫描时跳过的项和原因（mod 列表里提示用）
public struct ModScanIssue: Error, Hashable, Sendable {
    public let url: URL
    public let reason: String
}

public struct ModScanResult: Hashable, Sendable {
    /// 按文件名排序，保证每次加载顺序一样
    public var candidates: [ModCandidate]
    public var issues: [ModScanIssue]
}

public enum ModScanner {
    static let supportedExtensions: Set<String> = ["dylib", "framework", "bundle"]

    /// 扫 `directory` 第一层，再加上 `additionalURLs`（开发时指向构建输出，按给的顺序排在后面）。
    /// 目录不存在不算错，返回空。
    public static func scan(directory: URL, additionalURLs: [URL] = [],
                            fileManager: FileManager = .default) -> ModScanResult {
        var result = ModScanResult(candidates: [], issues: [])
        var seenBinaries = Set<String>()

        func add(_ url: URL) {
            switch candidate(at: url, fileManager: fileManager) {
            case .success(let candidate):
                // 同一个可执行文件（目录里放了一份、开发路径又指了一次）只加载一次
                let key = candidate.binaryURL.resolvingSymlinksInPath().standardizedFileURL.path
                if seenBinaries.insert(key).inserted {
                    result.candidates.append(candidate)
                } else {
                    result.issues.append(ModScanIssue(url: url, reason: "和前面的某一项是同一个文件，跳过"))
                }
            case .failure(let issue):
                result.issues.append(issue)
            }
        }

        let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles])) ?? []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where supportedExtensions.contains(url.pathExtension.lowercased()) {
            add(url)
        }
        for url in additionalURLs {
            add(url)
        }
        return result
    }

    /// 单独认一项：是不是 mod、可执行文件在哪
    public static func candidate(at url: URL, fileManager: FileManager = .default) -> Result<ModCandidate, ModScanIssue> {
        func fail(_ reason: String) -> Result<ModCandidate, ModScanIssue> {
            .failure(ModScanIssue(url: url, reason: reason))
        }
        func isFile(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return fail("文件不存在")
        }

        switch url.pathExtension.lowercased() {
        case "dylib":
            guard !isDirectory.boolValue else { return fail(".dylib 不该是目录") }
            return .success(ModCandidate(url: url, binaryURL: url))

        case "framework":
            guard isDirectory.boolValue else { return fail(".framework 应该是目录") }
            let name = url.deletingPathExtension().lastPathComponent
            let flat = url.appendingPathComponent(name)
            let versioned = url.appendingPathComponent("Versions/Current/\(name)")
            if isFile(flat) { return .success(ModCandidate(url: url, binaryURL: flat)) }
            if isFile(versioned) { return .success(ModCandidate(url: url, binaryURL: versioned)) }
            return fail("framework 里找不到可执行文件 \(name)")

        case "bundle":
            guard isDirectory.boolValue else { return fail(".bundle 应该是目录") }
            guard let binary = Bundle(url: url)?.executableURL, isFile(binary) else {
                return fail("bundle 的 Info.plist 没写 CFBundleExecutable，或可执行文件不存在")
            }
            return .success(ModCandidate(url: url, binaryURL: binary))

        default:
            // 开发路径直接指向某个可执行文件（没有扩展名）也认
            if !isDirectory.boolValue {
                return .success(ModCandidate(url: url, binaryURL: url))
            }
            return fail("不认识的格式（只认 .dylib / .framework / .bundle）")
        }
    }
}
