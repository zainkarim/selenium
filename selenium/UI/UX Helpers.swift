//
//  UX Helpers.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.monospaced())
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.8), in: Capsule())
            .foregroundStyle(.white)
            .shadow(radius: 10, y: 4)
    }
}
