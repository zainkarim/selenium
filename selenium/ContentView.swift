////
//  ContentView.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cam = CameraManager()

    // MARK: - Auto/Manual model
    // ISO is always manual. The auto param is whichever of aperture/shutter is NOT being directly controlled.
    enum AutoParam { case aperture, shutter }
    @State private var autoParam: AutoParam = .shutter // default: ISO + Aperture manual
    
    @State private var showGallery = false
    @ObservedObject private var store: LocalStore = .shared

    // MARK: - Values
    @State private var targetISO: Int = 400
    @State private var comp: Double = 0.0
    @State private var userAperture: Double = 5.6
    @State private var userShutter: Double = 1/125.0

    // MARK: - Scrub drivers & friction (pixels per 1/3-stop step)
    @State private var scrubF = VerticalScrubber()
    @State private var scrubT = VerticalScrubber()
    @State private var scrubISO = VerticalScrubber()
    @State private var scrubEV = VerticalScrubber()
    
    // Active-scrub visual state
    @State private var scrubbingF = false
    @State private var scrubbingT = false
    @State private var scrubbingISO = false
    @State private var scrubbingEV = false

    @State private var frictionF: CGFloat = 512   // aperture
    @State private var frictionT: CGFloat = 576   // shutter
    @State private var frictionISO: CGFloat = 448 // ISO
    @State private var frictionEV: CGFloat = 24  // EV

    // For EV slider ticks
    @State private var lastSnappedEV: Double = 0.0

    // Feedback
    @State private var saveMessage: String?
    @State private var showToast = false
    
    //Onboarding
    @State private var showOnboarding = false
    private let onboardingKey = "selenium.onboarding.v1"
    
    private let evNudgeKey = "selenium.evNudge.v1"
    @State private var evNudgeActive = false
    
    // Vision
    @StateObject private var sceneEngine = SceneEngine()
    @State private var aiEnabled = true

    // Smoothing caches (for auto param only)
    @State private var smoothedAutoF: Double?
    @State private var smoothedAutoT: Double?

    // Global AI bias gain (0…1). Start conservative.
    @State private var aiGain: CGFloat = 0.6
    
    @State private var showAISheet = false
    @State private var aiPreview = ""


    private let firstRunKey = "selenium.firstRunSeeded"

    // MARK: - Solve (two manual, one auto)
    private func computeSuggestion() -> (f: Double, t: Double, iso: Int) {
        let ev100 = EVMath.ev100(aperture: cam.aperture, shutter: cam.shutter, iso: cam.iso)

        func snapF(_ x: Double) -> Double {
            let clamped = min(22.0, max(0.95, x))
            return StopsTable.nearest(clamped, in: StopsTable.fStops)
        }
        func snapT(_ x: Double) -> Double {
            let minT = 1.0 / 8000.0, maxT = 1.0 / 1.0 // now 1/8000 ... 1s
            let clamped = min(maxT, max(minT, x))
            return StopsTable.nearest(clamped, in: StopsTable.shutters)
        }

        func snapISO(_ x: Int) -> Int {
            let clamped = min(6400, max(64, x))
            return StopsTable.nearestISO(clamped)
        }

        var f = userAperture
        var t = userShutter
        let S = targetISO

        switch autoParam {
        case .shutter:
            // Manual: ISO + Aperture → Auto: Shutter
            let targetEV = EVMath.targetEV(ev100: ev100, targetISO: Double(S), comp: comp)
            let tRaw = (f * f) / pow(2.0, targetEV)
            t = snapT(tRaw)
        case .aperture:
            // Manual: ISO + Shutter → Auto: Aperture
            let targetEV = EVMath.targetEV(ev100: ev100, targetISO: Double(S), comp: comp)
            let fRaw = sqrt(t * pow(2.0, targetEV))
            f = snapF(fRaw)
        }

        return (f, t, snapISO(S))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if cam.isConfigured {
                CameraPreview(session: cam.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                bottomPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .safeAreaPadding(.bottom, 8)
            }
        }
        .onAppear {
            cam.configure()
            cam.sceneSink = sceneEngine

            // Seed friction into scrub drivers
            scrubF.stepPixels = frictionF
            scrubT.stepPixels = frictionT
            scrubISO.stepPixels = frictionISO
            scrubEV.stepPixels = frictionEV

            // First run seed
            if !UserDefaults.standard.bool(forKey: firstRunKey) {
                targetISO = 400
                userAperture = 5.6
                autoParam = .shutter // aperture is manual by default
                UserDefaults.standard.set(true, forKey: firstRunKey)
            }
            
            // Onboarding
            if !UserDefaults.standard.bool(forKey: onboardingKey) {
                showOnboarding = true
            }
            
            if !UserDefaults.standard.bool(forKey: evNudgeKey) {
                // run a gentle double pulse after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true)) {
                        evNudgeActive = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        evNudgeActive = false
                        UserDefaults.standard.set(true, forKey: evNudgeKey)
                    }
                }
            }
            
            LocalStore.shared.sceneEngine = sceneEngine

        }
        .onDisappear {
            cam.sceneSink = nil
            cam.stop()
        }
        
        .overlay {
            if showOnboarding {
                FirstRunOverlay {
                    UserDefaults.standard.set(true, forKey: onboardingKey)
                    withAnimation(.spring(response: 0.35)) { showOnboarding = false }
                }
                .transition(.opacity)
            }
        }

        .overlay(alignment: .bottom) {
            if showToast, let msg = saveMessage {
                Toast(text: msg)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.35), value: showToast)
            }
        }
        .fullScreenCover(isPresented: $showGallery) {
            GalleryView {
                showGallery = false
            }
        }
        .confirmationDialog("AI suggestion", isPresented: $showAISheet, titleVisibility: .visible) {
            Button("Apply") {
                commitAISuggestion(keepAutoSplit: true)   // don’t flip auto/manual
            }
            Button("Apply & make manual") {
                commitAISuggestion(keepAutoSplit: false)  // flip to make this param manual
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(aiPreview)
        }

    }

    // MARK: - Panel

    private var bottomPanel: some View {
        GlassPanel {
            VStack(spacing: 12) {
                exposureReadout   // centered f / Shutter / ISO / EV (tap to choose which is manual)
                evRow             // EV slider with tick-on-1/3-stop (keep or remove later)
                HStack(spacing: 10) {
                    Toggle(isOn: $aiEnabled) {
                        Image(systemName: "sparkles")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()

                    // Chip with confidence cue
                    let conf = sceneEngine.latest.confidence
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(aiChipText()).lineLimit(1)
                        HStack(spacing: 2) { // confidence dots (0–3)
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i < Int((conf * 3).rounded(.down)) ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            // Build a preview like: "→ f/2.2" or "→ 1/250"
                            let s = computeSuggestion()
                            var f = s.f, t = s.t
                            if aiEnabled {
                                let b = SceneHeuristics.bias(for: sceneEngine.scene)
                                let conf = sceneEngine.latest.confidence
                                switch autoParam {
                                case .shutter:
                                    let biasedT = SceneHeuristics.biasedToward(t, center: b.tCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                                    t = StopsTable.nearest(biasedT, in: StopsTable.shutters)
                                    aiPreview = "→ \(EVMath.prettyShutter(t))"
                                case .aperture:
                                    let biasedF = SceneHeuristics.biasedToward(f, center: b.fCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                                    f = StopsTable.nearest(biasedF, in: StopsTable.fStops)
                                    aiPreview = String(format: "→ f/%.1f", f)
                                }
                            } else {
                                aiPreview = "AI off"
                            }
                            showAISheet = true
                        }
                    )

                    .font(Design.Text.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.25), in: Capsule())
                    .opacity(aiEnabled ? max(0.4, conf) : 0.4)

                    Spacer()

                    // Apply button: commit AI suggestion to manual control
                    if aiEnabled, conf > 0.25 {
                        Button {
                            Haptics.tap()
                            commitAISuggestion()
                        } label: {
                            Text("Apply")
                                .font(Design.Text.label.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .accessibilityLabel("Apply AI suggestion")
                    }
                }

                // Actions row
                HStack {
                    // Gallery
                    Button { Haptics.tap(); store.load(); showGallery = true } label: {
                        Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Open gallery")
                    }

                    Spacer(minLength: 20)

                    // Shutter
                    Button { Haptics.tap(); takeAndSave() } label: {
                        ZStack {
                            Circle().fill(.white.opacity(0.95)).frame(width: 84, height: 84)
                            Circle().strokeBorder(.black.opacity(0.25), lineWidth: 2).frame(width: 84, height: 84)
                        }
                    }
                    .buttonStyle(.plain)
                    .shadow(radius: 8, y: 4)
                    .accessibilityLabel("Shutter")

                    Spacer(minLength: 20)

                    // Flip
                    Button { Haptics.tap(); cam.switchCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Flip camera")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.bigCorner).stroke(.white.opacity(0.06), lineWidth: 1)
                )
                .padding(.top, 4)

            }
        }
    }

    // MARK: - Readout (tap to pick which is manual; scrub to adjust)
    private var exposureReadout: some View {
        let s = computeSuggestion()
        let displayF = s.f
        let displayT = s.t
        let displayISO = s.iso
        
        var fDisplay = s.f
        var tDisplay = s.t

        if aiEnabled {
            let b = SceneHeuristics.bias(for: sceneEngine.scene)
            let conf = sceneEngine.latest.confidence

            switch autoParam {
            case .shutter:
                // Aperture is manual; bias shutter only (then snap)
                let biasedT = SceneHeuristics.biasedToward(tDisplay,
                                                           center: b.tCenter,
                                                           userStrength: b.strength,
                                                           confidence: conf,
                                                           globalGain: aiGain)
                tDisplay = StopsTable.nearest(biasedT, in: StopsTable.shutters)

            case .aperture:
                // Shutter is manual; bias aperture only (then snap)
                let biasedF = SceneHeuristics.biasedToward(fDisplay,
                                                           center: b.fCenter,
                                                           userStrength: b.strength,
                                                           confidence: conf,
                                                           globalGain: aiGain)
                fDisplay = StopsTable.nearest(biasedF, in: StopsTable.fStops)
            }
        }



        // manual/auto styles
        let isApertureManual = (autoParam != .aperture)
        let isShutterManual  = (autoParam != .shutter)
        // ISO is always manual

        return HStack(spacing: 22) {
            scrubValue(
                title: "Aperture",
                stringValue: String(format: "%.1f", displayF),
                isManual: isApertureManual,
                onTap: {
                    autoParam = .shutter
                    userAperture = displayF
                },
                onStepUp: { stepAperture(+1) },
                onStepDown: { stepAperture(-1) },
                scrubber: $scrubF,
                treatAsEV: false,
                isScrubbing: $scrubbingF
            )

            scrubValue(
                title: "Shutter",
                stringValue: EVMath.prettyShutter(displayT),
                isManual: isShutterManual,
                onTap: {
                    autoParam = .aperture
                    userShutter = displayT
                },
                onStepUp: { stepShutter(+1) },
                onStepDown: { stepShutter(-1) },
                scrubber: $scrubT,
                treatAsEV: false,
                isScrubbing: $scrubbingT
            )

            scrubValue(
                title: "ISO",
                stringValue: "\(displayISO)",
                isManual: true,
                onTap: { /* ISO always manual */ },
                onStepUp: { stepISO(+1) },
                onStepDown: { stepISO(-1) },
                scrubber: $scrubISO,
                treatAsEV: false,
                isScrubbing: $scrubbingISO
            )

            scrubValue(
                title: "EV",
                stringValue: String(format: "%+.1f", comp),
                isManual: true,
                onTap: { /* no-op */ },
                onStepUp: { stepEV(+1) },
                onStepDown: { stepEV(-1) },
                scrubber: $scrubEV,
                treatAsEV: true,
                isScrubbing: $scrubbingEV
            )
            .frame(minWidth: 58)
            .scaleEffect(evNudgeActive ? 1.06 : 1.0)
            .opacity(evNudgeActive ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.6), value: evNudgeActive)


        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - EV slider row (optional; keeps ticking in 1/3 steps)
    private var evRow: some View {
        HStack {
            Text("EC").font(Design.Text.label).frame(width: 44, alignment: .leading)
            Slider(value: $comp, in: -2...2, step: 1/3)
                .onChange(of: comp) { new in
                    let snapped = (round(new * 3.0) / 3.0)
                    if snapped != lastSnappedEV {
                        Haptics.tap()
                        lastSnappedEV = snapped
                    }
                }
            Text(String(format: "%+.1f", comp))
                .font(Design.Text.label)
                .frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: - Scrubbable value view
    @ViewBuilder
    private func scrubValue(title: String,
                            stringValue: String,
                            isManual: Bool,
                            onTap: @escaping () -> Void,
                            onStepUp: @escaping () -> Void,
                            onStepDown: @escaping () -> Void,
                            scrubber: Binding<VerticalScrubber>,
                            treatAsEV: Bool = false,
                            isScrubbing: Binding<Bool> = .constant(false)) -> some View {

        let fg = isManual ? Color.white : Color.white.opacity(0.65)
        let weight: Font.Weight = isManual ? .semibold : .regular

        VStack(spacing: 2) {
            Text(stringValue)
                .font(Design.Text.overlay.weight(weight))
                .foregroundStyle(fg)
                .shadow(color: isScrubbing.wrappedValue ? .white.opacity(0.18) : .clear, radius: isScrubbing.wrappedValue ? 8 : 0, y: 0)
            Text(title)
                .font(Design.Text.caption)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(minWidth: 84)
        .contentShape(Rectangle())
        .scaleEffect(isScrubbing.wrappedValue ? 1.04 : 1.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.8), value: isScrubbing.wrappedValue)
        .gesture(TapGesture().onEnded { onTap() })
        .highPriorityGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    guard isManual || treatAsEV else { return }
                    isScrubbing.wrappedValue = true
                    var s = scrubber.wrappedValue
                    s.onChange(
                        translation: value.translation,
                        stepUp: { onStepUp() },
                        stepDown: { onStepDown() }
                    )
                    scrubber.wrappedValue = s
                }
                .onEnded { _ in
                    isScrubbing.wrappedValue = false
                    var s = scrubber.wrappedValue
                    s.reset()
                    scrubber.wrappedValue = s
                }
        )
    }


    // MARK: - Step helpers (±1 means one 1/3-stop step). Haptics only if value changes (no tick at bounds).

    private func stepAperture(_ dir: Int) {
        let table = StopsTable.fStops
        let current = StopsTable.nearest(userAperture, in: table)
        guard let idx = table.firstIndex(of: current) else { return }
        let newIdx = (idx + dir).clamped(to: 0...(table.count - 1))
        guard newIdx != idx else { return } // at bound -> no tick
        userAperture = table[newIdx]
        Haptics.tap()
    }

    private func stepShutter(_ dir: Int) {
        let table = StopsTable.shutters
        let current = StopsTable.nearest(userShutter, in: table)
        guard let idx = table.firstIndex(of: current) else { return }
        let newIdx = (idx + dir).clamped(to: 0...(table.count - 1))
        guard newIdx != idx else { return }
        userShutter = table[newIdx]
        Haptics.tap()
    }

    private func stepISO(_ dir: Int) {
        let table = StopsTable.isos
        let current = StopsTable.nearestISO(targetISO)
        guard let idx = table.firstIndex(of: current) else { return }
        let newIdx = (idx + dir).clamped(to: 0...(table.count - 1))
        guard newIdx != idx else { return }
        targetISO = table[newIdx]
        Haptics.tap()
    }

    private func stepEV(_ dir: Int) {
        let table = evSteps
        let current = nearestEV(comp)
        guard let idx = table.firstIndex(of: current) else { return }
        let newIdx = (idx + dir).clamped(to: 0...(table.count - 1))
        guard newIdx != idx else { return }
        comp = table[newIdx]
        Haptics.tap()
    }

    private var evSteps: [Double] {
        // -2.0 ... +2.0 in 1/3 stops
        stride(from: -2.0, through: 2.0, by: 1.0/3.0).map { Double(round($0 * 10) / 10) }
    }
    private func nearestEV(_ v: Double) -> Double {
        evSteps.min(by: { abs($0 - v) < abs($1 - v) }) ?? v
    }

    private func toast(_ msg: String) {
        saveMessage = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showToast = false }
        }
    }
    private func takeAndSave() {
        // Freeze values at capture time
        let s = computeSuggestion()
        
        var fDisplay = s.f
        var tDisplay = s.t

        if aiEnabled {
            let b = SceneHeuristics.bias(for: sceneEngine.scene)
            let conf = sceneEngine.latest.confidence

            switch autoParam {
            case .shutter:
                // Aperture is manual; bias shutter only
                let biasedT = SceneHeuristics.biasedToward(tDisplay, center: b.tCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                // One-pole low-pass (light smoothing)
                tDisplay = smooth(prev: &smoothedAutoT, new: biasedT, alpha: 0.35)
                // Snap to your shutter stops
                tDisplay = StopsTable.nearest(tDisplay, in: StopsTable.shutters)

            case .aperture:
                // Shutter is manual; bias aperture only
                let biasedF = SceneHeuristics.biasedToward(fDisplay, center: b.fCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                fDisplay = smooth(prev: &smoothedAutoF, new: biasedF, alpha: 0.35)
                fDisplay = StopsTable.nearest(fDisplay, in: StopsTable.fStops)
            }
        } else {
            // Reset smoothing caches when AI is off
            smoothedAutoF = nil
            smoothedAutoT = nil
        }
        
        let overlayText = "ISO \(targetISO) • f/\(String(format: "%.1f", fDisplay)) • \(EVMath.prettyShutter(tDisplay)) • \(comp >= 0 ? "+" : "")\(String(format: "%.1f", comp))EV"

        cam.capturePhoto { image in
            guard let base = image else { Haptics.error(); toast("Capture failed"); return }
            let composited = OverlayRenderer.draw(on: base, text: overlayText)

            Task { @MainActor in
                if let _ = await LocalStore.shared.add(image: composited) {
                    Haptics.success()
                    toast("Saved to Gallery")
                } else {
                    Haptics.error()
                    toast("Couldn’t save")
                }
            }
        }
    }
    
    private func smooth(prev: inout Double?, new: Double, alpha: Double) -> Double {
        guard let p = prev else { prev = new; return new }
        let y = p * (1 - alpha) + new * alpha
        prev = y
        return y
    }
    
    private func aiChipText() -> String {
        switch sceneEngine.scene {
        case .portrait:  return "Portrait • wider f/"
        case .group:     return "Group • f/↑"
        case .animal:    return "Animal • faster shutter"
        case .plant:     return "Plant • wider f/"
        case .landscape: return "Landscape • f/8–11"
        case .other:     return "AI ready"
        }
    }

    private func aiSummary(scene: SceneKind) -> String {
        switch scene {
        case .portrait:  return "Portrait: wider f/"
        case .group:     return "Group: f/↑"
        case .animal:    return "Animal: t↑"
        case .plant:     return "Plant: f/↓"
        case .landscape: return "Landscape: f/8–11"
        case .other:     return "AI ready"
        }
    }

    
    private func commitAISuggestion(keepAutoSplit: Bool = false) {
        let s = computeSuggestion()
        var fDisplay = s.f
        var tDisplay = s.t
        if aiEnabled {
            let b = SceneHeuristics.bias(for: sceneEngine.scene)
            let conf = sceneEngine.latest.confidence
            switch autoParam {
            case .shutter:
                let biasedT = SceneHeuristics.biasedToward(tDisplay, center: b.tCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                tDisplay = StopsTable.nearest(biasedT, in: StopsTable.shutters)
                userShutter = tDisplay
                if !keepAutoSplit { autoParam = .aperture }
            case .aperture:
                let biasedF = SceneHeuristics.biasedToward(fDisplay, center: b.fCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                fDisplay = StopsTable.nearest(biasedF, in: StopsTable.fStops)
                userAperture = fDisplay
                if !keepAutoSplit { autoParam = .shutter }
            }
        }
        toast("Applied")
    }
}

// MARK: - Utils
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
