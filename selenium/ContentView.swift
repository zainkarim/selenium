//
//  ContentView.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cam = CameraManager()

    // Values (display/solve)
    @State private var targetISO: Int = 400      // locked by default
    @State private var comp: Double = 0.0        // EV compensation (slider for Step A)
    @State private var userAperture: Double = 5.6 // locked by default
    @State private var userShutter: Double = 1/125.0

    // Locks (default ISO + aperture)
    @State private var locks = LockState()

    // Feedback
    @State private var saveMessage: String?
    @State private var showToast = false

    // Computed solution based on locks
    private func computeSuggestion() -> (f: Double, t: Double, iso: Int) {
        // Live scene EV100
        let ev100 = EVMath.ev100(aperture: cam.aperture, shutter: cam.shutter, iso: cam.iso)
        // We'll map into target ISO (if ISO locked) otherwise solve it
        var f = userAperture
        var t = userShutter
        var iso = targetISO

        // Helper to snap & clamp
        func snapF(_ x: Double) -> Double {
            let clamped = min(22.0, max(0.95, x))
            return StopsTable.nearest(clamped, in: StopsTable.fStops)
        }
        func snapT(_ x: Double) -> Double {
            // clamp to 1/2000 ... 1/240 (fastest to slowest allowed)
            let minT = 1.0 / 2000.0, maxT = 1.0 / 240.0
            let clamped = min(maxT, max(minT, x))
            return StopsTable.nearest(clamped, in: StopsTable.shutters)
        }
        func snapISO(_ x: Int) -> Int {
            let clamped = min(6400, max(64, x))
            return StopsTable.nearestISO(clamped)
        }

        // If two are locked → solve the third
        switch locks.locked {
        case [.iso, .aperture]:
            // solve shutter
            let targetEV = EVMath.targetEV(ev100: ev100, targetISO: Double(iso), comp: comp)
            let tRaw = (f * f) / pow(2.0, targetEV)
            t = snapT(tRaw)

        case [.iso, .shutter]:
            // solve aperture
            let targetEV = EVMath.targetEV(ev100: ev100, targetISO: Double(iso), comp: comp)
            let fRaw = sqrt(t * pow(2.0, targetEV))
            f = snapF(fRaw)

        case [.aperture, .shutter]:
            // solve ISO (then snap to nearest film-centric)
            // EVt = log2(N^2 / t) - log2(S/100)  ⇒ S = 100 * 2^(log2(N^2/t) - EVt)
            let EVt = ev100 + comp // because EV100 = ... at ISO100; target EVt adds comp only
            let Sraw = 100.0 * pow(2.0, log2((f * f) / t) - EVt)
            iso = snapISO(Int(Sraw.rounded()))
        default:
            // Fallback (shouldn't happen): default to ISO+aperture locked
            let targetEV = EVMath.targetEV(ev100: ev100, targetISO: Double(iso), comp: comp)
            let tRaw = (f * f) / pow(2.0, targetEV)
            t = snapT(tRaw)
        }
        return (f, t, iso)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if cam.isConfigured { CameraPreview(session: cam.session).ignoresSafeArea() }
            else { Color.black.ignoresSafeArea() }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .safeAreaPadding(.bottom, 8)
            }
        }
        .onAppear { cam.configure() }
        .onDisappear { cam.stop() }
        .overlay(alignment: .bottom) {
            if showToast, let msg = saveMessage {
                Toast(text: msg)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.35), value: showToast)
            }
        }
    }

    // MARK: - Panel

    private var bottomPanel: some View {
        GlassPanel {
            VStack(spacing: 12) {
                exposureReadout // centered f / t / ISO / EC with tap-to-lock

                // EC slider (only slider in Step A; Step B will make it a scrub)
                HStack {
                    Text("EC").font(Design.Text.label).frame(width: 44, alignment: .leading)
                    Slider(value: $comp, in: -2...2, step: 1/3)
                    Text(String(format: "%+.1f", comp)).font(Design.Text.label).frame(width: 56, alignment: .trailing)
                }

            }
        }
    }

    private var exposureReadout: some View {
        let suggestion = computeSuggestion()
        let displayF = suggestion.f
        let displayT = suggestion.t
        let displayISO = suggestion.iso

        return HStack(spacing: 20) {
            valuePill(title: "f/", value: String(format: "%.1f", displayF), param: .aperture, isLocked: locks.isLocked(.aperture)) {
                locks.toggle(.aperture)
                if locks.isLocked(.aperture) { userAperture = displayF }
            }
            valuePill(title: "Shutter", value: EVMath.prettyShutter(displayT), param: .shutter, isLocked: locks.isLocked(.shutter)) {
                locks.toggle(.shutter)
                if locks.isLocked(.shutter) { userShutter = displayT }
            }
            valuePill(title: "ISO", value: "\(displayISO)", param: .iso, isLocked: locks.isLocked(.iso)) {
                locks.toggle(.iso)
                if locks.isLocked(.iso) { targetISO = displayISO }
            }
            // EC shown at far right for context
            VStack(spacing: 2) {
                Text(String(format: "%+.1f", comp)).font(Design.Text.overlay).foregroundStyle(.white)
                Text("EV").font(Design.Text.caption).foregroundStyle(.white.opacity(0.9))
            }
            .frame(minWidth: 58)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func valuePill(title: String, value: String, param: Param, isLocked: Bool, onTap: @escaping () -> Void) -> some View {
        let fg = isLocked ? Color.white : Color.white.opacity(0.75)
        let weight: Font.Weight = isLocked ? .semibold : .regular

        VStack(spacing: 2) {
            HStack(spacing: 6) {
                if isLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(fg) }
                Text(value).font(Design.Text.overlay.weight(weight)).foregroundStyle(fg)
            }
            Text(title).font(Design.Text.caption).foregroundStyle(.white.opacity(0.9))
        }
        .frame(minWidth: 84)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private func toast(_ msg: String) {
        saveMessage = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showToast = false }
        }
    }
}



#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
