/// Pure-Dart IPv4 check (no `dart:io`) so UI code can run on web.
bool isIpv4Literal(String raw) {
  final s = raw.trim();
  final parts = s.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    if (p.isEmpty) return false;
    if (p.length > 1 && p.startsWith('0')) return false;
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}
