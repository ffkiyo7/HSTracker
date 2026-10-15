//
//  RedDragonEntry.swift
//  RedDragonMod
//
//  mod 动态库的入口（ModKit 的 `ModEntryPoint`）。只编进动态库，HSTrackerTests 不编它。
//

import ModKit

@_cdecl("hstracker_mod_entry")
public func hstrackerModEntry() -> UnsafeMutableRawPointer {
    return RedDragonMod.registration().retainedPointer()
}
