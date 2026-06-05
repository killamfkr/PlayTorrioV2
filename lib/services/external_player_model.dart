class ExternalPlayer {
  final String displayName;

  final String? androidPackage;
  final List<String>? androidAltPackages;
  final Map<String, dynamic>? androidExtras;

  final String? windowsBinary;
  final List<String>? windowsPaths;
  final String? windowsRegistryKey;
  final String? windowsRegistryValue;
  final String? windowsRegistryBinary;

  final String? linuxBinary;

  final String? macAppPath;
  final String? macBinary;

  final List<String> Function(
    String url,
    String? title,
    Map<String, String>? headers,
  )? desktopArgs;

  const ExternalPlayer({
    required this.displayName,
    this.androidPackage,
    this.androidAltPackages,
    this.androidExtras,
    this.windowsBinary,
    this.windowsPaths,
    this.windowsRegistryKey,
    this.windowsRegistryValue,
    this.windowsRegistryBinary,
    this.linuxBinary,
    this.macAppPath,
    this.macBinary,
    this.desktopArgs,
  });
}
