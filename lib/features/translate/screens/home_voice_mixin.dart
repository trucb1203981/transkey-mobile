import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/tracking/tracking_provider.dart';
import '../../../core/voice/voice_locales.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../providers/language_settings_provider.dart';
import '../providers/translate_provider.dart';
import '../widgets/language_picker_sheet.dart';

/// Voice-to-text controller mixin for the home screen. Owns the
/// SpeechToText plugin lifecycle, the listening flag, and the prefix
/// snapshot of the source-text field captured before listening starts.
///
/// Extracted from home_screen.dart so the screen file is no longer 870
/// LOC of mixed concerns. The mixin sits on top of `ConsumerState<T>` so
/// it can use [context], [ref], and [mounted] directly. The consuming
/// state must implement [voiceTextController] to expose the source-field
/// controller — both the build method and the voice handler need to
/// touch the same controller, and we don't want to pass it through a
/// constructor (mixins can't take constructor args).
mixin HomeVoiceMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The source-text field the voice recogniser writes partial / final
  /// transcripts into. Implementing State must already own this controller
  /// for its own build method — the mixin just borrows it.
  TextEditingController get voiceTextController;

  // Lazily created on first toggle and reused for the lifetime of the
  // widget; calling initialize() repeatedly is fine but the plugin warns
  // about leaked instances if you create a new SpeechToText on every
  // tap.
  stt.SpeechToText? _speech;
  // Text already in the field BEFORE we started listening — appended to
  // recognised words so users can dictate additions instead of dictating
  // a wholesale replacement of what they typed.
  String _speechPrefix = '';
  bool _isListening = false;

  // Tracking helpers: the SpeechToText instance is REUSED across sessions
  // and its onStatus/onError callbacks are registered once via initialize()
  // — the closure captures `sourceLang` from the FIRST call, which is wrong
  // when the user picks a different source lang between sessions. Mirror it
  // into a state variable that the callbacks read live. `_completeFired`
  // dedupes when both 'done' AND 'notListening' fire for the same session.
  String _activeVoiceLang = '';
  bool _completeFired = false;

  bool get isListening => _isListening;

  void _setListening(bool value) {
    if (!mounted) return;
    setState(() => _isListening = value);
  }

  /// Toggle voice-to-text. First tap: ask for mic permission (if not
  /// granted), start listening with the currently-selected source
  /// language as the recognition locale, and stream partial results
  /// into the text field. Second tap: stop early. Auto-stops on the
  /// pauseFor / listenFor timeouts configured below.
  Future<void> toggleSpeechToText() async {
    final l = AppLocalizations.of(context)!;
    if (_isListening) {
      await _speech?.stop();
      _setListening(false);
      // User-tap-stop: speech_to_text emits `notListening` here, not `done`,
      // so the onStatus branch below wouldn't fire a complete event. Fire
      // it manually with the partial text the user managed to dictate.
      _fireVoiceComplete(success: true, source: 'user_stop');
      return;
    }
    // Android SpeechRecognizer needs a concrete locale — it CAN'T
    // auto-detect across languages. If the picker is "Auto", open the
    // source picker WITH an inline hint banner explaining why (a
    // SnackBar would sit behind the modal sheet and the user would
    // never read it — Material renders snackbars on the Scaffold's
    // overlay, below modal routes on the Navigator stack).
    final langs = ref.read(languageSettingsProvider).valueOrNull;
    final sourceLang = langs?.sourceLang ?? 'auto';
    if (sourceLang == 'auto') {
      final code = await LanguagePickerSheet.show(
        context,
        selectedCode: sourceLang,
        showAuto: true,
        field: LanguagePickerField.source,
        hint: LanguagePickerHint(
          text: l.voicePickSourceLang,
          icon: Icons.mic_none,
        ),
      );
      if (code != null && code != 'auto') {
        await ref.read(languageSettingsProvider.notifier).setSourceLang(code);
        if (mounted) ref.read(translateProvider.notifier).clearResult();
      }
      return;
    }
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voicePermDenied)),
        );
      }
      return;
    }
    final speech = _speech ??= stt.SpeechToText();
    final available = await speech.initialize(
      // Both callbacks read `_activeVoiceLang` (state) instead of capturing
      // `sourceLang` in their closures — `initialize` registers handlers
      // ONCE and reusing the SpeechToText across sessions with new langs
      // would otherwise emit the stale lang from the first session.
      onError: (_) {
        _setListening(false);
        _fireVoiceComplete(success: false, source: 'plugin_error');
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _setListening(false);
          if (status == 'done') {
            _fireVoiceComplete(success: true, source: 'speech_done');
          }
        }
      },
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voiceUnsupported)),
        );
      }
      return;
    }
    // Recognition locale was validated above (auto is rejected).
    final localeId = bcp47ForLang(sourceLang);

    _speechPrefix = voiceTextController.text;
    _activeVoiceLang = sourceLang;
    _completeFired = false;
    _setListening(true);
    ref.read(trackingServiceProvider).event('voice_input_start',
        properties: {'lang': sourceLang});
    await speech.listen(
      localeId: localeId,
      // 60s session + 6s pause tolerance: previous 30s/3s defaults were
      // cutting users off mid-sentence — Vietnamese speakers in particular
      // pause a beat between clauses, and a 3 s silence timer fires before
      // the next word lands. Doubled both to leave room for natural cadence
      // without locking the mic open indefinitely.
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 6),
      // Dictation mode: streams partial results word-by-word as the user
      // speaks (matches the bubble's native SpeechRecognizer behaviour).
      // Without it, the plugin's default `confirmation` mode batches the
      // entire utterance and only emits one onResult at the end — which
      // looks identical to the user as "the mic is broken / nothing is
      // happening" until they stop talking.
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (result) {
        final joined = _speechPrefix.isEmpty
            ? result.recognizedWords
            : '$_speechPrefix ${result.recognizedWords}';
        voiceTextController.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
      },
    );
  }

  /// Stop any in-flight session. Called from the host's dispose() so the
  /// plugin doesn't keep an open mic when the screen is torn down.
  Future<void> stopVoiceIfListening() async {
    if (_isListening) {
      await _speech?.stop();
    }
  }

  /// Single place that fires `voice_input_complete`. Dedupes when both
  /// `done` and `notListening` arrive for the same session, and reads the
  /// CURRENT lang from state (not a stale closure).
  void _fireVoiceComplete({required bool success, required String source}) {
    if (_completeFired) return;
    _completeFired = true;
    final length = voiceTextController.text.length - _speechPrefix.length;
    ref.read(trackingServiceProvider).event('voice_input_complete',
        properties: {
          'lang':    _activeVoiceLang,
          'success': success,
          'length':  length < 0 ? 0 : length,
          'source':  source,
        });
  }
}
