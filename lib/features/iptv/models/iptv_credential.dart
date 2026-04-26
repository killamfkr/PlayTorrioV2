enum IptvLoginType { xtream, m3u }

class IptvCredential {
  final IptvLoginType type;
  final String id; // Unique identifier
  final String name; // Display name
  final String? serverUrl;
  final String? username;
  final String? password;
  final String? m3uUrl;

  IptvCredential({
    required this.type,
    String? id,
    String? name,
    this.serverUrl,
    this.username,
    this.password,
    this.m3uUrl,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name = name ?? (type == IptvLoginType.xtream ? (serverUrl ?? 'Xtream') : 'M3U Playlist');

  /// Xtream constructor
  IptvCredential.xtream({
    required String server,
    required String user,
    required String pass,
    String? id,
    String? name,
  })  : type = IptvLoginType.xtream,
        id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name = name ?? server,
        serverUrl = server,
        username = user,
        password = pass,
        m3uUrl = null;

  /// M3U constructor
  IptvCredential.m3u({
    required String url,
    String? id,
    String? name,
  })  : type = IptvLoginType.m3u,
        id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name = name ?? 'M3U Playlist',
        m3uUrl = url,
        serverUrl = null,
        username = null,
        password = null;

  Map<String, dynamic> toJson() => {
        'type': type == IptvLoginType.xtream ? 'xtream' : 'm3u',
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'm3uUrl': m3uUrl,
      };

  factory IptvCredential.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == 'xtream' ? IptvLoginType.xtream : IptvLoginType.m3u;
    return IptvCredential(
      type: type,
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? (type == IptvLoginType.xtream ? (json['serverUrl'] ?? 'Xtream') : 'M3U Playlist'),
      serverUrl: json['serverUrl'],
      username: json['username'],
      password: json['password'],
      m3uUrl: json['m3uUrl'],
    );
  }
}
