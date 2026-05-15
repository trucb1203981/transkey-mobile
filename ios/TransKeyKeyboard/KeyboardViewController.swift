import UIKit

class KeyboardViewController: UIInputViewController {

    // MARK: - State

    private var isPro = false
    private var resultPanelVisible = false
    private var lastResult = ""
    private var lastSource = ""
    private var selectedLang = "en"
    // Snapshot of full input text taken right before an auto-insert, so the
    // Undo banner can restore it.
    private var undoSnapshot: String?
    private var undoTimer: Timer?

    private let api = APIClient()

    // MARK: - UI Elements

    private var mainStack: UIStackView!
    private var toolbar: UIStackView!
    private var resultPanel: UIView!
    private var resultSourceLabel: UILabel!
    private var resultLabel: UILabel!
    private var resultErrorLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!
    private var insertBtn: UIButton!
    private var undoBtn: UIButton!
    private var keyboardRows: [UIStackView] = []

    private let primaryColor = UIColor(red: 0.42, green: 0.39, blue: 1.0, alpha: 1.0)
    private let keyBg = UIColor(white: 1.0, alpha: 1.0)
    private let keySpecialBg = UIColor(white: 0.85, alpha: 1.0)
    private let keyCharBg = UIColor(white: 0.95, alpha: 1.0)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        isPro = AppGroupStore.shared.plan != "free"
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasFullAccess {
            showAccessOverlay()
        }
    }

    // MARK: - Full Access Check

    private var hasFullAccess: Bool {
        return OpenAccessChecker.hasFullAccess(self)
    }

    private func showAccessOverlay() {
        view.subviews.forEach { $0.removeFromSuperview() }

        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.systemBackground
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -24),
        ])

        let icon = UILabel()
        icon.text = "🔒"
        icon.font = .systemFont(ofSize: 48)
        stack.addArrangedSubview(icon)

        let title = UILabel()
        title.text = "Full Access Required"
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textAlignment = .center
        stack.addArrangedSubview(title)

        let desc = UILabel()
        desc.text = "To use TransKey Keyboard, please enable Full Access:\n\nSettings → General → Keyboard → Keyboards → TransKey → Allow Full Access"
        desc.font = .systemFont(ofSize: 14)
        desc.textColor = .secondaryLabel
        desc.numberOfLines = 0
        desc.textAlignment = .center
        stack.addArrangedSubview(desc)

        view.addSubview(overlay)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.92, alpha: 1.0)

        mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupToolbar()
        setupResultPanel()
        setupQwerty()
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        toolbar = UIStackView()
        toolbar.axis = .horizontal
        toolbar.distribution = .fill
        toolbar.spacing = 0
        toolbar.backgroundColor = UIColor(white: 0.95, alpha: 1.0)

        let translateBtn = toolbarButton(title: "🌐 Dịch", action: #selector(translateTapped))
        let replyBtn = toolbarButton(title: "↩️ Reply", action: #selector(replyTapped))
        let refineBtn = toolbarButton(title: "✨ Refine", action: #selector(refineTapped))
        refineBtn.isEnabled = isPro
        refineBtn.alpha = isPro ? 1.0 : 0.4
        let nextBtn = toolbarButton(title: "▼", action: #selector(nextKeyboardTapped))

        toolbar.addArrangedSubview(translateBtn)
        toolbar.addArrangedSubview(replyBtn)
        toolbar.addArrangedSubview(refineBtn)
        toolbar.addArrangedSubview(nextBtn)

        let separator = UIView()
        separator.backgroundColor = UIColor.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        mainStack.addArrangedSubview(toolbar)
        mainStack.addArrangedSubview(separator)
    }

    private func toolbarButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.setTitleColor(primaryColor, for: .normal)
        btn.setTitleColor(UIColor.placeholderText, for: .disabled)
        btn.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return btn
    }

    // MARK: - Result Panel

    private func setupResultPanel() {
        resultPanel = UIView()
        resultPanel.backgroundColor = UIColor.systemBackground
        resultPanel.isHidden = true
        resultPanel.translatesAutoresizingMaskIntoConstraints = false
        resultPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        resultPanel.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: resultPanel.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: resultPanel.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: resultPanel.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: resultPanel.bottomAnchor, constant: -8),
        ])

        // Source (dimmed)
        resultSourceLabel = UILabel()
        resultSourceLabel.font = .systemFont(ofSize: 13)
        resultSourceLabel.textColor = .tertiaryLabel
        resultSourceLabel.numberOfLines = 2
        stack.addArrangedSubview(resultSourceLabel)

        // Arrow
        let arrow = UILabel()
        arrow.text = "↓"
        arrow.font = .systemFont(ofSize: 12)
        arrow.textColor = .tertiaryLabel
        stack.addArrangedSubview(arrow)

        // Result (bold)
        resultLabel = UILabel()
        resultLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        resultLabel.textColor = primaryColor
        resultLabel.numberOfLines = 0
        stack.addArrangedSubview(resultLabel)

        // Error
        resultErrorLabel = UILabel()
        resultErrorLabel.font = .systemFont(ofSize: 13)
        resultErrorLabel.textColor = .systemRed
        resultErrorLabel.numberOfLines = 0
        resultErrorLabel.isHidden = true
        stack.addArrangedSubview(resultErrorLabel)

        // Loading
        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = primaryColor
        stack.addArrangedSubview(activityIndicator)

        // Action buttons row
        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.spacing = 12

        insertBtn = smallButton(title: "Insert", action: #selector(insertTapped))
        undoBtn = smallButton(title: "↶ Undo", action: #selector(undoTapped))
        undoBtn.isHidden = true
        let copyBtn = smallButton(title: "Copy", action: #selector(copyResultTapped))
        let closeBtn = smallButton(title: "✕", action: #selector(closeResultTapped))

        actionStack.addArrangedSubview(insertBtn)
        actionStack.addArrangedSubview(undoBtn)
        actionStack.addArrangedSubview(copyBtn)
        actionStack.addArrangedSubview(closeBtn)
        actionStack.addArrangedSubview(UIView()) // spacer
        stack.addArrangedSubview(actionStack)

        let separator = UIView()
        separator.backgroundColor = UIColor.separator
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        mainStack.addArrangedSubview(resultPanel)
        mainStack.addArrangedSubview(separator)
    }

    private func smallButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.setTitleColor(primaryColor, for: .normal)
        btn.backgroundColor = primaryColor.withAlphaComponent(0.1)
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - QWERTY Keyboard

    private func setupQwerty() {
        let rows = [
            ["q","w","e","r","t","y","u","i","o","p"],
            ["a","s","d","f","g","h","j","k","l"],
            ["⇧","z","x","c","v","b","n","m","⌫"],
            ["123","🌐","space","." ,"return"],
        ]

        let keyHeight: CGFloat = 42

        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 2
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            rowStack.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true

            for key in row {
                let btn = UIButton(type: .system)
                btn.setTitle(key, for: .normal)
                btn.titleLabel?.font = key.count == 1
                    ? .systemFont(ofSize: 18)
                    : .systemFont(ofSize: 13, weight: .medium)
                btn.backgroundColor = isSpecialKey(key) ? keySpecialBg : keyCharBg
                btn.setTitleColor(.label, for: .normal)
                btn.layer.cornerRadius = 5
                btn.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                btn.tag = key == "space" ? 1 : 0
                rowStack.addArrangedSubview(btn)
            }

            keyboardRows.append(rowStack)
            mainStack.addArrangedSubview(rowStack)
        }
    }

    private func isSpecialKey(_ key: String) -> Bool {
        ["⇧", "⌫", "123", "🌐", "space", ".", "return"].contains(key)
    }

    // MARK: - Key Handling

    @objc private func keyTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }

        switch title {
        case "space":
            textDocumentProxy.insertText(" ")
        case "⌫":
            if let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty {
                textDocumentProxy.deleteBackward()
            }
        case "return":
            textDocumentProxy.insertText("\n")
        case "⇧":
            sender.isSelected.toggle()
            sender.backgroundColor = sender.isSelected ? primaryColor : keySpecialBg
            sender.setTitleColor(sender.isSelected ? .white : .label, for: .normal)
        case "🌐":
            advanceToNextInputMode()
        case "123":
            break // TODO: number/symbol keyboard
        case ".":
            textDocumentProxy.insertText(".")
        default:
            if sender.isSelected { // shift active = uppercase
                textDocumentProxy.insertText(title.uppercased())
            } else {
                textDocumentProxy.insertText(title)
            }
        }
    }

    // MARK: - Toolbar Actions

    @objc private func translateTapped() {
        // Read clipboard
        guard let clipboard = UIPasteboard.general.string, !clipboard.isEmpty else {
            showResultError("Clipboard is empty. Copy some text first.")
            return
        }

        showResultPanel(source: clipboard)
        setLoading(true)

        Task { @MainActor in
            do {
                let json = try await api.translate(text: clipboard, targetLang: selectedLang)
                let translation = extractTranslation(json)
                lastResult = translation
                lastSource = clipboard
                showResult(source: clipboard, result: translation)
            } catch {
                showResultError(error.localizedDescription)
            }
            setLoading(false)
        }
    }

    @objc private func replyTapped() {
        let fullText = (textDocumentProxy.documentContextBeforeInput ?? "")
            + (textDocumentProxy.documentContextAfterInput ?? "")
        guard !fullText.isEmpty else {
            showResultError("No text in input field.")
            return
        }

        showResultPanel(source: fullText)
        setLoading(true)

        Task { @MainActor in
            do {
                let json = try await api.translate(
                    text: fullText,
                    targetLang: selectedLang,
                    sourceLang: nil,
                    isReply: true
                )
                let translation = extractTranslation(json)
                lastResult = translation
                lastSource = fullText
                showResult(source: fullText, result: translation)
                autoInsertReply(originalText: fullText, replyText: translation)
            } catch {
                showResultError(error.localizedDescription)
            }
            setLoading(false)
        }
    }

    /// Replace the entire input with the reply, then offer a 5s Undo.
    private func autoInsertReply(originalText: String, replyText: String) {
        guard !replyText.isEmpty else { return }
        undoSnapshot = originalText
        textDocumentProxy.selectAll(nil)
        textDocumentProxy.insertText(replyText)
        resultSourceLabel.text = "✓ Replied — input replaced"
        insertBtn.isHidden = true
        undoBtn.isHidden = false
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.clearUndoState()
        }
    }

    private func clearUndoState() {
        undoSnapshot = nil
        undoTimer?.invalidate()
        undoTimer = nil
        undoBtn.isHidden = true
        insertBtn.isHidden = false
    }

    @objc private func undoTapped() {
        guard let snapshot = undoSnapshot else { return }
        textDocumentProxy.selectAll(nil)
        textDocumentProxy.insertText(snapshot)
        clearUndoState()
        closeResultTapped()
    }

    @objc private func refineTapped() {
        guard isPro else { return }
        guard let context = textDocumentProxy.documentContextBeforeInput,
              !context.isEmpty else {
            showResultError("No text in input field.")
            return
        }

        showResultPanel(source: context)
        setLoading(true)

        Task { @MainActor in
            do {
                let json = try await api.refine(text: context)
                let refined = extractTranslation(json)
                lastResult = refined
                lastSource = context
                showResult(source: context, result: refined)
            } catch {
                showResultError(error.localizedDescription)
            }
            setLoading(false)
        }
    }

    @objc private func nextKeyboardTapped() {
        advanceToNextInputMode()
    }

    // MARK: - Result Panel Actions

    @objc private func insertTapped() {
        guard !lastResult.isEmpty else { return }
        // Select all existing text and replace
        textDocumentProxy.selectAll(nil)
        textDocumentProxy.insertText(lastResult)
        closeResultTapped()
    }

    @objc private func copyResultTapped() {
        UIPasteboard.general.string = lastResult
    }

    @objc private func closeResultTapped() {
        resultPanel.isHidden = true
        resultPanelVisible = false
        undoTimer?.invalidate()
        undoTimer = nil
        undoBtn?.isHidden = true
        insertBtn?.isHidden = false
        undoSnapshot = nil
    }

    // MARK: - Result Helpers

    private func showResultPanel(source: String) {
        resultPanel.isHidden = false
        resultPanelVisible = true
        resultSourceLabel.text = String(source.prefix(100))
        resultLabel.text = ""
        resultErrorLabel.isHidden = true
    }

    private func showResult(source: String, result: String) {
        resultSourceLabel.text = String(source.prefix(100))
        resultLabel.text = result
        resultErrorLabel.isHidden = true
    }

    private func showResultError(_ message: String) {
        if !resultPanelVisible {
            resultPanel.isHidden = false
            resultPanelVisible = true
            resultSourceLabel.text = ""
        }
        resultLabel.text = ""
        resultErrorLabel.text = message
        resultErrorLabel.isHidden = false
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func extractTranslation(_ json: [String: Any]) -> String {
        return json["translation"] as? String
            ?? json["result"] as? String
            ?? json["summary"] as? String
            ?? json["explanation"] as? String
            ?? json["refined"] as? String
            ?? ""
    }
}

/// Helper to check full access without recursive property.
private class OpenAccessChecker {
    @MainActor static func hasFullAccess(_ controller: UIInputViewController) -> Bool {
        // UIInputViewController.hasFullAccess is available from iOS 11+
        if #available(iOS 11.0, *) {
            return controller.hasFullAccess
        }
        return true
    }
}
