//
//  LocalStore.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import SwiftUI

struct GalleryItem: Identifiable, Hashable, Codable {
    let id: UUID
    let url: URL
    let date: Date
    var aiKind: String?        // "portrait","group","animal","plant","landscape"
    var aiConfidence: Double?  // 0..1
}

@MainActor
final class LocalStore: ObservableObject {
    static let shared = LocalStore()

    @Published private(set) var items: [GalleryItem] = []

    // weak reference to the scene engine so we can snapshot AI metadata on save
    weak var sceneEngine: SceneEngine?

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

        let jpgs = dir.filter { ["jpg","jpeg"].contains($0.pathExtension.lowercased()) }
        let mapped: [GalleryItem] = jpgs.compactMap { url in
            let sidecar = url.deletingPathExtension().appendingPathExtension("json")
            if let data = try? Data(contentsOf: sidecar),
               let meta = try? JSONDecoder().decode(GalleryItem.self, from: data) {
                // hydrate with URL from disk (in case paths moved)
                return GalleryItem(id: meta.id, url: url, date: meta.date, aiKind: meta.aiKind, aiConfidence: meta.aiConfidence)
            } else {
                // fallback minimal item
                let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "selenium-", with: "")) ?? UUID()
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                return GalleryItem(id: id, url: url, date: date, aiKind: nil, aiConfidence: nil)
            }
        }

        items = mapped.sorted(by: { $0.date > $1.date })
    }

    func add(image: UIImage) async -> GalleryItem? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        let id = UUID()
        let url = folder.appendingPathComponent("selenium-\(id.uuidString).jpg")
        do {
            try data.write(to: url)

            // Build metadata from the current scene engine (if present)
            let aiKind = Self.sceneLabel(from: sceneEngine?.scene)
            let aiConf: Double? = sceneEngine.map { Double($0.latest.confidence) }
            
            let item = GalleryItem(id: id, url: url, date: Date(), aiKind: aiKind, aiConfidence: aiConf)

            // Write sidecar
            let sidecar = url.deletingPathExtension().appendingPathExtension("json")
            if let metaData = try? JSONEncoder().encode(item) {
                try? metaData.write(to: sidecar, options: Data.WritingOptions.atomic)
            }

            items.insert(item, at: 0)
            return item
        } catch {
            return nil
        }
    }

    func delete(_ itemsToDelete: [GalleryItem]) {
        for item in itemsToDelete {
            try? FileManager.default.removeItem(at: item.url)
            let sidecar = item.url.deletingPathExtension().appendingPathExtension("json")
            try? FileManager.default.removeItem(at: sidecar)
        }
        load()
    }

    // MARK: - Helpers

    static func sceneLabel(from scene: SceneKind?) -> String? {
        guard let s = scene else { return nil }
        switch s {
        case .portrait:  return "portrait"
        case .group:     return "group"
        case .animal:    return "animal"
        case .plant:     return "plant"
        case .landscape: return "landscape"
        case .other:     return nil
        }
        }
}
