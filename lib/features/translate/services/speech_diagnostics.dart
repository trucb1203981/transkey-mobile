import 'dart:convert';
import 'dart:io';

Future<void> _pending = Future<void>.value();

/// Opt-in device acceptance trace. Never records spoken text or credentials.
void recordSpeechEvent(String event, [Map<String, Object?> data = const {}]) {
  if (!const bool.fromEnvironment('TTS_DIAGNOSTICS')) return;
  final line = jsonEncode({
    'time': DateTime.now().toUtc().toIso8601String(),
    'event': event,
    ...data,
  });
  _pending = _pending.then((_) async {
    final file = File('${Directory.systemTemp.path}/transkey-tts.jsonl');
    final mode = await file.exists() && await file.length() > 256 * 1024
        ? FileMode.write
        : FileMode.append;
    await file.writeAsString('$line\n', mode: mode, flush: true);
  }).catchError((Object _) {});
}
