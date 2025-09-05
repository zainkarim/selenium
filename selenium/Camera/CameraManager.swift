//
//  CameraManager.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import AVFoundation

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
        // Seed current values
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
}
