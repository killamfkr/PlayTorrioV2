/// Port of `unpacker` npm package — decodes the standard
/// `eval(function(p,a,c,k,e,d){...}(...))` packed-JS used by virtually every
/// streaming file host. Used by Dropload/Fastream/FileLions/FileMoon/Fsst/
/// LuluStream/Mixdrop/Streamtape/SuperVideo/Uqload extractors and others.
library;


/// Unpacks the first p,a,c,k,e,d string found in [source]. Returns the
/// decoded JavaScript text (still JS — caller usually regex-extracts the
/// real stream URL from it).
String unpack(String source) {
  final m = RegExp(
          r"\}\s*\(\s*'([^']+)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'([^']+)'\.split\('\|'\)\s*,\s*\d+\s*,\s*(?:\{\}|null)\s*\)\s*\)")
      .firstMatch(source);
  if (m == null) {
    throw FormatException('No p,a,c,k,e,d string found');
  }
  final payload = _unescape(m.group(1)!);
  final radix = int.parse(m.group(2)!);
  final count = int.parse(m.group(3)!);
  final symtab = m.group(4)!.split('|');
  if (symtab.length != count) {
    throw FormatException('Symtab length mismatch ($count vs ${symtab.length})');
  }
  String unbase(String word) {
    if (radix <= 10) return int.parse(word, radix: radix).toString();
    var n = 0;
    for (var i = 0; i < word.length; i++) {
      final c = word.codeUnitAt(i);
      int d;
      if (c >= 48 && c <= 57) {
        d = c - 48; // 0-9
      } else if (c >= 97 && c <= 122) {
        d = c - 97 + 10; // a-z
      } else if (c >= 65 && c <= 90) {
        d = c - 65 + 36; // A-Z
      } else {
        d = 0;
      }
      n = n * radix + d;
    }
    return n.toString();
  }

  return payload.replaceAllMapped(RegExp(r'\b\w+\b'), (mm) {
    final word = mm.group(0)!;
    final idx = int.tryParse(unbase(word));
    if (idx == null || idx < 0 || idx >= count) return word;
    final repl = symtab[idx];
    return repl.isEmpty ? word : repl;
  });
}

String _unescape(String s) {
  return s
      .replaceAll(r"\\", '\\')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"');
}

/// Public re-export so callers can do `unpackEval`.
String unpackEval(String html) {
  final m = RegExp(r'eval\(function\(p,a,c,k,e,d\).*?\)\)', dotAll: true)
      .firstMatch(html);
  if (m == null) {
    throw FormatException('No p,a,c,k,e,d string found');
  }
  return unpack(m.group(0)!);
}

/// Walk [linkRegExps] over the unpacked JS and return the first match group(1)
/// as an absolute https URL. Mirrors webstreamr/src/utils/embed.ts.
Uri extractUrlFromPacked(String html, List<RegExp> linkRegExps) {
  final unpacked = unpackEval(html);
  for (final rx in linkRegExps) {
    final m = rx.firstMatch(unpacked);
    if (m != null && m.groupCount >= 1 && m.group(1) != null) {
      final raw = m.group(1)!.replaceFirst(RegExp(r'^(https:)?\/\/'), '');
      return Uri.parse('https://$raw');
    }
  }
  throw StateError('Could not find a stream link in embed');
}

