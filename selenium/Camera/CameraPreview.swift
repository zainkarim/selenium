//
//  CameraPreview.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        // we’ll control mirroring manually
        v.videoPreviewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        return v
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        guard let input = view.videoPreviewLayer.session?.inputs.first as? AVCaptureDeviceInput else { return }
        view.videoPreviewLayer.connection?.isVideoMirrored = (input.device.position == .front)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
