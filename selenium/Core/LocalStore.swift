//
//  LocalStore.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct GalleryItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let date: Date
}

@MainActor
final class LocalStore: ObservableObject {
    static let shared = LocalStore()

    @Published private(set) var items: [GalleryItem] = []

    private let folder: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        folder = docs.appendingPathComponent("Gallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    func load() {
        let fm = FileManager.default
        guard let dir = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            items = []; return
        }
        let jpgs = dir.filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
        let mapped: [GalleryItem] = jpgs.compactMap { url in
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "selenium-", with: "")) ?? UUID()
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return GalleryItem(id: id, url: url, date: date)
        }
        items = mapped.sorted(by: { $0.date > $1.date })
    }

    func add(image: UIImage) async -> GalleryItem? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        let id = UUID()
        let url = folder.appendingPathComponent("selenium-\(id.uuidString).jpg")
        do {
            try data.write(to: url)
            let item = GalleryItem(id: id, url: url, date: Date())
            items.insert(item, at: 0)
            return item
        } catch {
            return nil
        }
    }

    func delete(_ itemsToDelete: [GalleryItem]) {
        for item in itemsToDelete {
            try? FileManager.default.removeItem(at: item.url)
        }
        load()
    }
}
