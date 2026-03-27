import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

class TmdbApi {
  static const String _apiKey = 'c3515fdc674ea2bd7b514f4bc3616a4a';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageCdn = 'https://image.tmdb.org/t/p';

  Future<List<Movie>> getTrending() async {
    final response = await http.get(Uri.parse('$_baseUrl/trending/movie/day?api_key=$_apiKey'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to load trending movies');
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
    final response = await http.get(Uri.parse('$_baseUrl/search/multi?api_key=$_apiKey&query=${Uri.encodeComponent(query)}'));
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
    final response = await http.get(Uri.parse('$_baseUrl/search/movie?api_key=$_apiKey&query=${Uri.encodeComponent(query)}'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return (decoded['results'] as List).map((json) => Movie.fromJson(json, mediaType: 'movie')).toList();
    } else {
      throw Exception('Failed to search movies');
    }
  }

  Future<List<Movie>> searchTvShows(String query) async {
    final response = await http.get(Uri.parse('$_baseUrl/search/tv?api_key=$_apiKey&query=${Uri.encodeComponent(query)}'));
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
    String url = '$_baseUrl/discover/movie?api_key=$_apiKey&page=$page';
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
    String url = '$_baseUrl/discover/tv?api_key=$_apiKey&page=$page';
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

  /// [size] examples: w342, w500, w780, w1280, original (default).
  static String getImageUrl(String path, {String size = 'original'}) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$_imageCdn/$size$path';
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
