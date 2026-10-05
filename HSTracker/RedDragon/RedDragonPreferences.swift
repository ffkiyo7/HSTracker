//
//  RedDragonPreferences.swift
//  HSTracker
//
//  设置窗「覆盖层」组里单独一页「红龙辅助」：总开关 + 默认揭示档 + 答题模式 + 热键说明。
//  单开一页：它不属于任何现有页的主题（记牌器 / 计数器 / 各模式），现有页都是 nib，加控件得动 .xib。
//  写设置一律走 `Settings` 的属性（它会发通知，assistant 和热键靠通知热切换）；不用 @AppStorage，那条路不发通知。
//

import AppKit
import SwiftUI
@testable import RedDragonCore

final class RedDragonPreferences: PreferencePaneController, PreferencePane {
    var preferencePaneIdentifier = PreferencePaneIdentifier.redDragon

    var preferencePaneTitle = RDText.prefsTitle

    var preferencePaneIcon: NSImage = NSImage(systemSymbolName: "flame", accessibilityDescription: RDText.prefsTitle)
        ?? NSImage(named: "settings-counters") ?? NSImage()

    var preferencePaneSearchText: [String] {
        return [RDText.prefsEnable, RDText.prefsEnableNote, RDText.prefsReveal, RDText.prefsRevealNote,
                RDText.prefsQuiz, RDText.prefsQuizNote, RDText.prefsHotkeys]
            + RDRevealLevel.allCases.map(RDText.level)
    }

    override func makeContentView() -> NSView? {
        let hosting = NSHostingView(rootView: RedDragonPreferencesView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        return hosting
    }
}

extension PreferencePaneIdentifier {
    static let redDragon = Self("redDragon")
}

struct RedDragonPreferencesView: View {
    @SwiftUI.State private var enabled = Settings.redDragonAssist
    @SwiftUI.State private var reveal = RDRevealLevel(rawValue: Settings.redDragonRevealLevel) ?? .verdict
    @SwiftUI.State private var quiz = Settings.redDragonQuizMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(RDText.prefsEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, on in Settings.redDragonAssist = on }
                note(RDText.prefsEnableNote)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(RDText.prefsReveal)
                    Picker("", selection: $reveal) {
                        ForEach(RDRevealLevel.allCases, id: \.rawValue) { level in
                            Text(RDText.level(level)).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: reveal) { _, level in Settings.redDragonRevealLevel = level.rawValue }
                }
                note(RDText.prefsRevealNote)
            }
            .disabled(!enabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(RDText.prefsQuiz, isOn: $quiz)
                    .onChange(of: quiz) { _, on in Settings.redDragonQuizMode = on }
                note(RDText.prefsQuizNote)
            }
            .disabled(!enabled)

            VStack(alignment: .leading, spacing: 4) {
                Text(RDText.prefsHotkeys).fontWeight(.semibold)
                ForEach(RedDragonHotkeys.bindings, id: \.action.rawValue) { b in
                    Text(RDText.hotkeyLine(b.display, Self.label(b.action)))
                        .font(.system(.body, design: .monospaced))
                }
            }
            .padding(.top, 4)
        }
        .frame(width: PreferencePaneController.fixedWidth - 40, alignment: .leading)
        .padding(20)
        // 热键切了答题模式时跟上
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name(rawValue: Settings.red_dragon_quiz_mode))) { _ in
            if quiz != Settings.redDragonQuizMode { quiz = Settings.redDragonQuizMode }
        }
    }

    static func label(_ action: RedDragonHotkeys.Action) -> String {
        switch action {
        case .raise: return RDText.hotkeyRaise
        case .lower: return RDText.hotkeyLower
        case .quiz: return RDText.hotkeyQuiz
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
    }
}
