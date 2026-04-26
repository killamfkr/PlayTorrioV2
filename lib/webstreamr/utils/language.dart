/// Country / language tables — 1:1 from webstreamr/src/utils/language.ts
library;

import '../types.dart';

class _LangInfo {
  final String language;
  final String flag;
  final String? iso639;
  const _LangInfo(this.language, this.flag, this.iso639);
}

const Map<CountryCode, _LangInfo> _table = {
  CountryCode.multi: _LangInfo('Multi', '🌐', null),
  CountryCode.al: _LangInfo('Albanian', '🇦🇱', 'alb'),
  CountryCode.ar: _LangInfo('Arabic', '🇸🇦', 'ara'),
  CountryCode.bg: _LangInfo('Bulgarian', '🇧🇬', 'bul'),
  CountryCode.bl: _LangInfo('Bengali', '🇮🇳', 'mal'),
  CountryCode.cs: _LangInfo('Czech', '🇨🇿', 'ces'),
  CountryCode.de: _LangInfo('German', '🇩🇪', 'ger'),
  CountryCode.el: _LangInfo('Greek', '🇬🇷', 'gre'),
  CountryCode.en: _LangInfo('English', '🇺🇸', 'eng'),
  CountryCode.es: _LangInfo('Castilian Spanish', '🇪🇸', 'spa'),
  CountryCode.et: _LangInfo('Estonian', '🇪🇪', 'est'),
  CountryCode.fa: _LangInfo('Persian', '🇮🇷', 'fas'),
  CountryCode.fr: _LangInfo('French', '🇫🇷', 'fra'),
  CountryCode.gu: _LangInfo('Gujarati', '🇮🇳', 'guj'),
  CountryCode.he: _LangInfo('Hebrew', '🇮🇱', 'heb'),
  CountryCode.hi: _LangInfo('Hindi', '🇮🇳', 'hin'),
  CountryCode.hr: _LangInfo('Croatian', '🇭🇷', 'hrv'),
  CountryCode.hu: _LangInfo('Hungarian', '🇭🇺', 'hun'),
  CountryCode.id: _LangInfo('Indonesian', '🇮🇩', 'ind'),
  CountryCode.it: _LangInfo('Italian', '🇮🇹', 'ita'),
  CountryCode.ja: _LangInfo('Japanese', '🇯🇵', 'jpn'),
  CountryCode.kn: _LangInfo('Kannada', '🇮🇳', 'kan'),
  CountryCode.ko: _LangInfo('Korean', '🇰🇷', 'kor'),
  CountryCode.lt: _LangInfo('Lithuanian', '🇱🇹', 'lit'),
  CountryCode.lv: _LangInfo('Latvian', '🇱🇻', 'lav'),
  CountryCode.ml: _LangInfo('Malayalam', '🇮🇳', 'mal'),
  CountryCode.mr: _LangInfo('Marathi', '🇮🇳', 'mar'),
  CountryCode.mx: _LangInfo('Latin American Spanish', '🇲🇽', 'spa'),
  CountryCode.nl: _LangInfo('Dutch', '🇳🇱', 'nld'),
  CountryCode.no: _LangInfo('Norwegian', '🇳🇴', 'nor'),
  CountryCode.pa: _LangInfo('Punjabi', '🇮🇳', 'pan'),
  CountryCode.pl: _LangInfo('Polish', '🇵🇱', 'pol'),
  CountryCode.pt: _LangInfo('Portuguese', '🇧🇷', 'por'),
  CountryCode.ro: _LangInfo('Romanian', '🇷🇴', 'ron'),
  CountryCode.ru: _LangInfo('Russian', '🇷🇺', 'rus'),
  CountryCode.sk: _LangInfo('Slovak', '🇸🇰', 'slk'),
  CountryCode.sl: _LangInfo('Slovenian', '🇸🇮', 'slv'),
  CountryCode.sr: _LangInfo('Serbian', '🇷🇸', 'srp'),
  CountryCode.ta: _LangInfo('Tamil', '🇮🇳', 'tal'),
  CountryCode.te: _LangInfo('Telugu', '🇮🇳', 'tel'),
  CountryCode.th: _LangInfo('Thai', '🇹🇭', 'tha'),
  CountryCode.tr: _LangInfo('Turkish', '🇹🇷', 'tur'),
  CountryCode.uk: _LangInfo('Ukrainian', '🇺🇦', 'ukr'),
  CountryCode.vi: _LangInfo('Vietnamese', '🇻🇳', 'vie'),
  CountryCode.zh: _LangInfo('Chinese', '🇨🇳', 'zho'),
};

String languageFromCountryCode(CountryCode c) => _table[c]!.language;
String flagFromCountryCode(CountryCode c) => _table[c]!.flag;
String? iso639FromCountryCode(CountryCode c) => _table[c]!.iso639;

List<CountryCode> findCountryCodes(String value) {
  final out = <CountryCode>[];
  for (final entry in _table.entries) {
    if (!out.contains(entry.key) && value.contains(entry.value.language)) {
      out.add(entry.key);
    }
  }
  return out;
}
