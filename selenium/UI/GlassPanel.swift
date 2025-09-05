//
//  GlassPanel.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI

struct GlassPanel<Content: View>: View {
    var insets: EdgeInsets = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(insets)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
    }
}
