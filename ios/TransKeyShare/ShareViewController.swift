import UIKit
import Social
import Vision
import UniformTypeIdentifiers
import ImageIO

/// Share-sheet card: receives text, URLs or IMAGES (the iOS replacement for
/// Android's screen translate - screenshot, share to TransKey, on-device OCR
/// via Vision, then translate).
class ShareViewController: UIViewController {

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let imagePreview = UIImageView()
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
    // Per-feature gates mirrored from features_provider.dart via the App
    // Group — the SAME server-driven flags the home buttons use (admin can
    // flip per plan via /admin/features), never a hardcoded plan check.
    private var canSummarize = false
    private var canExplain = false
    private var canRefine = false

    // MARK: - Theme (mirrors lib/shared/theme/app_theme.dart AppColors)

    private enum TKTheme {
        static let primary = UIColor(red: 0.424, green: 0.388, blue: 1.0, alpha: 1)      // #6C63FF
        static let red = UIColor(red: 1.0, green: 0.420, blue: 0.420, alpha: 1)          // #FF6B6B
        static let bg = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 1)                   // #0E0E11
            : UIColor(red: 0.961, green: 0.949, blue: 0.933, alpha: 1) }                 // #F5F2EE
        static let surface = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1)                   // #16161A
            : .white }
        static let border = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.165, blue: 0.208, alpha: 1)                   // #2A2A35
            : UIColor(red: 0.898, green: 0.882, blue: 0.859, alpha: 1) }                 // #E5E1DB
        static let textPrimary = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.910, green: 0.910, blue: 0.941, alpha: 1)                   // #E8E8F0
            : UIColor(red: 0.102, green: 0.102, blue: 0.180, alpha: 1) }                 // #1A1A2E
        static let textSecondary = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.533, green: 0.533, blue: 0.627, alpha: 1)                   // #8888A0
            : UIColor(red: 0.420, green: 0.447, blue: 0.502, alpha: 1) }                 // #6B7280
        static let cardRadius: CGFloat = 16   // AppSpacing.cardRadius
        static let buttonRadius: CGFloat = 12 // AppSpacing.buttonRadius
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = TKTheme.bg

        // Read the mirrored feature flags BEFORE setupUI — the buttons take
        // their enabled state at configure time (the legacy code read the
        // plan after setupUI, so every gated button rendered disabled).
        let store = AppGroupStore.shared
        canSummarize = store.featureSummarize
        canExplain = store.featureExplain
        canRefine = store.featureRefine

        setupNavigation()
        setupUI()
        extractSharedContent()
    }

    // MARK: - Navigation

    private func setupNavigation() {
        navigationController?.isNavigationBarHidden = false
        navigationItem.title = "TransKey"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "✕", style: .plain, target: self, action: #selector(closeTapped)
        )
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = TKTheme.bg
        appearance.titleTextAttributes = [.foregroundColor: TKTheme.textPrimary]
        appearance.shadowColor = .clear
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = TKTheme.primary
    }

    // MARK: - UI Setup

    private func setupUI() {
        let primary = TKTheme.primary
        let secondaryLabel = TKTheme.textSecondary

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

        // Screenshot preview (hidden unless an image was shared)
        imagePreview.contentMode = .scaleAspectFill
        imagePreview.clipsToBounds = true
        imagePreview.layer.cornerRadius = TKTheme.cardRadius
        imagePreview.isHidden = true
        imagePreview.heightAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(imagePreview)

        // Source header
        sourceLabel.text = "Source text"
        sourceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sourceLabel.textColor = secondaryLabel
        stack.addArrangedSubview(sourceLabel)

        // Source text
        sourceTextView.isEditable = false
        sourceTextView.isScrollEnabled = false
        sourceTextView.font = .systemFont(ofSize: 15)
        sourceTextView.textColor = TKTheme.textPrimary
        sourceTextView.backgroundColor = TKTheme.surface
        sourceTextView.layer.cornerRadius = TKTheme.cardRadius
        sourceTextView.layer.borderWidth = 1
        sourceTextView.layer.borderColor = TKTheme.border.cgColor
        sourceTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        sourceTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        stack.addArrangedSubview(sourceTextView)

        // Feature buttons
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        configureButton(translateBtn, title: "Translate", icon: "doc.text.magnifyingglass", color: primary, enabled: true)
        configureButton(summarizeBtn, title: "Summarize", icon: "list.bullet.clipboard", color: primary, enabled: canSummarize)
        configureButton(explainBtn, title: "Explain", icon: "lightbulb", color: primary, enabled: canExplain)
        configureButton(refineBtn, title: "Refine", icon: "wand.and.stars", color: primary, enabled: canRefine)

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
        errorLabel.textColor = TKTheme.red
        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)

        // Activity indicator
        activityIndicator.color = TKTheme.primary
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(activityIndicator)

        // Result container — surface card with a primary-tinted border, the
        // result text in normal text color (matches the home result sheet;
        // primary-on-primary was hard to read).
        resultContainer.backgroundColor = TKTheme.surface
        resultContainer.layer.cornerRadius = TKTheme.cardRadius
        resultContainer.layer.borderWidth = 1
        resultContainer.layer.borderColor = primary.withAlphaComponent(0.45).cgColor
        resultContainer.isHidden = true

        resultTextView.isEditable = false
        resultTextView.font = .systemFont(ofSize: 16)
        resultTextView.textColor = TKTheme.textPrimary
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
        copyButton.layer.cornerRadius = TKTheme.buttonRadius
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        copyButton.isHidden = true

        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.backgroundColor = TKTheme.surface
        closeButton.setTitleColor(TKTheme.textPrimary, for: .normal)
        closeButton.layer.cornerRadius = TKTheme.buttonRadius
        closeButton.layer.borderWidth = 1
        closeButton.layer.borderColor = TKTheme.border.cgColor
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let btnHeight: CGFloat = 48
        copyButton.heightAnchor.constraint(equalToConstant: btnHeight).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: btnHeight).isActive = true

        actionStack.addArrangedSubview(copyButton)
        actionStack.addArrangedSubview(closeButton)
        stack.addArrangedSubview(actionStack)
    }

    private func configureButton(_ btn: UIButton, title: String, icon: String, color: UIColor, enabled: Bool) {
        // Plain UIButton, NOT UIButton.Configuration.filled() — the filled
        // configuration paints its own tint-blue background over the theme
        // colors set below.
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        btn.titleLabel?.adjustsFontSizeToFitWidth = true
        btn.titleLabel?.minimumScaleFactor = 0.7
        btn.titleLabel?.numberOfLines = 1
        btn.backgroundColor = enabled ? color.withAlphaComponent(0.16) : TKTheme.surface
        btn.setTitleColor(enabled ? color : TKTheme.textSecondary.withAlphaComponent(0.5), for: .normal)
        btn.layer.cornerRadius = TKTheme.buttonRadius
        btn.layer.borderWidth = enabled ? 0 : 1
        btn.layer.borderColor = TKTheme.border.cgColor
        btn.isEnabled = enabled
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    // MARK: - Extract shared content (text, URL or screenshot)

    private func extractSharedContent() {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        guard !attachments.isEmpty else {
            sourceTextView.text = "No text found"
            return
        }

        // An image wins over text: the screenshot-share flow is the whole
        // point of this extension on iOS.
        if let imageProvider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            extractImage(from: imageProvider)
            return
        }

        if let textProvider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if let text = item as? String {
                        self?.setSource(text)
                        // Same zero-tap convenience as the screenshot flow:
                        // the user shared text TO a translator — translate.
                        self?.translateTapped()
                    } else if let url = item as? URL,
                              let text = try? String(contentsOf: url, encoding: .utf8) {
                        self?.setSource(text)
                        self?.translateTapped()
                    } else {
                        self?.sourceTextView.text = "Could not read text"
                    }
                }
            }
            return
        }

        if let urlProvider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if let url = item as? URL {
                        self?.setSource(url.absoluteString)
                    } else {
                        self?.sourceTextView.text = "No text found"
                    }
                }
            }
            return
        }

        sourceTextView.text = "No text found"
    }

    private func setSource(_ text: String) {
        sourceText = text
        sourceTextView.text = text
    }

    // MARK: - Screenshot OCR (Vision, on-device)

    /// Share extensions are jetsamed at ~120MB; a 12MP photo decoded at full
    /// resolution plus the Vision model already exceeds that. Decode straight
    /// to a capped-size bitmap via ImageIO so the full-res image never exists.
    /// 1536 (not 2048): Vision .accurate peaks >110MB on a 2048px image on
    /// 3GB devices (iPhone X) - measured jetsam at the 120MB cap.
    private static let maxOCRPixelSize: CGFloat = 1536

    private static func downsample(url: URL? = nil, data: Data? = nil) -> CGImage? {
        let sourceOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        let source: CGImageSource?
        if let url {
            source = CGImageSourceCreateWithURL(url as CFURL, sourceOpts)
        } else if let data {
            source = CGImageSourceCreateWithData(data as CFData, sourceOpts)
        } else {
            source = nil
        }
        guard let source else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxOCRPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts) else {
            return nil
        }
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            return cropScreenshotChrome(image, originalSize: CGSize(width: w, height: h))
        }
        return image
    }

    /// Screenshots carry the status bar (clock, battery, "100") and the
    /// home-indicator strip; OCR happily reads that chrome and pollutes the
    /// result (Android parity: status-bar crop before OCR). Fires ONLY when
    /// the image pixel size exactly matches this device's portrait screen,
    /// i.e. a screenshot taken on this phone — regular photos are untouched.
    private static func cropScreenshotChrome(_ image: CGImage, originalSize: CGSize) -> CGImage {
        let native = UIScreen.main.nativeBounds.size // portrait pixels
        let isPortraitScreenshot = originalSize == native
        guard isPortraitScreenshot else { return image }

        let screenHpts = max(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        // Notched/Dynamic-Island devices: status area 44-59pt -> 60pt crop;
        // home-bar devices also reserve ~24pt at the bottom. Older devices:
        // 20pt status bar, no home bar.
        let notched = screenHpts >= 812
        let topPts: CGFloat = notched ? 60 : 24
        let bottomPts: CGFloat = notched ? 24 : 0
        let h = CGFloat(image.height)
        let topPx = (topPts / screenHpts * h).rounded()
        let bottomPx = (bottomPts / screenHpts * h).rounded()
        let rect = CGRect(x: 0, y: topPx,
                          width: CGFloat(image.width),
                          height: h - topPx - bottomPx)
        guard rect.height > 50, let cropped = image.cropping(to: rect) else { return image }
        return cropped
    }

    private static func downsample(image: UIImage) -> CGImage? {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let scale = min(1, maxOCRPixelSize / max(w, h))
        if scale >= 1 { return image.cgImage }
        let size = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.cgImage
    }

    private func extractImage(from provider: NSItemProvider) {
        sourceTextView.text = "Đang đọc chữ trong ảnh..."
        activityIndicator.startAnimating()
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
            let cgImage: CGImage?
            if let url = item as? URL {
                cgImage = Self.downsample(url: url)
            } else if let img = item as? UIImage {
                cgImage = Self.downsample(image: img)
            } else if let data = item as? Data {
                cgImage = Self.downsample(data: data)
            } else {
                cgImage = nil
            }
            DispatchQueue.main.async {
                guard let cgImage else {
                    self?.activityIndicator.stopAnimating()
                    self?.sourceTextView.text = "Could not read image"
                    return
                }
                self?.imagePreview.image = UIImage(cgImage: cgImage)
                self?.imagePreview.isHidden = false
                self?.runOCR(on: cgImage)
            }
        }
    }

    private func runOCR(on cgImage: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            let lines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.activityIndicator.stopAnimating()
                if let error {
                    self.errorLabel.text = error.localizedDescription
                    self.errorLabel.isHidden = false
                    self.sourceTextView.text = ""
                    return
                }
                let text = lines.joined(separator: "\n")
                guard !text.isEmpty else {
                    self.sourceTextView.text = "No text found in image"
                    return
                }
                self.setSource(text)
                // Screenshot shared to translate: go straight to the result,
                // no extra tap.
                self.translateTapped()
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = ["vi-VT", "en-US"]
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Actions

    /// The pair the user picked in the app (mirrored via the App Group).
    private var targetLang: String { AppGroupStore.shared.targetLang }

    @objc private func translateTapped() {
        performAPI { [weak self] in
            guard let self else { return [:] }
            return try await self.api.translate(
                text: self.sourceText,
                targetLang: self.targetLang,
                sourceLang: AppGroupStore.shared.sourceLang
            )
        }
    }

    @objc private func summarizeTapped() {
        performAPI { [weak self] in
            guard let self else { return [:] }
            return try await self.api.summarize(text: self.sourceText, targetLang: self.targetLang)
        }
    }

    @objc private func explainTapped() {
        performAPI { [weak self] in
            guard let self else { return [:] }
            return try await self.api.explain(text: self.sourceText, targetLang: self.targetLang)
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
        if canSummarize { summarizeBtn.isEnabled = enabled }
        if canExplain { explainBtn.isEnabled = enabled }
        if canRefine { refineBtn.isEnabled = enabled }
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
