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
}
