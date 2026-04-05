import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/iptv_service.dart';
import '../models/iptv_category.dart';
import '../models/iptv_movie.dart';
import '../../../screens/player_screen.dart';

class IptvMoviesScreen extends StatefulWidget {
  const IptvMoviesScreen({super.key});

  @override
  State<IptvMoviesScreen> createState() => _IptvMoviesScreenState();
}

class _IptvMoviesScreenState extends State<IptvMoviesScreen> {
  final _iptvService = IptvService();
  final _searchController = TextEditingController();
  final _categoryScrollController = ScrollController();

  List<IptvCategory> _categories = [];
  List<IptvMovie> _movies = [];
  String? _selectedCategory;
  String _searchQuery = '';
  bool _loadingCategories = true;
  bool _loadingMovies = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() { _loadingCategories = true; _error = null; });
      _categories = await _iptvService.getVodCategories();
      setState(() => _loadingCategories = false);
      _loadMovies();
    } catch (e) {
      setState(() { _loadingCategories = false; _error = e.toString(); });
    }
  }

  Future<void> _loadMovies() async {
    try {
      setState(() { _loadingMovies = true; _error = null; });
      _movies = await _iptvService.getVodStreams(categoryId: _selectedCategory);
      setState(() => _loadingMovies = false);
    } catch (e) {
      setState(() { _loadingMovies = false; _error = e.toString(); });
    }
  }

  List<IptvMovie> get _filteredMovies {
    if (_searchQuery.isEmpty) return _movies;
    final q = _searchQuery.toLowerCase();
    return _movies.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  void _showMovieDetail(IptvMovie movie) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MovieDetailSheet(
        movie: movie,
        iptvService: _iptvService,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0A0A), Color(0xFF0A0A0F)],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.movie_outlined, color: Color(0xFFE65100), size: 24),
                    const SizedBox(width: 8),
                    Text('MOVIES', style: GoogleFonts.bebasNeue(fontSize: 26, color: Colors.white, letterSpacing: 3)),
                    const Spacer(),
                    if (!_loadingMovies)
                      Text('${_filteredMovies.length} titles', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search movies...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.3)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Category chips
              if (_categories.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      _CategoryArrow(
                        icon: Icons.chevron_left,
                        onTap: () => _categoryScrollController.animateTo(
                          (_categoryScrollController.offset - 200).clamp(0.0, _categoryScrollController.position.maxScrollExtent),
                          duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _categoryScrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          itemCount: _categories.length + 1,
                          itemBuilder: (context, index) {
                            final isAll = index == 0;
                            final cat = isAll ? null : _categories[index - 1];
                            final isSelected = isAll ? _selectedCategory == null : _selectedCategory == cat!.categoryId;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: FilterChip(
                                label: Text(
                                  isAll ? 'All' : cat!.categoryName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white60,
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                onSelected: (_) {
                                  setState(() => _selectedCategory = isAll ? null : cat!.categoryId);
                                  _loadMovies();
                                },
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                                selectedColor: const Color(0xFFB71C1C),
                                checkmarkColor: Colors.white,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            );
                          },
                        ),
                      ),
                      _CategoryArrow(
                        icon: Icons.chevron_right,
                        onTap: () => _categoryScrollController.animateTo(
                          (_categoryScrollController.offset + 200).clamp(0.0, _categoryScrollController.position.maxScrollExtent),
                          duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // Grid
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loadingCategories || _loadingMovies) return _buildShimmerGrid();
    if (_error != null) return _buildError();
    final movies = _filteredMovies;
    if (movies.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text('No movies found', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: movies.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        childAspectRatio: 0.52,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) => _MovieCard(
        movie: movies[index],
        onTap: () => _showMovieDetail(movies[index]),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 16,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120, childAspectRatio: 0.52, crossAxisSpacing: 8, mainAxisSpacing: 8,
        ),
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text('Failed to load movies', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadCategories(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB71C1C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  final IptvMovie movie;
  final VoidCallback onTap;

  const _MovieCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  movie.streamIcon != null && movie.streamIcon!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: movie.streamIcon!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Center(child: Icon(Icons.movie, color: Colors.white12, size: 36)),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Center(child: Icon(Icons.movie, color: Colors.white12, size: 36)),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: const Center(child: Icon(Icons.movie, color: Colors.white12, size: 36)),
                        ),
                  // Rating badge
                  if (movie.rating != null && movie.rating! > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 12),
                            const SizedBox(width: 2),
                            Text(
                              movie.rating!.toStringAsFixed(1),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Gradient overlay at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            movie.name,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MovieDetailSheet extends StatefulWidget {
  final IptvMovie movie;
  final IptvService iptvService;

  const _MovieDetailSheet({required this.movie, required this.iptvService});

  @override
  State<_MovieDetailSheet> createState() => _MovieDetailSheetState();
}

class _MovieDetailSheetState extends State<_MovieDetailSheet> {
  VodInfo? _vodInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await widget.iptvService.getVodInfo(widget.movie.streamId);
      if (mounted) setState(() { _vodInfo = info; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _play() {
    final ext = _vodInfo?.movieData.containerExtension ?? widget.movie.containerExtension;
    final url = widget.iptvService.getMovieUrl(widget.movie.streamId, ext);

    // Collect external subtitles if available
    final externalSubs = _vodInfo?.info.subtitles.map((s) => {
      'lang': s['lang']?.toString() ?? 'Unknown',
      'url': s['url']?.toString() ?? '',
    }).where((s) => (s['url'] ?? '').isNotEmpty).toList();

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: widget.movie.name,
          externalSubtitles: externalSubs?.isNotEmpty == true ? externalSubs : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _vodInfo?.info;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121218),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Poster + info row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 140,
                      height: 210,
                      child: widget.movie.streamIcon != null
                          ? CachedNetworkImage(
                              imageUrl: widget.movie.streamIcon!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(color: const Color(0xFF1A1A2E)),
                            )
                          : Container(color: const Color(0xFF1A1A2E)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.movie.name,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        if (info?.genre != null && info!.genre!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(info.genre!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                        if (info?.releaseDate != null && info!.releaseDate!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(info.releaseDate!, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                        ],
                        if (info?.rating != null && info!.rating!.isNotEmpty && info.rating != '0') ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(info.rating!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ],
                        if (info?.duration != null && info!.duration!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Duration: ${info.duration}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Play button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFFE65100)]),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _play,
                    icon: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                    label: Text('PLAY', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),

              // Plot
              if (info?.plot != null && info!.plot!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Plot', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(info.plot!, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5)),
              ],

              // Cast
              if (info?.cast != null && info!.cast!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Cast', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(info.cast!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],

              // Director
              if (info?.director != null && info!.director!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Director', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(info.director!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],

              if (_loading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
              ],

              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CategoryArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Icon(icon, color: Colors.white38, size: 22),
      ),
    );
  }
}
