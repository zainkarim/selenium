//
//  Design.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

enum Design {
    static let pad: CGFloat = 8
    static let corner: CGFloat = 16
    static let bigCorner: CGFloat = 20

    // Typography
    enum Text {
        static var overlay: Font { .system(.title3, design: .monospaced) }
        static var label: Font { .system(.subheadline, design: .monospaced) }
        static var caption: Font { .system(.caption2, design: .monospaced) }
    }
}
