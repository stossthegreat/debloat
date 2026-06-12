//
//  RizzClient.swift
//  ImHimKeyboard
//
//  Talks to the same /rizz/reply backend the in-app Rizz screen uses.
//  Hard-coded host so the keyboard never needs to do an app-launch
//  handshake — the App Group UserDefaults still carries config the
//  main app sets (selected vibe, telemetry opt-in), but the host
//  itself is a constant.
//

import Foundation
import UIKit

struct RizzReplyItem {
    let text: String
    let tag:  String
}

enum RizzError: Error {
    case noAccess
    case network(String)
    case decode(String)
}

final class RizzClient {

    /// Same host as ApiConfig.backendBaseUrl in lib/config/api_config.dart.
    /// If the main app rotates its backend host, bump this constant.
    private let host = URL(string: "https://mirrorly-production.up.railway.app")!

    /// Shared UserDefaults written by the Flutter side. Lets the main
    /// app push the current selected vibe / tone into the keyboard
    /// without the user reconfiguring it twice.
    private let shared = UserDefaults(suiteName: "group.com.mirrorly.app.shared")

    /// Pull the user's preferred vibe (set in the Flutter Rizz tab).
    /// Falls back to "playful" if the main app hasn't written it yet.
    var preferredVibe: String {
        shared?.string(forKey: "rizz.vibe") ?? "playful"
    }

    /// POST screenshot → 3 replies. Reuses the same JSON payload shape
    /// the Flutter app uses: { vibe, ctx, scenario, imageBase64 }.
    func fetchReplies(
        screenshot: Data,
        completion: @escaping (Result<[RizzReplyItem], RizzError>) -> Void
    ) {
        // Re-encode the screenshot at a reasonable size + JPEG quality so
        // the upload doesn't burn the user's data on a 8MB iCloud PNG.
        let payloadImage = compress(screenshot) ?? screenshot
        let b64 = payloadImage.base64EncodedString()

        let body: [String: Any] = [
            "vibe":        preferredVibe,
            "ctx":         "keyboard",      // server-side tagging so we can A/B
            "scenario":    "",
            "imageBase64": b64,
        ]

        var req = URLRequest(url: host.appendingPathComponent("rizz/reply"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.network("encode: \(error)")))
            return
        }

        let task = URLSession.shared.dataTask(with: req) { data, response, err in
            if let err = err {
                DispatchQueue.main.async {
                    completion(.failure(.network(err.localizedDescription)))
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(.network("no data")))
                }
                return
            }
            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let replies = json["replies"] as? [[String: Any]]
                else {
                    let bodyStr = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
                    DispatchQueue.main.async {
                        completion(.failure(.decode("shape: \(bodyStr)")))
                    }
                    return
                }
                let mapped: [RizzReplyItem] = replies.compactMap {
                    guard let text = ($0["text"] as? String ?? $0["line"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty
                    else { return nil }
                    let tag = ($0["tag"] as? String ?? "RIZZ").uppercased()
                    return RizzReplyItem(text: text, tag: tag)
                }
                DispatchQueue.main.async { completion(.success(Array(mapped.prefix(3)))) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decode(error.localizedDescription)))
                }
            }
        }
        task.resume()
    }

    /// Squash to 1600px on the long edge + JPEG q 0.78. Mirrors what the
    /// Flutter app does before sending vision payloads. Keeps the upload
    /// under ~500 KB for a typical iPhone screenshot.
    private func compress(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxEdge: CGFloat = 1600
        let w = img.size.width, h = img.size.height
        let scale = min(1.0, maxEdge / max(w, h))
        let target = CGSize(width: w * scale, height: h * scale)
        UIGraphicsBeginImageContextWithOptions(target, true, 1.0)
        img.draw(in: CGRect(origin: .zero, size: target))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized?.jpegData(compressionQuality: 0.78)
    }
}
