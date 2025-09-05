//
//  EVUtils.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import Foundation

enum StopsTable {
    // 1/3-stop shutter speeds (fast → slow). We’ll reuse next step.
    static let shutters: [Double] = [
        1/8000, 1/6400, 1/5000, 1/4000, 1/3200, 1/2500, 1/2000, 1/1600, 1/1250, 1/1000,
        1/800, 1/640, 1/500, 1/400, 1/320, 1/250, 1/200, 1/160, 1/125, 1/100,
        1/80, 1/60, 1/50, 1/40, 1/30, 1/25, 1/20, 1/15, 1/13, 1/10,
        1/8, 1/6, 1/5, 0.25, 0.3, 0.4, 0.5, 0.6, 0.8,
        1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30
    ]
    static let fStops: [Double] = [1.0,1.1,1.2,1.4,1.6,1.8,2.0,2.2,2.5,2.8,3.2,3.5,4.0,4.5,5.0,5.6,6.3,7.1,8.0,9.0,10.0,11.0,13.0,14.0,16.0,18.0,20.0,22.0]
}

enum EVMath {
    /// Scene EV normalized to ISO 100
    static func ev100(aperture N: Double, shutter t: Double, iso S: Double) -> Double {
        // EV100 = log2(N^2 / t) - log2(S/100)
        log2((N * N) / t) - log2(S / 100.0)
    }

    // Pretty formatters
    static func prettyShutter(_ t: Double) -> String {
        if t < 1 { return "1/\(Int(round(1.0 / t)))" }
        if t < 10 { return String(format: "%.1fs", t) }
        return "\(Int(round(t)))s"
    }
    static func prettyF(_ f: Double) -> String {
        "f/\(String(format: "%.1f", f))"
    }
}

enum LockMode { case shutter, aperture, auto }

extension EVMath {
    static func targetEV(ev100: Double, targetISO: Double, comp: Double) -> Double {
        ev100 + log2(targetISO / 100.0) + comp
    }

    /// Solve for settings given a lock mode
    static func solve(lock: LockMode,
                      lockAperture: Double?,
                      lockShutter: Double?,
                      targetEV: Double) -> (f: Double, t: Double) {
        switch lock {
        case .aperture:
            let N = lockAperture ?? 2.8
            let t = (N * N) / pow(2.0, targetEV)
            return (N, t)
        case .shutter:
            let t = lockShutter ?? 1/125.0
            let N = sqrt(t * pow(2.0, targetEV))
            return (N, t)
        case .auto:
            let N = 5.6
            let t = (N * N) / pow(2.0, targetEV)
            return (N, t)
        }
    }

    static func snapped(f: Double, t: Double) -> (f: Double, t: Double) {
        let nf = StopsTable.fStops.min(by: { abs($0 - f) < abs($1 - f) }) ?? f
        let nt = StopsTable.shutters.min(by: { abs($0 - t) < abs($1 - t) }) ?? t
        return (nf, nt)
    }
}
