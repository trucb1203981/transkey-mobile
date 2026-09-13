import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/services/edge_speech_client.dart';
import 'package:transkey_mobile/features/translate/services/speech_voice.dart';

void main() {
  for (final failure in <Object>[
    const SpeechStreamIncomplete(0, false, 1002),
    const SocketException('Connection reset'),
    const HttpException('Connection closed before full header was received'),
    TimeoutException('Connect timeout'),
  ]) {
    test('reconnects after ${failure.runtimeType} before audio', () async {
      var attempts = 0;
      final chunks = await retrySpeechTransport(() async* {
        if (++attempts == 1) throw failure;
        yield [1, 2, 3];
        yield [4, 5];
      }, SpeechCancellation(), retryDelay: Duration.zero)
          .toList();
      expect(attempts, 2);
      expect(chunks, [
        [1, 2, 3],
        [4, 5]
      ]);
    });
  }

  test('successful first connection is never repeated', () async {
    var attempts = 0;
    final chunks = await retrySpeechTransport(() async* {
      attempts++;
      yield [1, 2, 3];
    }, SpeechCancellation())
        .toList();
    expect(chunks, [
      [1, 2, 3]
    ]);
    expect(attempts, 1);
  });

  test('stops after two retries and preserves the final failure', () async {
    var attempts = 0;
    const failure = SpeechStreamIncomplete(0, false, 1002);
    await expectLater(
        retrySpeechTransport(() async* {
          attempts++;
          throw failure;
        }, SpeechCancellation(), retryDelay: Duration.zero),
        emitsError(same(failure)));
    expect(attempts, 3);
  });

  test('never replays audio after a partial stream failure', () async {
    var attempts = 0;
    const failure = SpeechStreamIncomplete(3, false, 1002);
    await expectLater(
        retrySpeechTransport(() async* {
          attempts++;
          yield [1, 2, 3];
          throw failure;
        }, SpeechCancellation(), retryDelay: Duration.zero),
        emitsInOrder([
          [1, 2, 3],
          emitsError(same(failure))
        ]));
    expect(attempts, 1);
  });

  for (final failure in <Object>[
    const FormatException('TTS_INVALID_FRAME'),
    const SpeechStreamIncomplete(0, true, 1000),
    const SpeechStreamIncomplete(0, false, 1008),
    const WebSocketException('Forbidden'),
    TtsFailure.unsupported,
    ArgumentError('TTS_INVALID_INPUT'),
  ]) {
    test('does not retry permanent failure $failure', () async {
      var attempts = 0;
      await expectLater(
          retrySpeechTransport(() async* {
            attempts++;
            throw failure;
          }, SpeechCancellation(), retryDelay: Duration.zero),
          emitsError(same(failure)));
      expect(attempts, 1);
    });
  }

  test('cancel before connecting does not open a socket', () async {
    var attempts = 0;
    final cancellation = SpeechCancellation()..cancel();
    await expectLater(
        retrySpeechTransport(() async* {
          attempts++;
          yield [1];
        }, cancellation),
        emitsError(isA<SpeechCancelled>()));
    expect(attempts, 0);
  });

  test('cancel during retry delay stops promptly without a new attempt',
      () async {
    var attempts = 0;
    final cancellation = SpeechCancellation();
    final first = Completer<void>();
    final stream = retrySpeechTransport(() async* {
      attempts++;
      first.complete();
      throw const SpeechStreamIncomplete(0, false, 1002);
    }, cancellation, retryDelay: const Duration(minutes: 1));
    final result = expectLater(stream, emitsError(isA<SpeechCancelled>()));
    await first.future;
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    await result.timeout(const Duration(seconds: 1));
    expect(attempts, 1);
  });

  test('a subsequent chunk retries without replaying a completed chunk',
      () async {
    var attempts = 0;
    Stream<List<int>> audio() async* {
      yield [1, 2];
      yield* retrySpeechTransport(() async* {
        if (++attempts == 1) throw const SocketException('Connection reset');
        yield [3, 4];
      }, SpeechCancellation(), retryDelay: Duration.zero);
    }

    expect(await audio().toList(), [
      [1, 2],
      [3, 4]
    ]);
    expect(attempts, 2);
  });
}
