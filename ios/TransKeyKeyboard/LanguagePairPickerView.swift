import UIKit

/// In-keyboard language picker, styled like an iOS inset-grouped settings
/// table - the closest native look inside a keyboard panel. Two modes:
///  - .pair: source/target translate languages in TWO side-by-side columns
///    (source left with Auto on top, target right) like the Android picker,
///    plus a swap button. Writes to the App Group and raises the dirty flag
///    so the app adopts the change on next resume.
///  - .typing: the keyboard's input language (one column, native layouts)
/// Both modes auto-scroll to the current selection on open.
final class LanguagePairPickerView: UIView, UITableViewDataSource, UITableViewDelegate {

    enum Mode {
        case pair
        case typing(current: String)
    }

    /// Built-in fallback, same as the app's Language model. Used only until
    /// the app has mirrored the server catalog (pre-login first run).
    static let fallbackLanguages: [(code: String, name: String)] = [
        ("vi", "Tiếng Việt"), ("en", "English"), ("ja", "日本語"), ("zh", "中文"),
        ("ko", "한국어"), ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"),
        ("ru", "Русский"), ("th", "ไทย"), ("id", "Bahasa Indonesia"),
        ("pt", "Português"), ("it", "Italiano"), ("ar", "العربية"), ("hi", "हिन्दी"),
    ]

    /// Effective list: the server catalog mirrored into the App Group
    /// (`[{code,label}, ...]`, admin-managed - the SAME source the Android
    /// bubble/keyboard pickers parse), else the built-in fallback. Catalog
    /// order is preserved, like Android.
    static func loadLanguages() -> [(code: String, name: String)] {
        guard let raw = AppGroupStore.shared.langCatalogJSON,
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return fallbackLanguages
        }
        let parsed: [(String, String)] = arr.compactMap { obj in
            guard let code = obj["code"] as? String, !code.isEmpty else { return nil }
            let label = (obj["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? code
            return (code, label)
        }
        return parsed.isEmpty ? fallbackLanguages : parsed
    }

    /// Languages the keyboard can type natively (layout + composer). VI+EN
    /// first, then A→Z by English name - the Android picker order. The Latin
    /// languages share the QWERTY layout with the long-press accent popup,
    /// exactly like Android's DE/ES/FR/ID/IT/PT modes.
    static let typingLanguages: [(code: String, name: String)] = [
        ("vi", "Tiếng Việt"), ("en", "English"),
        ("ar", "العربية"), ("zh", "中文 (拼音)"), ("fr", "Français"), ("de", "Deutsch"),
        ("id", "Bahasa Indonesia"), ("it", "Italiano"), ("ja", "日本語 (ローマ字)"),
        ("ja_flick", "日本語 (フリック)"),
        ("ko", "한국어"), ("pt", "Português"), ("ru", "Русский"), ("es", "Español"), ("th", "ไทย"),
    ]

    var onDone: (() -> Void)?
    var onChanged: (() -> Void)?
    var onTypingPicked: ((String) -> Void)?

    private let mode: Mode
    private var typingSelection: String
    private let languages = LanguagePairPickerView.loadLanguages()
    // .typing uses the single table; .pair uses the two column tables.
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let srcTable = UITableView(frame: .zero, style: .insetGrouped)
    private let tgtTable = UITableView(frame: .zero, style: .insetGrouped)
    private var didAutoScroll = false

    init(mode: Mode) {
        self.mode = mode
        if case .typing(let current) = mode {
            typingSelection = current
        } else {
            typingSelection = ""
        }
        super.init(frame: .zero)
        backgroundColor = .systemGroupedBackground

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        let title = UILabel()
        if case .typing = mode {
            title.text = KB.t("typingLanguage")
        } else {
            title.text = KB.t("translationLanguage")
        }
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)

        let done = UIButton(type: .system)
        done.setTitle(KB.t("done"), for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(done)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            done.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
        ])

        if case .typing = mode {
            configure(table)
            addSubview(table)
            NSLayoutConstraint.activate([
                table.topAnchor.constraint(equalTo: header.bottomAnchor),
                table.leadingAnchor.constraint(equalTo: leadingAnchor),
                table.trailingAnchor.constraint(equalTo: trailingAnchor),
                table.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            // Swap button between the title and Done, Android's "⇄ Đổi chiều".
            let swap = UIButton(type: .system)
            swap.setTitle(KB.t("swap"), for: .normal)
            swap.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            swap.addTarget(self, action: #selector(swapTapped), for: .touchUpInside)
            swap.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(swap)
            NSLayoutConstraint.activate([
                swap.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                swap.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -16),
            ])

            configure(srcTable)
            configure(tgtTable)
            let divider = UIView()
            divider.backgroundColor = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            addSubview(srcTable)
            addSubview(tgtTable)
            addSubview(divider)
            NSLayoutConstraint.activate([
                srcTable.topAnchor.constraint(equalTo: header.bottomAnchor),
                srcTable.leadingAnchor.constraint(equalTo: leadingAnchor),
                srcTable.bottomAnchor.constraint(equalTo: bottomAnchor),
                tgtTable.topAnchor.constraint(equalTo: header.bottomAnchor),
                tgtTable.trailingAnchor.constraint(equalTo: trailingAnchor),
                tgtTable.bottomAnchor.constraint(equalTo: bottomAnchor),
                srcTable.widthAnchor.constraint(equalTo: tgtTable.widthAnchor),
                tgtTable.leadingAnchor.constraint(equalTo: srcTable.trailingAnchor),
                divider.topAnchor.constraint(equalTo: header.bottomAnchor),
                divider.bottomAnchor.constraint(equalTo: bottomAnchor),
                divider.centerXAnchor.constraint(equalTo: centerXAnchor),
                divider.widthAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure(_ t: UITableView) {
        t.dataSource = self
        t.delegate = self
        t.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Jump each column to its current selection so nothing needs scrolling
    /// for the common case.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didAutoScroll else { return }
        didAutoScroll = true
        DispatchQueue.main.async { self.scrollToSelections() }
    }

    private func scrollToSelections() {
        if case .typing = mode {
            if let i = Self.typingLanguages.firstIndex(where: { $0.code == typingSelection }) {
                table.scrollToRow(at: IndexPath(row: i, section: 0), at: .middle, animated: false)
            }
            return
        }
        let store = AppGroupStore.shared
        let srcRow = store.sourceLang == "auto"
            ? 0
            : (languages.firstIndex { $0.code == store.sourceLang }.map { $0 + 1 } ?? 0)
        srcTable.scrollToRow(at: IndexPath(row: srcRow, section: 0), at: .middle, animated: false)
        if let t = languages.firstIndex(where: { $0.code == store.targetLang }) {
            tgtTable.scrollToRow(at: IndexPath(row: t, section: 0), at: .middle, animated: false)
        }
    }

    @objc private func doneTapped() {
        onDone?()
    }

    /// Swap source and target; a no-op while the source is Auto (Android parity).
    @objc private func swapTapped() {
        let store = AppGroupStore.shared
        guard store.sourceLang != "auto" else { return }
        let src = store.sourceLang
        store.sourceLang = store.targetLang
        store.targetLang = src
        store.langsDirty = true
        srcTable.reloadData()
        tgtTable.reloadData()
        scrollToSelections()
        onChanged?()
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if case .typing = mode { return KB.t("chooseTypingLanguage") }
        return tableView === srcTable ? KB.t("sourceLanguage") : KB.t("translateTo")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if case .typing = mode { return Self.typingLanguages.count }
        return tableView === srcTable ? languages.count + 1 : languages.count
    }

    private func item(_ tableView: UITableView, _ row: Int) -> (code: String, name: String) {
        if case .typing = mode {
            return Self.typingLanguages[row]
        }
        if tableView === srcTable {
            if row == 0 { return ("auto", KB.t("autoDetect")) }
            return languages[row - 1]
        }
        return languages[row]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "lang")
            ?? UITableViewCell(style: .default, reuseIdentifier: "lang")
        let entry = item(tableView, indexPath.row)
        cell.textLabel?.text = entry.name
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.textLabel?.adjustsFontSizeToFitWidth = true
        cell.textLabel?.minimumScaleFactor = 0.75
        let selected: Bool
        if case .typing = mode {
            selected = typingSelection == entry.code
        } else {
            let store = AppGroupStore.shared
            selected = tableView === srcTable
                ? store.sourceLang == entry.code
                : store.targetLang == entry.code
        }
        cell.accessoryType = selected ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let entry = item(tableView, indexPath.row)
        if case .typing = mode {
            typingSelection = entry.code
            tableView.reloadData()
            onTypingPicked?(entry.code)
            return
        }
        let store = AppGroupStore.shared
        if tableView === srcTable {
            store.sourceLang = entry.code
        } else {
            store.targetLang = entry.code
        }
        store.langsDirty = true
        srcTable.reloadData()
        tgtTable.reloadData()
        onChanged?()
    }
}
