//
//  GalleryView.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import SwiftUI

struct GalleryView: View {
    @ObservedObject var store: LocalStore = .shared
    let onClose: () -> Void

    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(store.items) { item in
                        NavigationLink(value: item) {
                            Thumbnail(url: item.url)
                        }
                    }
                }
                .padding(10)
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { onClose() } }
            }
            .navigationDestination(for: GalleryItem.self) { item in
                // push the pager starting at this item
                if let idx = store.items.firstIndex(of: item) {
                    GalleryPagerView(startIndex: idx, onClose: onClose)
                } else {
                    Text("Item not found").foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { store.load() }
    }
}

private struct Thumbnail: View {
    let url: URL
    var body: some View {
        if let ui = UIImage(contentsOfFile: url.path) {
            Image(uiImage: ui)
                .resizable().scaledToFill()
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06)))
        } else {
            Rectangle().fill(.gray.opacity(0.2))
                .frame(height: 120)
                .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.secondary))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Pager (swipe left/right), with Save / Share / Delete
struct GalleryPagerView: View {
    @ObservedObject var store: LocalStore = .shared
    @State var index: Int
    let onClose: () -> Void

    init(startIndex: Int, onClose: @escaping () -> Void) {
        _index = State(initialValue: startIndex)
        self.onClose = onClose
    }

    @State private var showDeleteConfirm = false
    @State private var showExportToast = false
    @State private var exportMessage = ""

    var body: some View {
        ZStack {
            if store.items.isEmpty {
                Text("No photos").foregroundStyle(.secondary)
            } else {
                TabView(selection: $index) {
                    ForEach(store.items.indices, id: \.self) { i in
                        ZStack {
                            Color.black.ignoresSafeArea()
                            if let ui = UIImage(contentsOfFile: store.items[i].url.path) {
                                GeometryReader { proxy in
                                    let w = proxy.size.width, h = proxy.size.height
                                    Image(uiImage: ui)
                                        .resizable().scaledToFit()
                                        .frame(width: w, height: h)
                                }
                            } else {
                                Text("Could not load image").foregroundStyle(.secondary)
                            }
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { onClose() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let current = currentItem {
                    // Save to Photos
                    Button {
                        saveToPhotos(current)
                    } label: {
                        Image(systemName: "square.and.arrow.down") // "Save"
                    }

                    // Share via system sheet
                    ShareLink(item: current.url) {
                        Image(systemName: "square.and.arrow.up")
                    }

                    // Delete
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Image(systemName: "trash") }
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if showExportToast {
                Toast(text: exportMessage)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showExportToast)
    }

    private var currentItem: GalleryItem? {
        guard store.items.indices.contains(index) else { return nil }
        return store.items[index]
    }

    private func saveToPhotos(_ item: GalleryItem) {
        PhotoSaver.saveFileURLToLibrary(item.url) { ok, _ in
            exportMessage = ok ? "Saved to Photos" : "Couldn’t save"
            withAnimation { showExportToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation { showExportToast = false }
            }
        }
    }

    private func deleteCurrent() {
        guard let item = currentItem else { return }
        store.delete([item])
        // adjust index to stay in range
        if index >= store.items.count { index = max(0, store.items.count - 1) }
        // if nothing left, pop back
        if store.items.isEmpty { onClose() }
    }
}
