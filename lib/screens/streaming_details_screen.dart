import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/movie.dart';
import '../api/tmdb_api.dart';
import '../api/stream_extractor.dart';
import '../api/stremio_service.dart';
import '../api/stream_providers.dart';
import '../api/webstreamr_service.dart';
import '../api/settings_service.dart';
import '../api/debrid_api.dart';
import '../api/torrent_stream_service.dart';
import '../widgets/loading_overlay.dart';
import '../services/episode_watched_service.dart';
import 'player_screen.dart';

class StreamingDetailsScreen extends StatefulWidget {
  final Movie movie;
  final int? initialSeason;
  final int? initialEpisode;
  final Duration? startPosition;

  const StreamingDetailsScreen({
    super.key,
    required this.movie,
    this.initialSeason,
    this.initialEpisode,
    this.startPosition,
  });

  @override
  State<StreamingDetailsScreen> createState() => _StreamingDetailsScreenState();
}

class _StreamingDetailsScreenState extends State<StreamingDetailsScreen> {
  bool _isExtracting = false;
  bool _extractionCancelled = false;
  String? _statusMessage;
  final StreamExtractor _extractor = StreamExtractor();
  final StremioService _stremio = StremioService();
  final WebStreamrService _webStreamr = WebStreamrService();
  final SettingsService _settings = SettingsService();
  final TmdbApi _api = TmdbApi();
  late Movie _movie;
  bool _isLoading = true;
  bool _showFullSynopsis = false;
  List<Movie> _similarContent = [];

  // Source Selection
  String _selectedSourceId = 'playtorrio';
  List<Map<String, dynamic>> _streamAddons = [];
  List<dynamic> _stremioStreams = [];
  bool _isStremioFetching = false;

  // TV State
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  Map<String, dynamic>? _seasonData;
  bool _isLoadingSeason = false;

  // Episode watched tracking
  final EpisodeWatchedService _episodeWatchedService = EpisodeWatchedService();
  Set<String> _watchedEpisodes = {};
  
  final ScrollController _similarScrollController = ScrollController();
  final ScrollController _screenshotsScrollController = ScrollController();
  final ScrollController _episodeScrollController = ScrollController();

  final Map<String, dynamic> _providers = StreamProviders.providers;

  @override
  void initState() {
    super.initState();
    _movie = widget.movie;
    if (widget.initialSeason != null) _selectedSeason = widget.initialSeason!;
    if (widget.initialEpisode != null) _selectedEpisode = widget.initialEpisode!;
    _loadWatchedEpisodes();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final Movie fullDetails;
      if (_movie.mediaType == 'tv') {
        fullDetails = await _api.getTvDetails(widget.movie.id);
        await _fetchSeason(widget.initialSeason ?? 1);
      } else {
        fullDetails = await _api.getMovieDetails(widget.movie.id);
      }

      final streamAddons = await _stremio.getAddonsForResource('stream');
      final preferredSource = await _preferredStreamSourceId(streamAddons);

      // Fetch similar content
      final similar = _movie.mediaType == 'tv' 
          ? await _api.getSimilarTvShows(_movie.id)
          : await _api.getSimilarMovies(_movie.id);
      
      if (mounted) {
        setState(() {
          _movie = fullDetails;
          _streamAddons = streamAddons;
          _selectedSourceId = preferredSource;
          _similarContent = similar;
          _isLoading = false;
        });

        // Auto-start extraction when opened with a start position (e.g. from Continue Watching / Trakt)
        if (widget.startPosition != null) {
          _startExtraction();
        } else if (_selectedSourceId != 'playtorrio') {
          _startStremioExtraction();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSeason(int seasonNumber) async {
    setState(() => _isLoadingSeason = true);
    try {
      final data = await _api.getTvSeasonDetails(_movie.id, seasonNumber);
      if (mounted) {
        setState(() {
          _seasonData = data;
          _isLoadingSeason = false;
          _selectedSeason = seasonNumber;
        });
        _loadWatchedEpisodes();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSeason = false);
    }
  }

  @override
  void dispose() {
    _extractor.dispose();
    _similarScrollController.dispose();
    _screenshotsScrollController.dispose();
    _episodeScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadWatchedEpisodes() async {
    final set = await _episodeWatchedService.getWatchedSet(_movie.id);
    if (mounted) setState(() => _watchedEpisodes = set);
  }

  Future<void> _toggleEpisodeWatched(int season, int episode) async {
    await _episodeWatchedService.toggle(_movie.id, season, episode);
    await _loadWatchedEpisodes();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXTRACTION LOGIC - PRESERVED FROM ORIGINAL
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _preferredStreamSourceId(List<Map<String, dynamic>> addons) async {
    return _settings.resolveDefaultStreamSourceId(addons);
  }

  Future<void> _startExtraction() async {
    if (_selectedSourceId == 'playtorrio') {
      _startPlayTorrioExtraction();
    } else {
      _startStremioExtraction();
    }
  }

  Future<void> _startStremioExtraction() async {
    if (_streamAddons.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Install a Stremio addon in Settings first.')),
        );
      }
      return;
    }
    final addon = _streamAddons.firstWhere(
      (a) => a['baseUrl'] == _selectedSourceId,
      orElse: () => _streamAddons.first,
    );
    final baseUrl = addon['baseUrl'] as String;

    setState(() {
      _isStremioFetching = true;
      _stremioStreams = [];
      _statusMessage = 'Fetching from ${addon['name']}...';
    });

    try {
      String stremioId = _movie.imdbId ?? '';
      if (_movie.mediaType == 'tv') {
        stremioId = '$stremioId:$_selectedSeason:$_selectedEpisode';
      }

      final type = _movie.mediaType == 'tv' ? 'series' : 'movie';
      final streams = await _stremio.getStreams(baseUrl: baseUrl, type: type, id: stremioId);

      if (mounted) {
        setState(() {
          _stremioStreams = streams;
          if (streams.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No streams found for this content.')),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStremioFetching = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _playStremioStream(Map<String, dynamic> stream) async {
    final useDebrid = await _settings.useDebridForStreams();
    final debridService = await _settings.getDebridService();

    if (stream['url'] != null) {
      if (!mounted) return;
      final headers = stream['behaviorHints'] is Map
          ? Map<String, String>.from(
              (stream['behaviorHints'] as Map)['proxyHeaders']?['request'] as Map? ?? {},
            )
          : <String, String>{};
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: stream['url'] as String,
            title: _movie.mediaType == 'tv'
                ? '${_movie.title} - S$_selectedSeason E$_selectedEpisode'
                : _movie.title,
            headers: headers.isEmpty ? null : headers,
            movie: _movie,
            activeProvider: 'stremio_direct',
            selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
            selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
            stremioId: _movie.mediaType == 'tv'
                ? '${_movie.imdbId ?? ''}:$_selectedSeason:$_selectedEpisode'
                : (_movie.imdbId ?? ''),
            stremioAddonBaseUrl: _selectedSourceId != 'playtorrio' ? _selectedSourceId : null,
          ),
        ),
      );
    } else if (stream['infoHash'] != null) {
      final hash = stream['infoHash'] as String;
      final magnet = 'magnet:?xt=urn:btih:$hash';

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black,
        builder: (context) => LoadingOverlay(
          movie: _movie,
          message: useDebrid && debridService != 'None'
              ? 'Resolving with $debridService...'
              : 'Starting torrent engine...',
        ),
      );

      String? finalStreamUrl;

      try {
        if (useDebrid && debridService != 'None') {
          final debrid = DebridApi();
          List<DebridFile> files;
          if (debridService == 'Real-Debrid') {
            files = await debrid.resolveRealDebrid(magnet);
          } else {
            files = await debrid.resolveTorBox(magnet);
          }

          if (files.isNotEmpty) {
            if (_movie.mediaType == 'tv') {
              final seasonStr = 'S${_selectedSeason.toString().padLeft(2, '0')}';
              final episodeStr = 'E${_selectedEpisode.toString().padLeft(2, '0')}';
              final match = files
                  .where((f) =>
                      f.filename.toUpperCase().contains(seasonStr) &&
                      f.filename.toUpperCase().contains(episodeStr))
                  .toList();

              if (match.isNotEmpty) {
                finalStreamUrl = match.first.downloadUrl;
              } else {
                files.sort((a, b) => b.filesize.compareTo(a.filesize));
                finalStreamUrl = files.first.downloadUrl;
              }
            } else {
              files.sort((a, b) => b.filesize.compareTo(a.filesize));
              finalStreamUrl = files.first.downloadUrl;
            }
          }
        } else {
          finalStreamUrl = await TorrentStreamService().streamTorrent(
            magnet,
            season: _movie.mediaType == 'tv' ? _selectedSeason : null,
            episode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
          );
        }
      } catch (e) {
        debugPrint('Stremio torrent resolve error: $e');
      }

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (mounted && finalStreamUrl != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              streamUrl: finalStreamUrl!,
              title: _movie.mediaType == 'tv'
                  ? '${_movie.title} - S$_selectedSeason E$_selectedEpisode'
                  : _movie.title,
              magnetLink: magnet,
              movie: _movie,
              selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
              selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resolve Stremio torrent.')),
        );
      }
    }
  }

  Future<void> _startPlayTorrioExtraction() async {
    _extractionCancelled = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      builder: (context) => LoadingOverlay(
        movie: _movie,
        onCancel: () {
          _extractionCancelled = true;
          Navigator.of(context).pop();
        },
      ),
    );

    setState(() {
      _isExtracting = true;
      _statusMessage = 'Initializing Stream Extractor...';
    });

    bool found = false;

    // 1. Try WebStreamr first if IMDB ID is available
    if (_movie.imdbId != null && _movie.imdbId!.isNotEmpty) {
      setState(() => _statusMessage = 'Searching WebStreamr...');
      try {
        final webStreamrSources = await _webStreamr.getStreams(
          imdbId: _movie.imdbId!,
          isMovie: _movie.mediaType == 'movie',
          season: _selectedSeason,
          episode: _selectedEpisode,
        );

        if (_extractionCancelled) return;
        if (webStreamrSources.isNotEmpty) {
          found = true;
          if (mounted && !_extractionCancelled) {
            if (Navigator.canPop(context)) Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlayerScreen(
                  streamUrl: webStreamrSources.first.url,
                  title: _movie.mediaType == 'tv' 
                      ? '${_movie.title} - S$_selectedSeason E$_selectedEpisode' 
                      : _movie.title,
                  movie: _movie,
                  providers: _providers,
                  activeProvider: 'webstreamr',
                  selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
                  selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
                  startPosition: widget.startPosition,
                  sources: webStreamrSources,
                ),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error fetching from WebStreamr: $e');
      }
    }

    if (!found) {
      final providerKeys = _providers.keys.toList();

      for (var key in providerKeys) {
        if (!mounted || _extractionCancelled) break;
        if (key == 'webstreamr') continue; // Already tried directly
        
        final provider = _providers[key];
        
        final String url;
        if (_movie.mediaType == 'tv') {
          url = provider['tv'](
            widget.movie.id.toString(),
            _selectedSeason.toString(),
            _selectedEpisode.toString(),
          );
        } else {
          url = provider['movie'](widget.movie.id.toString());
        }
        
        setState(() => _statusMessage = 'Searching ${provider['name']}...');
        debugPrint('[StreamExtractor] Trying ${provider['name']} source: $url');

        try {
          var result = await _extractor.extract(url, timeout: const Duration(seconds: 5));
          if (_extractionCancelled) break;
          if (result != null) {
            found = true;
            if (mounted && !_extractionCancelled) {
              if (Navigator.canPop(context)) Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(
                    streamUrl: result.url,
                    audioUrl: result.audioUrl,
                    title: _movie.mediaType == 'tv' 
                        ? '${_movie.title} - S$_selectedSeason E$_selectedEpisode' 
                        : _movie.title,
                    headers: result.headers,
                    movie: _movie,
                    providers: _providers,
                    activeProvider: key,
                    selectedSeason: _movie.mediaType == 'tv' ? _selectedSeason : null,
                    selectedEpisode: _movie.mediaType == 'tv' ? _selectedEpisode : null,
                    startPosition: widget.startPosition,
                    sources: result.sources,
                  ),
                ),
              );
            }
            break;
          }
        } catch (e) {
          debugPrint('Error extracting from $key: $e');
        }
      }
    }

    if (mounted) {
      if (_extractionCancelled) {
        setState(() { _isExtracting = false; _statusMessage = null; });
        return;
      }
      if (!found && Navigator.canPop(context)) Navigator.pop(context);
      setState(() {
        _isExtracting = false;
        _statusMessage = found ? null : 'No streams found. Try again later.';
      });
      if (!found) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to find a working stream.')));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD METHOD - NEW DESIGN
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Fixed background
          Positioned.fill(
            child: _buildFixedBackground(),
          ),
          // Scrollable content
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 40),
                  _buildHeroSection(isTablet),
                  const SizedBox(height: 32),
                  _buildAboutSection(),
                  const SizedBox(height: 32),
                  if (_movie.mediaType == 'tv') ...[
                    _buildSeasonsAndEpisodes(),
                    const SizedBox(height: 32),
                  ],
                  if (_movie.screenshots.isNotEmpty) ...[
                    _buildScreenshotsSection(),
                    const SizedBox(height: 32),
                  ],
                  _buildSimilarContent(),
                  const SizedBox(height: 32),
                  _buildDetailsSection(),
                  const SizedBox(height: 48),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFixedBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_movie.backdropPath.isNotEmpty)
          CachedNetworkImage(
            imageUrl: TmdbApi.getBackdropUrl(_movie.backdropPath),
            fit: BoxFit.cover,
          ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(bool isTablet) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: isTablet
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPoster(),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMovieInfo(),
                      const SizedBox(height: 24),
                      _buildActionButtons(),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _buildPoster(),
                const SizedBox(height: 24),
                _buildMovieInfo(),
                const SizedBox(height: 24),
                _buildActionButtons(),
              ],
            ),
    );
  }

  Widget _buildPoster() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final posterWidth = isMobile ? screenWidth * 0.5 : 180.0;
    final posterHeight = posterWidth * 1.5;
    
    return Hero(
      tag: 'movie-poster-${_movie.id}',
      child: Container(
        width: posterWidth,
        height: posterHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: TmdbApi.getImageUrl(_movie.posterPath),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildMovieInfo() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final logoHeight = isTablet ? 100.0 : 80.0;
    
    return Column(
      crossAxisAlignment: isTablet ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        // Logo or Text Title
        if (_movie.logoPath.isNotEmpty)
          SizedBox(
            height: logoHeight,
            child: Row(
              mainAxisAlignment: isTablet ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Flexible(
                  child: CachedNetworkImage(
                    imageUrl: TmdbApi.getImageUrl(_movie.logoPath),
                    height: logoHeight,
                    fit: BoxFit.contain,
                    alignment: isTablet ? Alignment.centerLeft : Alignment.center,
                    fadeInDuration: const Duration(milliseconds: 0),
                    fadeOutDuration: const Duration(milliseconds: 0),
                    placeholder: (context, url) => SizedBox(
                      height: logoHeight,
                      width: double.infinity,
                    ),
                    errorWidget: (context, url, error) => Text(
                      _movie.title,
                      style: GoogleFonts.montserrat(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            _movie.title,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              _movie.releaseDate.isNotEmpty ? _movie.releaseDate.split('-').first : 'N/A',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(width: 8),
            const Text('·', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1565C0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _movie.voteAverage.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (_movie.runtime > 0) ...[
              const SizedBox(width: 8),
              const Text('·', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 8),
              Text(
                '${_movie.runtime}m',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (_movie.genres.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _movie.genres.take(4).map((genre) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Text(
                  genre,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildStreamSourceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STREAM SOURCE',
          style: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedSourceId == 'playtorrio' ||
                      _streamAddons.any((a) => a['baseUrl'] == _selectedSourceId)
                  ? _selectedSourceId
                  : 'playtorrio',
              isExpanded: true,
              dropdownColor: const Color(0xFF12121A),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF1565C0)),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: [
                const DropdownMenuItem(
                  value: 'playtorrio',
                  child: Row(
                    children: [
                      Icon(Icons.play_circle_filled, color: Color(0xFF1565C0), size: 20),
                      SizedBox(width: 10),
                      Expanded(child: Text('PlayTorrio (built-in)')),
                    ],
                  ),
                ),
                ..._streamAddons.map(
                  (addon) => DropdownMenuItem(
                    value: addon['baseUrl'] as String,
                    child: Row(
                      children: [
                        const Icon(Icons.extension, color: Colors.lightBlueAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            addon['name']?.toString() ?? 'Addon',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: (val) async {
                if (val == null) return;
                setState(() {
                  _selectedSourceId = val;
                  _stremioStreams = [];
                });
                if (val != 'playtorrio') {
                  await _startStremioExtraction();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStremioStreamList() {
    if (_stremioStreams.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stremioStreams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = _stremioStreams[index] as Map<String, dynamic>;
        final title = s['title'] ?? s['name'] ?? 'Stream';
        final description = s['description'] ?? '';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _playStremioStream(s),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_outline, color: Color(0xFF1565C0), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                        if (description.toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              description.toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.white38),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 600;

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStreamSourceSelector(),
          const SizedBox(height: 20),
          if (_selectedSourceId == 'playtorrio') ...[
            if (_isExtracting)
              Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFF1565C0)),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage ?? 'Processing...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              )
            else
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _startExtraction,
                  child: Container(
                    width: isDesktop ? 300 : double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'Play Now',
                          style: GoogleFonts.montserrat(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ] else ...[
            if (_isStremioFetching)
              const Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFF1565C0)),
                  SizedBox(height: 16),
                  Text('Loading streams…', style: TextStyle(color: Colors.white70)),
                ],
              )
            else if (_stremioStreams.isEmpty)
              TextButton.icon(
                onPressed: () => _startStremioExtraction(),
                icon: const Icon(Icons.cloud_download_outlined, color: Colors.white70),
                label: const Text('Load streams', style: TextStyle(color: Colors.white70)),
              )
            else
              _buildStremioStreamList(),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedCrossFade(
            firstChild: Text(
              _movie.overview.isNotEmpty ? _movie.overview : 'No synopsis available.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            secondChild: Text(
              _movie.overview.isNotEmpty ? _movie.overview : 'No synopsis available.',
              style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            crossFadeState: _showFullSynopsis ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
          if (_movie.overview.isNotEmpty && _movie.overview.length > 150)
            TextButton(
              onPressed: () => setState(() => _showFullSynopsis = !_showFullSynopsis),
              child: Text(
                _showFullSynopsis ? 'Show less' : 'Show more',
                style: const TextStyle(color: Color(0xFF1565C0)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeasonsAndEpisodes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Episodes',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _movie.numberOfSeasons,
            itemBuilder: (context, index) {
              final seasonNum = index + 1;
              final isSelected = _selectedSeason == seasonNum;
              return _SeasonChip(
                seasonNumber: seasonNum,
                isSelected: isSelected,
                onTap: () => _fetchSeason(seasonNum),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        if (_isLoadingSeason)
          const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
        else if (_seasonData != null && _seasonData!['episodes'] != null)
          _buildEpisodeList(),
      ],
    );
  }

  Widget _buildEpisodeList() {
    final episodes = _seasonData!['episodes'] as List;

    void scrollBy(double delta) {
      if (!_episodeScrollController.hasClients) return;
      final target = (_episodeScrollController.offset + delta)
          .clamp(0.0, _episodeScrollController.position.maxScrollExtent);
      _episodeScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── arrow row ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: Colors.white70),
                onPressed: () => scrollBy(-400),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.white70),
                onPressed: () => scrollBy(400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── horizontal list ────────────────────────────────────────────────
          SizedBox(
            height: 190,
            child: ListView.separated(
              controller: _episodeScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: episodes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final epNum = episode['episode_number'] as int;
                final title = (episode['name'] ?? 'Episode $epNum').toString();
                final still = episode['still_path'] as String?;
                final isSelected = _selectedEpisode == epNum;
                final isWatched = _watchedEpisodes.contains('${_movie.id}_S${_selectedSeason}_E$epNum');

                return _HorizontalEpisodeCard(
                  epNum: epNum,
                  title: title,
                  stillPath: still,
                  isSelected: isSelected,
                  isWatched: isWatched,
                  onToggleWatched: () => _toggleEpisodeWatched(_selectedSeason, epNum),
                  onTap: () {
                    setState(() => _selectedEpisode = epNum);
                    _startExtraction();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarContent() {
    if (_similarContent.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'More Like This',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
                    onPressed: () {
                      _similarScrollController.animateTo(
                        _similarScrollController.offset - 300,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                    onPressed: () {
                      _similarScrollController.animateTo(
                        _similarScrollController.offset + 300,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 250,
          child: ListView.builder(
            controller: _similarScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            itemCount: _similarContent.length,
            itemBuilder: (context, index) {
              final movie = _similarContent[index];
              return _SimilarMovieCard(movie: movie);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScreenshotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Screenshots',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
                    onPressed: () {
                      _screenshotsScrollController.animateTo(
                        _screenshotsScrollController.offset - 300,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                    onPressed: () {
                      _screenshotsScrollController.animateTo(
                        _screenshotsScrollController.offset + 300,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: ListView.builder(
            controller: _screenshotsScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _movie.screenshots.take(10).length,
            itemBuilder: (context, index) {
              final screenshot = _movie.screenshots[index];
              return Container(
                width: 320,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: TmdbApi.getStillUrl(screenshot),
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                _buildDetailRow('Type', _movie.mediaType == 'tv' ? 'TV Series' : 'Movie'),
                const SizedBox(height: 12),
                _buildDetailRow('Release Date', _movie.releaseDate.isNotEmpty ? _movie.releaseDate : 'N/A'),
                const SizedBox(height: 12),
                _buildDetailRow('Rating', '${_movie.voteAverage.toStringAsFixed(1)}/10'),
                if (_movie.runtime > 0) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow('Runtime', '${_movie.runtime} minutes'),
                ],
                if (_movie.mediaType == 'tv' && _movie.numberOfSeasons > 0) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow('Seasons', _movie.numberOfSeasons.toString()),
                ],
                if (_movie.genres.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow('Genres', _movie.genres.join(', ')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _HorizontalEpisodeCard extends StatefulWidget {
  final int epNum;
  final String title;
  final String? stillPath;
  final bool isSelected;
  final bool isWatched;
  final VoidCallback onTap;
  final VoidCallback onToggleWatched;

  const _HorizontalEpisodeCard({
    required this.epNum,
    required this.title,
    required this.stillPath,
    required this.isSelected,
    required this.isWatched,
    required this.onTap,
    required this.onToggleWatched,
  });

  @override
  State<_HorizontalEpisodeCard> createState() => _HorizontalEpisodeCardState();
}

class _HorizontalEpisodeCardState extends State<_HorizontalEpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFF1565C0)
                  : _isHovered
                      ? Colors.white38
                      : Colors.white12,
              width: 2,
            ),
            boxShadow: (widget.isSelected || _isHovered)
                ? [
                    BoxShadow(
                      color: widget.isSelected
                          ? const Color(0xFF1565C0).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.08),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: [
                // thumbnail
                SizedBox(
                  width: 220,
                  height: 190,
                  child: widget.stillPath != null
                      ? CachedNetworkImage(
                          imageUrl: TmdbApi.getStillUrl(widget.stillPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        )
                      : Container(
                          color: Colors.white10,
                          child: const Center(
                            child: Icon(Icons.movie_rounded,
                                color: Colors.white24, size: 40),
                          ),
                        ),
                ),
                // dark gradient at bottom
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    height: 70,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ),
                // play icon in centre
                Center(
                  child: AnimatedOpacity(
                    opacity: _isHovered || widget.isSelected ? 1.0 : 0.55,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? const Color(0xFF1565C0).withValues(alpha: 0.85)
                            : Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
                ),
                // watched checkmark
                Positioned(
                  top: 6, right: 6,
                  child: GestureDetector(
                    onTap: widget.onToggleWatched,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: widget.isWatched ? Colors.green : Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: widget.isWatched ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
                // episode number + title
                Positioned(
                  left: 10, right: 10, bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'E${widget.epNum}',
                        style: TextStyle(
                          color: widget.isSelected
                              ? const Color(0xFF64B5F6)
                              : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  final Map<String, dynamic> episode;
  final bool isSelected;
  final VoidCallback onTap;

  const _EpisodeCard({
    required this.episode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final epNum = widget.episode['episode_number'];
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isSelected 
                ? Colors.white.withValues(alpha: 0.12) 
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected 
                  ? const Color(0xFF1565C0) 
                  : _isHovered
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.transparent,
              width: widget.isSelected || _isHovered ? 2 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.isSelected
                          ? const Color(0xFF1565C0).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 130,
                height: 73,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black26,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: widget.episode['still_path'] != null
                          ? CachedNetworkImage(
                              imageUrl: TmdbApi.getStillUrl(widget.episode['still_path']),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : const Center(
                              child: Icon(Icons.movie, color: Colors.white24, size: 32),
                            ),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Episode $epNum',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.episode['name'] ?? 'Episode $epNum',
                      style: TextStyle(
                        color: _isHovered || widget.isSelected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.episode['runtime'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${widget.episode['runtime']}m',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                    if (widget.episode['overview'] != null && widget.episode['overview'].isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.episode['overview'],
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: _isHovered ? 0.3 : 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Color(0xFF1565C0), size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonChip extends StatefulWidget {
  final int seasonNumber;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeasonChip({
    required this.seasonNumber,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SeasonChip> createState() => _SeasonChipState();
}

class _SeasonChipState extends State<_SeasonChip> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          transform: _isPressed 
              ? Matrix4.diagonal3Values(0.95, 0.95, 1.0)
              : _isHovered 
                  ? Matrix4.diagonal3Values(1.05, 1.05, 1.0)
                  : Matrix4.identity(),
          decoration: BoxDecoration(
            color: widget.isSelected 
                ? const Color(0xFF1565C0) 
                : _isHovered 
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: widget.isSelected 
                  ? const Color(0xFF1565C0) 
                  : _isHovered
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.3),
              width: widget.isSelected || _isHovered ? 2 : 1,
            ),
            boxShadow: _isHovered && !widget.isSelected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              'Season ${widget.seasonNumber}',
              style: TextStyle(
                color: widget.isSelected || _isHovered ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SimilarMovieCard extends StatefulWidget {
  final Movie movie;

  const _SimilarMovieCard({required this.movie});

  @override
  State<_SimilarMovieCard> createState() => _SimilarMovieCardState();
}

class _SimilarMovieCardState extends State<_SimilarMovieCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => StreamingDetailsScreen(movie: widget.movie),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 130,
          margin: const EdgeInsets.only(right: 16),
          transform: _isHovered ? Matrix4.diagonal3Values(1.05, 1.05, 1.0) : Matrix4.identity(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 195,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _isHovered 
                          ? const Color(0xFF1565C0).withValues(alpha: 0.5)
                          : Colors.black.withValues(alpha: 0.3),
                      blurRadius: _isHovered ? 12 : 8,
                      spreadRadius: _isHovered ? 3 : 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.movie.posterPath.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: TmdbApi.getImageUrl(widget.movie.posterPath),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.1),
                          child: const Icon(Icons.movie, color: Colors.white38),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _isHovered ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: _isHovered ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    widget.movie.voteAverage.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
