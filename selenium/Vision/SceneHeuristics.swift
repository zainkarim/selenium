//
//  Untitled.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import Foundation
import CoreGraphics

struct SceneHeuristics {
    struct Bias {
        let fCenter: Double?     // preferred f/ center (nil = no bias)
        let tCenter: Double?     // preferred shutter center in seconds
        let strength: CGFloat    // 0…1 nominal strength before confidence
    }

    static func bias(for scene: SceneKind) -> Bias {
        switch scene {
        case .portrait:
            return .init(fCenter: 2.2, tCenter: 1.0/200.0, strength: 0.55)
        case .group:
            return .init(fCenter: 7.1, tCenter: 1.0/100.0, strength: 0.55)
        case .animal:
            return .init(fCenter: 2.8, tCenter: 1.0/600.0, strength: 0.65)
        case .plant: // close-up feel
            return .init(fCenter: 2.8, tCenter: 1.0/200.0, strength: 0.50)
        case .landscape:
            return .init(fCenter: 9.0, tCenter: 1.0/125.0, strength: 0.55)
        case .other:
            return .init(fCenter: nil, tCenter: nil, strength: 0)
        }
    }

    /// Softly bias a value toward a target center (doesn't override manual control).
    /// alpha = userStrength * confidence * globalGain, clamped 0…1
    static func biasedToward(_ current: Double, center: Double?, userStrength: CGFloat, confidence: CGFloat, globalGain: CGFloat) -> Double {
        guard let c = center, userStrength > 0, confidence > 0, globalGain > 0 else { return current }
        let a = Double(min(1, max(0, userStrength * confidence * globalGain)))
        // smoothstep-ish easing (less jumpy around small differences)
        let mix = a * a * (3 - 2 * a)
        return current * (1 - mix) + c * mix
    }
}
