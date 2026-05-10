import 'package:flutter/material.dart';
import '../api/anime_service.dart';
import '../utils/app_theme.dart';
import 'anime_screen.dart';
import 'anime_details_screen.dart';
import '../widgets/tv_interactive.dart';

class AnimeDiscoverScreen extends StatefulWidget {
  const AnimeDiscoverScreen({super.key});

  @override
  State<AnimeDiscoverScreen> createState() => _AnimeDiscoverScreenState();
}

class _AnimeDiscoverScreenState extends State<AnimeDiscoverScreen> {
  final AnimeService _service = AnimeService();
  final ScrollController _scrollController = ScrollController();

  List<AnimeCard> _results = [];
  bool _isLoading = false;
  int _page = 1;

  // Filters
  String? _selectedGenre;
  String? _selectedYear;
  String? _selectedSeason;
  String? _selectedFormat;
  String? _selectedStatus;
  String _selectedSort = 'POPULARITY_DESC';
  bool _isAdult = false;

  static const List<String> _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy',
    'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery',
    'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life',
    'Sports', 'Supernatural', 'Thriller',
  ];

  static const List<String> _seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];

  static const List<String> _formats = ['TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL', 'TV_SHORT'];

  static const List<String> _statuses = ['RELEASING', 'FINISHED', 'NOT_YET_RELEASED', 'CANCELLED'];

  static const Map<String, String> _sortOptions = {
    'POPULARITY_DESC': 'Most Popular',
    'TRENDING_DESC': 'Trending',
    'AVERAGE_SCORE_DESC': 'Highest Rated',
    'FAVOURITES_DESC': 'Most Favourited',
    'START_DATE_DESC': 'Newest',
  };

  @override
  void initState() {
    super.initState();
    _browse();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    setState(() {
      _isLoading = true;
      _page = 1;
    });
    try {
      final results = await _service.browse(
        genre: _selectedGenre,
        year: _selectedYear,
        season: _selectedSeason,
        format: _selectedFormat,
        status: _selectedStatus,
        isAdult: _isAdult ? true : null,
        sort: _selectedSort,
        page: _page,
        perPage: 30,
      );
      if (mounted) setState(() { _results = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
    _scrollToTop();
  }

  Future<void> _nextPage() async {
    setState(() { _page++; _isLoading = true; });
    try {
      final results = await _service.browse(
        genre: _selectedGenre,
        year: _selectedYear,
        season: _selectedSeason,
        format: _selectedFormat,
        status: _selectedStatus,
        isAdult: _isAdult ? true : null,
        sort: _selectedSort,
        page: _page,
        perPage: 30,
      );
      if (mounted) setState(() { _results = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
    _scrollToTop();
  }

  Future<void> _prevPage() async {
    if (_page <= 1) return;
    setState(() { _page--; _isLoading = true; });
    try {
      final results = await _service.browse(
        genre: _selectedGenre,
        year: _selectedYear,
        season: _selectedSeason,
        format: _selectedFormat,
        status: _selectedStatus,
        isAdult: _isAdult ? true : null,
        sort: _selectedSort,
        page: _page,
        perPage: 30,
      );
      if (mounted) setState(() { _results = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedGenre = null;
      _selectedYear = null;
      _selectedSeason = null;
      _selectedFormat = null;
      _selectedStatus = null;
      _selectedSort = 'POPULARITY_DESC';
      _isAdult = false;
    });
    _browse();
  }

  void _openDetails(AnimeCard anime) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnimeDetailsScreen(anime: anime)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        iconTheme: const IconThemeData(color: Colors.white),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)],
          ).createShader(bounds),
          child: const Text(
            'Discover Anime',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _resetFilters,
            tooltip: 'Reset filters',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B9D)))
                : _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, color: Colors.white.withValues(alpha: 0.15), size: 64),
                            const SizedBox(height: 12),
                            const Text('No results found', style: TextStyle(color: Colors.white30, fontSize: 15)),
                          ],
                        ),
                      )
                    : _buildResultsGrid(),
          ),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        children: [
          // Row 1: Genre + Sort
          Row(
            children: [
              Expanded(child: _buildDropdown<String>(
                label: 'Genre',
                value: _selectedGenre,
                items: _genres.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) { setState(() => _selectedGenre = v); _browse(); },
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildDropdown<String>(
                label: 'Sort',
                value: _selectedSort,
                items: _sortOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) { if (v != null) { setState(() => _selectedSort = v); _browse(); } },
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Year + Season + Format
          Row(
            children: [
              Expanded(child: _buildDropdown<String>(
                label: 'Year',
                value: _selectedYear,
                items: List.generate(30, (i) => '${DateTime.now().year + 1 - i}')
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (v) { setState(() => _selectedYear = v); _browse(); },
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildDropdown<String>(
                label: 'Season',
                value: _selectedSeason,
                items: _seasons.map((s) => DropdownMenuItem(value: s, child: Text(_capitalize(s)))).toList(),
                onChanged: (v) { setState(() => _selectedSeason = v); _browse(); },
              )),
              const SizedBox(width: 10),
              Expanded(child: _buildDropdown<String>(
                label: 'Format',
                value: _selectedFormat,
                items: _formats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (v) { setState(() => _selectedFormat = v); _browse(); },
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: Status + Adult toggle
          Row(
            children: [
              Expanded(child: _buildDropdown<String>(
                label: 'Status',
                value: _selectedStatus,
                items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(_formatStatus(s)))).toList(),
                onChanged: (v) { setState(() => _selectedStatus = v); _browse(); },
              )),
              const SizedBox(width: 16),
              // Adult toggle
              TvGestureTap(
                onTap: () { setState(() => _isAdult = !_isAdult); _browse(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isAdult
                        ? const Color(0xFFFF6B9D).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isAdult
                          ? const Color(0xFFFF6B9D).withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isAdult ? Icons.eighteen_up_rating : Icons.eighteen_up_rating_outlined,
                        color: _isAdult ? const Color(0xFFFF6B9D) : Colors.white38,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '18+',
                        style: TextStyle(
                          color: _isAdult ? const Color(0xFFFF6B9D) : Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(label, style: const TextStyle(color: Colors.white30, fontSize: 13)),
          dropdownColor: const Color(0xFF1E1E2E),
          isExpanded: true,
          icon: const Icon(Icons.expand_more, color: Colors.white24, size: 18),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: [
            DropdownMenuItem<T>(value: null, child: Text('All $label', style: const TextStyle(color: Colors.white38))),
            ...items,
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildResultsGrid() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          int cols;
          if (width > 1200) { cols = 6; }
          else if (width > 900) { cols = 5; }
          else if (width > 600) { cols = 4; }
          else { cols = 3; }
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: 0.58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
            ),
            itemCount: _results.length,
            itemBuilder: (_, i) => AnimeCardWidget(
              anime: _results[i],
              onTap: () => _openDetails(_results[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _page > 1 ? _prevPage : null,
            icon: Icon(Icons.chevron_left, color: _page > 1 ? Colors.white54 : Colors.white12),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Page $_page', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            onPressed: _results.isNotEmpty ? _nextPage : null,
            icon: Icon(Icons.chevron_right, color: _results.isNotEmpty ? Colors.white54 : Colors.white12),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0]}${s.substring(1).toLowerCase()}';

  String _formatStatus(String s) {
    switch (s) {
      case 'RELEASING': return 'Airing';
      case 'FINISHED': return 'Finished';
      case 'NOT_YET_RELEASED': return 'Upcoming';
      case 'CANCELLED': return 'Cancelled';
      default: return s;
    }
  }
}
