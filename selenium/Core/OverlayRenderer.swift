//
//  Overlay Renderer.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import UIKit

import UIKit

enum OverlayRenderer {
    static func draw(on base: UIImage, text: String) -> UIImage {
        let scale = base.scale
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale
        rendererFormat.opaque = false

        let renderer = UIGraphicsImageRenderer(size: base.size, format: rendererFormat)
        return renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: base.size))

            // Typography
            let titleFont = UIFont.monospacedSystemFont(ofSize: max(14, base.size.width * 0.038), weight: .semibold)
            let attr: [NSAttributedString.Key : Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white
            ]
            let padX: CGFloat = 14
            let padY: CGFloat = 8
            let corner: CGFloat = max(10, base.size.width * 0.025)

            let textSize = (text as NSString).size(withAttributes: attr)
            let boxSize = CGSize(width: textSize.width + padX * 2, height: textSize.height + padY * 2)

            // Position: bottom-left with margins
            let margin: CGFloat = max(12, base.size.width * 0.03)
            let origin = CGPoint(x: margin, y: base.size.height - margin - boxSize.height)
            let rect = CGRect(origin: origin, size: boxSize)

            // Glass pill
            let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)
            ctx.cgContext.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.fillPath()

            // Stroke
            ctx.cgContext.setStrokeColor(UIColor(white: 1, alpha: 0.10).cgColor)
            ctx.cgContext.setLineWidth(1)
            ctx.cgContext.addPath(path.cgPath)
            ctx.cgContext.strokePath()

            // Text
            let textPoint = CGPoint(x: rect.minX + padX, y: rect.minY + padY)
            (text as NSString).draw(at: textPoint, withAttributes: attr)

            // Subtle outer shadow to lift from background
            ctx.cgContext.setShadow(offset: .zero, blur: 0)
        }
    }
}


private extension UIImage {
    func with(scale: CGFloat) -> UIImage {
        UIImage(cgImage: self.cgImage!, scale: scale, orientation: self.imageOrientation)
    }
}
