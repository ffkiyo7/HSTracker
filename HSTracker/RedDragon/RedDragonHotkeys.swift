//
//  RedDragonHotkeys.swift
//  HSTracker
//
//  红龙辅助的热键：升档 / 降档 / 答题模式开关。
//
//  用 Carbon 的 `RegisterEventHotKey`：系统直接把组合键投给本进程，不需要「辅助功能」或「输入监控」权限
//  （`NSEvent.addGlobalMonitorForEvents` 监听键盘要权限）。只在「开关开着 + 炉石在前台」时注册，
//  炉石退到后台就注销，所以别的 app 在前台时这几个组合键原样给它们；回调里再核一次前台。
//
//  默认键位 ⌃⌥W / ⌃⌥S / ⌃⌥Q（W 上、S 下、Q = quiz）：HSTracker 自己的快捷键都是 ⌘ 组合（⌘D、⌘⇧R、⌘,），
//  而且只在 HSTracker 在前台时生效；炉石自己只用 Esc / Enter 和 ⌘ 组合；macOS 默认的 ⌃ 组合是 ⌃ + 方向键 / 空格 / 数字，
//  不带 ⌥。Rectangle 一类窗口工具常占 ⌃⌥ + 方向键 / Enter / U I J K / D F G E T / C，所以避开方向键。
//  组合键已被别的程序注册时 `RegisterEventHotKey` 返回 `eventHotKeyExistsErr`，记日志、不抢。
//

import AppKit
import Carbon.HIToolbox
@testable import RedDragonCore

final class RedDragonHotkeys {

    enum Action: UInt32, CaseIterable {
        case raise = 1
        case lower = 2
        case quiz = 3
    }

    struct Binding: Equatable {
        var action: Action
        var keyCode: UInt32
        var modifiers: UInt32
        /// 设置页上显示的写法
        var display: String
    }

    static let modifiers = UInt32(controlKey | optionKey)

    static let bindings: [Binding] = [
        Binding(action: .raise, keyCode: UInt32(kVK_ANSI_W), modifiers: modifiers, display: "⌃⌥W"),
        Binding(action: .lower, keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers, display: "⌃⌥S"),
        Binding(action: .quiz, keyCode: UInt32(kVK_ANSI_Q), modifiers: modifiers, display: "⌃⌥Q")
    ]

    static let hearthstoneBundleId = "unity.Blizzard Entertainment.Hearthstone"
    /// 'RDHK'
    private static let signature: OSType = 0x5244_484B

    static let shared = RedDragonHotkeys()

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var started = false
    /// 注册失败的组合键（被别的程序占了），测试 / 日志用
    private(set) var failed: [Action] = []

    var isRegistered: Bool { return !refs.isEmpty }

    /// 只在开关开着、炉石在前台时注册
    static func shouldRegister(enabled: Bool, frontmostBundleId: String?) -> Bool {
        return enabled && frontmostBundleId == hearthstoneBundleId
    }

    /// 热键动作。只在主线程调（Carbon 的回调在主线程的事件循环里）
    static func perform(_ action: Action, assistant: RedDragonAssistant) {
        switch action {
        case .raise: assistant.raiseReveal()
        case .lower: assistant.lowerReveal()
        // 走设置键：通知 → assistant.recompose，设置页也跟着变
        case .quiz: Settings.redDragonQuizMode = !Settings.redDragonQuizMode
        }
    }

    func start() {
        guard !started else { return }
        started = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.update()
            }))
        }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: Notification.Name(rawValue: Settings.red_dragon_assist),
                                                     object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }))
        update()
    }

    func update() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if Self.shouldRegister(enabled: Settings.redDragonAssist, frontmostBundleId: front) {
            register()
        } else {
            unregister()
        }
    }

    private func register() {
        guard refs.isEmpty else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                let got = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                            nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard got == noErr, id.signature == RedDragonHotkeys.signature,
                      let action = RedDragonHotkeys.Action(rawValue: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                RedDragonHotkeys.shared.fire(action)
                return noErr
            }, 1, &type, nil, &handler)
            if status != noErr {
                logger.error("red dragon hotkeys: InstallEventHandler failed \(status)")
                return
            }
        }
        failed = []
        for b in Self.bindings {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(b.keyCode, b.modifiers, EventHotKeyID(signature: Self.signature, id: b.action.rawValue),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.append(b.action)
                logger.warning("red dragon hotkeys: \(b.display) not registered (\(status))")
            }
        }
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
    }

    private func fire(_ action: Action) {
        // 注销和失焦之间可能还排着一个按键事件
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.hearthstoneBundleId,
              Settings.redDragonAssist else { return }
        Self.perform(action, assistant: .shared)
    }
}
