import UIKit
import Social

class ShareViewController: UIViewController {

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let sourceLabel = UILabel()
    private let sourceTextView = UITextView()

    private let buttonStack = UIStackView()
    private let translateBtn = UIButton(type: .system)
    private let summarizeBtn = UIButton(type: .system)
    private let explainBtn = UIButton(type: .system)
    private let refineBtn = UIButton(type: .system)

    private let resultContainer = UIView()
    private let resultTextView = UITextView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private let errorLabel = UILabel()

    private let copyButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    // MARK: - State

    private let api = APIClient()
    private var sourceText = ""
    private var resultText = ""
    private var isPro = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigation()
        setupUI()

        isPro = AppGroupStore.shared.plan != "free"

        extractSharedText()
    }

    // MARK: - Navigation

    private func setupNavigation() {
        navigationController?.isNavigationBarHidden = false
        navigationItem.title = "TransKey"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "✕", style: .plain, target: self, action: #selector(closeTapped)
        )
    }

    // MARK: - UI Setup

    private func setupUI() {
        let primary = UIColor(red: 0.42, green: 0.39, blue: 1.0, alpha: 1.0) // #6C63FF
        let secondaryLabel = UIColor.secondaryLabel

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.fillSuperview()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        // Source header
        sourceLabel.text = "Source text"
        sourceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sourceLabel.textColor = secondaryLabel
        stack.addArrangedSubview(sourceLabel)

        // Source text
        sourceTextView.isEditable = false
        sourceTextView.isScrollEnabled = false
        sourceTextView.font = .systemFont(ofSize: 15)
        sourceTextView.textColor = .label
        sourceTextView.backgroundColor = .secondarySystemBackground
        sourceTextView.layer.cornerRadius = 12
        sourceTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        sourceTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        stack.addArrangedSubview(sourceTextView)

        // Feature buttons
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        configureButton(translateBtn, title: "Translate", icon: "doc.text.magnifyingglass", color: primary, enabled: true)
        configureButton(summarizeBtn, title: "Summarize", icon: "list.bullet.clipboard", color: primary, enabled: isPro)
        configureButton(explainBtn, title: "Explain", icon: "lightbulb", color: primary, enabled: isPro)
        configureButton(refineBtn, title: "Refine", icon: "wand.and.stars", color: primary, enabled: isPro)

        translateBtn.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        summarizeBtn.addTarget(self, action: #selector(summarizeTapped), for: .touchUpInside)
        explainBtn.addTarget(self, action: #selector(explainTapped), for: .touchUpInside)
        refineBtn.addTarget(self, action: #selector(refineTapped), for: .touchUpInside)

        buttonStack.addArrangedSubview(translateBtn)
        buttonStack.addArrangedSubview(summarizeBtn)
        buttonStack.addArrangedSubview(explainBtn)
        buttonStack.addArrangedSubview(refineBtn)
        stack.addArrangedSubview(buttonStack)

        // Error
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)

        // Activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(activityIndicator)

        // Result container
        resultContainer.backgroundColor = primary.withAlphaComponent(0.08)
        resultContainer.layer.cornerRadius = 12
        resultContainer.isHidden = true

        resultTextView.isEditable = false
        resultTextView.font = .systemFont(ofSize: 16)
        resultTextView.textColor = primary
        resultTextView.backgroundColor = .clear
        resultTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        resultTextView.isScrollEnabled = false

        resultContainer.addSubview(resultTextView)
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resultTextView.topAnchor.constraint(equalTo: resultContainer.topAnchor),
            resultTextView.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
            resultTextView.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),
            resultTextView.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor),
        ])

        stack.addArrangedSubview(resultContainer)

        // Action buttons
        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.distribution = .fillEqually
        actionStack.spacing = 8

        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        copyButton.backgroundColor = primary
        copyButton.setTitleColor(.white, for: .normal)
        copyButton.layer.cornerRadius = 12
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        copyButton.isHidden = true

        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.backgroundColor = .secondarySystemFill
        closeButton.setTitleColor(.label, for: .normal)
        closeButton.layer.cornerRadius = 12
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let btnHeight: CGFloat = 48
        copyButton.heightAnchor.constraint(equalToConstant: btnHeight).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: btnHeight).isActive = true

        actionStack.addArrangedSubview(copyButton)
        actionStack.addArrangedSubview(closeButton)
        stack.addArrangedSubview(actionStack)
    }

    private func configureButton(_ btn: UIButton, title: String, icon: String, color: UIColor, enabled: Bool) {
        let config = UIButton.Configuration.filled()
        btn.configuration = config
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        btn.backgroundColor = enabled ? color.withAlphaComponent(0.12) : UIColor.separator
        btn.setTitleColor(enabled ? color : .tertiaryLabel, for: .normal)
        btn.layer.cornerRadius = 12
        btn.isEnabled = enabled
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    // MARK: - Extract shared text

    private func extractSharedText() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            sourceTextView.text = "No text found"
            return
        }

        let textType = kUTTypePlainText as String
        if itemProvider.hasItemConformingToTypeIdentifier(textType) {
            itemProvider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if let text = item as? String {
                        self?.sourceText = text
                        self?.sourceTextView.text = text
                    } else if let url = item as? URL,
                              let text = try? String(contentsOf: url, encoding: .utf8) {
                        self?.sourceText = text
                        self?.sourceTextView.text = text
                    } else {
                        self?.sourceTextView.text = "Could not read text"
                    }
                }
            }
        } else {
            // Try URL type
            let urlType = kUTTypeURL as String
            itemProvider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if let url = item as? URL {
                        self?.sourceText = url.absoluteString
                        self?.sourceTextView.text = url.absoluteString
                    } else {
                        self?.sourceTextView.text = "No text found"
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func translateTapped() {
        performAPI { [weak self] in
            try await self?.api.translate(text: self!.sourceText, targetLang: "en") ?? [:]
        }
    }

    @objc private func summarizeTapped() {
        performAPI { [weak self] in
            try await self?.api.summarize(text: self!.sourceText, targetLang: "en") ?? [:]
        }
    }

    @objc private func explainTapped() {
        performAPI { [weak self] in
            try await self?.api.explain(text: self!.sourceText, targetLang: "en") ?? [:]
        }
    }

    @objc private func refineTapped() {
        performAPI { [weak self] in
            try await self?.api.refine(text: self!.sourceText) ?? [:]
        }
    }

    private func performAPI(_ action: @escaping () async throws -> [String: Any]) {
        guard !sourceText.isEmpty else { return }

        setLoading(true)
        errorLabel.isHidden = true
        resultContainer.isHidden = true
        copyButton.isHidden = true

        Task { @MainActor in
            do {
                let json = try await action()
                let translation = json["translation"] as? String
                    ?? json["result"] as? String
                    ?? json["summary"] as? String
                    ?? json["explanation"] as? String
                    ?? json["refined"] as? String
                    ?? ""

                resultText = translation
                resultTextView.text = translation
                resultContainer.isHidden = false
                copyButton.isHidden = false
            } catch let error as APIError {
                errorLabel.text = error.errorDescription
                errorLabel.isHidden = false
            } catch {
                errorLabel.text = error.localizedDescription
                errorLabel.isHidden = false
            }
            setLoading(false)
        }
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = resultText
        copyButton.setTitle("Copied!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.setTitle("Copy", for: .normal)
        }
    }

    @objc private func closeTapped() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    // MARK: - Helpers

    private func setLoading(_ loading: Bool) {
        if loading {
            activityIndicator.startAnimating()
            setButtonsEnabled(false)
        } else {
            activityIndicator.stopAnimating()
            setButtonsEnabled(true)
        }
    }

    private func setButtonsEnabled(_ enabled: Bool) {
        translateBtn.isEnabled = enabled
        if isPro {
            summarizeBtn.isEnabled = enabled
            explainBtn.isEnabled = enabled
            refineBtn.isEnabled = enabled
        }
    }
}

// MARK: - Auto Layout helper

extension UIView {
    func fillSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        if let superview = superview {
            NSLayoutConstraint.activate([
                topAnchor.constraint(equalTo: superview.topAnchor),
                leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            ])
        }
    }
}
