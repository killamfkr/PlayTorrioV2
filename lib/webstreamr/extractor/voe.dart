/// Port of webstreamr/src/extractor/Voe.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import '../utils/media_flow_proxy.dart';
import 'extractor.dart';

const _kHosts = {
  '19turanosephantasia.com', '20demidistance9elongations.com',
  '30sensualizeexpression.com', '321naturelikefurfuroid.com',
  '35volitantplimsoles5.com', '449unceremoniousnasoseptal.com',
  '745mingiestblissfully.com', 'adrianmissionminute.com',
  'alleneconomicmatter.com', 'antecoxalbobbing1010.com',
  'apinchcaseation.com', 'audaciousdefaulthouse.com', 'availedsmallest.com',
  'bigclatterhomesguideservice.com', 'boonlessbestselling244.com',
  'bradleyviewdoctor.com', 'brittneystandardwestern.com',
  'brucevotewithin.com', 'christopheruntilpoint.com', 'chromotypic.com',
  'chuckle-tube.com', 'cindyeyefinal.com', 'counterclockwisejacky.com',
  'crownmakermacaronicism.com', 'crystaltreatmenteast.com',
  'cyamidpulverulence530.com', 'diananatureforeign.com',
  'donaldlineelse.com', 'edwardarriveoften.com', 'erikcoldperson.com',
  'figeterpiazine.com', 'fittingcentermondaysunday.com',
  'fraudclatterflyingcar.com', 'gamoneinterrupted.com',
  'generatesnitrosate.com', 'goofy-banana.com', 'graceaddresscommunity.com',
  'greaseball6eventual20.com', 'guidon40hyporadius9.com',
  'heatherdiscussionwhen.com', 'housecardsummerbutton.com',
  'jamessoundcost.com', 'jamiesamewalk.com', 'jasminetesttry.com',
  'jayservicestuff.com', 'jennifercertaindevelopment.com',
  'jilliandescribecompany.com', 'johnalwayssame.com',
  'jonathansociallike.com', 'josephseveralconcern.com',
  'kathleenmemberhistory.com', 'kellywhatcould.com',
  'kennethofficialitem.com', 'kinoger.ru', 'kristiesoundsimply.com',
  'lancewhosedifficult.com', 'launchreliantcleaverriver.com',
  'lauradaydo.com', 'lisatrialidea.com', 'loriwithinfamily.com',
  'lukecomparetwo.com', 'lukesitturn.com', 'mariatheserepublican.com',
  'matriculant401merited.com', 'maxfinishseveral.com',
  'metagnathtuggers.com', 'michaelapplysome.com', 'mikaylaarealike.com',
  'nathanfromsubject.com', 'nectareousoverelate.com', 'nonesnanking.com',
  'paulkitchendark.com', 'realfinanceblogcenter.com', 'rebeccaneverbase.com',
  'reputationsheriffkennethsand.com', 'richardsignfish.com',
  'roberteachfinal.com', 'robertordercharacter.com', 'robertplacespace.com',
  'sandratableother.com', 'sandrataxeight.com', 'scatch176duplicities.com',
  'sethniceletter.com', 'shannonpersonalcost.com', 'simpulumlamerop.com',
  'smoki.cc', 'stevenimaginelittle.com', 'strawberriesporail.com',
  'telyn610zoanthropy.com', 'timberwoodanotia.com', 'toddpartneranimal.com',
  'toxitabellaeatrebates306.com', 'uptodatefinishconferenceroom.com',
  'v-o-e-unblock.com', 'valeronevijao.com', 'walterprettytheir.com',
  'wolfdyslectic.com', 'yodelswartlike.com',
};

class Voe extends Extractor {
  Voe(super.fetcher);

  @override
  String get id => 'voe';
  @override
  String get label => 'VOE';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) {
    final ok = url.host.contains('voe') || _kHosts.contains(url.host);
    return ok && supportsMediaFlowProxy(ctx);
  }

  @override
  Uri normalize(Uri url) {
    final segs = url.path.replaceAll(RegExp(r'/+$'), '').split('/');
    return url.replace(path: '/${segs.last}');
  }

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    String html;
    try {
      html = await fetcher.text(
          ctx, url, FetcherRequestConfig(headers: headers));
    } on NotFoundError {
      if (!url.toString().contains('/e/')) {
        return extractInternal(
            ctx,
            url.replace(path: '/e${url.path}'),
            meta);
      }
      rethrow;
    }

    final redirectM =
        RegExp(r"window\.location\.href\s*=\s*'([^']+)").firstMatch(html);
    if (redirectM != null) {
      return extractInternal(ctx, Uri.parse(redirectM.group(1)!), meta);
    }
    if (RegExp(r'An error occurred during encoding').hasMatch(html)) {
      throw NotFoundError();
    }

    final doc = html_parser.parse(html);
    final title = doc
        .querySelector('meta[name="description"]')
        ?.attributes['content']
        ?.trim()
        .replaceFirst(RegExp(r'^Watch '), '')
        .replaceFirst(RegExp(r' at VOE$'), '')
        .trim();

    final sizes = RegExp(r'[\d.]+ ?[GM]B').allMatches(html).toList();
    final size = sizes.isNotEmpty ? parseBytes(sizes.last.group(0)) : null;

    final playlistUrl = await buildMediaFlowProxyExtractorStreamUrl(
        ctx, fetcher, 'Voe', url, headers);

    final hM = RegExp(r'<b>(\d{3,})p<\/b>').firstMatch(html);
    final height = hM != null
        ? int.tryParse(hM.group(1)!)
        : (meta.height ??
            await guessHeightFromPlaylist(
                ctx, fetcher, playlistUrl, FetcherRequestConfig()));

    final out = meta.clone();
    if (height != null) out.height = height;
    if (title != null && title.isNotEmpty) out.title = title;
    if (size != null && size > 16777216) out.bytes = size;

    return [
      InternalUrlResult(url: playlistUrl, format: Format.hls, meta: out),
    ];
  }
}
