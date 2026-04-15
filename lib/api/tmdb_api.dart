import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

class TmdbApi {
  static const String _apiKey = 'c3515fdc674ea2bd7b514f4bc3616a4a';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBaseUrl = 'https://image.tmdb.org/t/p/w500';

  /// TMDB defaults [include_adult] to false on search/discover — omitting it hides
  /// adult-rated titles. We pass true app-wide so NSFW / all certifications can appear.
  static const Map<String, String> _includeAdultParam = {'include_adult': 'true'};

  /// High-res backdrop for hero banners / full-width headers.
  static String getBackdropUrl(String path) => 'https://image.tmdb.org/t/p/w1280$path';

  /// Small profile photo for cast lists.
  static String getProfileUrl(String path) => 'https://image.tmdb.org/t/p/w185$path';

  /// Tiny still/thumbnail for episode lists.
  static String getStillUrl(String path) => 'https://image.tmdb.org/t/p/w300$path';

  /// Full original quality — only use when absolutely needed.
  static String getOriginalUrl(String path) => 'https://image.tmdb.org/t/p/original$path';

  Future<List<Movie>> getTrending() async {
    final response = await http.get(Uri.parse('$_baseUrl/trending/movie/day?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to load trending movies');
    }
  }

  /// Trending TV for the day (same window as [getTrending] for movies).
  Future<List<Movie>> getTrendingTv() async {
    final response = await http.get(Uri.parse('$_baseUrl/trending/tv/day?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'tv')).toList();
    } else {
      throw Exception('Failed to load trending TV');
    }
  }

  /// TMDB watch provider IDs (OR = `|`). Major US streaming apps; adjust [watchRegion] for catalog.
  static const String streamingWatchProvidersOr =
      '8|9|337|350|15|384|531|387'; // Netflix, Prime, Disney+, Apple TV+, Hulu, Max, Paramount+, Peacock

  /// Movies available on at least one of [streamingWatchProvidersOr] in [watchRegion].
  Future<List<Movie>> discoverMoviesOnStreaming({
    String watchProvidersOr = streamingWatchProvidersOr,
    String watchRegion = 'US',
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/discover/movie').replace(queryParameters: {
      'api_key': _apiKey,
      'page': '$page',
      'watch_region': watchRegion,
      'with_watch_providers': watchProvidersOr,
      'sort_by': 'popularity.desc',
      ..._includeAdultParam,
    });
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to discover movies on streaming');
    }
  }

  /// TV series available on at least one of [streamingWatchProvidersOr] in [watchRegion].
  Future<List<Movie>> discoverTvOnStreaming({
    String watchProvidersOr = streamingWatchProvidersOr,
    String watchRegion = 'US',
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/discover/tv').replace(queryParameters: {
      'api_key': _apiKey,
      'page': '$page',
      'watch_region': watchRegion,
      'with_watch_providers': watchProvidersOr,
      'sort_by': 'popularity.desc',
      ..._includeAdultParam,
    });
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'tv')).toList();
    } else {
      throw Exception('Failed to discover TV on streaming');
    }
  }

  Future<List<Movie>> getPopular() async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/popular?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to load popular movies');
    }
  }

  Future<List<Movie>> getPopularTv() async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/popular?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'tv')).toList();
    } else {
      throw Exception('Failed to load popular TV');
    }
  }

  Future<List<Movie>> getTopRated() async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/top_rated?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to load top rated movies');
    }
  }

  Future<List<Movie>> getNowPlaying() async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/now_playing?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to load now playing movies');
    }
  }

  Future<List<String>> getBackdrops(int movieId) async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/$movieId/images?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final backdrops = decoded['backdrops'] as List;
      return backdrops.take(5).map((e) => e['file_path'] as String).toList();
    } else {
      return [];
    }
  }

  /// Fetch the English clear logo for a movie or TV show.
  /// Returns the logo file_path or empty string if none found.
  Future<String> getLogoPath(int id, {String mediaType = 'movie'}) async {
    try {
      final type = mediaType == 'tv' ? 'tv' : 'movie';
      final response = await http.get(
        Uri.parse('$_baseUrl/$type/$id/images?api_key=$_apiKey&include_image_language=en,null'),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final logos = decoded['logos'] as List? ?? [];
        if (logos.isEmpty) return '';
        // Prefer English PNG logos
        final enLogo = logos.firstWhere(
          (e) => e['iso_639_1'] == 'en',
          orElse: () => logos.first,
        );
        return enLogo['file_path'] as String? ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<Movie> getMovieDetails(int movieId) async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/$movieId?api_key=$_apiKey&append_to_response=images,external_ids'));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      
      // Extract screenshots from 'images.backdrops'
      final images = json['images'];
      final backdrops = (images != null && images['backdrops'] != null) 
          ? (images['backdrops'] as List).map((e) => e['file_path'] as String).toList() 
          : <String>[];

      // Extract logo (prefer English)
      String logoPath = '';
      if (images != null && images['logos'] != null) {
        final logos = images['logos'] as List;
        final enLogo = logos.firstWhere(
          (e) => e['iso_639_1'] == 'en',
          orElse: () => logos.isNotEmpty ? logos.first : null,
        );
        if (enLogo != null) {
          logoPath = enLogo['file_path'];
        }
      }

      // Use copyWith or create new instance because fromJson handles list logic differently
      return Movie.fromJson(json, mediaType: 'movie').copyWith(
        imdbId: json['imdb_id'],
        overview: json['overview'] ?? '',
        genres: (json['genres'] as List?)?.map((e) => e['name'] as String).toList() ?? [],
        runtime: json['runtime'] ?? 0,
        screenshots: backdrops,
        logoPath: logoPath,
        numberOfSeasons: json['number_of_seasons'] ?? 0,
      );
    } else {
      throw Exception('Failed to load movie details');
    }
  }

  Future<Movie> getTvDetails(int tvId) async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/$tvId?api_key=$_apiKey&append_to_response=images,external_ids'));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      
      final images = json['images'];
      final backdrops = (images != null && images['backdrops'] != null) 
          ? (images['backdrops'] as List).map((e) => e['file_path'] as String).toList() 
          : <String>[];

      String logoPath = '';
      if (images != null && images['logos'] != null) {
        final logos = images['logos'] as List;
        final enLogo = logos.firstWhere(
          (e) => e['iso_639_1'] == 'en',
          orElse: () => logos.isNotEmpty ? logos.first : null,
        );
        if (enLogo != null) {
          logoPath = enLogo['file_path'];
        }
      }

      final externalIds = json['external_ids'];
      final String? imdbId = externalIds != null ? externalIds['imdb_id'] : null;

      return Movie.fromJson(json, mediaType: 'tv').copyWith(
        imdbId: imdbId,
        overview: json['overview'] ?? '',
        genres: (json['genres'] as List?)?.map((e) => e['name'] as String).toList() ?? [],
        runtime: (json['episode_run_time'] as List?)?.isNotEmpty == true ? json['episode_run_time'][0] : 0,
        screenshots: backdrops,
        logoPath: logoPath,
        numberOfSeasons: json['number_of_seasons'] ?? 0,
      );
    } else {
      throw Exception('Failed to load TV details');
    }
  }

  Future<Map<String, dynamic>> getTvSeasonDetails(int tvId, int seasonNumber) async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/$tvId/season/$seasonNumber?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load season details');
    }
  }

  Future<List<Movie>> searchMulti(String query) async {
    final response = await http.get(Uri.parse(
        '$_baseUrl/search/multi?api_key=$_apiKey&include_adult=true&query=${Uri.encodeComponent(query)}'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List)
          .where((json) => json['media_type'] == 'movie' || json['media_type'] == 'tv')
          .map((json) => Movie.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to search');
    }
  }

  Future<List<Movie>> searchMovies(String query) async {
    final response = await http.get(Uri.parse(
        '$_baseUrl/search/movie?api_key=$_apiKey&include_adult=true&query=${Uri.encodeComponent(query)}'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to search movies');
    }
  }

  Future<List<Movie>> searchTvShows(String query) async {
    final response = await http.get(Uri.parse(
        '$_baseUrl/search/tv?api_key=$_apiKey&include_adult=true&query=${Uri.encodeComponent(query)}'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'tv')).toList();
    } else {
      throw Exception('Failed to search TV shows');
    }
  }

  Future<List<Map<String, dynamic>>> getMovieGenres() async {
    final response = await http.get(Uri.parse('$_baseUrl/genre/movie/list?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['genres'] as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load movie genres');
    }
  }

  Future<List<Map<String, dynamic>>> getTvGenres() async {
    final response = await http.get(Uri.parse('$_baseUrl/genre/tv/list?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['genres'] as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load TV genres');
    }
  }

  Future<List<Movie>> discoverMovies({List<int>? genres, int? year, double? minRating, String? language, int page = 1}) async {
    String url = '$_baseUrl/discover/movie?api_key=$_apiKey&page=$page&include_adult=true';
    if (genres != null && genres.isNotEmpty) {
      url += '&with_genres=${genres.join(',')}';
    }
    if (year != null) {
      url += '&primary_release_year=$year';
    }
    if (minRating != null) {
      url += '&vote_average.gte=$minRating';
    }
    if (language != null) {
      url += '&with_original_language=$language';
    }
    
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to discover movies');
    }
  }

  Future<List<Movie>> discoverTvShows({List<int>? genres, int? year, double? minRating, String? language, int page = 1}) async {
    String url = '$_baseUrl/discover/tv?api_key=$_apiKey&page=$page&include_adult=true';
    if (genres != null && genres.isNotEmpty) {
      url += '&with_genres=${genres.join(',')}';
    }
    if (year != null) {
      url += '&first_air_date_year=$year';
    }
    if (minRating != null) {
      url += '&vote_average.gte=$minRating';
    }
    if (language != null) {
      url += '&with_original_language=$language';
    }
    
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'tv')).toList();
    } else {
      throw Exception('Failed to discover TV shows');
    }
  }

  Future<List<Movie>> getSimilarMovies(int movieId) async {
    final response = await http.get(Uri.parse('$_baseUrl/movie/$movieId/similar?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to load similar movies');
    }
  }

  Future<List<Movie>> getSimilarTvShows(int tvId) async {
    final response = await http.get(Uri.parse('$_baseUrl/tv/$tvId/similar?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'tv')).toList();
    } else {
      throw Exception('Failed to load similar TV shows');
    }
  }

  /// Find a movie/tv show by its IMDB ID via TMDB's /find endpoint.
  Future<Movie?> findByImdbId(String imdbId, {String mediaType = 'movie'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/find/$imdbId?api_key=$_apiKey&external_source=imdb_id'),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final movieResults = decoded['movie_results'] as List? ?? [];
      final tvResults = decoded['tv_results'] as List? ?? [];

      if (mediaType == 'tv' && tvResults.isNotEmpty) {
        return Movie.fromJson(tvResults.first, mediaType: 'tv');
      }
      if (movieResults.isNotEmpty) {
        return Movie.fromJson(movieResults.first, mediaType: 'movie');
      }
      if (tvResults.isNotEmpty) {
        return Movie.fromJson(tvResults.first, mediaType: 'tv');
      }
    }
    return null;
  }

  static String getImageUrl(String path) {
    return '$_imageBaseUrl$path';
  }

  /// Fetches ordered cast list for a movie or TV show.
  /// Returns up to [limit] entries each with:
  ///   name, character, profilePath (may be empty)
  Future<List<Map<String, String>>> getCredits(
      int id, String mediaType, {int limit = 12}) async {
    final type = mediaType == 'tv' ? 'tv' : 'movie';
    final response = await http
        .get(Uri.parse('$_baseUrl/$type/$id/credits?api_key=$_apiKey'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return [];
    final decoded = jsonDecode(response.body);
    final cast = (decoded['cast'] as List? ?? []);
    return cast.take(limit).map<Map<String, String>>((e) => {
      'name': (e['name'] ?? '').toString(),
      'character': (e['character'] ?? '').toString(),
      'profilePath': (e['profile_path'] ?? '').toString(),
    }).toList();
  }
}
