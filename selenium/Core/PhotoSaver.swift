//
//  PhotoSaver.swift
//  selenium
//
//  Created by Zain Karim on 9/4/25.
//

import Photos
import UIKit

enum PhotoSaver {
    static func saveToLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, err in
                DispatchQueue.main.async { completion(success, err) }
            }
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        saveToLibrary(image, completion: completion)
                    } else {
                        completion(false, nil)
                    }
                }
            }
        default:
            completion(false, nil)
        }
    }
}

extension PhotoSaver {
    static func saveFileURLToLibrary(_ url: URL, completion: @escaping (Bool, Error?) -> Void) {
        guard let img = UIImage(contentsOfFile: url.path) else {
            completion(false, nil); return
        }
        saveToLibrary(img, completion: completion) // uses your existing image saver
    }
}

extension PhotoSaver {
    static func saveFileURLsToLibrary(_ urls: [URL], completion: @escaping (Int, Int) -> Void) {
        var ok = 0, fail = 0
        func done() { completion(ok, fail) }

        guard !urls.isEmpty else { completion(0, 0); return }
        let group = DispatchGroup()
        for u in urls {
            group.enter()
            if let img = UIImage(contentsOfFile: u.path) {
                saveToLibrary(img) { success, _ in
                    if success { ok += 1 } else { fail += 1 }
                    group.leave()
                }
            } else {
                fail += 1
                group.leave()
            }
        }
        group.notify(queue: .main, execute: done)
    }
}
