import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/episode_matcher.dart';

class DebridFile {
  final String filename;
  final int filesize;
  final String downloadUrl;

  DebridFile({required this.filename, required this.filesize, required this.downloadUrl});
}

class DebridApi {
  static final DebridApi _instance = DebridApi._internal();
  factory DebridApi() => _instance;
  DebridApi._internal();

  // We use plain SharedPreferences instead of flutter_secure_storage. The
  // secure-storage backends (Android Keystore, macOS Keychain) can hang or
  // throw under various platform-specific conditions, leaving the settings
  // UI stuck on a spinner forever. Debrid API keys aren't sensitive enough
  // to justify that fragility — a stolen one only grants access to the
  // user's own debrid account, which they can rotate from the web UI.

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> _safeRead(String key) async {
    try {
      return (await _prefs).getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await (await _prefs).setString(key, value);
    } catch (_) {}
  }

  Future<void> _safeDelete(String key) async {
    try {
      await (await _prefs).remove(key);
    } catch (_) {}
  }

  // --- Real-Debrid (private API token) ---
  //
  // RD exposes a personal, long-lived API token at
  //   https://real-debrid.com/apitoken
  // which is used directly as `Authorization: Bearer <token>`. This avoids the
  // OAuth device flow (and its 1h access-token expiry) entirely, so the login
  // never silently disappears across restarts.

  static const String _rdTokenKey = 'rd_access_token';

  Future<void> saveRDApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await logoutRD();
      return;
    }
    await _safeWrite(_rdTokenKey, trimmed);
  }

  Future<String?> getRDAccessToken() async {
    return await _safeRead(_rdTokenKey);
  }

  /// Verifies the stored token by hitting RD's `/user` endpoint.
  /// Returns the user JSON on success, or null on failure.
  Future<Map<String, dynamic>?> verifyRDApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/user'),
        headers: {'Authorization': 'Bearer $trimmed'},
      );
      if (res.statusCode == 200) {
        return json.decode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> logoutRD() async {
    // Clean up the current key plus any leftovers from the old OAuth flow so
    // upgrading users don't end up with stale credentials.
    for (final key in [
      _rdTokenKey,
      'rd_refresh_token',
      'rd_token_expiry',
      'rd_client_id',
      'rd_client_secret',
    ]) {
      await _safeDelete(key);
    }
  }

  // --- Real-Debrid Flow ---

  /// Adds [magnet] to Real-Debrid, picks the file for the requested
  /// [season]/[episode] (or the largest video for movies / when SE is null),
  /// and unrestricts ONLY that single file.
  ///
  /// Returns a single-element list — the caller should just use
  /// `files.first.downloadUrl`. The `match.first.downloadUrl` /
  /// `files.first.downloadUrl` patterns in older call sites still work
  /// because the only file in the list is the right one.
  Future<List<DebridFile>> resolveRealDebrid(
    String magnet, {
    int? season,
    int? episode,
  }) async {
    final token = await getRDAccessToken();
    if (token == null) throw Exception("Real-Debrid not logged in");

    final headers = {'Authorization': 'Bearer $token'};

    // 1. Add the magnet.
    final addRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/addMagnet'),
      headers: headers,
      body: {'magnet': magnet},
    );
    if (addRes.statusCode != 201) {
      throw Exception("Failed to add magnet to RD: ${addRes.body}");
    }
    final torrentId = json.decode(addRes.body)['id'] as String;

    // 2. Wait for the file list to be available, then pick the file we want.
    Map<String, dynamic>? info;
    List<dynamic>? rdFiles;
    int attempts = 0;
    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      info = json.decode(infoRes.body) as Map<String, dynamic>;
      final status = info['status'] as String?;
      if (status == 'magnet_error' || status == 'error' || status == 'dead' ||
          status == 'virus') {
        throw Exception("RD rejected magnet (status: $status)");
      }
      rdFiles = (info['files'] as List?) ?? const [];
      if (rdFiles.isNotEmpty) break;
      await Future.delayed(const Duration(seconds: 2));
      attempts++;
    }
    if (rdFiles == null || rdFiles.isEmpty) {
      throw Exception("RD never returned a file list");
    }

    // 3. Pick the file we actually want and select ONLY that one. This
    //    speeds up the "downloaded" status (RD doesn't have to fetch the
    //    rest of the pack) and keeps quota usage minimal.
    final picked = (season != null && episode != null)
        ? EpisodeMatcher.pickEpisode<dynamic>(
            rdFiles,
            season,
            episode,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['bytes'] as num?)?.toInt() ?? 0,
          )
        : EpisodeMatcher.pickLargestVideo<dynamic>(
            rdFiles,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['bytes'] as num?)?.toInt() ?? 0,
          );
    if (picked == null) {
      throw Exception("No video file found in torrent");
    }
    final pickedId = picked['id'].toString();
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedSize = (picked['bytes'] as num?)?.toInt() ?? 0;
    debugPrint('[RD] picked file id=$pickedId  path=$pickedPath');

    final selRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
      headers: headers,
      body: {'files': pickedId},
    );
    if (selRes.statusCode != 204 && selRes.statusCode != 202) {
      // Fall back to selecting all if RD rejects single-file selection.
      debugPrint('[RD] single-file select failed (${selRes.statusCode}), falling back to all');
      await http.post(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/selectFiles/$torrentId'),
        headers: headers,
        body: {'files': 'all'},
      );
    }

    // 4. Poll until the file is fully fetched (cached torrents finish almost
    //    immediately).
    attempts = 0;
    while (attempts < 40) {
      final infoRes = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/torrents/info/$torrentId'),
        headers: headers,
      );
      info = json.decode(infoRes.body) as Map<String, dynamic>;
      final status = info['status'] as String?;
      if (status == 'downloaded') break;
      if (status == 'error' || status == 'dead' || status == 'virus') {
        throw Exception("RD download failed (status: $status)");
      }
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }
    if (info!['status'] != 'downloaded') {
      throw Exception("RD download timed out");
    }

    // 5. Unrestrict ONLY the picked file's link.
    final links = (info['links'] as List?) ?? const [];
    if (links.isEmpty) throw Exception("RD returned no links");
    // After single-file selection RD returns exactly one link. After the
    // 'all' fallback we have to find the link matching our picked file by
    // looking at the position of the picked file inside the selected files.
    String? targetLink;
    if (links.length == 1) {
      targetLink = links.first as String;
    } else {
      final selectedFiles = (info['files'] as List)
          .where((f) => (f['selected'] as int?) == 1)
          .toList();
      final idx = selectedFiles.indexWhere((f) => f['id'].toString() == pickedId);
      if (idx >= 0 && idx < links.length) {
        targetLink = links[idx] as String;
      } else {
        targetLink = links.first as String;
      }
    }

    final unRes = await http.post(
      Uri.parse('https://api.real-debrid.com/rest/1.0/unrestrict/link'),
      headers: headers,
      body: {'link': targetLink},
    );
    if (unRes.statusCode != 200) {
      throw Exception("RD unrestrict failed: ${unRes.body}");
    }
    final data = json.decode(unRes.body) as Map<String, dynamic>;
    return [
      DebridFile(
        filename: (data['filename'] as String?) ?? pickedPath.split('/').last,
        filesize: (data['filesize'] as num?)?.toInt() ?? pickedSize,
        downloadUrl: data['download'] as String,
      ),
    ];
  }

  // --- TorBox Flow ---

  Future<void> saveTorBoxKey(String key) async {
    await _safeWrite('torbox_api_key', key.trim());
  }

  Future<String?> getTorBoxKey() async {
    return await _safeRead('torbox_api_key');
  }

  Future<List<DebridFile>> resolveTorBox(
    String magnet, {
    int? season,
    int? episode,
  }) async {
    final apiKey = await getTorBoxKey();
    if (apiKey == null) throw Exception("TorBox API Key not set");

    final headers = {'Authorization': 'Bearer $apiKey'};

    // 1. Create Torrent
    final createRes = await http.post(
      Uri.parse('https://api.torbox.app/v1/api/torrents/createtorrent'),
      headers: headers,
      body: {'magnet': magnet},
    );
    
    final createData = json.decode(createRes.body);
    if (createData['success'] == false) throw Exception("TorBox failed: ${createData['detail']}");
    
    final torrentId = createData['data']['torrent_id'];

    // 2. Poll status
    Map<String, dynamic>? info;
    int attempts = 0;
    while (attempts < 20) {
      final infoRes = await http.get(
        Uri.parse('https://api.torbox.app/v1/api/torrents/mylist?id=$torrentId&bypass_cache=true'),
        headers: headers,
      );
      final mylist = json.decode(infoRes.body)['data'];
      // TorBox returns a single object if ID is provided
      info = mylist;
      if (info!['download_finished'] == true || info['download_state'] == 'cached') break;
      if (info['download_state'] == 'error') throw Exception("TorBox Download failed");
      
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    final List rawFiles = (info!['files'] as List?) ?? const [];
    if (rawFiles.isEmpty) throw Exception("TorBox returned no files");

    // 3. Pick the right file (episode match or largest video) instead of
    //    handing the caller all of them. Returns a single-element list so
    //    `files.first.downloadUrl` is always the right URL.
    final picked = (season != null && episode != null)
        ? EpisodeMatcher.pickEpisode<dynamic>(
            rawFiles,
            season,
            episode,
            name: (f) => (f['name'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          )
        : EpisodeMatcher.pickLargestVideo<dynamic>(
            rawFiles,
            name: (f) => (f['name'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          );
    if (picked == null) throw Exception("No video file found in torrent");

    final permalink =
        'https://api.torbox.app/v1/api/torrents/requestdl?token=$apiKey'
        '&torrent_id=$torrentId&file_id=${picked['id']}&redirect=true';
    return [
      DebridFile(
        filename: (picked['name'] as String?) ?? 'video',
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: permalink,
      ),
    ];
  }

  // --- AllDebrid Flow ---
  //
  // AllDebrid uses a magnet -> magnet id -> file tree -> per-file unlock flow:
  //   1. POST /v4/magnet/upload    {magnets[]}    -> {id}
  //   2. POST /v4.1/magnet/status  {id}           -> wait for statusCode == 4
  //   3. POST /v4/magnet/files     {id[]}         -> nested tree of {n,s,l}
  //   4. Pick the right file from the FLATTENED tree, then
  //   5. POST /v4/link/unlock      {link: <l>}    -> {link: "https://..."}
  //
  // The /magnet/files response is recursive: a folder is `{n: name, e: [...]}`,
  // a file is `{n: name, s: size, l: unlock-url}`. We flatten to a plain list
  // so EpisodeMatcher can do its thing on full paths.

  Future<void> saveAllDebridKey(String key) async {
    await _safeWrite('alldebrid_api_key', key.trim());
  }

  Future<String?> getAllDebridKey() async {
    return await _safeRead('alldebrid_api_key');
  }

  /// Recursively walks AllDebrid's nested file tree and collects every file
  /// node, building the full path so episode matching has the same context
  /// as RD/TorBox (where filename includes folder names).
  void _flattenAdFiles(
    List<dynamic> nodes,
    String prefix,
    List<Map<String, dynamic>> out,
  ) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final name = (node['n'] as String?) ?? '';
      final children = node['e'];
      if (children is List) {
        _flattenAdFiles(
          children,
          prefix.isEmpty ? name : '$prefix/$name',
          out,
        );
      } else {
        out.add({
          'path': prefix.isEmpty ? name : '$prefix/$name',
          'size': (node['s'] as num?)?.toInt() ?? 0,
          'link': (node['l'] as String?) ?? '',
        });
      }
    }
  }

  Map<String, dynamic> _adDecode(http.Response res) {
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['status'] == 'error') {
      final err = body['error'] as Map<String, dynamic>?;
      throw Exception(
        'AllDebrid: ${err?['code']} - ${err?['message'] ?? res.body}',
      );
    }
    return (body['data'] as Map).cast<String, dynamic>();
  }

  Future<List<DebridFile>> resolveAllDebrid(
    String magnet, {
    int? season,
    int? episode,
  }) async {
    final apiKey = await getAllDebridKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('AllDebrid API key not set');
    }
    final headers = {'Authorization': 'Bearer $apiKey'};

    // 1. Upload magnet.
    final upRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/magnet/upload'),
      headers: headers,
      body: {'magnets[]': magnet},
    );
    final upData = _adDecode(upRes);
    final magnets = (upData['magnets'] as List?) ?? const [];
    if (magnets.isEmpty || magnets.first is! Map) {
      throw Exception('AllDebrid: empty magnet upload response');
    }
    final m = (magnets.first as Map).cast<String, dynamic>();
    if (m['error'] != null) {
      final e = (m['error'] as Map).cast<String, dynamic>();
      throw Exception('AllDebrid: ${e['code']} - ${e['message']}');
    }
    final magnetId = m['id'];
    if (magnetId == null) throw Exception('AllDebrid: no magnet id returned');

    // 2. Poll status until ready (statusCode == 4) or hard error (>= 5).
    int attempts = 0;
    while (attempts < 40) {
      final stRes = await http.post(
        Uri.parse('https://api.alldebrid.com/v4.1/magnet/status'),
        headers: headers,
        body: {'id': magnetId.toString()},
      );
      final stData = _adDecode(stRes);
      final mags = stData['magnets'];
      Map<String, dynamic>? magObj;
      if (mags is List && mags.isNotEmpty && mags.first is Map) {
        magObj = (mags.first as Map).cast<String, dynamic>();
      } else if (mags is Map) {
        magObj = mags.cast<String, dynamic>();
      }
      final code = (magObj?['statusCode'] as num?)?.toInt() ?? -1;
      if (code == 4) break;
      if (code >= 5) {
        throw Exception(
          'AllDebrid magnet failed: ${magObj?['status']} (code $code)',
        );
      }
      await Future.delayed(const Duration(seconds: 3));
      attempts++;
    }

    // 3. Get the file tree.
    final filesRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/magnet/files'),
      headers: headers,
      body: {'id[]': magnetId.toString()},
    );
    final filesData = _adDecode(filesRes);
    final filesMagnets = (filesData['magnets'] as List?) ?? const [];
    if (filesMagnets.isEmpty || filesMagnets.first is! Map) {
      throw Exception('AllDebrid: empty files response');
    }
    final filesObj = (filesMagnets.first as Map).cast<String, dynamic>();
    if (filesObj['error'] != null) {
      final e = (filesObj['error'] as Map).cast<String, dynamic>();
      throw Exception('AllDebrid files: ${e['code']} - ${e['message']}');
    }
    final tree = (filesObj['files'] as List?) ?? const [];
    final flat = <Map<String, dynamic>>[];
    _flattenAdFiles(tree, '', flat);
    if (flat.isEmpty) {
      throw Exception('AllDebrid: no files in magnet');
    }

    // 4. Pick the right file. Same matchers RD/TorBox use, so behaviour is
    //    consistent: episode match for TV, largest-video for movies.
    final picked = (season != null && episode != null)
        ? EpisodeMatcher.pickEpisode<Map<String, dynamic>>(
            flat,
            season,
            episode,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          )
        : EpisodeMatcher.pickLargestVideo<Map<String, dynamic>>(
            flat,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          );
    if (picked == null) {
      throw Exception('AllDebrid: no video file found in torrent');
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    final pickedSize = (picked['size'] as num?)?.toInt() ?? 0;
    if (pickedLink.isEmpty) {
      throw Exception('AllDebrid: picked file has no unlock link');
    }
    debugPrint('[AD] picked file path=$pickedPath');

    // 5. Unlock the chosen file's link to get a direct download URL.
    final unRes = await http.post(
      Uri.parse('https://api.alldebrid.com/v4/link/unlock'),
      headers: headers,
      body: {'link': pickedLink},
    );
    final unData = _adDecode(unRes);
    final dlLink = unData['link'] as String?;
    if (dlLink == null || dlLink.isEmpty) {
      // AllDebrid sometimes returns a `delayed` id instead of a link for
      // generated streams. Torrent files don't normally hit that path, so
      // surface it as an error rather than silently polling for minutes.
      if (unData['delayed'] != null) {
        throw Exception('AllDebrid returned a delayed link (not supported)');
      }
      throw Exception('AllDebrid unlock returned no link');
    }
    return [
      DebridFile(
        filename: (unData['filename'] as String?) ?? pickedPath.split('/').last,
        filesize: (unData['filesize'] as num?)?.toInt() ?? pickedSize,
        downloadUrl: dlLink,
      ),
    ];
  }

  // --- Premiumize Flow ---
  //
  // Premiumize has two paths to a direct link:
  //   A) /transfer/directdl  (works instantly if the torrent is cached on
  //      their cloud — which is the common case for popular content). The
  //      response is already a flat `content` array of {path,size,link}.
  //   B) /transfer/create -> poll /transfer/list until status=="finished"
  //      -> recursive /folder/list to enumerate the resulting folder tree.
  //      Used as fallback when the torrent is not cached.
  //
  // Auth is `apikey` as a form field, NOT a Bearer header.

  Future<void> savePremiumizeKey(String key) async {
    await _safeWrite('premiumize_api_key', key.trim());
  }

  Future<String?> getPremiumizeKey() async {
    return await _safeRead('premiumize_api_key');
  }

  /// Recursively walks a Premiumize folder/list response, collecting every
  /// file node with its full path so EpisodeMatcher gets the same context
  /// as the other providers.
  Future<void> _walkPremiumizeFolder(
    String apiKey,
    String folderId,
    String prefix,
    List<Map<String, dynamic>> out,
  ) async {
    final res = await http.post(
      Uri.parse('https://www.premiumize.me/api/folder/list'),
      body: {'apikey': apiKey, 'id': folderId},
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['status'] != 'success') {
      throw Exception('Premiumize folder/list: ${body['message']}');
    }
    final content = (body['content'] as List?) ?? const [];
    for (final raw in content) {
      if (raw is! Map) continue;
      final node = raw.cast<String, dynamic>();
      final name = (node['name'] as String?) ?? '';
      final path = prefix.isEmpty ? name : '$prefix/$name';
      if (node['type'] == 'folder' && node['id'] is String) {
        await _walkPremiumizeFolder(apiKey, node['id'] as String, path, out);
      } else {
        out.add({
          'path': path,
          'size': (node['size'] as num?)?.toInt() ?? 0,
          'link': (node['link'] as String?) ?? '',
        });
      }
    }
  }

  Future<List<DebridFile>> resolvePremiumize(
    String magnet, {
    int? season,
    int? episode,
  }) async {
    final apiKey = await getPremiumizeKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Premiumize API key not set');
    }

    List<Map<String, dynamic>> files = [];

    // Path A: direct download (cached). Returns the file list flat.
    try {
      final dlRes = await http.post(
        Uri.parse('https://www.premiumize.me/api/transfer/directdl'),
        body: {'apikey': apiKey, 'src': magnet},
      );
      final dlBody = json.decode(dlRes.body) as Map<String, dynamic>;
      if (dlBody['status'] == 'success') {
        final content = (dlBody['content'] as List?) ?? const [];
        for (final raw in content) {
          if (raw is! Map) continue;
          final node = raw.cast<String, dynamic>();
          files.add({
            'path': (node['path'] as String?) ?? (node['name'] as String?) ?? '',
            'size': (node['size'] as num?)?.toInt() ?? 0,
            // Prefer stream_link (transcoded mp4) when present, fall back to
            // direct link. Both are direct HTTP URLs.
            'link': (node['stream_link'] as String?)?.isNotEmpty == true
                ? node['stream_link'] as String
                : (node['link'] as String?) ?? '',
          });
        }
      } else {
        debugPrint('[Premiumize] directdl miss: ${dlBody['message']}');
      }
    } catch (e) {
      debugPrint('[Premiumize] directdl error: $e');
    }

    // Path B: not cached -> create transfer, wait for it, then enumerate.
    if (files.isEmpty) {
      final createRes = await http.post(
        Uri.parse('https://www.premiumize.me/api/transfer/create'),
        body: {'apikey': apiKey, 'src': magnet},
      );
      final createBody = json.decode(createRes.body) as Map<String, dynamic>;
      if (createBody['status'] != 'success') {
        throw Exception('Premiumize create: ${createBody['message']}');
      }
      final transferId = createBody['id'] as String?;
      if (transferId == null) {
        throw Exception('Premiumize: no transfer id returned');
      }

      String? folderId;
      int attempts = 0;
      while (attempts < 40) {
        await Future.delayed(const Duration(seconds: 3));
        final listRes = await http.post(
          Uri.parse('https://www.premiumize.me/api/transfer/list'),
          body: {'apikey': apiKey},
        );
        final listBody = json.decode(listRes.body) as Map<String, dynamic>;
        if (listBody['status'] != 'success') {
          throw Exception('Premiumize list: ${listBody['message']}');
        }
        final transfers = (listBody['transfers'] as List?) ?? const [];
        Map<String, dynamic>? mine;
        for (final raw in transfers) {
          if (raw is Map && raw['id'] == transferId) {
            mine = raw.cast<String, dynamic>();
            break;
          }
        }
        if (mine == null) {
          throw Exception('Premiumize: transfer disappeared');
        }
        final status = mine['status'] as String?;
        if (status == 'finished' || status == 'seeding') {
          folderId = mine['folder_id'] as String?;
          break;
        }
        if (status == 'error' || status == 'deleted' || status == 'banned') {
          throw Exception('Premiumize transfer failed: $status (${mine['message']})');
        }
        attempts++;
      }
      if (folderId == null) {
        throw Exception('Premiumize: transfer did not finish in time');
      }

      await _walkPremiumizeFolder(apiKey, folderId, '', files);
    }

    if (files.isEmpty) {
      throw Exception('Premiumize: no files in torrent');
    }

    // Pick the right file with the same matcher RD/TorBox/AD use.
    final picked = (season != null && episode != null)
        ? EpisodeMatcher.pickEpisode<Map<String, dynamic>>(
            files,
            season,
            episode,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          )
        : EpisodeMatcher.pickLargestVideo<Map<String, dynamic>>(
            files,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          );
    if (picked == null) {
      throw Exception('Premiumize: no video file found in torrent');
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    if (pickedLink.isEmpty) {
      throw Exception('Premiumize: picked file has no download link');
    }
    debugPrint('[Premiumize] picked file path=$pickedPath');

    return [
      DebridFile(
        filename: pickedPath.split('/').last,
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: pickedLink,
      ),
    ];
  }

  // --- Debrid-Link Flow ---
  //
  // Debrid-Link API v2 uses Bearer auth with a personal API key from
  // https://debrid-link.com/webapp/apikey. The seedbox flow is:
  //   1. POST /api/v2/seedbox/add  body {url: <magnet>, async: true}
  //      -> returns torrent object with `id` and `files[]` (flat list).
  //   2. If files aren't ready (downloadPercent < 100 or no downloadUrl),
  //      poll GET /api/v2/seedbox/list?ids=<id> until they are.
  //   3. Each file has {name, size, downloadUrl}. `name` already contains
  //      the relative path inside the torrent so EpisodeMatcher works.
  //
  // Errors come back as {success: false, error: "code"} with HTTP 4xx/5xx.

  Future<void> saveDebridLinkKey(String key) async {
    await _safeWrite('debridlink_api_key', key.trim());
  }

  Future<String?> getDebridLinkKey() async {
    return await _safeRead('debridlink_api_key');
  }

  Map<String, dynamic> _dlDecode(http.Response res) {
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw Exception('Debrid-Link: ${body['error'] ?? res.body}');
    }
    return body;
  }

  /// Convert Debrid-Link `files[]` entries into the common matcher shape.
  List<Map<String, dynamic>> _dlExtractFiles(dynamic torrentValue) {
    final out = <Map<String, dynamic>>[];
    if (torrentValue is! Map) return out;
    final files = torrentValue['files'];
    if (files is! List) return out;
    for (final raw in files) {
      if (raw is! Map) continue;
      out.add({
        'path': (raw['name'] as String?) ?? '',
        'size': (raw['size'] as num?)?.toInt() ?? 0,
        'link': (raw['downloadUrl'] as String?) ?? '',
        'percent': (raw['downloadPercent'] as num?)?.toDouble() ?? 0.0,
      });
    }
    return out;
  }

  Future<List<DebridFile>> resolveDebridLink(
    String magnet, {
    int? season,
    int? episode,
  }) async {
    final apiKey = await getDebridLinkKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Debrid-Link API key not set');
    }
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

    // 1. Add the torrent. `async: true` returns immediately with whatever
    //    state the torrent is in (cached -> already finished, otherwise
    //    queued/downloading).
    final addRes = await http.post(
      Uri.parse('https://debrid-link.com/api/v2/seedbox/add'),
      headers: headers,
      body: json.encode({'url': magnet, 'async': true}),
    );
    final addBody = _dlDecode(addRes);
    final torrent = addBody['value'];
    if (torrent is! Map || torrent['id'] == null) {
      throw Exception('Debrid-Link: no torrent id returned');
    }
    final torrentId = torrent['id'] as String;

    var files = _dlExtractFiles(torrent);
    bool ready = files.isNotEmpty &&
        files.every((f) => (f['link'] as String).isNotEmpty);

    // 2. Poll until the files have downloadUrls.
    int attempts = 0;
    while (!ready && attempts < 40) {
      await Future.delayed(const Duration(seconds: 3));
      final stRes = await http.get(
        Uri.parse(
          'https://debrid-link.com/api/v2/seedbox/list?ids=$torrentId',
        ),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      final stBody = _dlDecode(stRes);
      final list = stBody['value'];
      if (list is List && list.isNotEmpty) {
        files = _dlExtractFiles(list.first);
        ready = files.isNotEmpty &&
            files.every((f) => (f['link'] as String).isNotEmpty);
      }
      attempts++;
    }
    if (files.isEmpty) {
      throw Exception('Debrid-Link: no files in torrent');
    }
    if (!ready) {
      throw Exception('Debrid-Link: torrent not ready after 120s');
    }

    // 3. Pick the right file. Same matcher the other providers use.
    final picked = (season != null && episode != null)
        ? EpisodeMatcher.pickEpisode<Map<String, dynamic>>(
            files,
            season,
            episode,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          )
        : EpisodeMatcher.pickLargestVideo<Map<String, dynamic>>(
            files,
            name: (f) => (f['path'] as String?) ?? '',
            size: (f) => (f['size'] as num?)?.toInt() ?? 0,
          );
    if (picked == null) {
      throw Exception('Debrid-Link: no video file found in torrent');
    }
    final pickedPath = (picked['path'] as String?) ?? '';
    final pickedLink = (picked['link'] as String?) ?? '';
    if (pickedLink.isEmpty) {
      throw Exception('Debrid-Link: picked file has no download link');
    }
    debugPrint('[DL] picked file path=$pickedPath');

    return [
      DebridFile(
        filename: pickedPath.split('/').last,
        filesize: (picked['size'] as num?)?.toInt() ?? 0,
        downloadUrl: pickedLink,
      ),
    ];
  }

  // --- Service dispatcher ---
  //
  // Centralises the `if (service == 'Real-Debrid') ... else if ...` ladder
  // so call sites don't need to grow every time a new provider is added.

  Future<List<DebridFile>> resolveByService(
    String service,
    String magnet, {
    int? season,
    int? episode,
  }) {
    switch (service) {
      case 'Real-Debrid':
        return resolveRealDebrid(magnet, season: season, episode: episode);
      case 'TorBox':
        return resolveTorBox(magnet, season: season, episode: episode);
      case 'AllDebrid':
        return resolveAllDebrid(magnet, season: season, episode: episode);
      case 'Premiumize':
        return resolvePremiumize(magnet, season: season, episode: episode);
      case 'Debrid-Link':
        return resolveDebridLink(magnet, season: season, episode: episode);
      default:
        throw Exception('Unknown debrid service: $service');
    }
  }
}
