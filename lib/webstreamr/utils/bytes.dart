/// Tiny port of the `bytes` npm package — only the parser side that the
/// extractors need. Accepts strings like `"1.23 GB"`, `"500MB"`, `"1,024 KB"`.
library;

int? parseBytes(String? input) {
  if (input == null) return null;
  final m = RegExp(r'([\d.,]+)\s*([KMGTP]?B)', caseSensitive: false)
      .firstMatch(input);
  if (m == null) return null;
  final num = double.tryParse(m.group(1)!.replaceAll(',', ''));
  if (num == null) return null;
  const mult = {
    'B': 1,
    'KB': 1024,
    'MB': 1024 * 1024,
    'GB': 1024 * 1024 * 1024,
    'TB': 1024 * 1024 * 1024 * 1024,
    'PB': 1024 * 1024 * 1024 * 1024 * 1024,
  };
  final unit = m.group(2)!.toUpperCase();
  return (num * (mult[unit] ?? 1)).round();
}
