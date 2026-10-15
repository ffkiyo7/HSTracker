//
//  GameEvents.swift
//  ModKit
//
//  口子 1：对局事件。
//
//  回调全部在解析线程（`LogReaderManager` 的串行队列）上同步调，`game` 只在回调期间有效：
//  - `batchEnded(idle: true)` 和 `topBlockClosed` 是一致边界：此刻只有解析线程写实体，读到的实体 tag、
//    场攻、剩余牌库是同一时刻的。要在别的线程用，在回调里拷成自己的值再走。
//  - 回调里不要阻塞：每批日志都会调，慢了整个解析跟着慢（宿主按耗时记日志点名）。
//    更新界面自己 `DispatchQueue.main.async`，同一份状态在同一个 main block 里提交，禁止 `main.sync`。
//  - 不要保存 `game` 或其中的实体，出了回调再读就是数据竞争。
//

import Foundation

/// 解析线程上的事件
public enum ModGameEvent: Hashable, Sendable {
    /// 新对局开始（解析到 CREATE_GAME 之后）
    case gameStarted
    /// 对局结束（胜负已定）
    case gameEnded
    /// 处理完一批日志行（没有新行的空批也会来）。`linesProcessed`：这批有没有行；
    /// `idle`：解析器没有未闭合的 BLOCK（一致边界）
    case batchEnded(linesProcessed: Bool, idle: Bool)
    /// 一行把最外层 BLOCK 闭合了（一致边界）。连着出牌时上一个 BLOCK_END 和下一个 BLOCK_START 落在同一批，
    /// 批尾永远不 idle，只有这个时机能读到中间的局面
    case topBlockClosed
}

/// 接对局事件的一方
public protocol ModGameEventHandler: AnyObject {
    /// 解析线程，同步。见文件头
    func handle(_ event: ModGameEvent, game: any ModGameState)
}
