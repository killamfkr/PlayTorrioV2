/// Port of webstreamr/src/extractor/KinoGer.ts. Needs AES-128-CBC + PKCS7.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import 'extractor.dart';

const _kHosts = {
  'asianembed.cam',
  'disneycdn.net',
  'dzo.vidplayer.live',
  'filedecrypt.link',
  'filma365.strp2p.site',
  'flimmer.rpmvip.com',
  'flixfilmesonline.strp2p.site',
  'kinoger.p2pplay.pro',
  'kinoger.re',
  'moflix.rpmplay.xyz',
  'moflix.upns.xyz',
  'player.upn.one',
  'securecdn.shop',
  'shiid4u.upn.one',
  'srbe84.vidplayer.live',
  'strp2p.site',
  't1.p2pplay.pro',
  'tuktuk.rpmvid.com',
  'ultrastream.online',
  'videoland.cfd',
  'videoshar.uns.bio',
  'w1tv.xyz',
  'wasuytm.store',
};

Uint8List _hexDecode(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _aes128CbcDecrypt(Uint8List key, Uint8List iv, Uint8List data) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  )..init(
      false,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ),
    );
  return cipher.process(data);
}

class KinoGer extends Extractor {
  KinoGer(super.fetcher);

  @override
  String get id => 'kinoger';
  @override
  String get label => 'KinoGer';
  @override
  Duration get ttl => const Duration(hours: 6);

  @override
  bool supports(Context ctx, Uri url) => _kHosts.contains(url.host);

  @override
  Uri normalize(Uri url) {
    final origin = '${url.scheme}://${url.host}';
    return Uri.parse('$origin/api/v1/video?id=${url.fragment}');
  }

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final origin = '${url.scheme}://${url.host}';
    final headers = {
      'Origin': origin,
      'Referer': '$origin/',
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
    };
    final hex = await fetcher.text(ctx, url,
        FetcherRequestConfig(headers: headers));
    final encrypted = _hexDecode(hex.substring(0, hex.length - 1));
    final key = _hexDecode('6b69656d7469656e6d75613931316361');
    final iv = _hexDecode('313233343536373839306f6975797472');
    final decrypted = utf8.decode(_aes128CbcDecrypt(key, iv, encrypted));
    final json = jsonDecode(decrypted) as Map<String, dynamic>;
    final m3u8 = Uri.parse(json['source'] as String);

    final out = meta.clone();
    out.height ??= await guessHeightFromPlaylist(
        ctx, fetcher, m3u8, FetcherRequestConfig(headers: headers));
    out.title = json['title'] as String?;

    return [
      InternalUrlResult(
        url: m3u8,
        format: Format.hls,
        meta: out,
        requestHeaders: headers,
      ),
    ];
  }
}
