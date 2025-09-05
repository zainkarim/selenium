//
//  Overlay Renderer.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import UIKit

enum OverlayRenderer {
    /// Draws the given text at the lower-left corner with a soft shadow.
    static func draw(on image: UIImage, text: String) -> UIImage {
        let size = image.size
        let scale = image.scale

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            // Text style
            let font = UIFont.monospacedSystemFont(ofSize: 28, weight: .semibold)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = .zero

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .shadow: shadow
            ]

            let margin: CGFloat = 18
            let ns = text as NSString
            let textSize = ns.size(withAttributes: attrs)
            let origin = CGPoint(x: margin, y: size.height - textSize.height - margin)

            // Draw background pill for legibility
            let bgRect = CGRect(x: origin.x - 10,
                                y: origin.y - 6,
                                width: textSize.width + 20,
                                height: textSize.height + 12)
            let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 10)
            UIColor.black.withAlphaComponent(0.35).setFill()
            path.fill()

            ns.draw(at: origin, withAttributes: attrs)
        }.with(scale: scale) // keep original scale
    }
}

private extension UIImage {
    func with(scale: CGFloat) -> UIImage {
        UIImage(cgImage: self.cgImage!, scale: scale, orientation: self.imageOrientation)
    }
}
