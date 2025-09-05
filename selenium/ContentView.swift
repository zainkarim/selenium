//
//  ContentView.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import SwiftUI
import SwiftData

import SwiftUI

struct ContentView: View {
    @StateObject private var cam = CameraManager()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if cam.isConfigured {
                CameraPreview(session: cam.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            Text(cam.isRunning ? "LIVE" : "READY")
                .font(.caption.monospaced())
                .padding(8)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(.white)
                .padding(12)
        }
        .onAppear { cam.configure() }
        .onDisappear { cam.stop() }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
