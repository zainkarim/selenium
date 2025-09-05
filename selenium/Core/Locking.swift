//
//  Locking.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import Foundation

enum Param: Hashable { case iso, aperture, shutter }

/// - Default: ISO + aperture locked
/// - If ISO + aperture are locked and shutter is locked, auto-unlock aperture
/// - If aperture + shutter locked, ISO becomes free (unlocked)
struct LockState {
    private(set) var locked: Set<Param> = [.iso, .aperture]

    mutating func toggle(_ p: Param) {
        if locked.contains(p) {
            locked.remove(p)
            return
        }
        // try to add
        if locked.count < 2 {
            locked.insert(p)
            return
        }
        // already two; applying your rules
        switch p {
        case .shutter:
            // if ISO+aperture locked and user taps shutter -> unlock aperture
            if locked == [.iso, .aperture] { locked = [.iso, .shutter]; return }
        case .aperture:
            // if ISO+shutter locked and user taps aperture -> unlock shutter
            if locked == [.iso, .shutter] { locked = [.iso, .aperture]; return }
        case .iso:
            // if aperture+shutter locked and user taps ISO -> unlock aperture (keep shutter)
            if locked == [.aperture, .shutter] { locked = [.iso, .shutter]; return }
        }
        // Otherwise, replace an arbitrary non-p to keep count at 2
        if let victim = locked.first(where: { $0 != p }) {
            locked.remove(victim)
            locked.insert(p)
        }
    }

    func isLocked(_ p: Param) -> Bool { locked.contains(p) }
}
