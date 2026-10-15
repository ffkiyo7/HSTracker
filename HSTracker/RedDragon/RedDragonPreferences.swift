//
//  RedDragonPreferences.swift
//  HSTracker
//
//  ModKit 口子 4：设置窗里红龙辅助的一页：总开关 + 默认揭示档 + 答题模式 + 热键说明。
//  读写一律走 mod 的设置（`ModSettings`，它会通知观察者，assistant 和热键靠它热切换）；不用 @AppStorage，那条路不通知。
//

import AppKit
import ModKit
import SwiftUI
import RedDragonCore

enum RedDragonPreferences {
    static func pane(settings: any ModSettings) -> ModPreferencePane {
        let icon = NSImage(systemSymbolName: "flame", accessibilityDescription: RDText.prefsTitle) ?? NSImage()
        let terms = [RDText.prefsEnable, RDText.prefsEnableNote, RDText.prefsReveal, RDText.prefsRevealNote,
                     RDText.prefsQuiz, RDText.prefsQuizNote, RDText.prefsHotkeys]
            + RDRevealLevel.allCases.map(RDText.level)
        return ModPreferencePane(title: RDText.prefsTitle, icon: icon, searchTerms: terms) {
            AnyView(RedDragonPreferencesView(settings: settings))
        }
    }
}

/// 宿主把它包成设置页（宽度、边距由设置窗定）
struct RedDragonPreferencesView: View {
    let settings: any ModSettings
    @SwiftUI.State private var enabled: Bool
    @SwiftUI.State private var reveal: RDRevealLevel
    @SwiftUI.State private var quiz: Bool
    @SwiftUI.State private var quizObservation: ModObservation?

    init(settings: any ModSettings) {
        self.settings = settings
        _enabled = SwiftUI.State(initialValue: RDSettings.isEnabled(settings))
        _reveal = SwiftUI.State(initialValue: RDSettings.reveal(settings))
        _quiz = SwiftUI.State(initialValue: RDSettings.quiz(settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(RDText.prefsEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, on in settings.set(on, forKey: RDSettings.assist) }
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
                    .onChange(of: reveal) { _, level in settings.set(level.rawValue, forKey: RDSettings.revealLevel) }
                }
                note(RDText.prefsRevealNote)
            }
            .disabled(!enabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(RDText.prefsQuiz, isOn: $quiz)
                    .onChange(of: quiz) { _, on in settings.set(on, forKey: RDSettings.quizMode) }
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
        // 热键切了答题模式时跟上
        .onAppear {
            quizObservation = settings.observe(RDSettings.quizMode) {
                let now = RDSettings.quiz(settings)
                if quiz != now { quiz = now }
            }
        }
        .onDisappear { quizObservation = nil }
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
