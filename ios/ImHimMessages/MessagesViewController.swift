//
//  MessagesViewController.swift
//  ImHimMessages
//
//  THE iMessage app — what you actually wanted. Lives in the "+"
//  drawer of iMessage. Open a chat, tap +, pick ImHim, our UI takes
//  over the bottom half, scans your latest screenshot, drops three
//  replies in. Tap one, it inserts straight into the iMessage
//  compose box — you tap send. Zero copy-paste, no app switch.
//
//  States, top to bottom:
//    .waiting   — "Drop a screenshot." Polls Photos every 1.5s.
//    .loading   — "Reading the chat… three options incoming."
//    .replies   — three tappable chips, each inserts via
//                  activeConversation.insertText.
//    .error     — short message + retry chip.
//

import Messages
import UIKit

final class MessagesViewController: MSMessagesAppViewController {

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
        wordmark.attributedText = makeWordmark(size: 22)
        wordmark.translatesAutoresizingMaskIntoConstraints = false

        let dot = UIView()
        dot.backgroundColor = Theme.red
        dot.layer.cornerRadius = 3
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(wordmark)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(spacer)
        return row
    }()

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
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])

        rootStack.addArrangedSubview(headerRow)
        rootStack.addArrangedSubview(bodyContainer)

        scanner.requestAuthorization { [weak self] _ in
            self?.render()
            self?.startPolling()
        }
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        if scanner.hasAccess && pollTimer == nil {
            startPolling()
        }
        render()
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        stopPolling()
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        // The expanded presentation is where the meaningful UI lives —
        // compact mode is just a teaser. We render the same scaffold
        // in both; layout adjusts to the new bounds automatically.
        render()
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
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
                    self.state = .error("No replies — try a clearer screenshot.")
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
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 0.8
        card.layer.borderColor = Theme.divider.cgColor

        let title = UILabel()
        title.text = "Drop a screenshot."
        title.font = Theme.italic(size: 24)
        title.textColor = Theme.textPrimary
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "Take a screenshot of any chat — we'll read it and write three replies you can drop straight in."
        sub.font = Theme.body(size: 13)
        sub.textColor = Theme.textSecondary
        sub.textAlignment = .center
        sub.numberOfLines = 0

        let pulse = makeRedPill(text: "WAITING FOR SCREENSHOT")
        animatePulse(pulse)

        let stack = UIStackView(arrangedSubviews: [title, sub, pulse])
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

    private func makeLoadingView() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface1
        card.layer.cornerRadius = 20
        card.layer.borderColor = Theme.red.withAlphaComponent(0.45).cgColor
        card.layer.borderWidth = 0.8

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Theme.red
        spinner.startAnimating()

        let title = UILabel()
        title.text = "Reading the chat…"
        title.font = Theme.italic(size: 22)
        title.textColor = Theme.textPrimary
        title.textAlignment = .center

        let sub = UILabel()
        sub.attributedText = NSAttributedString(
            string: "THREE OPTIONS INCOMING",
            attributes: [
                .kern: 3.2,
                .foregroundColor: Theme.red,
                .font: Theme.label(size: 11),
            ]
        )

        let stack = UIStackView(arrangedSubviews: [spinner, title, sub])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
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

        let rescan = makeOutlinePill(text: "NEW SCREENSHOT")
        let tap = UITapGestureRecognizer(target: self, action: #selector(resetToWaiting))
        rescan.addGestureRecognizer(tap)
        v.addArrangedSubview(rescan)
        return v
    }

    private func makeReplyChip(_ r: RizzReplyItem, index: Int) -> UIView {
        let chip = UIControl()
        chip.backgroundColor = Theme.surface1
        chip.layer.cornerRadius = 14
        chip.layer.borderWidth = 0.8
        chip.layer.borderColor = Theme.divider.cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false

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
        body.font = Theme.body(size: 14)
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
        title.textAlignment = .center
        title.numberOfLines = 0

        let retry = makeOutlinePill(text: "TRY AGAIN")
        let tap = UITapGestureRecognizer(target: self, action: #selector(resetToWaiting))
        retry.addGestureRecognizer(tap)

        let stack = UIStackView(arrangedSubviews: [title, retry])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
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

    private func makePermissionPrompt() -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface1
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.8
        card.layer.borderColor = Theme.red.withAlphaComponent(0.4).cgColor

        let title = UILabel()
        title.text = "Photos access needed."
        title.font = Theme.italic(size: 19)
        title.textColor = Theme.textPrimary
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "iOS needs to share your latest screenshot with ImHim so we can read it. Tap Allow when prompted."
        sub.font = Theme.body(size: 12.5)
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
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])
        return card
    }

    private func makeRedPill(text: String) -> UIView {
        let pill = UILabel()
        pill.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .kern: 3.2,
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

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pill)
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 32),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
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
            pill.heightAnchor.constraint(equalToConstant: 30),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
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

    // MARK: - Actions

    @objc private func replyTapped(_ sender: UIControl) {
        guard let text = sender.accessibilityValue else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // THE LANDING — drops the reply straight into the iMessage
        // compose box. User taps Send (one tap) and the message goes.
        activeConversation?.insertText(text, completionHandler: nil)
        resetToWaiting()
    }

    @objc private func resetToWaiting() {
        state = .waiting
        if scanner.hasAccess { startPolling() }
    }
}

private extension RizzError {
    var userMessage: String {
        switch self {
        case .network(let m):  return "Network issue · \(m.prefix(48))"
        case .decode(let m):   return "Bad response · \(m.prefix(48))"
        }
    }
}
