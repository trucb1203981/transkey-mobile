import 'edge_voice_catalog.dart';
import 'speech_voice.dart';

String normalizeSpeechLocale(String input) {
  final value = input.trim().replaceAll('_', '-').toLowerCase();
  if (!RegExp(r'^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$').hasMatch(value)) return '';
  final parts = value.split('-');
  parts[0] = const {
        'no': 'nb',
        'tl': 'fil',
        'iw': 'he',
        'in': 'id'
      }[parts[0]] ??
      parts[0];
  return parts.join('-');
}

const _defaultLocales = {
  'en': 'en-us',
  'vi': 'vi-vn',
  'zh': 'zh-cn',
  'ar': 'ar-sa',
  'pt': 'pt-br',
  'es': 'es-es',
  'fr': 'fr-fr',
  'de': 'de-de',
  'bn': 'bn-in',
  'ta': 'ta-in',
  'ur': 'ur-pk',
  'sw': 'sw-ke',
};
const _preferred = {
  'en-us': 'Jenny',
  'vi-vn': 'HoaiMy',
  'ja-jp': 'Nanami',
  'ko-kr': 'SunHi',
  'zh-cn': 'Xiaoxiao',
  'fr-fr': 'Denise',
  'de-de': 'Katja',
  'es-es': 'Elvira',
  'it-it': 'Elsa',
  'pt-br': 'Francisca',
  'ru-ru': 'Svetlana',
  'ar-sa': 'Zariyah',
  'th-th': 'Premwadee',
  'nl-nl': 'Colette',
  'pl-pl': 'Zofia',
  'tr-tr': 'Emel',
};

List<TtsVoice> edgeVoicesFor(String language) {
  final normalized = normalizeSpeechLocale(language);
  if (normalized.isEmpty) return const [];
  final parts = normalized.split('-');
  final base = parts.first;
  var locale = normalized;
  if (!edgeVoiceCatalog.any((voice) => voice.locale.toLowerCase() == locale)) {
    final regions = parts.skip(1).where((part) => part.length == 2);
    if (regions.isNotEmpty) {
      locale = '$base-${regions.first}';
    } else if (base == 'zh' && parts.contains('hant')) {
      locale = 'zh-tw';
    } else {
      locale = _defaultLocales[base] ?? normalized;
    }
  }
  var result = edgeVoiceCatalog
      .where((voice) => voice.locale.toLowerCase() == locale)
      .toList();
  if (result.isEmpty && base != 'zh') {
    result = edgeVoiceCatalog
        .where((voice) => voice.locale.split('-').first == base)
        .toList();
  }
  result.sort((a, b) {
    final preferred = _preferred[locale];
    if (a.label == preferred && b.label != preferred) return -1;
    if (b.label == preferred && a.label != preferred) return 1;
    final gender = (a.gender ?? '').compareTo(b.gender ?? '');
    return gender == 0 ? a.name.compareTo(b.name) : gender;
  });
  return result;
}

TtsVoice resolveEdgeVoice(String language, [String? selected]) {
  final voices = edgeVoicesFor(language);
  if (voices.isEmpty) throw TtsFailure.unsupported;
  return voices.where((voice) => voice.name == selected).firstOrNull ??
      voices.first;
}
