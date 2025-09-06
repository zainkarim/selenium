//
//  GalleryView.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

//
//  GalleryView.swift
//  selenium
//

import SwiftUI

enum GalleryFilter: String, CaseIterable, Identifiable {
    case all = "All", ai = "AI", manual = "Manual"
    var id: String { rawValue }
}

struct GalleryView: View {
    @ObservedObject var store: LocalStore = .shared
    let onClose: () -> Void

    @State private var filter: GalleryFilter = .all

    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var showDeleteConfirm = false
    @State private var toastMsg: String?
    @State private var showToast = false

    @State private var navPath = NavigationPath()

    private var filteredItems: [GalleryItem] {
        switch filter {
        case .all: return store.items
        case .ai: return store.items.filter { $0.aiKind != nil }
        case .manual: return store.items.filter { $0.aiKind == nil }
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {

                // Filter
                Picker("Filter", selection: $filter) {
                    ForEach(GalleryFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Grid
                GalleryGrid(
                    items: filteredItems,
                    selecting: selecting,
                    selected: selected,
                    onTapItem: { item in
                        if selecting {
                            toggle(item.id)
                        } else if let idx = filteredItems.firstIndex(of: item) {
                            navPath.append(idx) // push pager at filtered index
                        }
                    },
                    onToggleSelect: { id in toggle(id) }
                )

                // Bulk bar (acts on selected items)
                if selecting {
                    BulkBar(
                        canAct: !selected.isEmpty,
                        onSelectAll: { selected = Set(filteredItems.map(\.id)) },
                        onSave: {
                            let urls = store.items.filter { selected.contains($0.id) }.map(\.url)
                            PhotoSaver.saveFileURLsToLibrary(urls) { ok, fail in
                                toast(ok > 0 ? "\(ok) saved" + (fail > 0 ? ", \(fail) failed" : "") : (fail > 0 ? "Failed" : "Nothing selected"))
                            }
                        },
                        shareItems: store.items.filter { selected.contains($0.id) }.map(\.url),
                        onDelete: { showDeleteConfirm = true }
                    )
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { selected.removeAll() }
                    }
                }
            }
            .navigationDestination(for: Int.self) { idx in
                GalleryPagerView(items: filteredItems, startIndex: idx, onClose: { navPath.removeLast() })
            }
        }
        .onAppear { store.load() }
        .overlay(alignment: .bottom) {
            if showToast, let msg = toastMsg {
                Toast(text: msg)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showToast)
        .confirmationDialog("Delete selected photos?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let toDelete = store.items.filter { selected.contains($0.id) }
                store.delete(toDelete)
                selected.removeAll()
                toast("Deleted")
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func toast(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { showToast = false } }
    }
}

// MARK: - Grid

private struct GalleryGrid: View {
    let items: [GalleryItem]
    let selecting: Bool
    let selected: Set<UUID>
    let onTapItem: (GalleryItem) -> Void
    let onToggleSelect: (UUID) -> Void

    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(items) { item in
                    ZStack(alignment: .topTrailing) {

                        Button { onTapItem(item) } label: {
                            Thumbnail(url: item.url)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selected.contains(item.id)
                                            ? Color.accentColor.opacity(0.9)
                                            : Color.white.opacity(0.06),
                                            lineWidth: selected.contains(item.id) ? 3 : 1
                                        )
                                )
                                .overlay(alignment: .topLeading) {
                                    if item.aiKind != nil {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(.black.opacity(0.35), in: Capsule())
                                            .padding(6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)

                        if selecting {
                            Circle()
                                .fill(selected.contains(item.id) ? Color.accentColor : Color.black.opacity(0.5))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: selected.contains(item.id) ? "checkmark" : "circle")
                                        .foregroundStyle(.white).font(.system(size: 12, weight: .bold))
                                )
                                .padding(6)
                                .onTapGesture { onToggleSelect(item.id) }
                        }
                    }
                }
            }
            .padding(10)
        }
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
        } else {
            Rectangle().fill(.gray.opacity(0.2))
                .frame(height: 120)
                .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.secondary))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Bulk bar

private struct BulkBar: View {
    let canAct: Bool
    let onSelectAll: () -> Void
    let onSave: () -> Void
    let shareItems: [URL]
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Select All", action: onSelectAll)
                Spacer()
                Button("Save to Photos", action: onSave).disabled(!canAct)
                Spacer()
                ShareLink(items: shareItems) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }.disabled(shareItems.isEmpty)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Trash", systemImage: "trash")
                }.disabled(!canAct)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Pager (swipe left/right) with Save / Share / Delete

struct GalleryPagerView: View {
    let items: [GalleryItem]          // NEW: use same filtered source
    @State var index: Int
    let onClose: () -> Void

    @ObservedObject var store: LocalStore = .shared

    @State private var showDeleteConfirm = false
    @State private var toastMsg: String?
    @State private var showToast = false

    init(items: [GalleryItem], startIndex: Int, onClose: @escaping () -> Void) {
        self.items = items
        _index = State(initialValue: startIndex)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if items.isEmpty {
                Text("No photos").foregroundStyle(.secondary)
            } else {
                TabView(selection: $index) {
                    ForEach(items.indices, id: \.self) { i in
                        GeometryReader { proxy in
                            let w = proxy.size.width, h = proxy.size.height
                            if let ui = UIImage(contentsOfFile: items[i].url.path) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFit()
                                    .frame(width: w, height: h)
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
                    Button { saveToPhotos(current) } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    ShareLink(item: current.url) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if showToast, let msg = toastMsg {
                Toast(text: msg).padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showToast)
    }

    private var currentItem: GalleryItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func saveToPhotos(_ item: GalleryItem) {
        PhotoSaver.saveFileURLToLibrary(item.url) { ok, _ in
            toast(ok ? "Saved to Photos" : "Couldn’t save")
        }
    }

    private func deleteCurrent() {
        guard let item = currentItem else { return }
        store.delete([item])
        if index >= items.count { index = max(0, items.count - 1) }
        if store.items.isEmpty { onClose() } else { toast("Deleted") }
    }

    private func toast(_ msg: String) {
        toastMsg = msg
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { showToast = false } }
    }
}
