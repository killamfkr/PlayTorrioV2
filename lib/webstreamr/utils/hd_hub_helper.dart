/// Helper used by HDHub4u / FourKHDHub / HubCloud chains.
/// Port of webstreamr/src/source/hd-hub-helper.ts
///
/// The redirect page contains `'o','<base64>'` where the inner string after
/// base64-decoding twice + ROT13 decoding once + base64-decoding once is a
/// JSON `{"o": "<base64-of-real-url>"}`.
library;

import 'dart:convert';

import '../types.dart';
import 'fetcher.dart';

String _atob(String s) {
  // Tolerate URL-safe variants and missing padding.
  final norm = s.replaceAll('-', '+').replaceAll('_', '/');
  final pad = (4 - norm.length % 4) % 4;
  return utf8.decode(base64.decode(norm + ('=' * pad)));
}

String _rot13(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 65 && c <= 90) {
      out.writeCharCode(((c - 65 + 13) % 26) + 65);
    } else if (c >= 97 && c <= 122) {
      out.writeCharCode(((c - 97 + 13) % 26) + 97);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

Future<Uri> resolveRedirectUrl(
    Context ctx, Fetcher fetcher, Uri redirectUrl) async {
  final html = await fetcher.text(ctx, redirectUrl);
  final m = RegExp(r"'o'\s*,\s*'(.*?)'").firstMatch(html);
  if (m == null) {
    throw StateError('hd-hub redirect payload not found');
  }
  final inner = _atob(_rot13(_atob(_atob(m.group(1)!))));
  final data = jsonDecode(inner) as Map<String, dynamic>;
  return Uri.parse(_atob(data['o'] as String));
}
