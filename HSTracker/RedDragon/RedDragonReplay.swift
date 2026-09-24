//
//  RedDragonReplay.swift
//  HSTracker
//
//  路径重放校验（P0）。任何返回给调用方的序列，先由同一套规则引擎从初始状态重放一遍，
//  费用 / 格子 / 手牌数 / 目标合法性全过才允许返回 —— 宁可不给路径，也不给打不出来的路径。
//

import Foundation

struct RDReplayFailure: Error {
    var stepIndex: Int
    var reason: RDIllegal
}

enum RDReplay {

    struct Outcome {
        var finalState: RDState
        /// 每一步结算完剩余的可用法力（含临时水晶），给公式表逐 token 对账用
        var manaAfterEachStep: [Int]
        var damage: Int
    }

    static func run(_ actions: [RDAction], from state: RDState,
                    options: RDOptions = .search) throws -> Outcome {
        var s = state
        var mana: [Int] = []
        mana.reserveCapacity(actions.count)
        for (i, action) in actions.enumerated() {
            do {
                s = try RDEngine.apply(action, to: s, options: options)
            } catch let e as RDIllegal {
                throw RDReplayFailure(stepIndex: i, reason: e)
            }
            mana.append(s.availableMana)
        }
        return Outcome(finalState: s, manaAfterEachStep: mana, damage: s.damageDealt)
    }

    /// 校验成功返回终局状态，失败返回 nil（调用方据此丢掉这条线）
    static func validate(_ actions: [RDAction], from state: RDState,
                         expectedDamage: Int, options: RDOptions = .search) -> RDState? {
        guard let outcome = try? run(actions, from: state, options: options) else { return nil }
        guard outcome.damage == expectedDamage else { return nil }
        return outcome.finalState
    }
}
