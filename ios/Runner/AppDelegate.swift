import Flutter
import UIKit
import Vision
import ImageIO

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

    // AppGroup auth + language-pair sharing, so the keyboard / share
    // extensions can read the login and the translate pair.
    if let r = registry.registrar(forPlugin: "AppGroupPlugin") {
      AppGroupPlugin.register(with: r)
    }

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
/// recognizer to the Flutter camera pipeline.
///
/// `recognize` args:
///   path          (String, required) image file path
///   languages     ([String]?)        recognition language codes, priority order
///   level         (String?)          "fast" | "accurate" (default accurate)
///   maxEdge       (Int?)             long-edge cap for the native downscale;
///                                    0 / absent = recognize at full resolution
///   customWords   ([String]?)        domain words (user glossary) that take
///                                    priority over the built-in lexicon
///   regions       ([[Double]]?)      normalized [x, y, w, h] rects (TOP-left
///                                    origin). When present, recognition runs
///                                    per region in ONE native call (one image
///                                    decode) — used by the manga bubble path.
///
/// Returns { width, height, lines: [...] } where width/height are the
/// EXIF-applied ORIGINAL pixel dimensions (so Dart never re-decodes the
/// capture just to learn its size) and each line is
/// { text, left, top, width, height (normalized 0..1, top-left origin),
///   confidence, region (index into `regions`, -1 for full-page) }.
///
/// Engine: on iOS 18+ this uses the modern Swift Vision API
/// (`RecognizeTextRequest`, async, Sendable). Below 18 it falls back to
/// `VNRecognizeTextRequest` — same recognition model (revision 3), older
/// plumbing. When the project moves to Xcode 26+, the document scenes can
/// additionally adopt `RecognizeDocumentsRequest` (iOS 26) for native
/// paragraph/table structure.
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

    // ── Request plumbing ────────────────────────────────────────────────

    private struct LoadedImage {
        let cgImage: CGImage
        /// EXIF-applied dimensions of the ORIGINAL file (not the downscale).
        let orientedWidth: Int
        let orientedHeight: Int
    }

    private struct OcrConfig {
        let languages: [String]
        let fast: Bool
        let customWords: [String]
        /// Normalized [0..1] rects, TOP-left origin (Dart convention).
        let regions: [CGRect]
    }

    private static func recognize(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "path required", details: nil))
            return
        }
        let requested = args["languages"] as? [String] ?? []
        let fast = (args["level"] as? String) == "fast"
        let maxEdge = (args["maxEdge"] as? NSNumber)?.intValue ?? 0
        let customWords = args["customWords"] as? [String] ?? []
        let regionsRaw = args["regions"] as? [[Double]] ?? []

        let finish: ([String: Any]) -> Void = { payload in
            DispatchQueue.main.async { result(payload) }
        }
        let fail: (String, String) -> Void = { code, message in
            DispatchQueue.main.async {
                result(FlutterError(code: code, message: message, details: nil))
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = loadImage(path: path, maxEdge: maxEdge) else {
                fail("NO_IMAGE", "cannot load \(path)")
                return
            }
            // Keep only codes this OS version actually supports; an unsupported
            // code makes `perform` throw. Empty result → auto-detect. The legacy
            // probe is authoritative for both paths (same underlying model).
            let probe = VNRecognizeTextRequest()
            probe.recognitionLevel = fast ? .fast : .accurate
            let supported = Set((try? probe.supportedRecognitionLanguages()) ?? [])
            let config = OcrConfig(
                languages: requested.filter { supported.contains($0) },
                fast: fast,
                customWords: customWords,
                regions: regionsRaw.compactMap { r in
                    r.count == 4 ? CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) : nil
                }
            )

            if #available(iOS 18.0, *) {
                Task.detached(priority: .userInitiated) {
                    do {
                        let lines = try await recognizeModern(img.cgImage, config)
                        finish(payload(img, lines))
                    } catch {
                        fail("VISION_ERR", error.localizedDescription)
                    }
                }
            } else {
                do {
                    let lines = try recognizeLegacy(img.cgImage, config)
                    finish(payload(img, lines))
                } catch {
                    fail("VISION_ERR", error.localizedDescription)
                }
            }
        }
    }

    private static func payload(_ img: LoadedImage, _ lines: [[String: Any]]) -> [String: Any] {
        ["width": img.orientedWidth, "height": img.orientedHeight, "lines": lines]
    }

    /// Hardware JPEG decode via ImageIO with the EXIF transform baked in and
    /// an optional long-edge downscale — replaces the old UIImage full decode
    /// AND the Dart-side decode/resize/re-encode isolate (which cost hundreds
    /// of ms per capture). The thumbnail comes back upright, so Vision needs
    /// no orientation hint and normalized boxes are already in the upright
    /// frame.
    private static func loadImage(path: String, maxEdge: Int) -> LoadedImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        var w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let exif = (props?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        // EXIF 5-8 are the 90°-rotated orientations: the upright frame swaps
        // width/height vs the stored pixel grid.
        if exif >= 5 && exif <= 8 { swap(&w, &h) }

        var opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let longEdge = max(w, h)
        // MaxPixelSize must always be set or ImageIO may emit the embedded
        // EXIF thumbnail (tiny); clamp to the original size for "no downscale".
        opts[kCGImageSourceThumbnailMaxPixelSize] =
            (maxEdge > 0 && longEdge > maxEdge) ? maxEdge : max(longEdge, 1)
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        if w <= 0 || h <= 0 { w = cg.width; h = cg.height }
        return LoadedImage(cgImage: cg, orientedWidth: w, orientedHeight: h)
    }

    private static func lineDict(
        text: String, rect: CGRect, confidence: Double, region: Int
    ) -> [String: Any] {
        [
            "text": text,
            "left": Double(rect.minX),
            "top": Double(rect.minY),
            "width": Double(rect.width),
            "height": Double(rect.height),
            "confidence": confidence,
            "region": region,
        ]
    }

    // ── Modern path (iOS 18+, Swift Vision API) ─────────────────────────

    @available(iOS 18.0, *)
    private static func recognizeModern(
        _ cg: CGImage, _ config: OcrConfig
    ) async throws -> [[String: Any]] {
        var base = RecognizeTextRequest()
        base.recognitionLevel = config.fast ? .fast : .accurate
        base.usesLanguageCorrection = !config.fast
        base.customWords = config.customWords
        if config.languages.isEmpty {
            base.automaticallyDetectsLanguage = true
        } else {
            base.recognitionLanguages = config.languages.map { Locale.Language(identifier: $0) }
        }

        let size = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
        if config.regions.isEmpty {
            let observations = try await base.perform(on: cg)
            return observations.compactMap { obs in
                guard let top = obs.topCandidates(1).first else { return nil }
                let px = obs.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                return lineDict(
                    text: top.string,
                    rect: normalizedTopLeft(px, in: size),
                    confidence: Double(top.confidence),
                    region: -1
                )
            }
        }

        // Per-region: one request per ROI on the SAME decoded image, run
        // concurrently — Vision schedules them on the Neural Engine. This is
        // the manga bubble path: it replaces N crop-JPEG writes + decodes
        // with zero extra image work.
        return try await withThrowingTaskGroup(of: [[String: Any]].self) { group in
            for (index, r) in config.regions.enumerated() {
                group.addTask {
                    var req = base
                    // Dart sends TOP-left-origin rects; Vision wants lower-left.
                    let roi = NormalizedRect(
                        x: r.minX, y: 1.0 - r.maxY, width: r.width, height: r.height)
                    req.regionOfInterest = roi
                    let observations = try await req.perform(on: cg)
                    return observations.compactMap { obs in
                        guard let top = obs.topCandidates(1).first else { return nil }
                        // ROI results are ROI-relative; map back to full image.
                        let px = obs.boundingBox.toImageCoordinates(
                            from: roi, imageSize: size, origin: .upperLeft)
                        return lineDict(
                            text: top.string,
                            rect: normalizedTopLeft(px, in: size),
                            confidence: Double(top.confidence),
                            region: index
                        )
                    }
                }
            }
            var all: [[String: Any]] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    /// Pixel rect (top-left origin) → normalized [0..1] rect, top-left origin.
    private static func normalizedTopLeft(_ px: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(
            x: px.minX / size.width,
            y: px.minY / size.height,
            width: px.width / size.width,
            height: px.height / size.height
        )
    }

    // ── Legacy path (iOS 15.5–17, VNRecognizeTextRequest) ───────────────

    private static func recognizeLegacy(
        _ cg: CGImage, _ config: OcrConfig
    ) throws -> [[String: Any]] {
        func makeRequest() -> VNRecognizeTextRequest {
            let r = VNRecognizeTextRequest()
            r.recognitionLevel = config.fast ? .fast : .accurate
            r.usesLanguageCorrection = !config.fast
            r.customWords = config.customWords
            if !config.languages.isEmpty {
                r.recognitionLanguages = config.languages
            } else if #available(iOS 16.0, *) {
                r.automaticallyDetectsLanguage = true
            }
            return r
        }

        // (request, region index, ROI in Vision's lower-left normalized space)
        var requests: [(VNRecognizeTextRequest, Int, CGRect?)] = []
        if config.regions.isEmpty {
            requests.append((makeRequest(), -1, nil))
        } else {
            for (index, r) in config.regions.enumerated() {
                let req = makeRequest()
                let roi = CGRect(x: r.minX, y: 1.0 - r.maxY, width: r.width, height: r.height)
                req.regionOfInterest = roi
                requests.append((req, index, roi))
            }
        }

        // One handler = one image decode for ALL region requests.
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform(requests.map { $0.0 })

        var lines: [[String: Any]] = []
        for (req, index, roi) in requests {
            for obs in (req.results ?? []) {
                guard let top = obs.topCandidates(1).first else { continue }
                // With an ROI set the observation box is ROI-relative — map to
                // full-image normalized (still lower-left), then flip Y to the
                // top-left origin Dart expects.
                var bb = obs.boundingBox
                if let roi = roi {
                    bb = CGRect(
                        x: roi.minX + bb.minX * roi.width,
                        y: roi.minY + bb.minY * roi.height,
                        width: bb.width * roi.width,
                        height: bb.height * roi.height
                    )
                }
                lines.append(lineDict(
                    text: top.string,
                    rect: CGRect(x: bb.minX, y: 1.0 - bb.maxY, width: bb.width, height: bb.height),
                    confidence: Double(top.confidence),
                    region: index
                ))
            }
        }
        return lines
    }
}
