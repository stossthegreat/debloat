//
//  KeyboardViewController.swift
//  ImHimKeyboard
//
//  The visible keyboard. Three states drive the whole UI:
//
//    .waiting   — fresh boot. "Waiting for screenshot…" + manual "Pick"
//                 button. Polls Photos every 1.5s for the latest screenshot.
//    .loading   — we've sent the image to /rizz/reply, awaiting replies.
//    .replies   — three reply chips, tap to insert into the active field.
//    .error     — short toast-style banner with a retry chip.
//
//  Mirrors WingAI's UX: open the keyboard, take a screenshot, the chips
//  arrive in <5s, one tap drops a reply into iMessage. No app switch.
//

import UIKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - State

    private enum State {
        case waiting
        case loading
        case replies([RizzReplyItem])
        case error(String)
    }

    private var state: State = .waiting {
        didSet { render() }
    }

    private let scanner = ScreenshotScanner()
    private let client  = RizzClient()
    private var pollTimer: Timer?

    // MARK: - Views

    private lazy var rootStack: UIStackView = {
        let v = UIStackView()
        v.axis = .vertical
        v.alignment = .fill
        v.distribution = .fill
        v.spacing = 10
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var headerRow: UIStackView = {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = UILabel()
        wordmark.attributedText = makeWordmark(size: 18)
        wordmark.translatesAutoresizingMaskIntoConstraints = false

        let dot = UIView()
        dot.backgroundColor = Theme.red
        dot.layer.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(wordmark)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(makeNextKeyboardButton())
        return row
    }()

    /// Status/CTA region. Re-built per render(); we don't reuse subviews.
    private let bodyContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.base

        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])

        rootStack.addArrangedSubview(headerRow)
        rootStack.addArrangedSubview(bodyContainer)

        // First-paint: figure out if we have Photos access.
        scanner.requestAuthorization { [weak self] status in
            self?.render()
            if status == .authorized || status == .limited {
                self?.startPolling()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if scanner.hasAccess && pollTimer == nil {
            startPolling()
        }
        render()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        // Quick first attempt — the user often takes the screenshot BEFORE
        // they switch to our keyboard, so check once on mount.
        tryConsumeScreenshot()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tryConsumeScreenshot()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tryConsumeScreenshot() {
        // Only poll while idle — don't yank the user out of the replies
        // view by detecting an older screenshot.
        if case .waiting = state {} else { return }
        scanner.fetchLatestScreenshot { [weak self] data in
            guard let self = self, let data = data else { return }
            self.send(data)
        }
    }

    private func send(_ data: Data) {
        state = .loading
        stopPolling()
        client.fetchReplies(screenshot: data) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let replies):
                if replies.isEmpty {
                    self.state = .error("No replies — try again.")
                } else {
                    self.state = .replies(replies)
                }
            case .failure(let err):
                self.state = .error(err.userMessage)
            }
        }
    }

    // MARK: - Render

    private func render() {
        // Wipe body subviews so each state owns the layout cleanly.
        bodyContainer.subviews.forEach { $0.removeFromSuperview() }

        let inner: UIView
        if !scanner.hasAccess {
            inner = makePermissionPrompt()
        } else {
            switch state {
            case .waiting:        inner = makeWaitingView()
            case .loading:        inner = makeLoadingView()
            case .replies(let r): inner = makeRepliesView(r)
            case .error(let msg): inner = makeErrorView(msg)
            }
        }
        inner.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            inner.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
        ])
    }

    // MARK: - Builders

    private func makeWaitingView() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface1
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 0.8
        card.layer.borderColor = Theme.divider.cgColor

        let title = UILabel()
        title.text = "Drop a screenshot."
        title.font = makeItalic(size: 22, weight: .heavy)
        title.textColor = Theme.textPrimary
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Take the screenshot — we'll read it and write three replies."
        sub.font = Theme.body(size: 12.5, weight: .medium)
        sub.textColor = Theme.textSecondary
        sub.textAlignment = .center
        sub.numberOfLines = 0

        let pulse = makeRedPill(text: "WAITING FOR SCREENSHOT")
        animatePulse(pulse)

        let manual = makeOutlinePill(text: "OR PICK FROM PHOTOS")
        let tap = UITapGestureRecognizer(target: self, action: #selector(pickManually))
        manual.addGestureRecognizer(tap)

        let stack = UIStackView(arrangedSubviews: [title, sub, pulse, manual])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])
        return card
    }

    private func makeLoadingView() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface1
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 0.8
        card.layer.borderColor = Theme.red.withAlphaComponent(0.4).cgColor

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Theme.red
        spinner.startAnimating()

        let title = UILabel()
        title.text = "Reading the chat…"
        title.font = makeItalic(size: 20, weight: .heavy)
        title.textColor = Theme.textPrimary

        let sub = UILabel()
        sub.text = "THREE OPTIONS INCOMING"
        sub.font = Theme.label(size: 10.5)
        sub.textColor = Theme.red
        let traits = sub.font.fontDescriptor.withSymbolicTraits([])
        if let trait = traits {
            sub.font = UIFont(descriptor: trait, size: 10.5)
        }
        sub.attributedText = NSAttributedString(
            string: "THREE OPTIONS INCOMING",
            attributes: [
                .kern: 3.2,
                .foregroundColor: Theme.red,
                .font: Theme.label(size: 10.5),
            ]
        )

        let stack = UIStackView(arrangedSubviews: [spinner, title, sub])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
        ])
        return card
    }

    private func makeRepliesView(_ replies: [RizzReplyItem]) -> UIView {
        let v = UIStackView()
        v.axis = .vertical
        v.spacing = 8

        for (idx, r) in replies.enumerated() {
            v.addArrangedSubview(makeReplyChip(r, index: idx))
        }
        // Bottom row: re-scan + "type your own"
        let actionRow = UIStackView()
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.distribution = .fillEqually

        let rescan = makeOutlinePill(text: "NEW SCREENSHOT")
        let rescanTap = UITapGestureRecognizer(target: self, action: #selector(resetToWaiting))
        rescan.addGestureRecognizer(rescanTap)
        actionRow.addArrangedSubview(rescan)

        v.addArrangedSubview(actionRow)
        return v
    }

    private func makeReplyChip(_ r: RizzReplyItem, index: Int) -> UIView {
        let chip = UIControl()
        chip.backgroundColor = Theme.surface1
        chip.layer.cornerRadius = 14
        chip.layer.borderWidth = 0.8
        chip.layer.borderColor = Theme.divider.cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.tag = index

        let tag = UILabel()
        tag.attributedText = NSAttributedString(
            string: r.tag,
            attributes: [
                .kern: 2.4,
                .foregroundColor: Theme.red,
                .font: Theme.label(size: 9.5),
            ]
        )
        tag.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.text = r.text
        body.font = Theme.body(size: 14, weight: .medium)
        body.textColor = Theme.textPrimary
        body.numberOfLines = 0
        body.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [tag, body])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: chip.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -14),
        ])
        chip.addTarget(self, action: #selector(replyTapped(_:)), for: .touchUpInside)
        // Store the text on the chip itself so the tap handler can pull it.
        chip.accessibilityValue = r.text
        return chip
    }

    private func makeErrorView(_ msg: String) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface1
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.8
        card.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.45).cgColor

        let title = UILabel()
        title.text = msg
        title.font = Theme.body(size: 13, weight: .semibold)
        title.textColor = Theme.textPrimary
        title.numberOfLines = 0

        let retry = makeOutlinePill(text: "TRY AGAIN")
        let tap = UITapGestureRecognizer(target: self, action: #selector(resetToWaiting))
        retry.addGestureRecognizer(tap)

        let stack = UIStackView(arrangedSubviews: [title, retry])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    private func makePermissionPrompt() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface1
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.8
        card.layer.borderColor = Theme.red.withAlphaComponent(0.4).cgColor

        let title = UILabel()
        title.text = "Photos access needed."
        title.font = makeItalic(size: 18, weight: .heavy)
        title.textColor = Theme.textPrimary
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Open ImHim → Keyboard, tap Enable, then turn on \"Allow Full Access.\""
        sub.font = Theme.body(size: 12, weight: .medium)
        sub.textColor = Theme.textSecondary
        sub.textAlignment = .center
        sub.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, sub])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])
        return card
    }

    private func makeNextKeyboardButton() -> UIView {
        // Required by Apple — every custom keyboard must surface a way to
        // switch back to the system keyboard. Globe glyph, low-key.
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "globe"), for: .normal)
        btn.tintColor = Theme.textTertiary
        btn.addTarget(self,
                      action: #selector(handleInputModeList(from:with:)),
                      for: .allTouchEvents)
        btn.widthAnchor.constraint(equalToConstant: 34).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return btn
    }

    private func makeRedPill(text: String) -> UIView {
        let pill = UILabel()
        pill.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .kern: 3.4,
                .foregroundColor: Theme.red,
                .font: Theme.label(size: 11),
            ]
        )
        pill.textAlignment = .center
        pill.backgroundColor = Theme.redDim
        pill.layer.cornerRadius = 99
        pill.layer.masksToBounds = true
        pill.layer.borderWidth = 0.9
        pill.layer.borderColor = Theme.red.withAlphaComponent(0.65).cgColor
        pill.setContentHuggingPriority(.required, for: .horizontal)
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pill)
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 30),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        // Padding via attributed string isn't free in UILabel; just give
        // the pill width via insets through layout margin.
        pill.textAlignment = .center
        return container
    }

    private func makeOutlinePill(text: String) -> UIView {
        let pill = UILabel()
        pill.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .kern: 3.0,
                .foregroundColor: Theme.textSecondary,
                .font: Theme.label(size: 10.5),
            ]
        )
        pill.textAlignment = .center
        pill.backgroundColor = .clear
        pill.layer.cornerRadius = 99
        pill.layer.masksToBounds = true
        pill.layer.borderWidth = 0.8
        pill.layer.borderColor = Theme.textTertiary.cgColor
        pill.isUserInteractionEnabled = true
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pill)
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 28),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
        container.isUserInteractionEnabled = true
        return container
    }

    private func animatePulse(_ view: UIView) {
        UIView.animate(
            withDuration: 1.2,
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction],
            animations: { view.alpha = 0.55 }
        )
    }

    private func makeWordmark(size: CGFloat) -> NSAttributedString {
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(
            string: "Im",
            attributes: [
                .font: Theme.wordmark(size: size),
                .foregroundColor: Theme.textPrimary,
                .kern: -0.5,
            ]
        ))
        attr.append(NSAttributedString(
            string: "Him",
            attributes: [
                .font: Theme.wordmark(size: size),
                .foregroundColor: Theme.red,
                .kern: -0.5,
            ]
        ))
        return attr
    }

    private func makeItalic(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withSymbolicTraits([.traitItalic]) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    // MARK: - Actions

    @objc private func replyTapped(_ sender: UIControl) {
        guard let text = sender.accessibilityValue else { return }
        // Haptic on insert — keeps the "this worked" beat alive.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        textDocumentProxy.insertText(text)
        // Reset back to waiting so the next screenshot is ready to land.
        resetToWaiting()
    }

    @objc private func resetToWaiting() {
        state = .waiting
        if scanner.hasAccess { startPolling() }
    }

    @objc private func pickManually() {
        // Manual pick isn't supported from inside a keyboard extension
        // (UIImagePickerController + PHPickerViewController both require
        // a presenting view controller that the keyboard context can't
        // safely host). Instead, the chip nudges the user to take a
        // screenshot — same affordance, no host-app dependency.
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        state = .error("Take a screenshot of the chat — we'll pick it up automatically.")
    }
}

private extension RizzError {
    var userMessage: String {
        switch self {
        case .noAccess:           return "Photos access not granted."
        case .network(let m):     return "Network issue · \(m.prefix(40))"
        case .decode(let m):      return "Bad response · \(m.prefix(40))"
        }
    }
}
