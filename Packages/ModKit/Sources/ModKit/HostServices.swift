//
//  HostServices.swift
//  ModKit
//
//  口子 5：宿主服务。`HSTrackerMod.activate(_:)` 时交给 mod，mod 可以一直留着用。
//  除标了 @MainActor 的以外，任何线程都可以调。
//

import Foundation
import SwiftUI

public enum ModLogLevel: Int, Hashable, Comparable, Sendable {
    case debug
    case info
    case warning
    case error

    public static func < (lhs: ModLogLevel, rhs: ModLogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// HSTracker 给 mod 的服务
public protocol ModHostServices: AnyObject {
    /// 这个 mod 自己的身份（宿主读到的那份）
    var manifest: ModManifest { get }
    /// HSTracker 的版本号（CFBundleShortVersionString），只用于显示和日志
    var hostVersion: String { get }

    /// 写进 HSTracker 的日志，宿主自动带上 mod id
    func log(_ level: ModLogLevel, _ message: String)
    /// 跟随应用语言的卡名；卡库里没有这个 id 时为 nil
    func cardName(_ cardId: String) -> String?
    /// mod 自己的数据目录（`…/HSTracker/ModData/<mod id>/`），宿主保证已存在
    var dataDirectory: URL { get }
    /// mod 自己的设置（口子 4）
    var settings: any ModSettings { get }
    /// 记牌器的配色和数字字体，mod 的面板想和记牌器一个样式时用
    var trackerStyle: ModTrackerStyle { get }
}

extension ModHostServices {
    public func debug(_ message: String) { log(.debug, message) }
    public func info(_ message: String) { log(.info, message) }
    public func warning(_ message: String) { log(.warning, message) }
    public func error(_ message: String) { log(.error, message) }
}

/// 记牌器的高亮色
public enum ModHighlight: Hashable, Sendable {
    case teal
    case orange
    case green
}

/// 记牌器的样式（宿主的记牌器换样式时跟着变，mod 不用改）
public struct ModTrackerStyle {
    /// 面板底色
    public var base: Color
    /// 金色描边 / 强调
    public var gold: Color
    /// 面板外框线
    public var line: Color
    /// 行之间的细线
    public var rowLine: Color
    public var text: Color
    /// 传奇星标
    public var star: Color
    /// 已进坟场的骷髅图标
    public var skull: Color
    /// 烧掉的火焰图标
    public var flame: Color
    /// 暗掉的内容（张数 0 之类）乘的不透明度
    public var dimContentOpacity: Double
    /// 记牌器数字用的字体名（宿主已注册）
    public var digitFontName: String
    private var highlights: [ModHighlight: Color]

    public init(base: Color, gold: Color, line: Color, rowLine: Color, text: Color,
                star: Color, skull: Color, flame: Color, dimContentOpacity: Double,
                digitFontName: String, highlights: [ModHighlight: Color]) {
        self.base = base
        self.gold = gold
        self.line = line
        self.rowLine = rowLine
        self.text = text
        self.star = star
        self.skull = skull
        self.flame = flame
        self.dimContentOpacity = dimContentOpacity
        self.digitFontName = digitFontName
        self.highlights = highlights
    }

    public func highlight(_ color: ModHighlight) -> Color? {
        highlights[color]
    }

    /// 记牌器的数字字体，`size` 是已经乘过缩放的磅数
    public func digits(size: CGFloat) -> Font {
        Font.custom(digitFontName, size: size)
    }
}
