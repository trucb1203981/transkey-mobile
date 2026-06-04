import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle deep link when app is already running (iOS 13+ Scene-based)
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return handleDeepLink(url) || super.application(app, open: url, options: options)
  }

  private func handleDeepLink(_ url: URL) -> Bool {
    guard url.scheme == "transkey" else { return false }
    // Forward to Flutter via the app_links plugin
    // The plugin listens for URL events automatically
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registry = engineBridge.pluginRegistry

    // NOTE: AppGroup auth-sharing (so the keyboard / share extensions can read
    // the login) is DEFERRED — those extensions aren't Xcode targets yet and
    // App Group needs a paid Apple account. Re-enable when resuming the keyboard
    // handoff by adding AppGroupPlugin.swift + AppGroupStore.swift to the Runner
    // target and uncommenting:
    //   if let r = registry.registrar(forPlugin: "AppGroupPlugin") {
    //     AppGroupPlugin.register(with: r)
    //   }

    // Deeplink: open iOS Settings pages from Dart.
    if let registrar = registry.registrar(forPlugin: "DeeplinkPlugin") {
      let deeplinkChannel = FlutterMethodChannel(
        name: "transkey/deeplink",
        binaryMessenger: registrar.messenger()
      )
      deeplinkChannel.setMethodCallHandler { call, result in
        if call.method == "open", let args = call.arguments as? [String: Any],
           let urlStr = args["url"] as? String,
           let url = URL(string: urlStr) {
          if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            result(true)
          } else if let fallback = URL(string: UIApplication.openSettingsURLString) {
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

    // IME channel: the Dart settings tile probes keyboard status and opens the
    // system keyboard settings. iOS gives no public API to detect whether a
    // custom keyboard is enabled/selected, so status probes return false and the
    // tile behaves as an "open Settings" link. There is no in-app keyboard picker
    // on iOS (the system globe handles switching), so showImePicker just opens
    // Settings.
    if let registrar = registry.registrar(forPlugin: "ImePlugin") {
      let imeChannel = FlutterMethodChannel(
        name: "transkey/ime",
        binaryMessenger: registrar.messenger()
      )
      imeChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "isEnabled", "isSelected":
          result(false)
        case "openImeSettings", "showImePicker":
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

    // Apple Vision OCR: on-device text + bounding boxes, runs on the Neural
    // Engine. Replaces the ML Kit 4-pass pipeline on iOS (Vision handles
    // stylized / low-contrast text natively in a single pass). The server still
    // owns translation; Vision only reads.
    if let registrar = registry.registrar(forPlugin: "VisionOcrPlugin") {
      VisionOcrChannel.register(with: registrar)
    }
  }
}

/// MethodChannel `transkey/vision_ocr` exposing Apple's Vision text
/// recognizer to the Flutter camera pipeline. Returns one entry per detected
/// line: { text, left, top, width, height (image-pixel coords), confidence }.
class VisionOcrChannel {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "transkey/vision_ocr",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "recognize":
                recognize(call, result)
            case "supportedLanguages":
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let langs = (try? request.supportedRecognitionLanguages()) ?? []
                result(langs)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func recognize(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "path required", details: nil))
            return
        }
        guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
            result(FlutterError(code: "NO_IMAGE", message: "cannot load \(path)", details: nil))
            return
        }

        let languages = args["languages"] as? [String]
        let fast = (args["level"] as? String) == "fast"
        // Read the file's orientation so Vision recognizes upright text even when
        // the JPEG carries EXIF rotation (Dart's image-package downscale can keep
        // the EXIF tag). Boxes then come back in the upright frame.
        let orientation = Self.cgOrientation(image.imageOrientation)

        let request = VNRecognizeTextRequest { req, err in
            if let err = err {
                DispatchQueue.main.async {
                    result(FlutterError(code: "VISION_ERR", message: err.localizedDescription, details: nil))
                }
                return
            }
            var blocks: [[String: Any]] = []
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                // Return NORMALIZED [0..1] coords in the upright frame (flip
                // Vision's bottom-left Y to top-left). The Dart side multiplies by
                // the EXIF-applied image size so boxes land in the overlay's space
                // regardless of the OCR downscale — fixes boxes shrinking into the
                // top-left corner when the capture is larger than the OCR image.
                let bb = obs.boundingBox
                blocks.append([
                    "text": top.string,
                    "left": Double(bb.minX),
                    "top": Double(1.0 - bb.maxY),
                    "width": Double(bb.width),
                    "height": Double(bb.height),
                    "confidence": Double(top.confidence),
                ])
            }
            DispatchQueue.main.async { result(blocks) }
        }

        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = true
        // Keep only codes this OS version actually supports; an unsupported
        // code makes `perform` throw. Fall back to auto-detect when none match.
        let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let valid = (languages ?? []).filter { supported.contains($0) }
        if !valid.isEmpty {
            request.recognitionLanguages = valid
        } else if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "VISION_PERFORM", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// Map a UIImage orientation to the Vision/CoreGraphics orientation enum so
    /// VNImageRequestHandler reads the pixels upright.
    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
