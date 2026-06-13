//
//  ShareViewController.swift
//  ImHimShare
//
//  iOS Share Extension. Dead simple, silent hand-off:
//
//   1. iOS hands us a screenshot via extensionContext.inputItems.
//   2. We write the JPEG to the App Group container at a known
//      path and bump a timestamp in the shared UserDefaults so the
//      Flutter side can detect it.
//   3. We deep-link the main Runner app via the imhim://rizz URL
//      scheme.
//   4. Runner foregrounds, reads the file off the App Group, opens
//      the Rizz screen with the screenshot pre-loaded, fires the
//      existing OCR + AI reply pipeline.
//   5. Extension closes itself.
//
//  Total view-controller lifetime: ~200ms. No UI, no animations,
//  nothing to fail at. This is the v191/v195 architecture that
//  was reaching TestFlight cleanly before v196's in-place UI
//  rewrite. The "panel slides up with scan inside the share sheet"
//  rewrite is shelved until the silent path is reliably shipping.
//

import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {

    static let appGroupID      = "group.com.mirrorly.app.shared"
    static let urlScheme       = "imhim"
    static let payloadName     = "shared_screenshot.jpg"
    static let payloadStampKey = "share.screenshot.timestamp"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        ingestSharedImage()
    }

    // MARK: - Ingest

    private func ingestSharedImage() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }
        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadItem(
                        forTypeIdentifier: UTType.image.identifier,
                        options: nil
                    ) { [weak self] item, _ in
                        DispatchQueue.main.async {
                            self?.handleLoadedItem(item)
                        }
                    }
                    return
                }
            }
        }
        close()
    }

    private func handleLoadedItem(_ item: NSSecureCoding?) {
        var imageData: Data?
        if let url = item as? URL {
            imageData = try? Data(contentsOf: url)
        } else if let image = item as? UIImage {
            imageData = image.jpegData(compressionQuality: 0.92)
        } else if let raw = item as? Data {
            imageData = raw
        }
        guard let imageData = imageData else {
            close()
            return
        }
        writeToAppGroup(imageData)
        openHostApp()
    }

    // MARK: - App Group write

    private func writeToAppGroup(_ data: Data) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareViewController.appGroupID
        ) else { return }

        let fileURL = container.appendingPathComponent(ShareViewController.payloadName)
        try? data.write(to: fileURL, options: .atomic)

        let defaults = UserDefaults(suiteName: ShareViewController.appGroupID)
        defaults?.set(
            Date().timeIntervalSince1970,
            forKey: ShareViewController.payloadStampKey
        )
        defaults?.synchronize()
    }

    // MARK: - Deep-link back to Runner

    private func openHostApp() {
        guard let url = URL(string: "\(ShareViewController.urlScheme)://rizz?source=share") else {
            close()
            return
        }
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                let selector = #selector(UIApplication.open(_:options:completionHandler:))
                if application.responds(to: selector) {
                    application.perform(selector, with: url, with: [:])
                }
                break
            }
            responder = responder?.next
        }
        close()
    }

    // MARK: - Done

    private func close() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
