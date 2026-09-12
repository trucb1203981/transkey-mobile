class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    this.label,
    this.gender,
    this.neural = false,
  });
  final String name;
  final String locale;
  final String? label;
  final String? gender;
  final bool neural;

  factory TtsVoice.fromMap(Map<dynamic, dynamic> map) => TtsVoice(
        name: map['name']?.toString() ?? '',
        locale: map['locale']?.toString() ?? '',
      );
  Map<String, String> toPluginMap() => {'name': name, 'locale': locale};
}

enum TtsMode { natural, device }

enum TtsFailure { unsupported, network, playback }

class SpeechCancelled implements Exception {}

/// Owns cancellation across socket setup, transport and playback.
class SpeechCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw SpeechCancelled();
  }

  void add(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void remove(void Function() listener) => _listeners.remove(listener);
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }
}
