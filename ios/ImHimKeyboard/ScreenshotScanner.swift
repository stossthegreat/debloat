//
//  ScreenshotScanner.swift
//  ImHimKeyboard
//
//  Polls the Photo Library for the most recent screenshot and hands the
//  image bytes up to the keyboard view controller. Mirrors WingAI's
//  "Waiting for Screenshot…" pattern — the moment the user hits the
//  iOS screenshot chord, our extension sees the asset land in Photos
//  and grabs it without the user having to do anything.
//

import Foundation
import Photos
import UIKit

final class ScreenshotScanner {

    /// How fresh a screenshot needs to be to count. 90s matches the
    /// "I just took it" intent — anything older we ignore so we don't
    /// recycle yesterday's screenshot.
    private let freshnessWindow: TimeInterval = 90

    /// The last asset ID we returned to the caller. Stops us re-pinging
    /// the same screenshot the user has already had us scan.
    private(set) var lastConsumedAssetID: String?

    /// Request authorisation status. Returns `.authorized` or `.limited`
    /// to mean "we can read", anything else means we can't.
    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Looks up the newest screenshot in the Photo Library. If it was
    /// taken inside `freshnessWindow` seconds AND we haven't already
    /// consumed it, fetches the image data and calls `completion` with
    /// the bytes. Otherwise calls `completion(nil)`.
    func fetchLatestScreenshot(_ completion: @escaping (Data?) -> Void) {
        guard hasAccess else {
            completion(nil)
            return
        }

        // Predicate: only screenshots, newest first, take the top one.
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

        // Freshness gate.
        if Date().timeIntervalSince(created) > freshnessWindow {
            completion(nil)
            return
        }
        // Don't re-emit a screenshot we already handed up.
        if asset.localIdentifier == lastConsumedAssetID {
            completion(nil)
            return
        }

        let manager = PHImageManager.default()
        let requestOpts = PHImageRequestOptions()
        requestOpts.isNetworkAccessAllowed = true  // covers iCloud-backed assets
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
