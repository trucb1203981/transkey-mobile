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
    private let kInputLang = "tk_kb_input_lang"
    private let kLangsDirty = "tk_langs_dirty"
    private let kFeatureReply = "tk_feature_reply"
    private let kFeatureRefine = "tk_feature_refine"
    private let kFeatureSummarize = "tk_feature_summarize"
    private let kFeatureExplain = "tk_feature_explain"
    private let kLangCatalog = "tk_lang_catalog"

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

    /// The keyboard's typing language (layout + composer), independent from
    /// the translate pair, like Android's typing_mode. Default Vietnamese.
    var keyboardInputLang: String {
        get { defaults?.string(forKey: kInputLang) ?? "vi" }
        set { defaults?.set(newValue, forKey: kInputLang) }
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

    /// Server-driven language catalog, JSON `[{code,label}, ...]`, mirrored
    /// from features_provider.dart - the same source the Android bubble and
    /// keyboard pickers read, so all pickers show the admin-managed list.
    var langCatalogJSON: String? {
        get { defaults?.string(forKey: kLangCatalog) }
        set { defaults?.set(newValue, forKey: kLangCatalog) }
    }
}
