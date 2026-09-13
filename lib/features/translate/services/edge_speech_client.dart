import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'speech_text.dart';
import 'speech_voice.dart';
import 'speech_diagnostics.dart';

const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _version = '143.0.3650.96';

String speechToken(DateTime now) {
  final seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000 + 11644473600;
  final ticks = (seconds - seconds % 300) * 10000000;
  return sha256.convert(utf8.encode('$ticks$_token')).toString().toUpperCase();
}

String escapeSpeechXml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Uint8List? speechAudioFrame(List<int> message, String requestId) {
  if (message.length < 2) throw const FormatException('TTS_INVALID_FRAME');
  final length = message[0] * 256 + message[1];
  if (length > message.length - 2) {
    throw const FormatException('TTS_INVALID_FRAME');
  }
  final headers = utf8.decode(message.sublist(2, 2 + length));
  if (!headers.contains('Path:audio') ||
      !headers.contains('X-RequestId:$requestId')) {
    return null;
  }
  return Uint8List.fromList(message.sublist(2 + length));
}

/// Drain a bounded transport while playback pauses its subscription.
/// Propagating that pause to a WebSocket can block protocol control frames.
Stream<List<int>> bufferSpeechTransport(Stream<List<int>> source) {
  StreamSubscription<List<int>>? subscription;
  late final StreamController<List<int>> output;
  output = StreamController<List<int>>(
    sync: true,
    onListen: () {
      subscription = source.listen(
        output.add,
        onError: output.addError,
        onDone: () => unawaited(output.close()),
      );
    },
    onCancel: () async => subscription?.cancel(),
  );
  return output.stream;
}

class SpeechStreamIncomplete implements Exception {
  const SpeechStreamIncomplete(this.bytes, this.ended, this.closeCode);
  final int bytes;
  final bool ended;
  final int? closeCode;

  @override
  String toString() =>
      'TTS_INCOMPLETE_AUDIO bytes=$bytes ended=$ended code=$closeCode';
}

bool _retryableSpeechFailure(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is TimeoutException ||
    (error is SpeechStreamIncomplete &&
        error.bytes == 0 &&
        !error.ended &&
        const {null, 1001, 1002, 1006, 1011, 1012, 1013}
            .contains(error.closeCode));

/// Retry a dropped connection only before this chunk has emitted audio.
/// Restarting a partly delivered MP3 would repeat speech or corrupt playback.
Stream<List<int>> retrySpeechTransport(
  Stream<List<int>> Function() connect,
  SpeechCancellation cancellation, {
  Duration retryDelay = const Duration(milliseconds: 300),
}) async* {
  for (var attempt = 1; attempt <= 3; attempt++) {
    cancellation.check();
    var receivedAudio = false;
    try {
      await for (final audio in connect()) {
        cancellation.check();
        if (audio.isNotEmpty) receivedAudio = true;
        yield audio;
      }
      return;
    } catch (error) {
      cancellation.check();
      if (receivedAudio || attempt == 3 || !_retryableSpeechFailure(error)) {
        rethrow;
      }
      recordSpeechEvent('transport-retry', {
        'attempt': attempt,
        'type': error.runtimeType.toString(),
        if (error is SpeechStreamIncomplete) 'closeCode': error.closeCode,
      });
      final waiting = Completer<void>();
      void stopWaiting() {
        if (!waiting.isCompleted) waiting.complete();
      }

      final timer = Timer(retryDelay * attempt, stopWaiting);
      cancellation.add(stopWaiting);
      try {
        await waiting.future;
        cancellation.check();
      } finally {
        timer.cancel();
        cancellation.remove(stopWaiting);
      }
    }
  }
}

/// Each subscription owns its TLS socket; cancellation cannot stop another request.
class EdgeSpeechClient {
  Stream<List<int>> speak(String text, TtsVoice voice, double rate,
          SpeechCancellation cancellation) =>
      // _speak caps each request at 8 MB of compressed audio. The player
      // separately bounds its decoded PCM queue, so neither buffer is unbounded.
      bufferSpeechTransport(retrySpeechTransport(
          () => _speak(text, voice, rate, cancellation), cancellation));

  Stream<List<int>> _speak(String text, TtsVoice voice, double rate,
      SpeechCancellation cancellation) async* {
    if (!rate.isFinite ||
        rate < 0.25 ||
        rate > 1.75 ||
        text.isEmpty ||
        text.length > speechChunkLimit) {
      throw ArgumentError('TTS_INVALID_INPUT');
    }
    cancellation.check();
    final requestId = const Uuid().v4().replaceAll('-', '');
    // WebSocket.connect adds supplied headers rather than replacing defaults.
    // Set the protocol client identity once to avoid a duplicate User-Agent.
    final client = HttpClient()
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_version Safari/537.36 Edg/$_version'
      ..connectionTimeout = const Duration(seconds: 15);
    WebSocket? socket;
    void cancel() {
      client.close(force: true);
      unawaited(socket?.close());
    }

    cancellation.add(cancel);
    final totalTimer = Timer(const Duration(minutes: 10), cancel);
    var bytes = 0;
    var ended = false;
    try {
      final uri = Uri.https('speech.platform.bing.com',
          '/consumer/speech/synthesize/readaloud/edge/v1', {
        'TrustedClientToken': _token,
        'Sec-MS-GEC': speechToken(DateTime.now()),
        'Sec-MS-GEC-Version': '1-$_version',
        'ConnectionId': requestId,
      }).replace(scheme: 'wss', port: 443);
      socket = await WebSocket.connect(uri.toString(),
          customClient: client,
          headers: {
            'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          }).timeout(const Duration(seconds: 15));
      cancellation.check();
      final config = jsonEncode({
        'context': {
          'synthesis': {
            'audio': {
              'metadataoptions': {
                'sentenceBoundaryEnabled': 'false',
                'wordBoundaryEnabled': 'false'
              },
              'outputFormat': 'audio-24khz-48kbitrate-mono-mp3',
            }
          }
        }
      });
      socket.add(
          'Content-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n$config');
      final ssml =
          '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${voice.locale}">'
          '<voice name="${voice.name}"><prosody pitch="+0Hz" rate="$rate" volume="100.0">'
          '${escapeSpeechXml(text)}</prosody></voice></speak>';
      socket.add(
          'X-RequestId:$requestId\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n$ssml');
      await for (final frame in socket.timeout(const Duration(seconds: 30))) {
        cancellation.check();
        if (frame is List<int>) {
          final audio = speechAudioFrame(frame, requestId);
          if (audio == null || audio.isEmpty) continue;
          bytes += audio.length;
          if (bytes > 8 * 1024 * 1024) {
            throw const FormatException('TTS_AUDIO_TOO_LARGE');
          }
          yield audio;
        } else if (frame is String &&
            frame.contains('Path:turn.end') &&
            frame.contains('X-RequestId:$requestId')) {
          ended = true;
          break;
        }
      }
      cancellation.check();
      if (!ended || bytes == 0) {
        throw SpeechStreamIncomplete(bytes, ended, socket.closeCode);
      }
    } finally {
      totalTimer.cancel();
      cancellation.remove(cancel);
      client.close(force: true);
      await socket?.close();
    }
  }
}
