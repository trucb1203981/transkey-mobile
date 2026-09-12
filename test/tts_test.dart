import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:transkey_mobile/l10n/generated/app_localizations.dart';
import 'package:transkey_mobile/features/translate/widgets/tts_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transkey_mobile/features/translate/services/edge_voice_catalog.dart';
import 'package:transkey_mobile/features/translate/services/edge_voices.dart';
import 'package:transkey_mobile/features/translate/services/edge_speech_client.dart';
import 'package:transkey_mobile/features/translate/services/neural_speech_output.dart';
import 'package:transkey_mobile/features/translate/services/speech_text.dart';
import 'package:transkey_mobile/features/translate/services/speech_voice.dart';
import 'package:transkey_mobile/features/translate/services/tts_service.dart';

class FakeSpeechClient extends EdgeSpeechClient {
  final voices = <String>[];
  final texts = <String>[];
  bool fail = false;
  @override
  Stream<List<int>> speak(String text, TtsVoice voice, double rate,
      SpeechCancellation cancellation) async* {
    cancellation.check();
    if (fail) throw StateError('offline');
    voices.add(voice.locale);
    texts.add(text);
    yield [1, 2, 3];
  }
}

class ControlledOutput implements NeuralSpeechOutput {
  final pending = <Completer<void>>[];
  final tokens = <SpeechCancellation>[];
  @override
  Future<void> play(Stream<List<int>> audio, SpeechCancellation cancellation,
      void Function() onStarted) async {
    final done = Completer<void>();
    pending.add(done);
    tokens.add(cancellation);
    void cancel() {
      if (!done.isCompleted) done.complete();
    }

    cancellation.add(cancel);
    try {
      await for (final _ in audio) {
        cancellation.check();
      }
      cancellation.check();
      onStarted();
      await done.future;
    } finally {
      cancellation.remove(cancel);
    }
  }
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every published locale resolves without changing its language', () {
    final locales = edgeVoiceCatalog.map((v) => v.locale).toSet();
    expect(locales.length, 142);
    for (final locale in locales) {
      expect(resolveEdgeVoice(locale).locale, locale);
    }
    expect(resolveEdgeVoice('tl').locale, 'fil-PH');
    expect(resolveEdgeVoice('no').locale, 'nb-NO');
    expect(resolveEdgeVoice('zh_Hant').locale, 'zh-TW');
    expect(resolveEdgeVoice('zh-Hant-HK').locale, 'zh-HK');
    expect(resolveEdgeVoice('VI_vn').locale, 'vi-VN');
    expect(resolveEdgeVoice('vi', 'en-US-JennyNeural').locale, 'vi-VN');
    for (final code in ['auto', 'und', 'xx', '', 'zh-XX']) {
      expect(() => resolveEdgeVoice(code), throwsA(TtsFailure.unsupported));
    }
  });
  test('cleaning retains natural punctuation, paragraphs, numbers and joiners',
      () {
    expect(
        cleanSpeechText(
            '**Hello!**\n\nPrice: \$1,250.50.\n[More](https://test)\n[ROM] skip'),
        'Hello!\n\nPrice: \$1,250.50.\nMore');
    expect(cleanSpeechText('ක්\u200Dය'), 'ක්\u200Dය');
    final text = List.filled(40, 'Price 1.25. Hello!\n\n').join().trim();
    final parts = speechChunks(text);
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.length <= 500), isTrue);
    expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '),
        text.replaceAll(RegExp(r'\s+'), ' '));
    final emojis = List.filled(501, '😀').join();
    final split = speechChunks(emojis);
    expect(split.join(), emojis);
    expect(split.every((p) => p.runes.every((r) => r == 0x1f600)), isTrue);
  });
  test('binary frames validate length and request ownership', () {
    List<int> frame(String id) {
      final headers = utf8.encode('X-RequestId:$id\r\nPath:audio\r\n');
      return [headers.length >> 8, headers.length & 255, ...headers, 7, 8];
    }

    expect(speechAudioFrame(frame('mine'), 'mine'), [7, 8]);
    expect(speechAudioFrame(frame('old'), 'mine'), isNull);
    expect(() => speechAudioFrame([1], 'mine'), throwsFormatException);
    expect(() => speechAudioFrame([1, 1, 2], 'mine'), throwsFormatException);
    expect(escapeSpeechXml('<a & "b">'), '&lt;a &amp; &quot;b&quot;&gt;');
    final now = DateTime.utc(2026, 9, 12, 12, 0, 0);
    expect(
        speechToken(now), speechToken(now.add(const Duration(seconds: 299))));
    expect(speechToken(now),
        isNot(speechToken(now.add(const Duration(minutes: 5)))));
  });
  test('cancellation is idempotent and new subscribers stop immediately', () {
    final token = SpeechCancellation();
    var calls = 0;
    token.add(() => calls++);
    token.cancel();
    token.cancel();
    token.add(() => calls++);
    expect(calls, 2);
    expect(token.check, throwsA(isA<SpeechCancelled>()));
  });
  test('paused playback keeps draining the transport and preserves audio',
      () async {
    var upstreamPauses = 0;
    var upstreamClosed = false;
    final source = StreamController<List<int>>(
      sync: true,
      onPause: () => upstreamPauses++,
      onCancel: () => upstreamClosed = true,
    );
    final received = <int>[];
    final done = Completer<void>();
    final output = bufferSpeechTransport(source.stream)
        .listen(received.addAll, onDone: done.complete);
    source.add([1, 2]);
    output.pause();
    source.add([3, 4]);
    source.add([5, 6]);
    await source.close();
    expect(upstreamPauses, 0);
    expect(upstreamClosed, isTrue);
    expect(received, [1, 2]);
    output.resume();
    await done.future;
    expect(received, [1, 2, 3, 4, 5, 6]);
    await output.cancel();
  });
  test('cancelling buffered playback releases its transport subscription',
      () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final output = bufferSpeechTransport(source.stream).listen((_) {});
    output.pause();
    await output.cancel();
    expect(cancelled, isTrue);
    await source.close();
  });
  group('speech lifecycle', () {
    late ProviderContainer container;
    late FakeSpeechClient client;
    late ControlledOutput output;
    late TtsNotifier tts;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter_tts'), (call) async => 1);
      client = FakeSpeechClient();
      output = ControlledOutput();
      container = ProviderContainer(overrides: [
        edgeSpeechClientProvider.overrideWithValue(client),
        neuralSpeechOutputProvider.overrideWithValue(output),
      ]);
      tts = container.read(ttsProvider.notifier);
      await tts.reload();
    });
    tearDown(() async {
      await tts.stop();
      container.dispose();
    });
    test(
        'same text with different language cancels old request and stays active',
        () async {
      final first = tts.speak('Hello!', lang: 'vi', owner: 'source');
      await until(() => container.read(ttsProvider).isPlaying);
      final next = tts.speak('Hello!', lang: 'en', owner: 'target');
      await until(() =>
          output.pending.length == 2 && container.read(ttsProvider).isPlaying);
      await first;
      expect(output.tokens.first.isCancelled, isTrue);
      expect(container.read(ttsProvider).matches('Hello!', 'en', 'target'),
          isTrue);
      expect(client.voices, ['vi-VN', 'en-US']);
      output.pending.last.complete();
      await next;
      expect(container.read(ttsProvider).isBusy, isFalse);
    });
    test('closing bubble stops only bubble playback, including pending setup',
        () async {
      final active = tts.speak('Hello!', lang: 'vi', owner: 'app');
      await until(() => container.read(ttsProvider).isPlaying);
      await tts.stop(ownerPrefix: 'bubble:');
      expect(container.read(ttsProvider).isPlaying, isTrue);
      await tts.stop();
      await active;
      final pending = tts.speak('Hello!', lang: 'vi', owner: 'bubble:source');
      await tts.stop(ownerPrefix: 'bubble:');
      await pending;
      expect(container.read(ttsProvider).isBusy, isFalse);
      expect(output.pending.length, 1);
    });
    test(
        'repeated tap stops and unsupported language reports without English fallback',
        () async {
      final active = tts.speak('Hello!', lang: 'vi', owner: 'button');
      await until(() => container.read(ttsProvider).isPlaying);
      await tts.speak('Hello!', lang: 'vi', owner: 'button');
      await active;
      expect(container.read(ttsProvider).isBusy, isFalse);
      expect(await tts.speak('Hello!', lang: 'xx'), TtsFailure.unsupported);
      expect(client.voices, ['vi-VN']);
      expect(container.read(ttsProvider).error, TtsFailure.unsupported);
    });
    testWidgets('unsupported languages keep mode selection reachable',
        (tester) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: Center(child: TtsButton(text: 'Hello', lang: 'xx'))),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1×'));
      await tester.pump();
      // Drain platform/preferences work without starting gesture animations
      // in the real-time zone. All taps stay on the widget test's clock.
      await tester.runAsync(() async {
        expect(await tts.voicesFor('xx'), isEmpty);
      });
      await tester.pumpAndSettle();
      expect(find.text('Natural voice (online)'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Device voice (offline)'));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        if (container.read(ttsProvider).mode == TtsMode.device &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(container.read(ttsProvider).mode, TtsMode.device);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Natural voice (online)'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    test('network error releases loading and another request can play',
        () async {
      client.fail = true;
      expect(await tts.speak('Hello!', lang: 'km'), TtsFailure.network);
      expect(container.read(ttsProvider).isBusy, isFalse);
      client.fail = false;
      final next = tts.speak('Hello!', lang: 'fil');
      await until(() => container.read(ttsProvider).isPlaying);
      expect(container.read(ttsProvider).error, isNull);
      output.pending.last.complete();
      await next;
    });
    test(
        'neural and device voice preferences remain separate and survive reload',
        () async {
      await tts.setVoice('VI_vn', 'vi-VN-NamMinhNeural');
      await tts.setMode(TtsMode.device);
      expect(container.read(ttsProvider).voiceByLang, isEmpty);
      await tts.setVoice('VI_vn', 'Device Voice');
      await tts.setMode(TtsMode.natural);
      expect(container.read(ttsProvider).voiceByLang['vi-vn'],
          'vi-VN-NamMinhNeural');
      await tts.reload();
      expect(container.read(ttsProvider).mode, TtsMode.natural);
    });
  });
}
