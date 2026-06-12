//
//  RizzClient.swift
//  ImHimMessages
//
//  Talks to the same /rizz/reply backend the main app's Rizz screen
//  hits. Same JSON payload shape: { vibe, ctx, scenario, imageBase64 }.
//

import Foundation
import UIKit

struct RizzReplyItem {
    let text: String
    let tag:  String
}

enum RizzError: Error {
    case network(String)
    case decode(String)
}

final class RizzClient {

    /// Same host as ApiConfig.backendBaseUrl in lib/config/api_config.dart.
    private let host = URL(string: "https://mirrorly-production.up.railway.app")!

    /// Hard default vibe. Could be pulled from a shared App Group
    /// once the entitlement is registered on the dev portal, but for
    /// now the iMessage extension picks "playful" — matches what the
    /// main app's Rizz screen defaults to.
    var preferredVibe: String { "playful" }

    func fetchReplies(
        screenshot: Data,
        completion: @escaping (Result<[RizzReplyItem], RizzError>) -> Void
    ) {
        let payloadImage = compress(screenshot) ?? screenshot
        let b64 = payloadImage.base64EncodedString()

        let body: [String: Any] = [
            "vibe":        preferredVibe,
            "ctx":         "imessage",
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

        URLSession.shared.dataTask(with: req) { data, _, err in
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
        }.resume()
    }

    /// Squash to ≤1600px long edge + JPEG q 0.78. Keeps the upload
    /// under ~500 KB for a typical iPhone screenshot — matches what
    /// the Flutter Rizz screen does before sending vision payloads.
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
