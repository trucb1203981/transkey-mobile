import 'package:dio/dio.dart';

enum CameraRetryStatus { updated, unchanged, failed, stale }

class CameraRetryResult {
  const CameraRetryResult(this.status, [this.translation]);
  final CameraRetryStatus status;
  final String? translation;
}

/// One explicit retry. A failed/echoed response never replaces a prior result.
/// The owner supplies a page/content/settings guard so late responses cannot
/// overwrite a different page or a newer edit. The caller updates only the
/// still-current page; a failed result carries no replacement translation.
Future<CameraRetryResult> retryCameraBlock({
  required Dio dio,
  required String text,
  required String previousTranslation,
  required String sourceLang,
  required String targetLang,
  required String scene,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return const CameraRetryResult(CameraRetryStatus.stale);
  if (text.trim().isEmpty) {
    return const CameraRetryResult(CameraRetryStatus.failed);
  }
  try {
    final response = await dio
        .post('/translate-batch',
            data: {
              'texts': [text],
              'sourceLang': sourceLang,
              'targetLang': targetLang,
              'appHint': 'camera',
              'scene': scene,
            },
            options: Options(
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ))
        .timeout(const Duration(seconds: 60));
    if (!isCurrent()) return const CameraRetryResult(CameraRetryStatus.stale);
    final body = response.data;
    final values = body is Map ? body['translations'] : null;
    if (values is! List || values.length != 1 || values.first is! String) {
      return const CameraRetryResult(CameraRetryStatus.failed);
    }
    final translated = (values.first as String).trim();
    if (translated.isEmpty || translated.startsWith('[?]')) {
      return const CameraRetryResult(CameraRetryStatus.failed);
    }
    if (_normalize(translated) == _normalize(text) ||
        _normalize(translated) == _normalize(previousTranslation)) {
      return const CameraRetryResult(CameraRetryStatus.unchanged);
    }
    return CameraRetryResult(CameraRetryStatus.updated, translated);
  } on Exception {
    return CameraRetryResult(
        isCurrent() ? CameraRetryStatus.failed : CameraRetryStatus.stale);
  }
}

String _normalize(String text) => text
    .replaceAll(r'\r\n', '\n')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\r', '\n')
    .replaceAll(r'\t', ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');
