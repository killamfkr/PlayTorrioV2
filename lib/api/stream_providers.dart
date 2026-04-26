class StreamProviders {
  static final Map<String, dynamic> providers = {
    // 111477.xyz direct file index — highest priority. Resolved via
    // Site111477Service (TMDB title → file URL) and streamed through the
    // local seekable proxy. Movie/tv URL lambdas are intentionally null;
    // the player layer special-cases this provider and looks up the URL
    // from the Movie object instead of a static template.
    'service111477': {
      'name': '111477.xyz',
      'movie': null,
      'tv': null,
    },
    // WebStreamr (local on-device port). Special-cased like service111477.
    'webstreamr': {
      'name': 'WebStreamr',
      'movie': null,
      'tv': null,
    },
    'vidlink': {
      'name': 'VidLink',
      'movie': (tmdbId) => 'https://vidlink.pro/movie/$tmdbId',
      'tv': (tmdbId, s, e) => 'https://vidlink.pro/tv/$tmdbId/$s/$e',
    },
    'vixsrc': {
      'name': 'VixSrc',
      'movie': (tmdbId) => 'https://vixsrc.to/movie/$tmdbId/',
      'tv': (tmdbId, s, e) => 'https://vixsrc.to/tv/$tmdbId/$s/$e/',
    },
    'vidnest': {
      'name': 'VidNest',
      'movie': (tmdbId) => 'https://vidnest.fun/movie/$tmdbId',
      'tv': (tmdbId, s, e) => 'https://vidnest.fun/tv/$tmdbId/$s/$e',
    },
    '111movies': {
      'name': '111Movies',
      'movie': (tmdbId) => 'https://111movies.com/movie/$tmdbId',
      'tv': (tmdbId, s, e) => 'https://111movies.com/tv/$tmdbId/$s/$e',
    },
  };
}
