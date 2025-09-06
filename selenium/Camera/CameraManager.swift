//
//  CameraManager.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import AVFoundation
import UIKit

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "selenium.session")

    @Published var isConfigured = false
    @Published var isRunning = false
    @Published var currentPosition: AVCaptureDevice.Position = .back

    // Live exposure readouts
    @Published var iso: Double = 100
    @Published var shutter: Double = 1/120.0   // seconds
    @Published var aperture: Double = 1.8

    private var device: AVCaptureDevice?
    private var obsISO: NSKeyValueObservation?
    private var obsDuration: NSKeyValueObservation?
    private var obsAperture: NSKeyValueObservation?
    private let photoOutput = AVCapturePhotoOutput()
    
    private let videoOutput = AVCaptureVideoDataOutput()
    weak var sceneSink: SceneEngine?


    // Keep strong refs to photo delegates until capture finishes
    private var inFlightDelegates: [AVCapturePhotoCaptureDelegate] = []

    // MARK: - Configure

    func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Use currentPosition (front/back)
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                DispatchQueue.main.async { self.isConfigured = true }
                self.session.commitConfiguration()
                return
            }

            // Replace existing inputs
            self.session.inputs.forEach { self.session.removeInput($0) }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.device = device

            // Add photo output if needed
            if self.session.canAddOutput(self.photoOutput), !self.session.outputs.contains(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            
            if self.session.canAddOutput(self.videoOutput) {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.session.addOutput(self.videoOutput)
            }

            // Match preview: portrait 90° + mirror when front
            if let photoConn = self.photoOutput.connection(with: .video) {
                photoConn.automaticallyAdjustsVideoMirroring = false
                photoConn.isVideoMirrored = (self.currentPosition == .front)
                if photoConn.isVideoRotationAngleSupported(90) {
                    photoConn.videoRotationAngle = 90
                }
            }

            self.session.commitConfiguration()

            self.startObservingExposure(on: device)

            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.isConfigured = true
                self.isRunning = true
            }
        }
    }

    // Toggle camera
    @MainActor
    func switchCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        sessionQueue.async { [weak self] in self?.configure() }
    }

    // MARK: - KVO for exposure readouts

    private func startObservingExposure(on device: AVCaptureDevice) {
        DispatchQueue.main.async {
            self.iso = Double(device.iso)
            self.aperture = Double(device.lensAperture)
            self.shutter = device.exposureDuration.isValid ? CMTimeGetSeconds(device.exposureDuration) : self.shutter
        }

        obsISO = device.observe(\.iso, options: [.initial, .new]) { [weak self] dev, _ in
            DispatchQueue.main.async { self?.iso = Double(dev.iso) }
        }
        obsDuration = device.observe(\.exposureDuration, options: [.initial, .new]) { [weak self] dev, _ in
            let s = dev.exposureDuration
            if s.isValid {
                DispatchQueue.main.async { self?.shutter = CMTimeGetSeconds(s) }
            }
        }
        obsAperture = device.observe(\.lensAperture, options: [.initial, .new]) { [weak self] dev, _ in
            DispatchQueue.main.async { self?.aperture = Double(dev.lensAperture) }
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Capture

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let settings = AVCapturePhotoSettings()
        let isFront = (currentPosition == .front)

        // Create a delegate instance and retain it until finish
        let delegate = PhotoDelegate(
            isFront: isFront,
            onImage: { image in completion(image) },
            onFinish: { [weak self] del in
                self?.inFlightDelegates.removeAll { $0 === del }
            }
        )
        inFlightDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    // Inner delegate
    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private let isFront: Bool
        private let onImage: (UIImage?) -> Void
        private let onFinish: (AVCapturePhotoCaptureDelegate) -> Void

        init(isFront: Bool,
             onImage: @escaping (UIImage?) -> Void,
             onFinish: @escaping (AVCapturePhotoCaptureDelegate) -> Void) {
            self.isFront = isFront
            self.onImage = onImage
            self.onFinish = onFinish
        }

        // CameraManager.swift → inside PhotoDelegate
        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let base = UIImage(data: data) else {
                onImage(nil)
                return
            }

            // Bake pixels to .up; mirror only for front
            let shouldMirror = !isFront
            let final = base.normalized(mirrorHorizontally: isFront)
            onImage(final)
        }

        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                         error: Error?) {
            onFinish(self)
        }
    }
}

private extension UIImage {
    func normalized(mirrorHorizontally: Bool) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = self.scale
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: self.size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            if mirrorHorizontally {
                cg.translateBy(x: self.size.width, y: 0)
                cg.scaleBy(x: -1, y: 1)
            }
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        DispatchQueue.main.async { [weak self] in
            self?.sceneSink?.analyze(sampleBuffer: sampleBuffer)
        }
    }
}
