//
//  ContentView.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

import SwiftUI

struct ContentView: View {
    @StateObject private var cam = CameraManager()

    // User-controlled values
    @State private var targetISO: Double = 400
    @State private var comp: Double = 0.0
    @State private var lockMode: LockMode = .shutter
    @State private var lockShutter: Double = 1/125.0
    @State private var lockAperture: Double = 5.6

    var body: some View {
        ZStack(alignment: .bottom) {
            if cam.isConfigured {
                CameraPreview(session: cam.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 12) {
                liveReadout
                controls
            }
            .padding(.bottom, 24)
        }
        .onAppear { cam.configure() }
        .onDisappear { cam.stop() }
    }

    private var liveReadout: some View {
        let ev100 = EVMath.ev100(aperture: cam.aperture,
                                 shutter: cam.shutter,
                                 iso: cam.iso)
        let targetEV = EVMath.targetEV(ev100: ev100,
                                       targetISO: targetISO,
                                       comp: comp)
        var (fSol, tSol) = EVMath.solve(lock: lockMode,
                                        lockAperture: lockAperture,
                                        lockShutter: lockShutter,
                                        targetEV: targetEV)
        (fSol, tSol) = EVMath.snapped(f: fSol, t: tSol)

        let overlay = "ISO \(Int(targetISO)) • \(EVMath.prettyF(fSol)) • \(EVMath.prettyShutter(tSol)) • \(comp >= 0 ? "+" : "")\(String(format: "%.1f", comp))EV"

        return VStack(spacing: 6) {
            Text(overlay)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
                .foregroundStyle(.white)

            Text(String(format: "EV100=%.2f  (f=%.1f, t≈%@, ISO≈%.0f)",
                        ev100,
                        cam.aperture,
                        EVMath.prettyShutter(cam.shutter),
                        cam.iso))
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.top, 32)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            // Lock mode picker
            Picker("Lock", selection: $lockMode) {
                Text("Shutter").tag(LockMode.shutter)
                Text("Aperture").tag(LockMode.aperture)
                Text("Auto").tag(LockMode.auto)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Shutter / Aperture slider depending on lock
            if lockMode == .shutter {
                HStack {
                    Text("Shutter")
                    Slider(value: $lockShutter,
                           in: StopsTable.shutters.min()!...StopsTable.shutters.max()!)
                    Text(EVMath.prettyShutter(lockShutter))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal)
            } else if lockMode == .aperture {
                HStack {
                    Text("Aperture")
                    Slider(value: $lockAperture, in: 1.0...22.0)
                    Text(EVMath.prettyF(lockAperture))
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal)
            }

            // ISO slider
            HStack {
                Text("ISO")
                Slider(value: $targetISO, in: 25...6400, step: 1)
                Text("\(Int(targetISO))").frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal)

            // EC slider
            HStack {
                Text("EC")
                Slider(value: $comp, in: -2...2, step: 1/3)
                Text(String(format: "%+.1f", comp))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal)
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
