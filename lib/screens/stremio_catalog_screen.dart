import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../api/stremio_service.dart';
import '../api/tmdb_api.dart';
import '../models/movie.dart';
import '../utils/app_theme.dart';
import 'details_screen.dart';

/// Full-screen catalog browser for Stremio addons.
/// Shows all catalogs from installed addons, supports genre filtering,
/// search within catalogs, and pagination.
class StremioCatalogScreen extends StatefulWidget {
  /// If set, opens directly to this specific catalog.
  final Map<String, dynamic>? initialCatalog;
  /// If set, pre-fills the search field.
  final String? initialSearch;

  const StremioCatalogScreen({super.key, this.initialCatalog, this.initialSearch});

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialSearch != null) {
      _searchController.text = widget.initialSearch!;
      _searchQuery = widget.initialSearch!;
    }
    _loadCatalogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadCatalogs() async {
    final catalogs = await _stremio.getAllCatalogs();
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

  Future<void> _openItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'movie';
    final name = item['name']?.toString() ?? 'Unknown';
    final isCustomId = !id.startsWith('tt');

    // Tag item with addon info from the selected catalog
    if (_selectedCatalog != null) {
      item['_addonBaseUrl'] ??= _selectedCatalog!['addonBaseUrl'];
      item['_addonName'] ??= _selectedCatalog!['addonName'];
    }

    // If IMDB id → resolve via TMDB
    if (!isCustomId) {
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
    if (!isCustomId) {
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

    // Custom ID or all lookups failed → use Stremio poster directly
    if (mounted) {
      final movie = _stremioMetaToMovie(item);
      _navigateToDetails(movie, stremioItem: item);
    }
  }

  Movie _stremioMetaToMovie(Map<String, dynamic> meta) {
    final id = meta['id']?.toString() ?? '';
    final imdbId = id.startsWith('tt') ? id : null;
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
      mediaType: (meta['type'] == 'series' || meta['type'] == 'channel') ? 'tv' : 'movie',
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.extension_off, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text('No catalog addons installed', style: TextStyle(color: Colors.white38, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Install Stremio addons in Settings', style: TextStyle(color: Colors.white24, fontSize: 13)),
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
          width: 280,
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(right: BorderSide(color: Colors.white10)),
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
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text('Catalogs', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 6),
          _buildFilterChip('Movies', 'movie'),
          const SizedBox(width: 6),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primaryColor : Colors.white12,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppTheme.primaryColor : Colors.white54,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
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
      padding: const EdgeInsets.all(8),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _selectCatalog(cat),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  cat['catalogType'] == 'movie' ? Icons.movie : Icons.tv,
                  size: 16,
                  color: isSelected ? AppTheme.primaryColor : Colors.white38,
                ),
                const SizedBox(width: 10),
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
    return Column(
      children: [
        _buildMobileAppBar(),
        _buildMobileCatalogChips(),
        if (_selectedCatalog != null && (_selectedCatalog!['genres'] as List).isNotEmpty)
          _buildGenreChips(),
        if (_selectedCatalog != null && _selectedCatalog!['supportsSearch'] == true)
          _buildSearchBar(),
        Expanded(child: _buildContentGrid()),
      ],
    );
  }

  Widget _buildMobileAppBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text('Addon Catalogs', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          _buildTypeFilterDropdown(),
        ],
      ),
    );
  }

  Widget _buildTypeFilterDropdown() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_list, color: Colors.white70),
      color: AppTheme.bgCard,
      onSelected: (type) => setState(() => _filterType = type),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'all', child: Text('All Types', style: TextStyle(color: Colors.white70))),
        const PopupMenuItem(value: 'movie', child: Text('Movies', style: TextStyle(color: Colors.white70))),
        const PopupMenuItem(value: 'series', child: Text('Series', style: TextStyle(color: Colors.white70))),
      ],
    );
  }

  Widget _buildMobileCatalogChips() {
    final catalogs = _filteredCatalogs;
    if (catalogs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: catalogs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = catalogs[index];
          final isSelected = _selectedCatalog != null &&
              _selectedCatalog!['addonBaseUrl'] == cat['addonBaseUrl'] &&
              _selectedCatalog!['catalogId'] == cat['catalogId'] &&
              _selectedCatalog!['catalogType'] == cat['catalogType'];

          return GestureDetector(
            onTap: () => _selectCatalog(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.2) : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? AppTheme.primaryColor : Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${cat['catalogName']}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${cat['addonName']})',
                    style: TextStyle(
                      color: isSelected ? Colors.white54 : Colors.white30,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.5) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
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
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 8),
      child: Row(
        children: [
          if ((_selectedCatalog!['addonIcon'] ?? '').toString().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: _selectedCatalog!['addonIcon'],
                width: 28, height: 28,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if ((_selectedCatalog!['addonIcon'] ?? '').toString().isNotEmpty)
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedCatalog!['catalogName'],
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  'from ${_selectedCatalog!['addonName']}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty)
            Text(
              '${_items.length} items',
              style: const TextStyle(color: Colors.white30, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search in ${_selectedCatalog!['catalogName']}...',
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
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
    // Determine poster shape from first item
    final shape = _items.firstOrNull?['posterShape']?.toString() ?? 'poster';
    final double aspectRatio;
    final int crossAxisCount;

    if (shape == 'landscape') {
      aspectRatio = 16 / 9;
      crossAxisCount = width > 1200 ? 5 : (width > 900 ? 4 : (width > 600 ? 3 : 2));
    } else if (shape == 'square') {
      aspectRatio = 1.0;
      crossAxisCount = width > 1200 ? 6 : (width > 900 ? 5 : (width > 600 ? 4 : 3));
    } else {
      aspectRatio = 2 / 3;
      crossAxisCount = width > 1200 ? 7 : (width > 900 ? 5 : (width > 600 ? 4 : 3));
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _items.length + (_isLoadingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _buildShimmerCard();
        }
        return _StremioCatalogCard(
          item: _items[index],
          onTap: () => _openItem(_items[index]),
        );
      },
    );
  }

  Widget _buildShimmerGrid() {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 7 : (width > 900 ? 5 : (width > 600 ? 4 : 3));

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
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
          borderRadius: BorderRadius.circular(12),
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

  const _StremioCatalogCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final poster = item['poster']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Unknown';
    final type = item['type']?.toString() ?? '';
    final rating = item['imdbRating']?.toString() ?? '';
    final releaseInfo = item['releaseInfo']?.toString() ?? '';

    return FocusableControl(
      onTap: onTap,
      borderRadius: 12,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
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

            // Type badge
            if (type.isNotEmpty)
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (releaseInfo.isNotEmpty)
                      Text(
                        releaseInfo,
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
