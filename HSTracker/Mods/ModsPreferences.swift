//
//  ModsPreferences.swift
//  HSTracker
//
//  Fork：设置窗的「Mod」分组。第一页是 mod 列表（开关、状态、安全模式），后面每个已启用的 mod 各一页
//  （ModKit 口子 4，`ModPreferencePaneController` 把 mod 给的 SwiftUI 视图包成设置页）。
//

import AppKit
import ModHost
import ModKit
import SwiftUI

extension PreferencePaneIdentifier {
    static let mods = Self("mods")
}

/// mod 自己的设置页
final class ModPreferencePaneController: PreferencePaneController, PreferencePane {
    let pane: ModPreferencePane
    let preferencePaneIdentifier: PreferencePaneIdentifier

    init(manifest: ModManifest, pane: ModPreferencePane) {
        self.pane = pane
        preferencePaneIdentifier = PreferencePaneIdentifier(rawValue: "mod.\(manifest.id)")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var preferencePaneTitle: String { pane.title }
    var preferencePaneIcon: NSImage { pane.icon }
    var preferencePaneSearchText: [String] { pane.searchTerms }

    override func makeContentView() -> NSView? {
        let content = pane.makeView()
        let hosting = NSHostingView(rootView: content
            .frame(width: PreferencePaneController.fixedWidth - 40, alignment: .leading)
            .padding(20))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        return hosting
    }
}

/// mod 列表
final class ModsPreferences: PreferencePaneController, PreferencePane {
    var preferencePaneIdentifier = PreferencePaneIdentifier.mods
    var preferencePaneTitle = "Mod"
    var preferencePaneIcon: NSImage = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: "Mod")
        ?? NSImage(named: "settings-counters") ?? NSImage()
    var preferencePaneSearchText: [String] {
        ["Mod", "安全模式", "下次启动生效"] + ModManager.shared.entries.map { $0.name }
    }

    override func makeContentView() -> NSView? {
        let hosting = NSHostingView(rootView: ModsPreferencesView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        return hosting
    }
}

struct ModsPreferencesView: View {
    @SwiftUI.State private var disabled = ModManager.disabledModIDs
    @SwiftUI.State private var leftSafeMode = false
    private let manager = ModManager.shared

    private var modsDirectory: URL? { manager.host?.configuration.modsDirectory }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let safe = manager.host?.safeMode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("安全模式：这次启动没有加载 Mods 目录里的 mod").fontWeight(.semibold)
                    Text(safeModeReason(safe))
                        .font(.callout).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(leftSafeMode ? "已退出，下次启动加载 mod" : "退出安全模式") {
                        manager.host?.leaveSafeMode()
                        leftSafeMode = true
                    }
                    .disabled(leftSafeMode)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
            }

            if manager.entries.isEmpty {
                Text("没有 mod。把 mod 放进 Mods 目录后重启 HSTracker。").foregroundColor(.secondary)
            }
            ForEach(Array(manager.entries.enumerated()), id: \.offset) { _, entry in
                row(entry)
            }

            Text("开关下次启动 HSTracker 生效；换 mod 文件也要重启。启动时按住 ⇧ 进安全模式，不加载 Mods 目录里的 mod。")
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let dir = modsDirectory {
                Button("在访达中显示 Mods 目录") {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            }
        }
        .frame(width: PreferencePaneController.fixedWidth - 40, alignment: .leading)
        .padding(20)
    }

    private func row(_ entry: ModManager.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: binding(entry.id))
                .labelsHidden()
                .disabled(entry.id == nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).fontWeight(.semibold)
                    if let version = entry.version {
                        Text(version).foregroundColor(.secondary)
                    }
                    if case .builtIn = entry.source {
                        Text("内置").font(.caption).foregroundColor(.secondary)
                    }
                }
                Text(entry.status)
                    .font(.callout)
                    .foregroundColor(entry.isActive ? .secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
                if case .file(let url) = entry.source {
                    Text(url.path).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private func binding(_ id: String?) -> Binding<Bool> {
        Binding(get: { id.map { !disabled.contains($0) } ?? true },
                set: { on in
                    guard let id else { return }
                    if on { disabled.remove(id) } else { disabled.insert(id) }
                    ModManager.disabledModIDs = disabled
                })
    }

    private func safeModeReason(_ info: ModSafeModeInfo) -> String {
        switch info.reason {
        case .crashedShortlyAfterLaunch(let at):
            let suspects = info.suspectMods.joined(separator: "、")
            return "上次启动（\(at.formatted(date: .abbreviated, time: .standard))）后不久 HSTracker 就退出了，"
                + "那次加载了：\(suspects)。关掉可疑的 mod、换掉 mod 文件，或点下面的按钮。"
        case .forced:
            return "启动时按住了 ⇧。"
        @unknown default:
            return ""
        }
    }
}
