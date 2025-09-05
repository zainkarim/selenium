//
//  Design.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

enum Design {
    // Spacing & radii
    static let pad: CGFloat = 12
    static let corner: CGFloat = 14
    static let bigCorner: CGFloat = 20

    // Typography
    enum Text {
        static let overlay = Font.system(.title3, design: .monospaced).weight(.semibold)
        static let label   = Font.subheadline.monospaced()
        static let caption = Font.caption.monospaced()
    }
}
