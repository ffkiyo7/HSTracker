//
//  ModOverlayLayer.swift
//  HSTracker
//
//  Fork：ModKit 口子 3（overlay 图层）在 app 里的实现。挂在 `RootOverlayView` 的固定像素层
//  （画布 = 炉石窗口的真实像素），每个已启用、给了 overlay 的 mod 一层，按加载顺序叠。
//
//  每一跳（AGENTS.md「线程与时序」）：记牌器的 @Published 在主线程变 → `ModReservedFrames.stage` 攒着 →
//  **`main.async`** 一次提交（拖动一步先后改 left、top，只提交一次）→ `ModOverlayLayerView` 重算画布 →
//  主线程调各 mod 的 `overlayView(canvas:)`。mod 自己的状态走它自己的 ObservableObject，不经过这里。
//  `RootOverlayView` 里和 mod 无关的刷新不让这一层重算（视图只带 view model 和画布尺寸）。
//

import AppKit
import Combine
import ModKit
import SwiftUI

/// 宿主的手牌 / 场面几何（构筑模式口径），照 `BoardOverlayView` 的公式
struct HostBoardGeometry: ModBoardGeometry {
    let canvas: CGSize

    func handCard(index: Int, count: Int) -> ModHandCardPlacement {
        let pos = BoardOverlayView.handCardPosition(index: index, count: count, canvasSize: canvas)
        let angle = BoardOverlayView.handCardAngle(index: index, count: count, pos: pos, canvasSize: canvas)
        // 悬停判定用的手牌矩形大小（`BoardOverlayView.handTargets`）
        return ModHandCardPlacement(center: pos, angle: angle,
                                    size: CGSize(width: canvas.height * 0.125, height: canvas.height * 0.189))
    }

    /// 横向照 `BoardOverlayView.row` 的居中 HStack，纵向是它的 `opponentTop` / `playerTop`（无佣兵偏移）
    func minionFrame(isOpponent: Bool, index: Int, count: Int) -> CGRect {
        let width = BoardOverlayView.minionWidth(canvas)
        let margin = BoardOverlayView.minionMargin(canvas, isMercenariesMatch: false)
        let slot = width + 2 * margin
        let height = BoardOverlayView.boardHeight(canvas)
        let centerX = canvas.width / 2 + (CGFloat(index) - CGFloat(count - 1) / 2) * slot
        let top = isOpponent
            ? BoardOverlayView.opponentTop(canvas, isMercenariesMatch: false, isMainAction: false, mercsToNominate: false)
            : BoardOverlayView.playerTop(canvas, isMercenariesMatch: false, isMainAction: false, mercsToNominate: false)
        return CGRect(x: centerX - width / 2, y: top, width: width, height: height)
    }

    var boardBadgeSize: CGFloat {
        BoardOrderSlotViewModel.badgeSize(height: BoardOverlayView.boardHeight(canvas))
    }

    func scaledX(_ fraction: CGFloat) -> CGFloat {
        SizeHelper.getScaledXPos(fraction, width: canvas.width, ratio: BoardOverlayView.ratio(canvas))
    }
}

/// 宿主面板占的位置（`ModOverlayCanvas.reservedFrames`）：目前是两个记牌器。订阅它们 view model 的
/// isShown / left / top / height / scaling（拖动、改高度时每一步都变）和卡牌尺寸设置；去重后才发，
/// 记牌器内容刷新不会让 mod 图层重算
final class ModReservedFrames: ObservableObject {
    /// 记牌器的位置参数（`TrackerPanelViewModel` 的 top / left / height / scaling / isShown）
    struct TrackerPlacement: Equatable {
        var isOpponent: Bool
        var isShown: Bool
        var left: Double
        var top: Double
        var height: Double
        var scaling: Double
    }

    struct State: Equatable {
        var placements: [TrackerPlacement]
        var cardSize: CardSize
    }

    @Published private(set) var state: State
    /// 提交了几次（测试用）
    private(set) var commits = 0
    private var cancellables: [AnyCancellable] = []
    private var cardSizeObserver: NSObjectProtocol?

    init(trackers: [TrackerPanelViewModel]) {
        state = State(placements: trackers.map(Self.placement), cardSize: Settings.cardSize)
        for (i, vm) in trackers.enumerated() {
            let isOpponent = vm.playerType == .opponent
            Publishers.CombineLatest(Publishers.CombineLatest3(vm.$isShown, vm.$left, vm.$top),
                                     Publishers.CombineLatest(vm.$height, vm.$scaling))
                .map { a, b in
                    TrackerPlacement(isOpponent: isOpponent, isShown: a.0, left: a.1, top: a.2,
                                     height: b.0, scaling: b.1)
                }
                .removeDuplicates()
                .sink { [weak self] p in
                    self?.stage { $0.placements[i] = p }
                }
                .store(in: &cancellables)
        }
        cardSizeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: Settings.card_size), object: nil, queue: .main) { [weak self] _ in
                self?.stage { $0.cardSize = Settings.cardSize }
            }
    }

    deinit {
        if let cardSizeObserver {
            NotificationCenter.default.removeObserver(cardSizeObserver)
        }
    }

    private static func placement(_ vm: TrackerPanelViewModel) -> TrackerPlacement {
        return TrackerPlacement(isOpponent: vm.playerType == .opponent, isShown: vm.isShown,
                                left: vm.left, top: vm.top, height: vm.height, scaling: vm.scaling)
    }

    private var staged: State?
    private var flushScheduled = false

    /// 主线程（记牌器的 @Published 在主线程写）。拖动一步会先后改 left、top：先攒着，下一跳 main.async 一次提交
    private func stage(_ change: (inout State) -> Void) {
        var next = staged ?? state
        change(&next)
        staged = next
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        guard let next = staged else { return }
        staged = nil
        guard next != state else { return }
        state = next
        commits += 1
    }

    func frames(canvas: CGSize) -> [CGRect] {
        return state.placements.compactMap { Self.trackerBox($0, cardSize: state.cardSize, canvas: canvas) }
    }

    /// 记牌器占的矩形，照 `TrackerPanelView` 的摆法：对手的左沿挂在 left%，我方的右沿挂在 left%；
    /// 高 = height% H；宽取「按区域分组」和老布局两种宽度的大者（不管哪种布局都不会少算）
    static func trackerBox(_ p: TrackerPlacement, cardSize: CardSize, canvas: CGSize) -> CGRect? {
        guard p.isShown else { return nil }
        let scale = CGFloat(max(p.scaling / 100, 0.01))
        let width = max(TrackerMetrics.panelWidth(windowWidth: canvas.width, windowHeight: canvas.height,
                                                  cardSize: cardSize),
                        legacyTrackerWidth(cardSize)) * scale
        let anchor = canvas.width * CGFloat(p.left / 100)
        return CGRect(x: p.isOpponent ? anchor : anchor - width, y: canvas.height * CGFloat(p.top / 100),
                      width: width, height: canvas.height * CGFloat(p.height / 100))
    }

    /// `SizeHelper.trackerWidth` 的同一张表，按参数而不是当前设置取
    static func legacyTrackerWidth(_ cardSize: CardSize) -> CGFloat {
        switch cardSize {
        case .tiny: return CGFloat(kTinyFrameWidth)
        case .small: return CGFloat(kSmallFrameWidth)
        case .medium: return CGFloat(kMediumFrameWidth)
        case .big: return CGFloat(kFrameWidth)
        case .huge: return CGFloat(kHighRowFrameWidth)
        }
    }
}

/// `RootOverlayViewModel` 持有的 mod 图层状态：画哪些 mod（启动时定，之后不变）和记牌器位置
final class ModOverlayLayerModel: ObservableObject {
    let providers: [(id: String, provider: any ModOverlayProvider)]
    let reserved: ModReservedFrames

    init(providers: [(id: String, provider: any ModOverlayProvider)], trackers: [TrackerPanelViewModel]) {
        self.providers = providers
        self.reserved = ModReservedFrames(trackers: trackers)
    }

    func canvas(size: CGSize) -> ModOverlayCanvas {
        ModOverlayCanvas(size: size, reservedFrames: reserved.frames(canvas: size),
                         geometry: HostBoardGeometry(canvas: size))
    }
}

struct ModOverlayLayerView: View {
    let model: ModOverlayLayerModel
    @ObservedObject private var reserved: ModReservedFrames
    let canvasSize: CGSize

    init(model: ModOverlayLayerModel, canvasSize: CGSize) {
        self.model = model
        self._reserved = ObservedObject(wrappedValue: model.reserved)
        self.canvasSize = canvasSize
    }

    var body: some View {
        let usable = RootOverlayView.isUsableCanvas(canvasSize)
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if usable {
                let canvas = model.canvas(size: canvasSize)
                ForEach(model.providers, id: \.id) { item in
                    item.provider.overlayView(canvas: canvas)
                        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .coordinateSpace(name: ModOverlayCoordinateSpace.name)
        // mod 用 `.modInteractiveRegion()` 报的外框（mod 坐标空间）换算成宿主的 `rootOverlayCanvas`，
        // 交给 `RootOverlayWindow` 判断点击穿透
        .backgroundPreferenceValue(ModInteractiveRegionKey.self) { regions in
            GeometryReader { proxy in
                let origin = proxy.frame(in: .rootOverlayCanvas).origin
                Color.clear.preference(key: InteractiveRegionPreferenceKey.self,
                                       value: regions.map { $0.offsetBy(dx: origin.x, dy: origin.y) })
            }
        }
    }
}
