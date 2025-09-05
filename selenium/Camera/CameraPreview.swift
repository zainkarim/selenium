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
        v.videoPreviewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        return v
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        guard
            let conn = view.videoPreviewLayer.connection,
            let input = view.videoPreviewLayer.session?.inputs.first as? AVCaptureDeviceInput
        else { return }

        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = (input.device.position == .front)
        
        if conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
