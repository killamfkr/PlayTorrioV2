import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../api/tmdb_api.dart';
import '../models/movie.dart';
import '../services/my_list_service.dart';
import '../services/xmltv_epg_service.dart';
import '../utils/app_theme.dart';
import '../utils/stremio_tv_schedule.dart';
import 'details_screen.dart';
import 'stremio_tv_guide_screen.dart';

/// Full-screen catalog browser for Stremio addons.
/// Shows all catalogs from installed addons, supports genre filtering,
/// search within catalogs, and pagination.
class StremioCatalogScreen extends StatefulWidget {
  /// If set, opens directly to this specific catalog.
  final Map<String, dynamic>? initialCatalog;
  /// If set, pre-fills the search field.
  final String? initialSearch;
  /// Only show catalogs whose Stremio type is `channel` (live TV from addons).
  final bool tvChannelsOnly;
  /// Set false when this screen is a root tab (no route to pop).
  final bool showCatalogBackButton;

  const StremioCatalogScreen({
    super.key,
    this.initialCatalog,
    this.initialSearch,
    this.tvChannelsOnly = false,
    this.showCatalogBackButton = true,
  });

  @override
  State<StremioCatalogScreen> createState() => _StremioCatalogScreenState();
}

class _StremioCatalogScreenState extends State<StremioCatalogScreen> {
  final StremioService _stremio = StremioService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allCatalogs = [];
  Map<String, dynamic>? _selectedCatalog;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _skip = 0;
  String? _selectedGenre;
  String _searchQuery = '';
  String _filterType = 'all'; // 'all', 'movie', 'series'

  /// Per-channel "now playing" for TV Channels tab (key: addon|type|id).
  /// Missing key = not loaded yet; `null` value = loaded, no programme in the current window.
  final Map<String, TvScheduleSlot?> _nowPlayingByKey = {};
  Timer? _nowPlayingTicker;
  int _nowPlayingFetchGen = 0;
  Timer? _lazyEpgDebounce;
  int _lazyEpgSession = 0;
  int _lazyEpgPreparedSession = -1;
  Map<String, String> _lazyEpgChannelMap = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialSearch != null) {
      _searchController.text = widget.initialSearch!;
      _searchQuery = widget.initialSearch!;
    }
    _loadCatalogs();
    if (widget.tvChannelsOnly) {
      _nowPlayingTicker = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && _nowPlayingByKey.isNotEmpty) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _lazyEpgDebounce?.cancel();
    _nowPlayingTicker?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  static String _channelRowKey(Map<String, dynamic> item, String catalogType) {
    final base = item['_addonBaseUrl']?.toString() ?? '';
    final id = item['id']?.toString() ?? '';
    final type = item['type']?.toString() ?? catalogType;
    return '$base|$type|$id';
  }

  /// Same cross-axis layout math as [_buildContentGrid] (for visible-index range).
  ({int crossAxisCount, double aspectRatio}) _gridLayoutForItems(double width) {
    final shape = _items.firstOrNull?['posterShape']?.toString() ?? 'poster';
    final double aspectRatio;
    final int crossAxisCount;

    if (shape == 'landscape') {
      aspectRatio = widget.tvChannelsOnly ? 16 / 11.2 : 16 / 9;
      crossAxisCount = width > 1200 ? 5 : (width > 900 ? 4 : (width > 600 ? 3 : 2));
    } else if (shape == 'square') {
      aspectRatio = 1.0;
      crossAxisCount = width > 1200 ? 6 : (width > 900 ? 5 : (width > 600 ? 4 : 3));
    } else {
      aspectRatio = 2 / 3;
      crossAxisCount = width > 1200 ? 7 : (width > 900 ? 5 : (width > 600 ? 4 : 3));
    }
    return (crossAxisCount: crossAxisCount, aspectRatio: aspectRatio);
  }

  /// Approximate grid indices currently visible (plus buffer rows) for lazy EPG fetch.
  ({int start, int end})? _visibleItemIndexRange({
    required int crossAxisCount,
    required double aspectRatio,
  }) {
    if (!mounted || _items.isEmpty) return null;
    if (!_scrollController.hasClients) return null;
    final pos = _scrollController.position;
    final width = MediaQuery.sizeOf(context).width;
    const horizontalPadding = 16.0;
    const crossSpacing = 14.0;
    const mainSpacing = 14.0;
    const verticalPadding = 16.0;

    final usableW = width - 2 * horizontalPadding;
    final childW = (usableW - (crossAxisCount - 1) * crossSpacing) / crossAxisCount;
    final childH = childW / aspectRatio;
    final rowStride = childH + mainSpacing;
    if (rowStride < 1) return null;

    final scrollTop = pos.pixels;
    final viewportH = pos.viewportDimension;
    var firstRow = ((scrollTop - verticalPadding) / rowStride).floor();
    if (firstRow < 0) firstRow = 0;
    var lastRow = ((scrollTop + viewportH - verticalPadding) / rowStride).ceil();
    const bufferRows = 2;
    firstRow = (firstRow - bufferRows).clamp(0, 1 << 20);
    final maxRow = _items.length <= 0 ? 0 : (_items.length - 1) ~/ crossAxisCount;
    lastRow = (lastRow + bufferRows).clamp(0, maxRow);

    final start = firstRow * crossAxisCount;
    final end = ((lastRow + 1) * crossAxisCount - 1).clamp(0, _items.length - 1);
    if (start > end) return null;
    return (start: start, end: end);
  }

  Future<void> _prepareLazyEpgIfNeeded() async {
    if (_lazyEpgPreparedSession == _lazyEpgSession) return;
    final session = _lazyEpgSession;
    final settings = SettingsService();
    final epgUrl = await settings.getXmltvEpgUrl();
    final map = await settings.getXmltvChannelMap();
    if (!mounted || session != _lazyEpgSession) return;
    final epg = XmltvEpgService.instance;
    if (epgUrl != null && epgUrl.isNotEmpty) {
      await epg.loadFromUrl(epgUrl);
    } else {
      epg.clear();
    }
    if (!mounted || session != _lazyEpgSession) return;
    _lazyEpgChannelMap = map;
    _lazyEpgPreparedSession = session;
  }

  void _scheduleLazyNowPlayingPrefetch() {
    if (!widget.tvChannelsOnly) return;
    _lazyEpgDebounce?.cancel();
    _lazyEpgDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      unawaited(_runLazyNowPlayingPrefetch());
    });
  }

  Future<void> _runLazyNowPlayingPrefetch() async {
    if (!widget.tvChannelsOnly || !mounted || _items.isEmpty) return;
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleLazyNowPlayingPrefetch();
      });
      return;
    }

    final gen = _nowPlayingFetchGen;
    final session = _lazyEpgSession;
    final width = MediaQuery.sizeOf(context).width;
    final layout = _gridLayoutForItems(width);
    final range = _visibleItemIndexRange(
      crossAxisCount: layout.crossAxisCount,
      aspectRatio: layout.aspectRatio,
    );
    if (range == null) return;

    await _prepareLazyEpgIfNeeded();
    if (!mounted || gen != _nowPlayingFetchGen || session != _lazyEpgSession) return;

    final epg = XmltvEpgService.instance;
    final epgLoaded = epg.isLoaded;
    final epgMap = _lazyEpgChannelMap;
    final catType = _selectedCatalog?['catalogType']?.toString() ?? 'channel';

    const maxBatch = 30;
    const concurrency = 6;
    final toFetch = <Map<String, dynamic>>[];
    for (var i = range.start; i <= range.end && toFetch.length < maxBatch; i++) {
      final item = _items[i];
      final key = _channelRowKey(item, catType);
      if (_nowPlayingByKey.containsKey(key)) continue;
      toFetch.add(item);
    }
    if (toFetch.isEmpty) return;

    for (var i = 0; i < toFetch.length; i += concurrency) {
      if (!mounted || gen != _nowPlayingFetchGen || session != _lazyEpgSession) return;
      final chunk = toFetch.skip(i).take(concurrency).toList();
      final updates = <String, TvScheduleSlot?>{};
      await Future.wait(chunk.map((item) async {
        final base = item['_addonBaseUrl']?.toString() ?? '';
        final id = item['id']?.toString() ?? '';
        if (base.isEmpty || id.isEmpty) return;
        final type = item['type']?.toString() ?? catType;
        final key = _channelRowKey(item, catType);
        try {
          final meta = await _stremio.getMeta(baseUrl: base, type: type, id: id);
          if (meta == null) {
            updates[key] = null;
            return;
          }
          final name = item['name']?.toString() ?? meta['name']?.toString() ?? 'Channel';
          final mapKey = SettingsService.xmltvChannelMapKeyFor(
            addonBaseUrl: base,
            stremioChannelId: id,
          );
          final slots = StremioTvSchedule.resolveSlots(
            meta: meta,
            channelName: name,
            stremioId: id,
            epg: epg,
            epgLoaded: epgLoaded,
            epgChannelOverride: epgMap[mapKey],
            catalogItemTvgId: item['tvgId']?.toString(),
          );
          updates[key] = StremioTvSchedule.currentSlot(slots);
        } catch (_) {
          updates[key] = null;
        }
      }));
      if (!mounted || gen != _nowPlayingFetchGen || session != _lazyEpgSession) return;
      setState(() {
        for (final e in updates.entries) {
          _nowPlayingByKey[e.key] = e.value;
        }
      });
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
    if (widget.tvChannelsOnly && _items.isNotEmpty) {
      _scheduleLazyNowPlayingPrefetch();
    }
  }

  Future<void> _loadCatalogs() async {
    var catalogs = await _stremio.getAllCatalogs();
    if (widget.tvChannelsOnly) {
      catalogs = catalogs.where((c) => StremioService.isLiveTvCatalogType(c['catalogType'])).toList();
    }
    if (!mounted) return;
    setState(() {
      _allCatalogs = catalogs;
      if (widget.initialCatalog != null) {
        _selectedCatalog = widget.initialCatalog;
      } else if (catalogs.isNotEmpty) {
        _selectedCatalog = catalogs.first;
      }
      _isLoading = false;
    });
    if (_selectedCatalog != null) {
      _fetchCatalogItems();
    }
  }

  List<Map<String, dynamic>> get _filteredCatalogs {
    if (widget.tvChannelsOnly) return _allCatalogs;
    if (_filterType == 'all') return _allCatalogs;
    return _allCatalogs.where((c) => c['catalogType'] == _filterType).toList();
  }

  Future<void> _fetchCatalogItems() async {
    if (_selectedCatalog == null) return;
    setState(() {
      _isLoading = true;
      _items = [];
      _skip = 0;
      _hasMore = true;
    });

    final cat = _selectedCatalog!;
    final results = await _stremio.getCatalog(
      baseUrl: cat['addonBaseUrl'],
      type: cat['catalogType'],
      id: cat['catalogId'],
      genre: _selectedGenre,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
    );

    // Tag each item with the addon that provided it
    for (final item in results) {
      item['_addonBaseUrl'] = cat['addonBaseUrl'];
      item['_addonName'] = cat['addonName'];
    }

    if (!mounted) return;
    setState(() {
      _items = results;
      _isLoading = false;
      _hasMore = results.length >= 100;
      _skip = results.length;
    });
    if (widget.tvChannelsOnly) {
      _nowPlayingFetchGen++;
      _lazyEpgSession++;
      _lazyEpgPreparedSession = -1;
      setState(() => _nowPlayingByKey.clear());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleLazyNowPlayingPrefetch();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _selectedCatalog == null) return;
    final cat = _selectedCatalog!;
    if (cat['supportsSkip'] != true) return;

    setState(() => _isLoadingMore = true);
    final results = await _stremio.getCatalog(
      baseUrl: cat['addonBaseUrl'],
      type: cat['catalogType'],
      id: cat['catalogId'],
      genre: _selectedGenre,
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      skip: _skip,
    );
    // Tag each item with the addon that provided it
    for (final item in results) {
      item['_addonBaseUrl'] = cat['addonBaseUrl'];
      item['_addonName'] = cat['addonName'];
    }
    if (!mounted) return;
    setState(() {
      _items.addAll(results);
      _skip += results.length;
      _hasMore = results.length >= 100;
      _isLoadingMore = false;
    });
    if (widget.tvChannelsOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleLazyNowPlayingPrefetch();
      });
    }
  }

  void _selectCatalog(Map<String, dynamic> catalog) {
    setState(() {
      _selectedCatalog = catalog;
      _selectedGenre = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _fetchCatalogItems();
  }

  void _selectGenre(String? genre) {
    setState(() => _selectedGenre = genre);
    _fetchCatalogItems();
  }

  IconData _catalogTypeIcon(Object? type) {
    final t = type?.toString() ?? '';
    if (t == 'movie') return Icons.movie_outlined;
    if (StremioService.isLiveTvCatalogType(t)) return Icons.live_tv_outlined;
    return Icons.tv_outlined;
  }

  Color _catalogTypeBadgeBg(Object? type, {bool mobilePicker = false}) {
    final t = type?.toString() ?? '';
    final alpha = mobilePicker ? 0.15 : 0.2;
    if (t == 'series') return Colors.blue.withValues(alpha: alpha);
    if (StremioService.isLiveTvCatalogType(t)) return Colors.green.withValues(alpha: alpha);
    return AppTheme.primaryColor.withValues(alpha: alpha);
  }

  Color _catalogTypeBadgeFg(Object? type) {
    final t = type?.toString() ?? '';
    if (t == 'series') return Colors.blue[300]!;
    if (StremioService.isLiveTvCatalogType(t)) return Colors.greenAccent;
    return AppTheme.primaryColor;
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'movie';
    final name = item['name']?.toString() ?? 'Unknown';
    final isCustomId = !id.startsWith('tt');
    
    // Check if this is a collection by ID prefix
    final isCollection = id.startsWith('ctmdb.') || type == 'collections';

    // Tag item with addon info from the selected catalog
    if (_selectedCatalog != null) {
      item['_addonBaseUrl'] ??= _selectedCatalog!['addonBaseUrl'];
      item['_addonName'] ??= _selectedCatalog!['addonName'];
    }

    // If IMDB id → resolve via TMDB
    if (!isCustomId && !isCollection) {
      final tmdb = TmdbApi();
      try {
        final movie = await tmdb.findByImdbId(id, mediaType: type == 'series' ? 'tv' : 'movie');
        if (movie != null && mounted) {
          _navigateToDetails(movie);
          return;
        }
      } catch (_) {}
    }

    // For non-custom IDs that failed IMDB lookup, try name search
    if (!isCustomId && !isCollection) {
      final tmdb = TmdbApi();
      try {
        final results = await tmdb.searchMulti(name);
        if (results.isNotEmpty && mounted) {
          final match = results.firstWhere(
            (m) => m.title.toLowerCase() == name.toLowerCase(),
            orElse: () => results.first,
          );
          _navigateToDetails(match);
          return;
        }
      } catch (_) {}
    }

    // Custom ID, collection, or all lookups failed → use Stremio poster directly
    if (mounted) {
      // Update the item type to collections if needed
      if (isCollection) {
        item['type'] = 'collections';
      }
      
      final movie = _stremioMetaToMovie(item);
      _navigateToDetails(movie, stremioItem: item);
    }
  }

  Movie _stremioMetaToMovie(Map<String, dynamic> meta) {
    final id = meta['id']?.toString() ?? '';
    final type = meta['type']?.toString() ?? 'movie';
    final imdbId = id.startsWith('tt') ? id : null;
    final isCollection = id.startsWith('ctmdb.') || type == 'collections';
    
    return Movie(
      id: imdbId != null ? 0 : id.hashCode,
      imdbId: imdbId,
      title: meta['name']?.toString() ?? 'Unknown',
      posterPath: meta['poster']?.toString() ?? '',
      backdropPath: meta['background']?.toString() ?? meta['poster']?.toString() ?? '',
      voteAverage: double.tryParse(meta['imdbRating']?.toString() ?? '') ?? 0.0,
      releaseDate: meta['releaseInfo']?.toString() ?? '',
      overview: meta['description']?.toString() ?? '',
      genres: (meta['genres'] as List?)?.cast<String>() ?? [],
      mediaType: isCollection
          ? 'collections'
          : ((type == 'series' || type == 'channel' || type == 'tv') ? 'tv' : 'movie'),
      numberOfSeasons: 0,
    );
  }

  Future<void> _navigateToDetails(Movie movie, {Map<String, dynamic>? stremioItem}) async {
    // Always use DetailsScreen for Stremio catalog items (they have addon context)
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DetailsScreen(movie: movie, stremioItem: stremioItem),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 900;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: _allCatalogs.isEmpty && !_isLoading
          ? _buildEmptyState()
          : isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildEmptyState() {
    final isChannels = widget.tvChannelsOnly;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isChannels ? Icons.live_tv_rounded : Icons.extension_off,
              size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text(
            isChannels ? 'No TV channel catalogs' : 'No catalog addons installed',
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            isChannels
                ? 'Install a Stremio addon that provides live TV catalogs (type channel or tv) in Settings'
                : 'Install Stremio addons in Settings',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DESKTOP LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left sidebar — catalog list
        Container(
          width: 300,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1A2E), Color(0xFF0D0D16)],
            ),
            border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Column(
            children: [
              _buildSidebarHeader(),
              _buildTypeFilter(),
              Expanded(child: _buildCatalogList()),
            ],
          ),
        ),
        // Right content
        Expanded(child: _buildContentArea()),
      ],
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
      ),
      child: Row(
        children: [
          if (widget.showCatalogBackButton) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Text(
              widget.tvChannelsOnly ? 'TV Channels' : 'Catalogs',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
          ),
          if (widget.tvChannelsOnly)
            IconButton(
              tooltip: 'TV Guide',
              icon: const Icon(Icons.grid_view_rounded, color: AppTheme.primaryColor, size: 22),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StremioTvGuideScreen()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    if (widget.tvChannelsOnly) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Movies', 'movie'),
          const SizedBox(width: 8),
          _buildFilterChip('Series', 'series'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final selected = _filterType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white54,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogList() {
    final catalogs = _filteredCatalogs;
    // Group by addon name
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final c in catalogs) {
      final name = c['addonName'] as String;
      grouped.putIfAbsent(name, () => []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Row(
              children: [
                if ((entry.value.first['addonIcon'] ?? '').toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: entry.value.first['addonIcon'],
                      width: 18, height: 18,
                      errorWidget: (_, _, _) => const Icon(Icons.extension, size: 18, color: Colors.white38),
                    ),
                  ),
                if ((entry.value.first['addonIcon'] ?? '').toString().isNotEmpty)
                  const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          for (final cat in entry.value)
            _buildCatalogTile(cat),
        ],
      ],
    );
  }

  Widget _buildCatalogTile(Map<String, dynamic> cat) {
    final isSelected = _selectedCatalog != null &&
        _selectedCatalog!['addonBaseUrl'] == cat['addonBaseUrl'] &&
        _selectedCatalog!['catalogId'] == cat['catalogId'] &&
        _selectedCatalog!['catalogType'] == cat['catalogType'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Material(
        color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectCatalog(cat),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    cat['catalogType'] == 'movie'
                        ? Icons.movie_outlined
                        : (StremioService.isLiveTvCatalogType(cat['catalogType'])
                            ? Icons.live_tv_outlined
                            : Icons.tv_outlined),
                    size: 16,
                    color: isSelected ? AppTheme.primaryColor : Colors.white38,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cat['catalogName'],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cat['catalogType'].toString().toUpperCase(),
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MOBILE LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout() {
    return SafeArea(
      bottom: false,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── App Bar ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  if (widget.showCatalogBackButton) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.tvChannelsOnly ? 'TV Channels' : 'Catalogs',
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                        if (_selectedCatalog != null)
                          Text(
                            '${_selectedCatalog!['addonName']} • ${_selectedCatalog!['catalogName']}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (widget.tvChannelsOnly) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        tooltip: 'TV Guide',
                        icon: const Icon(Icons.grid_view_rounded, color: Colors.white70, size: 20),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StremioTvGuideScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Catalog picker button
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.dashboard_rounded, color: AppTheme.primaryColor, size: 20),
                      onPressed: _showCatalogPicker,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Type filter chips ──
          if (!widget.tvChannelsOnly)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    _buildMobileFilterPill('All', 'all'),
                    const SizedBox(width: 8),
                    _buildMobileFilterPill('Movies', 'movie'),
                    const SizedBox(width: 8),
                    _buildMobileFilterPill('Series', 'series'),
                  ],
                ),
              ),
            ),

          // ── Quick catalog scroller ──
          SliverToBoxAdapter(
            child: _buildMobileCatalogScroller(),
          ),

          // ── Genre chips ──
          if (_selectedCatalog != null && (_selectedCatalog!['genres'] as List).isNotEmpty)
            SliverToBoxAdapter(child: _buildGenreChips()),

          // ── Search bar ──
          if (_selectedCatalog != null && _selectedCatalog!['supportsSearch'] == true)
            SliverToBoxAdapter(child: _buildSearchBar()),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        body: _buildContentGrid(),
      ),
    );
  }

  Widget _buildMobileFilterPill(String label, String type) {
    final selected = _filterType == type;
    return GestureDetector(
      onTap: () => setState(() => _filterType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCatalogScroller() {
    final catalogs = _filteredCatalogs;
    if (catalogs.isEmpty) return const SizedBox.shrink();

    // Group catalogs by addon
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final c in catalogs) {
      grouped.putIfAbsent(c['addonName'] as String, () => []).add(c);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: catalogs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final cat = catalogs[index];
            final isSelected = _selectedCatalog != null &&
                _selectedCatalog!['addonBaseUrl'] == cat['addonBaseUrl'] &&
                _selectedCatalog!['catalogId'] == cat['catalogId'] &&
                _selectedCatalog!['catalogType'] == cat['catalogType'];
            final addonIcon = (cat['addonIcon'] ?? '').toString();

            return GestureDetector(
              onTap: () => _selectCatalog(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 130,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (addonIcon.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: addonIcon, width: 16, height: 16,
                              errorWidget: (_, _, _) => Icon(
                                _catalogTypeIcon(cat['catalogType']),
                                size: 16, color: Colors.white38,
                              ),
                            ),
                          )
                        else
                          Icon(
                            _catalogTypeIcon(cat['catalogType']),
                            size: 16, color: isSelected ? AppTheme.primaryColor : Colors.white38,
                          ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _catalogTypeBadgeBg(cat['catalogType']),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (cat['catalogType'] as String).toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: _catalogTypeBadgeFg(cat['catalogType']),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      cat['catalogName'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cat['addonName'] as String,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCatalogPicker() {
    final catalogs = _filteredCatalogs;
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final c in catalogs) {
      grouped.putIfAbsent(c['addonName'] as String, () => []).add(c);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.dashboard_rounded, color: AppTheme.primaryColor, size: 22),
                const SizedBox(width: 10),
                const Text('All Catalogs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${catalogs.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                    child: Row(
                      children: [
                        if ((entry.value.first['addonIcon'] ?? '').toString().isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: CachedNetworkImage(
                              imageUrl: entry.value.first['addonIcon'],
                              width: 20, height: 20,
                              errorWidget: (_, _, _) => const Icon(Icons.extension, size: 20, color: Colors.white38),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(entry.key,
                            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  for (final cat in entry.value)
                    _buildCatalogPickerTile(cat, ctx),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogPickerTile(Map<String, dynamic> cat, BuildContext sheetCtx) {
    final isSelected = _selectedCatalog != null &&
        _selectedCatalog!['addonBaseUrl'] == cat['addonBaseUrl'] &&
        _selectedCatalog!['catalogId'] == cat['catalogId'] &&
        _selectedCatalog!['catalogType'] == cat['catalogType'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(sheetCtx);
            _selectCatalog(cat);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  _catalogTypeIcon(cat['catalogType']),
                  size: 20,
                  color: isSelected ? AppTheme.primaryColor : Colors.white38,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cat['catalogName'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _catalogTypeBadgeBg(cat['catalogType'], mobilePicker: true),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (cat['catalogType'] as String).toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _catalogTypeBadgeFg(cat['catalogType']),
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenreChips() {
    final genres = (_selectedCatalog!['genres'] as List).cast<String>();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: genres.length + 1, // +1 for "All" chip
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildGenreChip('All', null);
            }
            return _buildGenreChip(genres[index - 1], genres[index - 1]);
          },
        ),
      ),
    );
  }

  Widget _buildGenreChip(String label, String? genre) {
    final isSelected = _selectedGenre == genre;
    return GestureDetector(
      onTap: () => _selectGenre(genre),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search in ${_selectedCatalog!['catalogName']}...',
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
          filled: true,
          fillColor: AppTheme.bgCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primaryColor),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _fetchCatalogItems();
                  },
                )
              : const Icon(Icons.search, color: Colors.white24, size: 18),
        ),
        onSubmitted: (query) {
          setState(() => _searchQuery = query);
          _fetchCatalogItems();
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CONTENT AREA (shared)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContentArea() {
    return Column(
      children: [
        if (_selectedCatalog != null) ...[
          _buildContentHeader(),
          if (_selectedCatalog!['supportsSearch'] == true) _buildDesktopSearchBar(),
          if ((_selectedCatalog!['genres'] as List).isNotEmpty) _buildGenreChips(),
        ],
        const SizedBox(height: 8),
        Expanded(child: _buildContentGrid()),
      ],
    );
  }

  Widget _buildContentHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 12),
      child: Row(
        children: [
          if ((_selectedCatalog!['addonIcon'] ?? '').toString().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: _selectedCatalog!['addonIcon'],
                width: 32, height: 32,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if ((_selectedCatalog!['addonIcon'] ?? '').toString().isNotEmpty)
            const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedCatalog!['catalogName'],
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'from ${_selectedCatalog!['addonName']}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_items.length} items',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search in ${_selectedCatalog!['catalogName']}...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 14),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.3), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _fetchCatalogItems();
                  },
                )
              : null,
        ),
        onSubmitted: (query) {
          setState(() => _searchQuery = query);
          _fetchCatalogItems();
        },
      ),
    );
  }

  Widget _buildContentGrid() {
    if (_isLoading && _items.isEmpty) {
      return _buildShimmerGrid();
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_filter, size: 60, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No results for "$_searchQuery"' : 'No items in this catalog',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final layout = _gridLayoutForItems(width);
    final crossAxisCount = layout.crossAxisCount;
    final aspectRatio = layout.aspectRatio;

    final catType = _selectedCatalog?['catalogType']?.toString() ?? 'channel';

    if (widget.tvChannelsOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleLazyNowPlayingPrefetch();
      });
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _items.length + (_isLoadingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _buildShimmerCard();
        }
        final item = _items[index];
        final rowKey = widget.tvChannelsOnly ? _channelRowKey(item, catType) : null;
        final nowSlot = widget.tvChannelsOnly && rowKey != null ? _nowPlayingByKey[rowKey] : null;
        return _StremioCatalogCard(
          item: item,
          onTap: () => _openItem(item),
          nowPlaying: nowSlot,
          showNowPlayingBar: widget.tvChannelsOnly,
          nowPlayingLoaded: widget.tvChannelsOnly && rowKey != null && _nowPlayingByKey.containsKey(rowKey),
        );
      },
    );
  }

  Widget _buildShimmerGrid() {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 7 : (width > 900 ? 5 : (width > 600 ? 4 : 3));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: 20,
      itemBuilder: (_, _) => _buildShimmerCard(),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: AppTheme.bgCard,
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CATALOG CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _StremioCatalogCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final TvScheduleSlot? nowPlaying;
  final bool showNowPlayingBar;
  final bool nowPlayingLoaded;

  const _StremioCatalogCard({
    required this.item,
    required this.onTap,
    this.nowPlaying,
    this.showNowPlayingBar = false,
    this.nowPlayingLoaded = false,
  });

  @override
  Widget build(BuildContext context) {
    final poster = item['poster']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Unknown';
    final type = item['type']?.toString() ?? '';
    final rating = item['imdbRating']?.toString() ?? '';
    final releaseInfo = item['releaseInfo']?.toString() ?? '';
    final progress = nowPlaying != null ? StremioTvSchedule.progressOf(nowPlaying!) : 0.0;

    return FocusableControl(
      onTap: onTap,
      borderRadius: 14,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster
            if (poster.isNotEmpty)
              CachedNetworkImage(
                imageUrl: poster,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.bgCard),
                errorWidget: (_, _, _) => Container(
                  color: AppTheme.bgCard,
                  child: Center(child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white38))),
                ),
              )
            else
              Container(
                color: AppTheme.bgCard,
                child: Center(child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white38))),
              ),

            // Rating badge
            if (rating.isNotEmpty)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 10, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                    ],
                  ),
                ),
              ),

            // Type badge (hidden on TV channels — cards are always live TV)
            if (type.isNotEmpty && !showNowPlayingBar)
              Positioned(
                top: 6, left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: type == 'series'
                        ? Colors.blue.withValues(alpha: 0.7)
                        : AppTheme.primaryColor.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    type.toUpperCase(),
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),

            // Bottom info
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, 10, 8, showNowPlayingBar ? 10 : 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.92), Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: showNowPlayingBar ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (showNowPlayingBar) ...[
                      const SizedBox(height: 6),
                      if (nowPlaying != null) ...[
                        Text(
                          'Now · ${nowPlaying!.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.2),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.primaryColor.withValues(alpha: 0.95),
                            ),
                          ),
                        ),
                      ] else if (!nowPlayingLoaded)
                        Text(
                          'Loading schedule…',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
                        )
                      else
                        Text(
                          'No listing for now',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                        ),
                    ] else if (releaseInfo.isNotEmpty)
                      Text(
                        releaseInfo,
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                  ],
                ),
              ),
            ),

            // My List add/remove button
            Positioned(
              bottom: showNowPlayingBar ? 88 : 44,
              right: 6,
              child: _AddToMyListStremioButton(item: item),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddToMyListStremioButton extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AddToMyListStremioButton({required this.item});

  @override
  Widget build(BuildContext context) {
    final uid = MyListService.stremioItemId(item);
    return ValueListenableBuilder<int>(
      valueListenable: MyListService.changeNotifier,
      builder: (context, _, _) {
        final inList = MyListService().contains(uid);
        return GestureDetector(
          onTap: () async {
            final added = await MyListService().toggleStremioItem(item);
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(added ? 'Added to My List' : 'Removed from My List'),
                duration: const Duration(seconds: 1),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              inList ? Icons.bookmark : Icons.add,
              size: 16,
              color: inList ? AppTheme.primaryColor : Colors.white70,
            ),
          ),
        );
      },
    );
  }
}
