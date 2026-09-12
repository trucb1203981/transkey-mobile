import 'dart:async';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'speech_voice.dart';
import 'speech_diagnostics.dart';

abstract class NeuralSpeechOutput {
  Future<void> play(Stream<List<int>> audio, SpeechCancellation cancellation,
      void Function() onStarted);
}

class StreamingSpeechOutput implements NeuralSpeechOutput {
  Future<void>? _initialization;

  @override
  Future<void> play(Stream<List<int>> audio, SpeechCancellation cancellation,
      void Function() onStarted) async {
    final engine = SoLoud.instance;
    recordSpeechEvent('output-initializing');
    final session = await AudioSession.instance;
    var sessionActive = false;
    AudioSource? source;
    StreamIterator<List<int>>? input;
    StreamSubscription<dynamic>? events;
    StreamSubscription<dynamic>? interruptions;
    StreamSubscription<dynamic>? unplugged;
    var finished = false;
    var started = false;
    final done = Completer<void>();
    void cancel() {
      finished = true;
      unawaited(input?.cancel());
      if (source != null) {
        for (final handle in source.handles.toList()) {
          unawaited(engine.stop(handle));
        }
      }
      if (!done.isCompleted) done.complete();
    }

    cancellation.add(cancel);
    try {
      cancellation.check();
      await session.configure(const AudioSessionConfiguration.speech());
      cancellation.check();
      sessionActive = await session.setActive(true);
      if (!sessionActive) throw TtsFailure.playback;
      cancellation.check();
      if (!engine.isInitialized) {
        await (_initialization ??= engine.init());
      }
      cancellation.check();
      recordSpeechEvent('output-active');
      interruptions = session.interruptionEventStream.listen((event) {
        if (event.begin) cancellation.cancel();
      });
      unplugged =
          session.becomingNoisyEventStream.listen((_) => cancellation.cancel());
      input = StreamIterator(audio);
      final prefix = BytesBuilder(copy: false);
      var inputEnded = false;
      while (prefix.length <= 32 * 1024) {
        final hasNext = await input.moveNext();
        cancellation.check();
        if (!hasNext) {
          inputEnded = true;
          break;
        }
        if (prefix.isEmpty) recordSpeechEvent('output-first-bytes');
        prefix.add(input.current);
      }
      if (prefix.isEmpty) throw TtsFailure.playback;
      var bytes = prefix.length;
      final initialAudio = prefix.takeBytes();
      // SoLoud 3.4.10 loses the final decode signal below its 32 KiB
      // streaming threshold (upstream #434). Decode bounded short files
      // completely; larger inputs still start before synthesis finishes.
      source = inputEnded
          ? await engine.loadMem(
              'tts-${DateTime.now().microsecondsSinceEpoch}.mp3', initialAudio)
          : engine.setBufferStream(
              format: BufferType.auto,
              bufferingType: BufferingType.released,
              maxBufferSizeBytes: 8 * 1024 * 1024,
              bufferingTimeNeeds: 0.3,
              onBuffering: (buffering, handle, time) {
                if (!buffering && !finished && !started) {
                  started = true;
                  onStarted();
                }
              },
            );
      final ownedSource = source;
      cancellation.check();
      final handle = await engine.play(ownedSource);
      recordSpeechEvent('output-handle');
      cancellation.check();
      events = ownedSource.soundEvents.listen((event) {
        if (event.event == SoundEventType.handleIsNoMoreValid &&
            event.handle == handle) {
          if (!done.isCompleted) done.complete();
        }
      });
      if (inputEnded) {
        started = true;
        onStarted();
      } else {
        engine.addAudioDataStream(ownedSource, initialAudio);
        while (await input.moveNext()) {
          cancellation.check();
          // Bound decoded audio while the independently buffered transport
          // continues draining protocol frames.
          while (engine.getBufferSize(ownedSource) > 2 * 1024 * 1024) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            cancellation.check();
          }
          final chunk = input.current;
          engine.addAudioDataStream(ownedSource, Uint8List.fromList(chunk));
          bytes += chunk.length;
        }
      }
      cancellation.check();
      recordSpeechEvent('output-input-ended', {'bytes': bytes});
      if (!inputEnded) engine.setDataIsEnded(ownedSource);
      await done.future.timeout(const Duration(minutes: 10));
      recordSpeechEvent('output-complete');
    } finally {
      finished = true;
      cancellation.remove(cancel);
      await input?.cancel();
      await events?.cancel();
      await interruptions?.cancel();
      await unplugged?.cancel();
      try {
        if (source != null) await engine.disposeSource(source);
      } finally {
        // iOS requires the output audio unit to stop before deactivation.
        // Disposing a source alone leaves the engine running and causes
        // AVAudioSession isBusy, followed by a stalled next playback.
        if (engine.isInitialized) engine.deinit();
        _initialization = null;
        if (sessionActive) await session.setActive(false);
        recordSpeechEvent('output-released');
      }
    }
  }
}
