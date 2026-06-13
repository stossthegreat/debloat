//
//  MessagesViewController.swift
//  ImHimMessages
//
//  iMessage App Extension — the WingAI flow you described.
//
//  Lives in iOS 17's "+" Messages App Menu. The user taps the +
//  button next to the text input, picks ImHim, and our UI shows
//  inside the Messages window:
//
//    Waiting state      "Drop a screenshot." + pulsing "WAITING FOR
//                       SCREENSHOT" pill + manual "OR PICK FROM PHOTOS"
//                       button. Polls PHPhotoLibrary every 1.5s for
//                       a fresh screenshot — if the user just took one
//                       it lands instantly.
//
//    Scanning state     The screenshot at 50% of the panel height +
//                       "SCANNING…" + a thin red progress bar.
//
//    Replies state      Three iMessage-style chips. Tap one and we
//                       call activeConversation.insertText(text) which
//                       drops the reply straight into the user's compose
//                       box. Then we requestPresentationStyle(.compact)
//                       to collapse back so they see the conversation
//                       with the message waiting to send.
//
//  Dead simple — no CADisplayLink animations, no constraint tricks,
//  just UIKit primitives. The earlier rewrite (v196-v197 Share
//  Extension) over-engineered the layout and didn't ship; this one
//  has zero "clever" code that could break compile or runtime.
//

import Messages
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

@objc(MessagesViewController)
class MessagesViewController: MSMessagesAppViewController, PHPickerViewControllerDelegate {

    // MARK: - State

    private enum State {
        case waiting
        case scanning(Data)
        case replies(Data, [Reply])
        case error(String)
    }
    private var state: State = .waiting { didSet { render() } }
    private let client = RizzClient()
    private var pollTimer: Timer?
    private var lastConsumedAssetID: String?

    // MARK: - Views

    private let header  = UIStackView()
    private let body    = UIView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupChrome()
        render()
        startPolling()
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        startPolling()
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        stopPolling()
    }

    deinit { pollTimer?.invalidate() }

    private func setupChrome() {
        // Title row: italic "ImHim" + close X.
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.attributedText = makeWordmark(size: 22)

        let spacer = UIView()

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = UIColor(white: 1, alpha: 0.7)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.widthAnchor.constraint(equalToConstant: 36).isActive = true
        close.heightAnchor.constraint(equalToConstant: 30).isActive = true

        header.addArrangedSubview(title)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(close)

        body.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(body)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            body.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
        ])
    }

    private func makeWordmark(size: CGFloat) -> NSAttributedString {
        let italic: UIFont = {
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            if let d = base.fontDescriptor.withSymbolicTraits([.traitItalic]) {
                return UIFont(descriptor: d, size: size)
            }
            return base
        }()
        let red = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Im",  attributes: [.font: italic, .foregroundColor: UIColor.white, .kern: -0.5]))
        s.append(NSAttributedString(string: "Him", attributes: [.font: italic, .foregroundColor: red, .kern: -0.5]))
        return s
    }

    // MARK: - Photos polling (auto-pickup of latest screenshot)

    private func startPolling() {
        stopPolling()
        tryConsume()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tryConsume()
        }
    }
    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func tryConsume() {
        if case .waiting = state {} else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
            return
        }
        guard status == .authorized || status == .limited else { return }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        opts.fetchLimit = 1
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        guard let asset = result.firstObject,
              let created = asset.creationDate,
              Date().timeIntervalSince(created) <= 120,
              asset.localIdentifier != lastConsumedAssetID
        else { return }

        let req = PHImageRequestOptions()
        req.isNetworkAccessAllowed = true
        req.deliveryMode = .highQualityFormat
        req.isSynchronous = false
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: req) { [weak self] data, _, _, _ in
            DispatchQueue.main.async {
                guard let self = self, let data = data else { return }
                self.lastConsumedAssetID = asset.localIdentifier
                self.send(data)
            }
        }
    }

    // MARK: - Manual photo picker

    @objc private func pickFromPhotos() {
        if presentationStyle != .expanded {
            requestPresentationStyle(.expanded)
        }
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.filter = .images
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.present(picker, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        else { return }
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var data: Data?
                if let url = item as? URL { data = try? Data(contentsOf: url) }
                else if let image = item as? UIImage { data = image.jpegData(compressionQuality: 0.92) }
                else if let raw = item as? Data { data = raw }
                if let data = data { self.send(data) }
            }
        }
    }

    // MARK: - Send → /rizz/reply

    private func send(_ data: Data) {
        state = .scanning(data)
        stopPolling()
        client.fetchReplies(screenshot: data) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let replies):
                if replies.isEmpty {
                    self.state = .error("No replies. Try a clearer screenshot.")
                } else {
                    self.state = .replies(data, replies)
                }
            case .failure(let err):
                self.state = .error(err.message)
            }
        }
    }

    // MARK: - Render

    private func render() {
        body.subviews.forEach { $0.removeFromSuperview() }
        let inner: UIView
        switch state {
        case .waiting:               inner = renderWaiting()
        case .scanning(let d):       inner = renderScanning(d)
        case .replies(let d, let r): inner = renderReplies(d, r)
        case .error(let m):          inner = renderError(m)
        }
        inner.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: body.topAnchor),
            inner.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
    }

    private func renderWaiting() -> UIView {
        let red = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1)
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.07, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 0.8
        card.layer.borderColor = UIColor(white: 0.22, alpha: 1).cgColor

        let title = UILabel()
        title.text = "Drop a screenshot."
        title.font = italic(24, .heavy)
        title.textColor = .white
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Take a screenshot of the chat — we'll write three replies you can tap straight in."
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = UIColor(white: 1, alpha: 0.82)
        sub.numberOfLines = 0
        sub.textAlignment = .center

        let pulse = pill(text: "WAITING FOR SCREENSHOT", bg: red.withAlphaComponent(0.18), fg: red, border: red.withAlphaComponent(0.65))
        UIView.animate(withDuration: 1.1, delay: 0,
                       options: [.repeat, .autoreverse, .allowUserInteraction],
                       animations: { pulse.alpha = 0.55 })

        let pick = pill(text: "OR PICK FROM PHOTOS", bg: .clear, fg: UIColor(white: 1, alpha: 0.85), border: UIColor(white: 1, alpha: 0.45))
        pick.isUserInteractionEnabled = true
        pick.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickFromPhotos)))

        let stack = UIStackView(arrangedSubviews: [title, sub, pulse, pick])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
        ])
        return card
    }

    private func renderScanning(_ data: Data) -> UIView {
        let imageView = UIImageView(image: UIImage(data: data))
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let half = imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.50)
        half.priority = .required

        let label = UILabel()
        label.text = "SCANNING…"
        label.font = .systemFont(ofSize: 11, weight: .black)
        label.textColor = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1)
        label.attributedText = NSAttributedString(
            string: "SCANNING…",
            attributes: [
                .kern: 3.6,
                .foregroundColor: UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1),
                .font: UIFont.systemFont(ofSize: 11, weight: .black),
            ]
        )
        label.textAlignment = .center

        let bar = UIProgressView(progressViewStyle: .bar)
        bar.progressTintColor = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1)
        bar.trackTintColor = UIColor(white: 0.16, alpha: 1)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        bar.setProgress(0.05, animated: false)
        // Idle climb to 0.96 over ~12s.
        UIView.animate(withDuration: 12, delay: 0, options: [.curveEaseOut], animations: {
            bar.setProgress(0.96, animated: true)
        })

        let stack = UIStackView(arrangedSubviews: [imageView, spacer(12), label, spacer(10), bar])
        stack.axis = .vertical
        stack.alignment = .fill
        NSLayoutConstraint.activate([half])
        return stack
    }

    private func renderReplies(_ data: Data, _ replies: [Reply]) -> UIView {
        let thumb = UIImageView(image: UIImage(data: data))
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 10
        thumb.contentMode = .scaleAspectFill
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.widthAnchor.constraint(equalToConstant: 48).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let caption = UILabel()
        caption.attributedText = NSAttributedString(
            string: "TAP A REPLY TO INSERT",
            attributes: [
                .kern: 3.0,
                .foregroundColor: UIColor(white: 1, alpha: 0.55),
                .font: UIFont.systemFont(ofSize: 10.5, weight: .black),
            ]
        )

        let captionRow = UIStackView(arrangedSubviews: [thumb, caption])
        captionRow.axis = .horizontal
        captionRow.alignment = .center
        captionRow.spacing = 12

        let chipStack = UIStackView()
        chipStack.axis = .vertical
        chipStack.spacing = 8
        for r in replies {
            chipStack.addArrangedSubview(makeChip(r))
        }

        let outer = UIStackView(arrangedSubviews: [captionRow, spacer(10), chipStack])
        outer.axis = .vertical
        return outer
    }

    private func makeChip(_ r: Reply) -> UIView {
        let chip = UIControl()
        chip.backgroundColor = UIColor(white: 0.07, alpha: 1)
        chip.layer.cornerRadius = 14
        chip.layer.borderWidth = 0.8
        chip.layer.borderColor = UIColor(white: 0.22, alpha: 1).cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false

        let tag = UILabel()
        tag.attributedText = NSAttributedString(
            string: r.tag,
            attributes: [
                .kern: 2.4,
                .foregroundColor: UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1),
                .font: UIFont.systemFont(ofSize: 9.5, weight: .black),
            ]
        )
        let body = UILabel()
        body.text = r.text
        body.font = .systemFont(ofSize: 14, weight: .medium)
        body.textColor = .white
        body.numberOfLines = 3

        let s = UIStackView(arrangedSubviews: [tag, body])
        s.axis = .vertical
        s.spacing = 3
        s.alignment = .leading
        s.isUserInteractionEnabled = false
        s.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: chip.topAnchor, constant: 10),
            s.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -10),
            s.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 14),
            s.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -14),
        ])
        chip.accessibilityValue = r.text
        chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        return chip
    }

    private func renderError(_ msg: String) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.07, alpha: 1)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.8
        card.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.45).cgColor

        let title = UILabel()
        title.text = msg
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.textAlignment = .center
        title.numberOfLines = 0

        let retry = pill(text: "TRY AGAIN", bg: .clear, fg: UIColor(white: 1, alpha: 0.85), border: UIColor(white: 1, alpha: 0.45))
        retry.isUserInteractionEnabled = true
        retry.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryWaiting)))

        let stack = UIStackView(arrangedSubviews: [title, retry])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])
        return card
    }

    // MARK: - Helpers

    private func pill(text: String, bg: UIColor, fg: UIColor, border: UIColor) -> UIView {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .kern: 3.2,
                .foregroundColor: fg,
                .font: UIFont.systemFont(ofSize: 11, weight: .black),
            ]
        )
        label.textAlignment = .center
        label.backgroundColor = bg
        label.layer.cornerRadius = 99
        label.layer.masksToBounds = true
        label.layer.borderWidth = 0.9
        label.layer.borderColor = border.cgColor
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrap.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            label.heightAnchor.constraint(equalToConstant: 32),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        return wrap
    }

    private func spacer(_ h: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    private func italic(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withSymbolicTraits([.traitItalic]) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    // MARK: - Actions

    @objc private func chipTapped(_ sender: UIControl) {
        guard let text = sender.accessibilityValue else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // The landing — drops the reply straight into iMessage's compose
        // box. The user taps Send once.
        activeConversation?.insertText(text, completionHandler: nil)
        // Collapse back to compact so they see the conversation with the
        // message text ready to send.
        requestPresentationStyle(.compact)
    }

    @objc private func closeTapped() {
        requestPresentationStyle(.compact)
    }

    @objc private func retryWaiting() {
        lastConsumedAssetID = nil
        state = .waiting
        startPolling()
    }
}

// MARK: - Reply model + backend client (inlined so the installer only
// has to ship one source file).

struct Reply {
    let text: String
    let tag:  String
}

// Swift's Result type requires Failure: Error. Wrap our user-facing
// string in a tiny error type so the call sites can just read
// .message — keeps the API ergonomic without forcing every caller
// to bridge to NSError.
struct RizzError: Error {
    let message: String
}

final class RizzClient {
    private let host = URL(string: "https://mirrorly-production.up.railway.app")!

    func fetchReplies(screenshot: Data, completion: @escaping (Result<[Reply], RizzError>) -> Void) {
        let payload = compress(screenshot) ?? screenshot

        // v204 ELITE MODE v2 — example-driven, persona-grounded.
        // Identical to the in-app Rizz screen so the iMessage drop
        // reads the same voice as the in-app result.
        let eliteMode = """
        ELITE MODE.

        You are writing for a man who already knows she likes him. He has 12
        women in his phone. He doesn't need this one to work — which is
        exactly why she wants him to.

        Voice: Hank Moody. Don Draper. John Wick at the bar. Dry. Specific.
        Implication over assertion. One degree of dangerous, two of warm.

        Calibrate against these examples:

          She: "ok that was smooth"
          ❌ Cringe: "haha thanks 😏 you're not so bad yourself"
          ❌ Mid:    "i mean, i try"
          ✅ Elite:  "wait til you see me sober"

          She: "your my type too ;)"
          ❌ Cringe: "omg you're my type too! 😊"
          ❌ Mid:    "good. saves us a step"
          ✅ Elite:  "good. saves me the speech."

          She: "i'm ready when you are"
          ❌ Cringe: "amazing!! what about friday?"
          ❌ Mid:    "tomorrow at 7"
          ✅ Elite:  "tomorrow. 7. bring whoever you're making jealous."

          She: "stopp rn 🙈"
          ❌ Cringe: "haha sorry not sorry 😂"
          ❌ Mid:    "no"
          ✅ Elite:  "make me."

          She: "call me tn daddy"
          ❌ Cringe: "haha you're so cute 😍 absolutely"
          ❌ Mid:    "ok i'll call"
          ✅ Elite:  "be ready by 9. answer on the first ring."

        Hard rules — non-negotiable:
        • 4–14 words per reply. Less is more.
        • Real-guy voice. No "haha", "lol", "honestly", "I think", "definitely", "absolutely", "amazing".
        • No hedging. No "would you", "if you want", "maybe", "I'd love to". Decide for her.
        • Don't explain the joke. Land it. Walk.
        • Specific to ONE beat from HER message — reference an actual word she used.
        • The three replies must hit different angles:
            1. Playful with bite — teases her without explaining the tease.
            2. Calm dominance   — decides, doesn't ask.
            3. Tension          — one-degree dirty, leaves something unsaid.
        • Imply over ask. "We're getting drinks Friday" beats "want to grab drinks?".
        • No emojis unless one is the punchline itself.
        • Never apologise. Never simp. Never beg. Never explain yourself.
        • Sound like a guy she'd replay a conversation with at 2am.
        """

        let body: [String: Any] = [
            "vibe":        "flirty",
            "ctx":         "imessage",
            "scenario":    eliteMode,
            "imageBase64": payload.base64EncodedString(),
        ]
        var req = URLRequest(url: host.appendingPathComponent("rizz/reply"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        do { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch {
            DispatchQueue.main.async { completion(.failure(RizzError(message: "encode: \(error)"))) }
            return
        }
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(RizzError(message: "Network: \(err.localizedDescription)"))) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let replies = json["replies"] as? [[String: Any]]
            else {
                DispatchQueue.main.async { completion(.failure(RizzError(message: "Bad response from server."))) }
                return
            }
            let mapped: [Reply] = replies.compactMap {
                guard let text = ($0["text"] as? String ?? $0["line"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { return nil }
                let tag = ($0["tag"] as? String ?? "RIZZ").uppercased()
                return Reply(text: text, tag: tag)
            }
            DispatchQueue.main.async { completion(.success(Array(mapped.prefix(3)))) }
        }.resume()
    }

    private func compress(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxEdge: CGFloat = 1600
        let scale = min(1.0, maxEdge / max(img.size.width, img.size.height))
        let target = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(target, true, 1.0)
        img.draw(in: CGRect(origin: .zero, size: target))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized?.jpegData(compressionQuality: 0.78)
    }
}
