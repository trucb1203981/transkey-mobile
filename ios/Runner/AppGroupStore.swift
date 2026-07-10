import Foundation

/// Shared storage using App Group UserDefaults.
/// The main app writes token + deviceID here so extensions can read them.
class AppGroupStore {

    static let shared = AppGroupStore()

    private let appGroupIdentifier = "group.app.transkey"
    private let defaults: UserDefaults?

    private let kToken = "tk_access_token"
    private let kDeviceID = "tk_device_id"
    private let kUserPlan = "tk_user_plan"
    private let kApiBaseURL = "tk_api_base_url"
    private let kKeyboardTelex = "tk_kb_vi_telex"
    private let kKeyboardAutocorrect = "tk_kb_autocorrect"
    private let kSourceLang = "tk_source_lang"
    private let kTargetLang = "tk_target_lang"
    private let kUiLang = "tk_ui_lang"
    private let kInputLang = "tk_kb_input_lang"
    private let kLangsDirty = "tk_langs_dirty"
    private let kFeatureReply = "tk_feature_reply"
    private let kFeatureRefine = "tk_feature_refine"
    private let kFeatureSummarize = "tk_feature_summarize"
    private let kFeatureExplain = "tk_feature_explain"
    private let kLangCatalog = "tk_lang_catalog"
    private let kKbGuideSeen = "tk_kb_guide_seen_v1"

    private init() {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Write (called from Flutter main app)

    func saveToken(_ token: String) {
        defaults?.set(token, forKey: kToken)
    }

    func saveDeviceID(_ id: String) {
        defaults?.set(id, forKey: kDeviceID)
    }

    func savePlan(_ plan: String) {
        defaults?.set(plan, forKey: kUserPlan)
    }

    func saveApiBaseURL(_ url: String) {
        defaults?.set(url, forKey: kApiBaseURL)
    }

    func clearAll() {
        defaults?.removeObject(forKey: kToken)
        defaults?.removeObject(forKey: kDeviceID)
        defaults?.removeObject(forKey: kUserPlan)
        defaults?.removeObject(forKey: kApiBaseURL)
    }

    // MARK: - Read (called from extensions)

    var token: String? {
        defaults?.string(forKey: kToken)
    }

    var deviceID: String? {
        defaults?.string(forKey: kDeviceID)
    }

    var plan: String? {
        defaults?.string(forKey: kUserPlan)
    }

    var apiBaseURL: String {
        defaults?.string(forKey: kApiBaseURL) ?? "https://api.transkey.app"
    }

    // MARK: - Keyboard settings (read/written by the keyboard extension)

    /// Vietnamese Telex typing on the custom keyboard. Default ON.
    var keyboardTelexEnabled: Bool {
        get { defaults?.object(forKey: kKeyboardTelex) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: kKeyboardTelex) }
    }

    /// Vietnamese autocorrect on word commit. Default OFF, matching Android
    /// (strict Telex: plain letters yield plain text unless the user opts in).
    var keyboardAutocorrectEnabled: Bool {
        get { defaults?.object(forKey: kKeyboardAutocorrect) as? Bool ?? false }
        set { defaults?.set(newValue, forKey: kKeyboardAutocorrect) }
    }

    // MARK: - Translate language pair (mirrored from the Flutter app; the
    // keyboard may also change it, signalled back via the dirty flag)

    var sourceLang: String {
        get { defaults?.string(forKey: kSourceLang) ?? "auto" }
        set { defaults?.set(newValue, forKey: kSourceLang) }
    }

    var targetLang: String {
        get { defaults?.string(forKey: kTargetLang) ?? "en" }
        set { defaults?.set(newValue, forKey: kTargetLang) }
    }

    // MARK: - Reply-compose language pair (KEYBOARD-LOCAL)
    //
    // The reply is written in the OTHER party's language, so it needs its own
    // pair distinct from the read/translate pair above (with Auto->VI set for
    // reading, a reply would come out Vietnamese instead of the partner's
    // language). Writes here deliberately never raise langsDirty - that flag
    // mirrors the SHARED translate pair back to the Flutter app via
    // readLanguages, and the app must not adopt the reply pair. Android keeps
    // the same split via its tk_reply_lang pref (TransKeyIME).
    private let kReplySourceLang = "tk_kb_reply_source_lang"
    private let kReplyTargetLang = "tk_kb_reply_target_lang"

    var replySourceLang: String {
        get { defaults?.string(forKey: kReplySourceLang) ?? "auto" }
        set { defaults?.set(newValue, forKey: kReplySourceLang) }
    }

    var replyTargetLang: String {
        get { defaults?.string(forKey: kReplyTargetLang) ?? "en" }
        set { defaults?.set(newValue, forKey: kReplyTargetLang) }
    }

    /// The app's UI language (the locale the user picked INSIDE the app),
    /// mirrored from Flutter so the keyboard extension can localize its own
    /// chips/labels to match the app instead of always showing Vietnamese.
    /// Empty when never mirrored; callers fall back to device language / "en".
    var uiLang: String {
        get { defaults?.string(forKey: kUiLang) ?? "" }
        set { defaults?.set(newValue, forKey: kUiLang) }
    }

    /// The keyboard's typing language (layout + composer), independent from
    /// the translate pair, like Android's typing_mode. Default Vietnamese.
    var keyboardInputLang: String {
        get { defaults?.string(forKey: kInputLang) ?? "vi" }
        set { defaults?.set(newValue, forKey: kInputLang) }
    }

    /// Recently-used emoji for the keyboard's emoji panel, most-recent first
    /// (capped). Stored as a plain array so the order is preserved.
    private let kEmojiRecents = "tk_kb_emoji_recents"
    private static let emojiRecentsMax = 30

    var emojiRecents: [String] {
        get { (defaults?.array(forKey: kEmojiRecents) as? [String]) ?? [] }
        set { defaults?.set(newValue, forKey: kEmojiRecents) }
    }

    /// Record `emoji` as just-used: move/insert it to the front, dedupe, cap.
    func pushEmojiRecent(_ emoji: String) {
        var list = emojiRecents
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        if list.count > Self.emojiRecentsMax { list = Array(list.prefix(Self.emojiRecentsMax)) }
        emojiRecents = list
    }

    /// Set by the keyboard when IT changes the language pair; the app reads
    /// and consumes it to decide who wins on next resume.
    var langsDirty: Bool {
        get { defaults?.bool(forKey: kLangsDirty) ?? false }
        set { defaults?.set(newValue, forKey: kLangsDirty) }
    }

    // MARK: - Plan-gated feature flags (mirrored from features_provider.dart;
    // the keyboard gates its chips like the Android strip: Reply replaces
    // Translate for entitled users, Refine paid-only)

    var featureReply: Bool {
        get { defaults?.bool(forKey: kFeatureReply) ?? false }
        set { defaults?.set(newValue, forKey: kFeatureReply) }
    }

    var featureRefine: Bool {
        get { defaults?.bool(forKey: kFeatureRefine) ?? false }
        set { defaults?.set(newValue, forKey: kFeatureRefine) }
    }

    var featureSummarize: Bool {
        get { defaults?.bool(forKey: kFeatureSummarize) ?? false }
        set { defaults?.set(newValue, forKey: kFeatureSummarize) }
    }

    var featureExplain: Bool {
        get { defaults?.bool(forKey: kFeatureExplain) ?? false }
        set { defaults?.set(newValue, forKey: kFeatureExplain) }
    }

    /// First-run guide for the keyboard action chips - shown exactly once
    /// (parity with the Android keyboard's first-run guide overlay).
    var keyboardGuideSeen: Bool {
        get { defaults?.bool(forKey: kKbGuideSeen) ?? false }
        set { defaults?.set(newValue, forKey: kKbGuideSeen) }
    }

    /// Server-driven language catalog, JSON `[{code,label}, ...]`, mirrored
    /// from features_provider.dart - the same source the Android bubble and
    /// keyboard pickers read, so all pickers show the admin-managed list.
    var langCatalogJSON: String? {
        get { defaults?.string(forKey: kLangCatalog) }
        set { defaults?.set(newValue, forKey: kLangCatalog) }
    }

    // MARK: - Translate result cache
    //
    // Exact-match, bounded LRU cache mirroring the Flutter app's
    // BubbleTranslateCache (lib/features/translate/services/bubble_translate_cache.dart):
    // re-running an identical request (same text + langs + mode + tone + flags)
    // returns the stored result with NO paid API round-trip. Lives in the App
    // Group so the keyboard AND share extensions share ONE cache. It is NOT
    // shared with the Flutter app's own cache - that one lives in the app's
    // standard UserDefaults (shared_preferences), a different suite. Stored as a
    // single JSON blob `{ "order": [key...], "entries": { key: responseJSON } }`;
    // the order array gives cheap LRU since Swift dictionaries are unordered.
    private static let kTranslateCache = "tk_ext_translate_cache_v1"
    // Keep the blob SMALL: the whole thing is one UserDefaults value that the
    // keyboard extension loads into RAM at first access (jetsam cap ~60MB)
    // and re-serializes on every store. 50 entries of chat-sized text is
    // plenty of hit rate; an old oversized blob still reads fine and shrinks
    // to the cap on the next store.
    private static let translateCacheMax = 50
    // Keys embed the full source text; skip pathological entries (a 3000-char
    // clipboard) instead of letting one paste balloon the blob.
    private static let translateCacheMaxKeyLength = 1500

    /// Composite key from the normalized request, kept byte-identical to
    /// BubbleTranslateCache.keyFor so the format stays in lockstep if the two
    /// caches are ever unified into the App Group.
    static func translateCacheKey(
        text: String,
        mode: String,
        targetLang: String,
        sourceLang: String,
        tone: String = "",
        romanization: Bool = false,
        suggestReplies: Bool = false,
        replyToOriginal: String? = nil
    ) -> String {
        let r = romanization ? "1" : "0"
        let s = suggestReplies ? "1" : "0"
        let reply = replyToOriginal ?? ""
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(mode)\(targetLang)\(sourceLang)\(tone)\(r)\(s)\(reply)\(t)"
    }

    /// Returns the cached response JSON for `key`, or nil on a miss.
    func cachedTranslation(forKey key: String) -> [String: Any]? {
        guard let data = defaults?.data(forKey: Self.kTranslateCache),
              let blob = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = blob["entries"] as? [String: Any],
              let hit = entries[key] as? [String: Any] else { return nil }
        return hit
    }

    /// Stores `value` (the raw API response JSON) under `key`, evicting the
    /// least-recently-used entries past the cap. Best-effort: any failure must
    /// never break translation. Recency is refreshed on WRITE only - a read
    /// hit deliberately does not rewrite the blob (that would cost a full
    /// re-serialize per lookup for a marginal hit-rate gain).
    func storeTranslation(_ value: [String: Any], forKey key: String) {
        guard let defaults else { return }
        guard key.count <= Self.translateCacheMaxKeyLength else { return }
        var order: [String] = []
        var entries: [String: Any] = [:]
        if let data = defaults.data(forKey: Self.kTranslateCache),
           let blob = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            order = blob["order"] as? [String] ?? []
            entries = blob["entries"] as? [String: Any] ?? [:]
        }
        // Move-to-end on write = most-recently-used.
        order.removeAll { $0 == key }
        entries[key] = value
        order.append(key)
        // Evict the oldest entries (front of the order) past the cap.
        while order.count > Self.translateCacheMax {
            let oldest = order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        let blob: [String: Any] = ["order": order, "entries": entries]
        guard JSONSerialization.isValidJSONObject(blob),
              let data = try? JSONSerialization.data(withJSONObject: blob) else { return }
        defaults.set(data, forKey: Self.kTranslateCache)
    }
}
