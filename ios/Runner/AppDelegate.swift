import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register AppGroup plugin so Flutter can save auth data for extensions
    AppGroupPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "AppGroupPlugin"))

    // Register deeplink plugin for opening iOS Settings pages
    let deeplinkRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeeplinkPlugin")
    let deeplinkChannel = FlutterMethodChannel(
      name: "transkey/deeplink",
      binaryMessenger: deeplinkRegistrar.messenger()
    )
    deeplinkChannel.setMethodCallHandler { call, result in
      if call.method == "open", let args = call.arguments as? [String: Any],
         let urlStr = args["url"] as? String,
         let url = URL(string: urlStr) {
        if UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url)
          result(true)
        } else if let fallback = URL(string: "App-prefs:root=General&path=Keyboard") {
          UIApplication.shared.open(fallback)
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
