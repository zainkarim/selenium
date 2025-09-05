//
//  ContentView.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cam = CameraManager()

    // User-controlled values
    @State private var targetISO: Double = 400
    @State private var comp: Double = 0.0
    @State private var lockMode: LockMode = .shutter
    @State private var lockShutter: Double = 1/125.0
    @State private var lockAperture: Double = 5.6

    // Feedback
    @State private var saveMessage: String?
    @State private var showToast = false

    var body: some View {
        ZStack {
            // Camera behind everything
            if cam.isConfigured {
                CameraPreview(session: cam.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Top overlay + bottom controls
            VStack(spacing: 0) {
                topOverlay
                    .padding(.top, 22)
                    .padding(.horizontal, 14)

                Spacer(minLength: 0)

                bottomControls
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .safeAreaPadding(.bottom, 8) // keep off the home indicator
            }
        }
        .onAppear { cam.configure() }
        .onDisappear { cam.stop() }
        .overlay(alignment: .bottom) {
            if showToast, let msg = saveMessage {
                Toast(text: msg)
                    .padding(.bottom, 90) // above shutter
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.35), value: showToast)
            }
        }
    }

    // MARK: - Overlays

    private var topOverlay: some View {
        let ev100 = EVMath.ev100(aperture: cam.aperture, shutter: cam.shutter, iso: cam.iso)
        let targetEV = EVMath.targetEV(ev100: ev100, targetISO: targetISO, comp: comp)
        var (fSol, tSol) = EVMath.solve(lock: lockMode, lockAperture: lockAperture, lockShutter: lockShutter, targetEV: targetEV)
        (fSol, tSol) = EVMath.snapped(f: fSol, t: tSol)

        let overlay = "ISO \(Int(targetISO)) • \(EVMath.prettyF(fSol)) • \(EVMath.prettyShutter(tSol)) • \(comp >= 0 ? "+" : "")\(String(format: "%.1f", comp))EV"

        return VStack(alignment: .leading, spacing: 8) {
            // LIVE/READY badge
            Text(cam.isRunning ? "LIVE" : "READY")
                .font(Design.Text.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.45), in: Capsule())
                .foregroundStyle(.white)

            // Suggested settings pill
            Text(overlay)
                .font(Design.Text.overlay)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.35), in: Capsule())
                .foregroundStyle(.white)

            // Raw measured data (smaller)
            Text(String(format: "EV100=%.2f  (f=%.1f, t≈%@, ISO≈%.0f)", ev100, cam.aperture, EVMath.prettyShutter(cam.shutter), cam.iso))
                .font(Design.Text.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomControls: some View {
        GlassPanel {
            VStack(spacing: 14) {
                // Lock picker
                Picker("Lock", selection: $lockMode) {
                    Text("Shutter").tag(LockMode.shutter)
                    Text("Aperture").tag(LockMode.aperture)
                    Text("Auto").tag(LockMode.auto)
                }
                .pickerStyle(.segmented)

                if lockMode == .shutter {
                    row(title: "Shutter") {
                        Slider(value: $lockShutter, in: StopsTable.shutters.min()!...StopsTable.shutters.max()!)
                    } trailing: {
                        Text(EVMath.prettyShutter(lockShutter)).frame(width: 72, alignment: .trailing)
                    }
                } else if lockMode == .aperture {
                    row(title: "Aperture") {
                        Slider(value: $lockAperture, in: 1.0...22.0)
                    } trailing: {
                        Text(EVMath.prettyF(lockAperture)).frame(width: 72, alignment: .trailing)
                    }
                }

                row(title: "ISO") {
                    Slider(value: $targetISO, in: 25...6400, step: 1)
                } trailing: {
                    Text("\(Int(targetISO))").frame(width: 60, alignment: .trailing)
                }

                row(title: "EC") {
                    Slider(value: $comp, in: -2...2, step: 1/3)
                } trailing: {
                    Text(String(format: "%+.1f", comp)).frame(width: 60, alignment: .trailing)
                }

                // Shutter centered below controls
                HStack {
                    Spacer()
                    shutterButton
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
    }

    private func row<Control: View, Trailing: View>(title: String,
                                                    @ViewBuilder control: () -> Control,
                                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title).font(Design.Text.label).frame(width: 68, alignment: .leading)
            control()
            trailing()
        }
    }

    private var shutterButton: some View {
        Button {
            Haptics.tap()

            // Freeze suggested values at capture
            let ev100 = EVMath.ev100(aperture: cam.aperture, shutter: cam.shutter, iso: cam.iso)
            let targetEV = EVMath.targetEV(ev100: ev100, targetISO: targetISO, comp: comp)
            var (fSol, tSol) = EVMath.solve(lock: lockMode, lockAperture: lockAperture, lockShutter: lockShutter, targetEV: targetEV)
            (fSol, tSol) = EVMath.snapped(f: fSol, t: tSol)
            let text = "ISO \(Int(targetISO)) • \(EVMath.prettyF(fSol)) • \(EVMath.prettyShutter(tSol)) • \(comp >= 0 ? "+" : "")\(String(format: "%.1f", comp))EV"

            cam.capturePhoto { image in
                guard let base = image else { toast("Capture failed"); Haptics.error(); return }
                let composited = OverlayRenderer.draw(on: base, text: text)
                PhotoSaver.saveToLibrary(composited) { ok, _ in
                    if ok { Haptics.success(); toast("Saved to Photos") }
                    else   { Haptics.error();   toast("Couldn’t save (check Photos)") }
                }
            }
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.95)).frame(width: 84, height: 84)
                Circle().strokeBorder(.black.opacity(0.25), lineWidth: 2).frame(width: 84, height: 84)
            }
        }
        .buttonStyle(.plain)
        .shadow(radius: 8, y: 4)
        .accessibilityLabel("Shutter")
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
