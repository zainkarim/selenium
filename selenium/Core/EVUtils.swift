//
//  EVUtils.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import Foundation

enum StopsTable {
    // 1/3-stop shutters
    static let shutters: [Double] = [
        1/2000.0, 1/1600.0, 1/1250.0, 1/1000.0, 1/800.0, 1/640.0, 1/500.0, 1/400.0, 1/320.0, 1/250.0,
        1/240.0  // include exact 1/240 for your floor
    ]

    // 1/3-stop f-stops
    static let fStops: [Double] = [
        0.95, 1.0, 1.1, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.8,
        3.2, 3.5, 4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 8.0, 9.0,
        10.0, 11.0, 13.0, 14.0, 16.0, 18.0, 20.0, 22.0
    ]

    // Film-centric ISO
    static let isos: [Int] = [64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400]

    static func nearest<T: BinaryFloatingPoint>(_ value: T, in options: [T]) -> T {
        options.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    static func nearestISO(_ value: Int) -> Int {
        isos.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }
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
