import Flutter
import UIKit

/// MethodChannel handler that lets Flutter save auth data to App Group.
/// Called after login/register/deepLink to share token with extensions.
class AppGroupPlugin: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "transkey/appgroup",
            binaryMessenger: registrar.messenger()
        )
        let instance = AppGroupPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let store = AppGroupStore.shared

        switch call.method {
        case "saveAuth":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected map", details: nil))
                return
            }
            if let token = args["token"] as? String {
                store.saveToken(token)
            }
            if let deviceId = args["deviceId"] as? String {
                store.saveDeviceID(deviceId)
            }
            if let plan = args["plan"] as? String {
                store.savePlan(plan)
            }
            if let baseURL = args["baseURL"] as? String {
                store.saveApiBaseURL(baseURL)
            }
            result(true)

        case "clearAuth":
            store.clearAll()
            result(true)

        case "saveLanguages":
            // App -> group mirror, so the keyboard/share extensions follow the
            // pair chosen in the app. Never touches the dirty flag.
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected map", details: nil))
                return
            }
            if let source = args["source"] as? String {
                store.sourceLang = source
            }
            if let target = args["target"] as? String {
                store.targetLang = target
            }
            result(true)

        case "saveFeatures":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected map", details: nil))
                return
            }
            if let reply = args["reply"] as? Bool {
                store.featureReply = reply
            }
            if let refine = args["refine"] as? Bool {
                store.featureRefine = refine
            }
            result(true)

        case "saveLangCatalog":
            guard let args = call.arguments as? [String: Any],
                  let json = args["json"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected json", details: nil))
                return
            }
            store.langCatalogJSON = json
            result(true)

        case "readLanguages":
            // Read-and-consume: `dirty` tells the app the KEYBOARD changed the
            // pair since the last read, so the app should adopt these values.
            let dirty = store.langsDirty
            if dirty {
                store.langsDirty = false
            }
            result([
                "source": store.sourceLang,
                "target": store.targetLang,
                "dirty": dirty,
            ])

        case "openKeyboardSettings":
            // Open the app's own page in Settings. Apple rejects private
            // App-prefs deep links, so openSettingsURLString is the only
            // App-Store-safe entry; from there the user reaches Keyboards.
            if let url = URL(string: UIApplication.openSettingsURLString),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                result(true)
            } else {
                result(false)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
