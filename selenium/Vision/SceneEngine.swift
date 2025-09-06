//
//  SceneEngine.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

@preconcurrency
import Vision
import AVFoundation
import UIKit

// Evidence reported each tick
struct SceneEvidence {
    let kind: SceneKind
    let faces: Int
    let faceMaxArea: CGFloat      // fraction of frame, 0…1
    let salientMaxArea: CGFloat   // fraction of frame, 0…1
    let label: String             // top classifier label (lowercased)
    let confidence: CGFloat       // 0…1 overall confidence
}

@MainActor
final class SceneEngine: NSObject, ObservableObject {
    @Published private(set) var scene: SceneKind = .other
    @Published private(set) var latest: SceneEvidence = .init(kind: .other, faces: 0, faceMaxArea: 0, salientMaxArea: 0, label: "", confidence: 0)

    private var lastRun = Date.distantPast
    private let minInterval: TimeInterval = 0.6
    private let q = DispatchQueue(label: "selenium.sceneengine")

    func analyze(sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastRun) > minInterval else { return }
        lastRun = now

        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let reqFaces = VNDetectFaceRectanglesRequest()
        let reqClass = VNClassifyImageRequest()
        let reqSal   = VNGenerateAttentionBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
        q.async {
            do {
                try handler.perform([reqFaces, reqClass, reqSal])

                // Faces
                let faceObs = (reqFaces.results as? [VNFaceObservation]) ?? []
                let faces = faceObs.count
                let faceMax = faceObs.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0

                // Saliency (largest attention region)
                var salientMax: CGFloat = 0
                if let salResult = reqSal.results?.first as? VNSaliencyImageObservation {
                    salientMax = salResult.salientObjects?
                        .map { $0.boundingBox.width * $0.boundingBox.height }
                        .max() ?? 0
                }

                // Classifier
                let top = reqClass.results?.first
                let label = top?.identifier.lowercased() ?? ""
                let labelConf = CGFloat(top?.confidence ?? 0)

                // Heuristic kind
                let kind: SceneKind
                if faces >= 2 { kind = .group(faces) }
                else if faces == 1 { kind = .portrait(1) }
                else if label.contains("dog") || label.contains("cat") || label.contains("animal") {
                    kind = .animal
                } else if label.contains("flower") || label.contains("plant") || label.contains("leaf") || salientMax >= 0.40 {
                    // "close-up" proxy: either plant-ish label OR large salient subject
                    kind = .plant
                } else if label.contains("landscape") || label.contains("mountain") || label.contains("sky") || label.contains("architecture") {
                    kind = .landscape
                } else {
                    kind = .other
                }

                // Confidence blend: faces/area/label
                // Face area weight if any face; else saliency; else label confidence
                let faceWeight: CGFloat = min(1, faceMax * 3.2)      // bigger face → higher confidence
                let salWeight:  CGFloat = min(1, salientMax * 1.8)   // big subject
                // combine with label confidence but cap so it’s not jumpy
                let conf = max(faceWeight, max(salWeight, min(1, labelConf)))

                let ev = SceneEvidence(kind: kind, faces: faces, faceMaxArea: faceMax, salientMaxArea: salientMax, label: label, confidence: conf)

                DispatchQueue.main.async {
                    self.scene = kind
                    self.latest = ev
                }
            } catch {
                // swallow errors
            }
        }
    }
}
