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
