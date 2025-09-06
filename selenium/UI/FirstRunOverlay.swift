//
//  FirstRunOverlay.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import SwiftUI

struct FirstRunOverlay: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dim backdrop that still shows the live camera
            Color.black.opacity(0.45).ignoresSafeArea()

            // Glass card with tips
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                    Text("Welcome to selenium")
                        .font(Design.Text.overlay) // monospaced title style
                }

                TipRow(icon: "hand.tap", text: "Tap a value (Aperture, Shutter, ISO) to make it manual. Other values will auto-adjust accordingly.")
                TipRow(icon: "arrow.up.and.down", text: "Swipe up/down on a manual value to adjust it.")
                TipRow(icon: "camera.shutter.button", text: "Use the shutter to capture. Your captures go to the in-app Gallery.")

                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        Haptics.tap()
                        onDismiss()
                    } label: {
                        Text("Got it")
                            .font(Design.Text.label.weight(.semibold))
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Design.bigCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.bigCorner)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale))
    }
}

private struct TipRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.body)
                .frame(width: 22)
            Text(text)
                .font(Design.Text.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
