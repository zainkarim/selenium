//
//  ContentView.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

private struct PreviewWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ContentView: View {
    @StateObject private var cam = CameraManager()

    // MARK: - Auto/Manual model
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
    @State private var frictionEV: CGFloat = 24   // EV

    // For EV slider ticks
    @State private var lastSnappedEV: Double = 0.0

    // Feedback
    @State private var saveMessage: String?
    @State private var showToast = false
    
    // Onboarding
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
    
    @State private var showGrid = false
    @State private var evDragActive = false
    @State private var evDragAccum: CGFloat = 0   // pixels accumulated → 1/3 EV steps
    @State private var previewWidth: CGFloat = 0
    private let evPixelsPerThird: CGFloat = 32    // tune: higher = slower
    
    private let valueMinWidth: CGFloat = 84
    
    private let panelGap: CGFloat = 28
    private let panelNarrowBy: CGFloat = 24


    private let firstRunKey = "selenium.firstRunSeeded"

    // MARK: - Solve (two manual, one auto)
    private func computeSuggestion() -> (f: Double, t: Double, iso: Int) {
        let ev100 = EVMath.ev100(aperture: cam.aperture, shutter: cam.shutter, iso: cam.iso)

        func snapF(_ x: Double) -> Double {
            let clamped = min(22.0, max(0.95, x))
            return StopsTable.nearest(clamped, in: StopsTable.fStops)
        }
        func snapT(_ x: Double) -> Double {
            let minT = 1.0 / 8000.0, maxT = 1.0 / 1.0 // 1/8000 … 1s
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
            // Simple backdrop; avoids double-rendering a second AVCapture layer.
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                // PREVIEW WINDOW (card)
                let previewAspect: CGFloat = 2.0 / 3.0
                
                ZStack {
                    if cam.isConfigured {
                        CameraPreview(session: cam.session)
                            .clipShape(RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous)
                                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(radius: 20, y: 8)
                    } else {
                        // placeholder while the session spins up
                        RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: Design.bigCorner)
                                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(radius: 20, y: 8)
                    }
                    
                    // GRID (see step 3 for stronger styling)
                    if showGrid {
                        RuleOfThirdsGrid(color: .white, lineWidth: 0.5)
                    } else {
                        RuleOfThirdsGrid(color: .white.opacity(0.0), lineWidth: 0.0)
                        
                    }
                    
                    // EV tap / vertical drag
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(TapGesture().onEnded { Haptics.tap(); comp = 0 })
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { v in
                                    evDragActive = true
                                    evDragAccum += v.translation.height
                                    let thirds = Int((-evDragAccum / evPixelsPerThird).rounded(.towardZero))
                                    if thirds != 0 {
                                        stepEV(thirds > 0 ? +1 : -1)
                                        evDragAccum -= CGFloat(thirds) * (-evPixelsPerThird)
                                    }
                                }
                                .onEnded { _ in
                                    evDragActive = false
                                    evDragAccum = 0
                                }
                        )
                    
                    // Top controls (grid / AI)
                    VStack {
                        HStack {
                            Button {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.28)) { showGrid.toggle() }
                            } label: {
                                Image(systemName: "grid")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(showGrid ? .white : .white.opacity(0.6))
                                    .frame(width: 32, height: 32)
                                    .background(.black.opacity(0.25), in: Circle())
                            }
                            .padding(10)
                            
                            Spacer()
                            
                            Button {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.25)) { aiEnabled.toggle() }
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(aiEnabled ? .white : .white.opacity(0.6))
                                    .frame(width: 32, height: 32)
                                    .background(.black.opacity(0.25), in: Circle())
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                    // Bottom-center AI chip (icon only)  // NEW
                    .overlay(alignment: .bottom) {
                        if aiEnabled {
                            AIChip(systemName: aiSceneSymbol())
                                .padding(.bottom, 8)
                        }
                    }
                    .zIndex(2)
                }
                .aspectRatio(previewAspect, contentMode: .fit)
                .padding(.horizontal, Design.pad)
                .padding(.top, 16)
                // Report *final* laid-out width so we can match the panel to it
                .background(
                    GeometryReader { g in
                        Color.clear
                            .preference(key: PreviewWidthKey.self, value: g.size.width)
                    }
                )
                .onPreferenceChange(PreviewWidthKey.self) { previewWidth = $0 }
                .padding(.bottom, 8)
            }
        }
        // Bottom control panel pinned to safe area
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer(minLength: 0)
                bottomPanel
                    .frame(width: max(0, previewWidth - panelNarrowBy))
                    .padding(.bottom, 8)
                Spacer(minLength: 0)
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
                autoParam = .shutter
                UserDefaults.standard.set(true, forKey: firstRunKey)
            }
            
            // Onboarding
            if !UserDefaults.standard.bool(forKey: onboardingKey) {
                showOnboarding = true
            }
            
            if !UserDefaults.standard.bool(forKey: evNudgeKey) {
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
                commitAISuggestion(keepAutoSplit: true)
            }
            Button("Apply & make manual") {
                commitAISuggestion(keepAutoSplit: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(aiPreview)
        }
    }

    // MARK: - Panel

    private var bottomPanel: some View {
        GlassPanel(insets: .init(top: 10, leading: 8, bottom: 10, trailing: 8)) {
            VStack(spacing: 12) {
                exposureReadout
                // Actions row
                HStack {
                    // Gallery (live thumb)
                    Button { Haptics.tap(); store.load(); showGallery = true } label: {
                        if let first = store.items.first, let ui = UIImage(contentsOfFile: first.url.path) {
                            Image(uiImage: ui)
                                .resizable().scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
                                .shadow(radius: 8, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.1))
                                .frame(width: 52, height: 52)
                                .overlay(Image(systemName: "photo").font(.title3).foregroundStyle(.white.opacity(0.8)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))
                        }
                    }

                    .accessibilityLabel("Open gallery")

                    Spacer(minLength: 40)

                    // Shutter
                    Button { Haptics.tap(); takeAndSave() } label: {
                        ZStack {
                            Circle().fill(.white.opacity(0.95)).frame(width: 72, height: 72 )
                            Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1.5).frame(width: 60, height: 60)
                        }
                    }
                    .buttonStyle(.plain)
                    .shadow(radius: 8, y: 4)
                    .accessibilityLabel("Shutter")

                    Spacer(minLength: 40)

                    // Flip camera
                    Button { Haptics.tap(); cam.switchCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.25), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Flip camera")
                }
                .frame(maxWidth: 256)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous))

                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Readout (tap to pick which is manual; scrub to adjust)
    private var exposureReadout: some View {
        let s = computeSuggestion()
        let displayF = s.f
        let displayT = s.t
        let displayISO = s.iso

        return HStack(spacing: 22) {
            scrubValue(
                title: "Aperture",
                stringValue: String(format: "%.1f", displayF),
                isManual: (autoParam != .aperture),
                onTap: { autoParam = .shutter; userAperture = displayF },
                onStepUp: { stepAperture(+1) },
                onStepDown: { stepAperture(-1) },
                scrubber: $scrubF,
                treatAsEV: false,
                isScrubbing: $scrubbingF
            )

            scrubValue(
                title: "Shutter",
                stringValue: EVMath.prettyShutter(displayT),
                isManual: (autoParam != .shutter),
                onTap: { autoParam = .aperture; userShutter = displayT },
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
                onTap: {},
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
                onTap: {},
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
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    // MARK: - EV slider row
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
        .frame(minWidth: valueMinWidth)
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

    // MARK: - Step helpers (±1 = one 1/3-stop)
    private func stepAperture(_ dir: Int) {
        let table = StopsTable.fStops
        let current = StopsTable.nearest(userAperture, in: table)
        guard let idx = table.firstIndex(of: current) else { return }
        let newIdx = (idx + dir).clamped(to: 0...(table.count - 1))
        guard newIdx != idx else { return }
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
                let biasedT = SceneHeuristics.biasedToward(tDisplay, center: b.tCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                tDisplay = smooth(prev: &smoothedAutoT, new: biasedT, alpha: 0.35)
                tDisplay = StopsTable.nearest(tDisplay, in: StopsTable.shutters)
            case .aperture:
                let biasedF = SceneHeuristics.biasedToward(fDisplay, center: b.fCenter, userStrength: b.strength, confidence: conf, globalGain: aiGain)
                fDisplay = smooth(prev: &smoothedAutoF, new: biasedF, alpha: 0.35)
                fDisplay = StopsTable.nearest(fDisplay, in: StopsTable.fStops)
            }
        } else {
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
    
    private func aiSceneSymbol() -> String {
        switch sceneEngine.scene {
        case .portrait:  return "person.crop.circle"
        case .group:     return "person.3"
        case .animal:    return "pawprint"
        case .plant:     return "leaf"
        case .landscape: return "mountain.2"
        case .other:     return "sparkles"
        }
    }
    
    private struct AIChip: View {
        let systemName: String
        var body: some View {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(radius: 8, y: 4)
        }
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
