//
//  Overlay.swift
//  ModKit
//
//  口子 3：overlay 图层。
//
//  mod 给一个 SwiftUI 视图，宿主把它放进 overlay 的固定像素层（画布 = 炉石窗口的真实像素，左上角为原点，
//  和宿主自己的场面网格、入场序号同一层）。每个 mod 各自一层，按加载顺序叠，宿主不替它们互相避让：
//  mod 自己让开 `reservedFrames`（记牌器等宿主面板）。
//
//  画布尺寸、记牌器位置变了，宿主重新调 `overlayView(canvas:)`（SwiftUI 的 body 重算），mod 拿新的 canvas 重排；
//  mod 自己的状态变化走自己的 ObservableObject。
//
//  overlay 窗口默认点击穿透。要接鼠标的控件用 `.modInteractiveRegion()` 上报自己的外框，
//  光标进了这块区域窗口才接鼠标；窗口是不激活的面板，点了炉石不失去前台。
//

import CoreGraphics
import SwiftUI

/// 交给 mod 视图的画布信息（每次重排都是新值）
public struct ModOverlayCanvas {
    /// 画布像素尺寸（炉石窗口）
    public var size: CGSize
    /// 宿主面板占的矩形（画布像素）：目前是显示中的双方记牌器，拖动、缩放时跟着变。mod 的面板别压上去
    public var reservedFrames: [CGRect]
    /// 宿主怎么摆手牌、场面（跟着宿主版本走，mod 不要自己抄公式）
    public var geometry: any ModBoardGeometry

    public init(size: CGSize, reservedFrames: [CGRect], geometry: any ModBoardGeometry) {
        self.size = size
        self.reservedFrames = reservedFrames
        self.geometry = geometry
    }

    /// 1 u = 窗口高 / 1080：按 1080p 设计的尺寸乘它
    public var unit: CGFloat { size.height / 1080 }
}

/// 一张手牌在画布上的位置（宿主悬停判定用的那个矩形，绕中心转过 `angle` 度）
public struct ModHandCardPlacement: Hashable, Sendable {
    public var center: CGPoint
    /// 顺时针，度
    public var angle: Double
    public var size: CGSize

    public init(center: CGPoint, angle: Double, size: CGSize) {
        self.center = center
        self.angle = angle
        self.size = size
    }
}

/// 宿主的手牌 / 场面几何，按当前画布算好（构筑模式口径）
public protocol ModBoardGeometry {
    /// 第 `index` 张手牌（共 `count` 张，从左数，0 起）
    func handCard(index: Int, count: Int) -> ModHandCardPlacement
    /// 第 `index` 格随从（共 `count` 格，从左数，0 起）的矩形
    func minionFrame(isOpponent: Bool, index: Int, count: Int) -> CGRect
    /// 入场序号徽章的高度（mod 想画同款徽章时对齐用）
    var boardBadgeSize: CGFloat { get }
    /// 4:3 安全区里的横坐标：`fraction` 是相对 4:3 区域宽度的比例（宽屏两侧是黑边）
    func scaledX(_ fraction: CGFloat) -> CGFloat
}

/// 提供 overlay 的一方
public protocol ModOverlayProvider: AnyObject {
    /// 主线程。宿主每次重排都会调，返回的视图铺满画布（左上角对齐），别做重活
    @MainActor
    func overlayView(canvas: ModOverlayCanvas) -> AnyView
}

// MARK: - 接鼠标的区域

/// 宿主给 mod 视图的容器设的坐标空间名：`.modInteractiveRegion()` 在这个空间里量外框
public enum ModOverlayCoordinateSpace {
    public static let name = "hstracker.mod.overlay-canvas"
}

/// mod 视图里要接鼠标的矩形（`ModOverlayCoordinateSpace` 坐标），宿主收集后交给 overlay 窗口
public struct ModInteractiveRegionKey: PreferenceKey {
    public static var defaultValue: [CGRect] { [] }

    /// 收成列表，不并成一个外接框：两块离得远时外接框会盖住大半屏，点不穿
    public static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// 这个视图要接鼠标（按钮之类）。没挂它的地方照旧点击穿透到炉石
    public func modInteractiveRegion() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ModInteractiveRegionKey.self,
                                   value: [proxy.frame(in: .named(ModOverlayCoordinateSpace.name))])
        })
    }
}
