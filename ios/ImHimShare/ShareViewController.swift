//
//  ShareViewController.swift
//  ImHimShare
//
//  iOS Share Extension. Lives in the iOS Share Sheet (the row of
//  app icons you see when you tap the Share button anywhere). When
//  the user shares a screenshot:
//
//    1. iOS launches THIS view controller and hands us the image via
//       extensionContext.inputItems.
//    2. We write the bytes to the App Group shared container at a
//       known path (shared_screenshot.jpg) and bump a timestamp in
//       the shared UserDefaults so the Flutter side can detect it.
//    3. We deep-link the main Runner app via the custom URL scheme
//       imhim://rizz?source=share, which AppDelegate handles by
//       forwarding to Flutter over a MethodChannel.
//    4. The Runner app launches (or foregrounds), reads the file
//       from the App Group, navigates straight to the Rizz reply
//       screen with the screenshot already loaded, and fires the
//       existing OCR + AI reply pipeline.
//
//  No copy/paste, no app-switch friction — same UX as WingAI.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

@objc(ShareViewController)
class ShareViewController: UIViewController {

    // ───────────────────────────────────────────────────────────────
    //  Configuration — keep these in sync with the main app's
    //  entitlements + Info.plist URL Types + Flutter constants.
    // ───────────────────────────────────────────────────────────────
    static let appGroupID  = "group.com.mirrorly.app.shared"
    static let urlScheme   = "imhim"
    /// Filename used for the handoff payload inside the App Group
    /// container. Read by Flutter via ShareIntakeService.
    static let payloadName = "shared_screenshot.jpg"
    /// UserDefaults key whose value (epoch seconds) bumps every time
    /// we drop a new screenshot. Flutter polls this on launch / resume
    /// to know there's something to consume.
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
        // The shared "image" item can arrive as a UIImage, a Data
        // blob, or a file URL pointing at a temp copy. Normalise.
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

        // Timestamp so the Flutter side knows this is a NEW
        // screenshot, not the one we left behind from yesterday.
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

        // Walk the responder chain to find a UIApplication. Pure
        // public-API on iOS — UIApplication.shared isn't accessible
        // from inside an app extension, but we ARE in a UIResponder
        // tree whose root is the application itself.
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
