/// Resolution helpers — 1:1 from webstreamr/src/utils/resolution.ts
library;

const List<String> kResolutions = [
  '2160p',
  '1440p',
  '1080p',
  '720p',
  '576p',
  '480p',
  '360p',
  '240p',
  '144p',
  'Unknown',
];

String getClosestResolution(int? height) {
  if (height == null) return 'Unknown';
  final nums = kResolutions
      .map((r) => int.tryParse(r.replaceAll('p', '')))
      .whereType<int>()
      .toList();
  int? closest;
  for (final n in nums) {
    if (closest == null || (height - n).abs() < (height - closest).abs()) {
      closest = n;
    }
  }
  return '${closest}p';
}

int? findHeight(String value) {
  final lower = value.toLowerCase();
  for (final r in kResolutions) {
    if (lower.contains(r.toLowerCase())) {
      return int.tryParse(r.replaceAll('p', ''));
    }
  }
  return null;
}
