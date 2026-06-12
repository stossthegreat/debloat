//
//  ScreenshotScanner.swift
//  ImHimMessages
//
//  Polls the Photo Library for the most recent screenshot and hands
//  the image bytes up to the messages view controller. Same pattern
//  WingAI uses — user takes a screenshot of the chat (or anywhere),
//  opens the iMessage app drawer, our extension grabs it without the
//  user having to pick it manually.
//

import Foundation
import Photos
import UIKit

final class ScreenshotScanner {

    /// How fresh a screenshot needs to be to count. 120s window so
    /// the user has time to switch apps + open the iMessage drawer.
    private let freshnessWindow: TimeInterval = 120

    /// The last asset ID we returned to the caller. Prevents
    /// re-emitting the same screenshot after we've already scanned it.
    private(set) var lastConsumedAssetID: String?

    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    func fetchLatestScreenshot(_ completion: @escaping (Data?) -> Void) {
        guard hasAccess else {
            completion(nil)
            return
        }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        opts.fetchLimit = 1

        let result = PHAsset.fetchAssets(with: .image, options: opts)
        guard let asset = result.firstObject,
              let created = asset.creationDate
        else {
            completion(nil)
            return
        }

        if Date().timeIntervalSince(created) > freshnessWindow {
            completion(nil)
            return
        }
        if asset.localIdentifier == lastConsumedAssetID {
            completion(nil)
            return
        }

        let manager = PHImageManager.default()
        let requestOpts = PHImageRequestOptions()
        requestOpts.isNetworkAccessAllowed = true
        requestOpts.deliveryMode = .highQualityFormat
        requestOpts.resizeMode = .none
        requestOpts.isSynchronous = false

        manager.requestImageDataAndOrientation(for: asset, options: requestOpts) { data, _, _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let data = data else {
                    completion(nil)
                    return
                }
                self.lastConsumedAssetID = asset.localIdentifier
                completion(data)
            }
        }
    }
}
