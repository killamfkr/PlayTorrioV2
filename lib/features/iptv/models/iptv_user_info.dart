class IptvUserInfo {
  final String username;
  final String password;
  final String? message;
  final bool auth;
  final String status;
  final int? expDate; // Unix timestamp in seconds
  final bool isTrial;
  final int activeCons;
  final String? createdAt;
  final int maxConnections;
  final List<String> allowedOutputFormats;

  // Server info
  final String? serverUrl;
  final String? port;
  final String? httpsPort;
  final String? serverProtocol;
  final String? timezone;

  const IptvUserInfo({
    required this.username,
    required this.password,
    this.message,
    required this.auth,
    required this.status,
    this.expDate,
    this.isTrial = false,
    this.activeCons = 0,
    this.createdAt,
    this.maxConnections = 1,
    this.allowedOutputFormats = const ['m3u8', 'ts'],
    this.serverUrl,
    this.port,
    this.httpsPort,
    this.serverProtocol,
    this.timezone,
  });

  bool get isActive => status.toLowerCase() == 'active';
  bool get isExpired => status.toLowerCase() == 'expired';

  DateTime? get expiryDate {
    if (expDate == null || expDate == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(expDate! * 1000);
  }

  String get expiryString {
    final date = expiryDate;
    if (date == null) return 'Unlimited';
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  static String _monthName(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m - 1];
  }

  factory IptvUserInfo.fromJson(Map<String, dynamic> json) {
    final userInfo = json['user_info'] ?? {};
    final serverInfo = json['server_info'] ?? {};

    return IptvUserInfo(
      username: userInfo['username']?.toString() ?? '',
      password: userInfo['password']?.toString() ?? '',
      message: userInfo['message']?.toString(),
      auth: _parseBool(userInfo['auth']),
      status: userInfo['status']?.toString() ?? 'Unknown',
      expDate: _parseInt(userInfo['exp_date']),
      isTrial: _parseBool(userInfo['is_trial']),
      activeCons: _parseInt(userInfo['active_cons']) ?? 0,
      createdAt: userInfo['created_at']?.toString(),
      maxConnections: _parseInt(userInfo['max_connections']) ?? 1,
      allowedOutputFormats: _parseStringList(userInfo['allowed_output_formats']),
      serverUrl: serverInfo['url']?.toString(),
      port: serverInfo['port']?.toString(),
      httpsPort: serverInfo['https_port']?.toString(),
      serverProtocol: serverInfo['server_protocol']?.toString(),
      timezone: serverInfo['timezone']?.toString(),
    );
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return ['m3u8', 'ts'];
    if (value is List) return value.map((e) => e.toString()).toList();
    return ['m3u8', 'ts'];
  }
}
