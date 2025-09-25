//
//  GridOverlay.swift
//  selenium
//
//  Created by Zain Karim on 9/6/25.
//

import SwiftUI

struct RuleOfThirdsGrid: View {
    var color: Color
    var lineWidth: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // verticals
                p.move(to: CGPoint(x: w/3, y: 0));     p.addLine(to: CGPoint(x: w/3, y: h))
                p.move(to: CGPoint(x: 2*w/3, y: 0));   p.addLine(to: CGPoint(x: 2*w/3, y: h))
                // horizontals
                p.move(to: CGPoint(x: 0, y: h/3));     p.addLine(to: CGPoint(x: w, y: h/3))
                p.move(to: CGPoint(x: 0, y: 2*h/3));   p.addLine(to: CGPoint(x: w, y: 2*h/3))
            }
            .stroke(color.opacity(0.9), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}
