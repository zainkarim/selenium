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

    // Live exposure readouts
    @Published var iso: Double = 100
    @Published var shutter: Double = 1/120.0   // seconds
    @Published var aperture: Double = 1.8

    private var device: AVCaptureDevice?
    private var obsISO: NSKeyValueObservation?
    private var obsDuration: NSKeyValueObservation?
    private var obsAperture: NSKeyValueObservation?
    
    private var inFlightDelegates: [AVCapturePhotoCaptureDelegate] = []


    // NEW: photo output
    private let photoOutput = AVCapturePhotoOutput()

    func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                DispatchQueue.main.async { self.isConfigured = true }
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.device = device

            // Add photo output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()

            self.startObservingExposure(on: device)

            self.session.startRunning()
            DispatchQueue.main.async {
                self.isConfigured = true
                self.isRunning = true
            }
        }
    }

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

    // NEW: capture still image and return UIImage
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let settings = AVCapturePhotoSettings()
        let delegate = PhotoDelegate(
            onImage: { image in completion(image) },
            onFinish: { [weak self] del in
                // Release the strong reference when finished
                self?.inFlightDelegates.removeAll { $0 === del }
            }
        )
        // Keep a strong ref so callbacks happen
        inFlightDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    // Inner delegate
    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private let onImage: (UIImage?) -> Void
        private let onFinish: (AVCapturePhotoCaptureDelegate) -> Void

        init(onImage: @escaping (UIImage?) -> Void,
             onFinish: @escaping (AVCapturePhotoCaptureDelegate) -> Void) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                onImage(nil)
                return
            }
            onImage(image)
        }

        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                         error: Error?) {
            // Called after all processing callbacks — safe to release
            onFinish(self)
        }
    }
}
