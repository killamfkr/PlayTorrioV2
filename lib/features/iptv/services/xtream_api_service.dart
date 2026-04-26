import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/iptv_user_info.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/iptv_movie.dart';
import '../models/iptv_series.dart';

class XtreamApiService {
  final String serverUrl;
  final String username;
  final String password;
  final http.Client _client = http.Client();

  XtreamApiService({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  String get _base {
    final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    return '$base/player_api.php?username=$username&password=$password';
  }

  String get _serverBase {
    return serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
  }

  // ─── Authentication ─────────────────────────────────────────
  Future<IptvUserInfo> authenticate() async {
    final response = await _client.get(Uri.parse(_base)).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Authentication failed: ${response.statusCode}');
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) throw Exception('Invalid response format');
    return IptvUserInfo.fromJson(data);
  }

  // ─── Live TV ────────────────────────────────────────────────
  Future<List<IptvCategory>> getLiveCategories() async {
    final r = await _client.get(Uri.parse('$_base&action=get_live_categories')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Failed to fetch live categories');
    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.map((e) => IptvCategory.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<IptvChannel>> getLiveStreams({String? categoryId}) async {
    final url = categoryId != null
        ? '$_base&action=get_live_streams&category_id=$categoryId'
        : '$_base&action=get_live_streams';
    final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Failed to fetch live streams');
    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.map((e) => IptvChannel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  // ─── VOD (Movies) ──────────────────────────────────────────
  Future<List<IptvCategory>> getVodCategories() async {
    final r = await _client.get(Uri.parse('$_base&action=get_vod_categories')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Failed to fetch VOD categories');
    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.map((e) => IptvCategory.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<IptvMovie>> getVodStreams({String? categoryId}) async {
    final url = categoryId != null
        ? '$_base&action=get_vod_streams&category_id=$categoryId'
        : '$_base&action=get_vod_streams';
    final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Failed to fetch VOD streams');
    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.map((e) => IptvMovie.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<VodInfo> getVodInfo(int vodId) async {
    final r = await _client.get(Uri.parse('$_base&action=get_vod_info&vod_id=$vodId')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Failed to fetch VOD info');
    final data = jsonDecode(r.body);
    return VodInfo.fromJson(Map<String, dynamic>.from(data));
  }

  // ─── Series ─────────────────────────────────────────────────
  Future<List<IptvCategory>> getSeriesCategories() async {
    final r = await _client.get(Uri.parse('$_base&action=get_series_categories')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Failed to fetch series categories');
    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.map((e) => IptvCategory.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<IptvSeries>> getSeries({String? categoryId}) async {
    final url = categoryId != null
        ? '$_base&action=get_series&category_id=$categoryId'
        : '$_base&action=get_series';
    final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Failed to fetch series');
    final data = jsonDecode(r.body);
    if (data is! List) return [];
    return data.map((e) => IptvSeries.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    final r = await _client.get(Uri.parse('$_base&action=get_series_info&series_id=$seriesId')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Failed to fetch series info');
    final data = jsonDecode(r.body);
    return SeriesInfo.fromJson(Map<String, dynamic>.from(data));
  }

  // ─── EPG ────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getShortEpg(int streamId) async {
    try {
      final r = await _client.get(Uri.parse('$_base&action=get_short_epg&stream_id=$streamId&limit=2')).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      final listings = data['epg_listings'] as List?;
      if (listings != null && listings.isNotEmpty) {
        return Map<String, dynamic>.from(listings.first);
      }
    } catch (_) {}
    return null;
  }

  // ─── URL Builders ───────────────────────────────────────────
  String getLiveStreamUrl(int streamId, {String ext = 'm3u8'}) =>
      '$_serverBase/live/$username/$password/$streamId.$ext';

  String getMovieUrl(int streamId, String containerExtension) =>
      '$_serverBase/movie/$username/$password/$streamId.$containerExtension';

  String getEpisodeUrl(int episodeId, String containerExtension) =>
      '$_serverBase/series/$username/$password/$episodeId.$containerExtension';

  void dispose() {
    _client.close();
  }
}
