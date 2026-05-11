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

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
