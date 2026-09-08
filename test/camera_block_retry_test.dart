import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/services/camera_block_retry.dart';

void main() {
  const source = 'S JAI BIEN COMDRS VOUS\nVOULEZ PENETRER DANS CE CIRQUE';
  const previous = 'Bạn muốn vào rạp xiếc này.';
  late Dio dio;
  late int requests;
  late bool current;
  RequestOptions? sent;

  setUp(() {
    dio = Dio();
    requests = 0;
    current = true;
    sent = null;
  });
  tearDown(() => dio.close(force: true));

  void reply(Object? data) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      sent = options;
      handler.resolve(Response(requestOptions: options, data: data));
    }));
  }

  Future<CameraRetryResult> retry({
    String prior = previous,
  }) =>
      retryCameraBlock(
        dio: dio,
        text: source,
        previousTranslation: prior,
        sourceLang: 'fr',
        targetLang: 'vi',
        scene: 'manga',
        isCurrent: () => current,
      );

  test('one request preserves selected language, scene, and source text',
      () async {
    reply({
      'translations': ['Nếu tôi hiểu đúng, bạn muốn vào rạp xiếc này.']
    });
    final result = await retry(prior: source);
    expect(result.status, CameraRetryStatus.updated);
    expect(result.translation, startsWith('Nếu tôi hiểu đúng'));
    expect(requests, 1);
    expect(sent!.path, '/translate-batch');
    expect(sent!.data, {
      'texts': [source],
      'sourceLang': 'fr',
      'targetLang': 'vi',
      'appHint': 'camera',
      'scene': 'manga',
    });
  });

  for (final value in [source, source.replaceAll('\n', r'\n'), previous]) {
    test('unchanged result cannot overwrite the existing translation: $value',
        () async {
      reply({
        'translations': [value]
      });
      final result = await retry();
      expect(result.status, CameraRetryStatus.unchanged);
      expect(result.translation, isNull);
      expect(requests, 1);
      expect((sent!.data as Map).containsKey('contextTexts'), isFalse);
    });
  }

  for (final data in [
    null,
    {'translations': []},
    {
      'translations': ['']
    },
    {
      'translations': [42]
    },
    {
      'translations': ['One', 'Two']
    },
    {
      'translations': ['[?] $source']
    },
  ]) {
    test('invalid or uncertain output keeps the previous result: $data',
        () async {
      reply(data);
      final result = await retry();
      expect(result.status, CameraRetryStatus.failed);
      expect(result.translation, isNull);
      expect(requests, 1);
    });
  }

  test('network failure returns no replacement and schedules no extra request',
      () async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.reject(DioException(
          requestOptions: options, type: DioExceptionType.connectionError));
    }));
    final result = await retry();
    expect(result.status, CameraRetryStatus.failed);
    expect(result.translation, isNull);
    expect(requests, 1);
  });

  test('response arriving after page or language changes cannot be applied',
      () async {
    final started = Completer<void>();
    final response = Completer<void>();
    dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      requests++;
      started.complete();
      await response.future;
      handler.resolve(Response(requestOptions: options, data: {
        'translations': ['A valid but obsolete translation']
      }));
    }));
    final pending = retry();
    await started.future;
    current = false;
    response.complete();
    final result = await pending;
    expect(result.status, CameraRetryStatus.stale);
    expect(result.translation, isNull);
    expect(requests, 1);
  });

  test('already obsolete retry sends no request', () async {
    reply({
      'translations': ['New']
    });
    current = false;
    expect((await retry()).status, CameraRetryStatus.stale);
    expect(requests, 0);
  });
}
