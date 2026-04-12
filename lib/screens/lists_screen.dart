import 'package:flutter/material.dart';
import '../api/trakt_service.dart';
import '../api/mdblist_service.dart';
import '../api/tmdb_api.dart';
import '../models/movie.dart';
import '../utils/app_theme.dart';
import 'details_screen.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TraktService _trakt = TraktService();
  final MdblistService _mdblist = MdblistService();

  bool _isTraktLoggedIn = false;
  bool _isMdblistConfigured = false;

  List<Map<String, dynamic>> _traktLists = [];
  List<Map<String, dynamic>> _mdblistLists = [];
  List<Map<String, dynamic>> _mdblistTopLists = [];

  bool _loadingTrakt = true;
  bool _loadingMdblist = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final traktLoggedIn = await _trakt.isLoggedIn();
    final mdblistConfigured = await _mdblist.isConfigured();
    if (mounted) {
      setState(() {
        _isTraktLoggedIn = traktLoggedIn;
        _isMdblistConfigured = mdblistConfigured;
      });
    }
    if (traktLoggedIn) _loadTraktLists();
    if (mdblistConfigured) {
      _loadMdblistLists();
      _loadMdblistTopLists();
    }
  }

  Future<void> _loadTraktLists() async {
    try {
      final lists = await _trakt.getUserLists();
      if (mounted) setState(() { _traktLists = lists; _loadingTrakt = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTrakt = false);
    }
  }

  Future<void> _loadMdblistLists() async {
    try {
      final lists = await _mdblist.getUserLists();
      if (mounted) setState(() { _mdblistLists = lists; _loadingMdblist = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMdblist = false);
    }
  }

  Future<void> _loadMdblistTopLists() async {
    try {
      final lists = await _mdblist.getTopLists();
      if (mounted) setState(() => _mdblistTopLists = lists);
    } catch (_) {}
  }

  Future<void> _createTraktList() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String privacy = 'private';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Create Trakt List', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'List name',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Description (optional)',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: privacy,
                dropdownColor: const Color(0xFF1A1A2E),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                items: const [
                  DropdownMenuItem(value: 'private', child: Text('Private')),
                  DropdownMenuItem(value: 'friends', child: Text('Friends')),
                  DropdownMenuItem(value: 'public', child: Text('Public')),
                ],
                onChanged: (v) => setDialogState(() => privacy = v ?? 'private'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create', style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final created = await _trakt.createList(
        name: nameController.text.trim(),
        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
        privacy: privacy,
      );
      if (created != null) {
        _loadTraktLists();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('List created!')),
          );
        }
      }
    }
    nameController.dispose();
    descController.dispose();
  }

  void _openTraktListItems(Map<String, dynamic> list) {
    final ids = list['ids'] as Map<String, dynamic>? ?? {};
    final slug = ids['slug']?.toString() ?? ids['trakt']?.toString() ?? '';
    final name = list['name']?.toString() ?? 'List';
    final itemCount = list['item_count'] as int? ?? 0;

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _TraktListItemsScreen(
        listId: slug,
        listName: name,
        itemCount: itemCount,
      ),
    ));
  }

  void _openMdblistItems(Map<String, dynamic> list, {bool isUserList = false}) {
    final id = list['id'] as int? ?? 0;
    final name = list['name']?.toString() ?? 'List';

    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _MdblistItemsScreen(listId: id, listName: name, isUserList: isUserList),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        title: const Text('Lists', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Trakt'),
            Tab(text: 'MDBlist'),
            Tab(text: 'Top Lists'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTraktTab(),
          _buildMdblistTab(),
          _buildTopListsTab(),
        ],
      ),
    );
  }

  Widget _buildTraktTab() {
    if (!_isTraktLoggedIn) {
      return const Center(
        child: Text('Login to Trakt in Settings', style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }
    if (_loadingTrakt) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _createTraktList(),
              icon: const Icon(Icons.add),
              label: const Text('Create New List'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        ),
        Expanded(
          child: _traktLists.isEmpty
            ? const Center(child: Text('No lists yet', style: TextStyle(color: Colors.white38)))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _traktLists.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final list = _traktLists[index];
                  final name = list['name']?.toString() ?? 'Unnamed';
                  final desc = list['description']?.toString() ?? '';
                  final itemCount = list['item_count'] as int? ?? 0;
                  final privacy = list['privacy']?.toString() ?? 'private';

                  return _listCard(
                    name: name,
                    subtitle: '$itemCount items • $privacy',
                    description: desc,
                    icon: Icons.list_rounded,
                    color: const Color(0xFFED1C24),
                    onTap: () => _openTraktListItems(list),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildMdblistTab() {
    if (!_isMdblistConfigured) {
      return const Center(
        child: Text('Configure MDBlist in Settings', style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }
    if (_loadingMdblist) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    return _mdblistLists.isEmpty
      ? const Center(child: Text('No lists yet', style: TextStyle(color: Colors.white38)))
      : ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _mdblistLists.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final list = _mdblistLists[index];
            final name = list['name']?.toString() ?? 'Unnamed';
            final itemCount = list['items'] as int? ?? 0;

            return _listCard(
              name: name,
              subtitle: '$itemCount items',
              icon: Icons.list_alt_rounded,
              color: const Color(0xFF5799EF),
              onTap: () => _openMdblistItems(list, isUserList: true),
            );
          },
        );
  }

  Widget _buildTopListsTab() {
    if (!_isMdblistConfigured) {
      return const Center(
        child: Text('Configure MDBlist in Settings', style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }
    if (_mdblistTopLists.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _mdblistTopLists.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final list = _mdblistTopLists[index];
        final name = list['name']?.toString() ?? 'Unnamed';
        final itemCount = list['items'] as int? ?? 0;
        final likes = list['likes'] as int? ?? 0;

        return _listCard(
          name: name,
          subtitle: '$itemCount items • $likes likes',
          icon: Icons.trending_up_rounded,
          color: const Color(0xFFFFD700),
          onTap: () => _openMdblistItems(list),
        );
      },
    );
  }

  Widget _listCard({
    required String name,
    required String subtitle,
    String description = '',
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TRAKT LIST ITEMS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class _TraktListItemsScreen extends StatefulWidget {
  final String listId;
  final String listName;
  final int itemCount;

  const _TraktListItemsScreen({
    required this.listId,
    required this.listName,
    required this.itemCount,
  });

  @override
  State<_TraktListItemsScreen> createState() => _TraktListItemsScreenState();
}

class _TraktListItemsScreenState extends State<_TraktListItemsScreen> {
  final TraktService _trakt = TraktService();
  final TmdbApi _api = TmdbApi();
  List<Movie> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final items = await _trakt.getListItems(widget.listId);
      final entries = items.map((item) {
        final media = item['movie'] ?? item['show'];
        if (media == null) return null;
        final type = item.containsKey('show') ? 'tv' : 'movie';
        final ids = media['ids'] as Map<String, dynamic>? ?? {};
        final tmdbId = ids['tmdb'] as int?;
        if (tmdbId == null) return null;
        return (tmdbId: tmdbId, type: type);
      }).whereType<({int tmdbId, String type})>().toList();

      final movies = <Movie>[];
      for (var i = 0; i < entries.length; i += 5) {
        final batch = entries.skip(i).take(5);
        final results = await Future.wait(
          batch.map((e) async {
            try {
              return e.type == 'tv'
                  ? await _api.getTvDetails(e.tmdbId)
                  : await _api.getMovieDetails(e.tmdbId);
            } catch (_) { return null; }
          }),
        );
        movies.addAll(results.whereType<Movie>());
      }
      if (mounted) setState(() { _movies = movies; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeItem(Movie movie) async {
    final type = movie.mediaType == 'tv' ? 'shows' : 'movies';
    final entry = <String, dynamic>{
      'ids': {'tmdb': movie.id},
    };
    final success = await _trakt.removeFromList(
      listId: widget.listId,
      movies: type == 'movies' ? [entry] : [],
      shows: type == 'shows' ? [entry] : [],
    );
    if (success && mounted) {
      setState(() => _movies.removeWhere((m) => m.id == movie.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "${movie.title}"')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove item')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        title: Text(widget.listName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
        : _movies.isEmpty
          ? const Center(child: Text('No items', style: TextStyle(color: Colors.white38)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _movies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final movie = _movies[index];
                return _movieListTile(
                  movie: movie,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DetailsScreen(movie: movie),
                  )),
                  onRemove: () => _removeItem(movie),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MDBLIST ITEMS SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class _MdblistItemsScreen extends StatefulWidget {
  final int listId;
  final String listName;
  final bool isUserList;

  const _MdblistItemsScreen({
    required this.listId,
    required this.listName,
    this.isUserList = false,
  });

  @override
  State<_MdblistItemsScreen> createState() => _MdblistItemsScreenState();
}

class _MdblistItemsScreenState extends State<_MdblistItemsScreen> {
  final MdblistService _mdblist = MdblistService();
  final TmdbApi _api = TmdbApi();
  List<Movie> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final items = await _mdblist.getListItems(widget.listId);
      final entries = items.map((item) {
        final tmdbId = item['tmdb_id'] as int? ?? item['id'] as int?;
        final mediaType = item['mediatype']?.toString() ?? 'movie';
        if (tmdbId == null) return null;
        return (tmdbId: tmdbId, type: mediaType);
      }).whereType<({int tmdbId, String type})>().toList();

      final movies = <Movie>[];
      for (var i = 0; i < entries.length; i += 5) {
        final batch = entries.skip(i).take(5);
        final results = await Future.wait(
          batch.map((e) async {
            try {
              return e.type == 'show'
                  ? await _api.getTvDetails(e.tmdbId)
                  : await _api.getMovieDetails(e.tmdbId);
            } catch (_) { return null; }
          }),
        );
        movies.addAll(results.whereType<Movie>());
      }
      if (mounted) setState(() { _movies = movies; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeItem(Movie movie) async {
    final success = await _mdblist.removeFromList(
      listId: widget.listId,
      tmdbId: movie.id,
      mediaType: movie.mediaType,
    );
    if (success && mounted) {
      setState(() => _movies.removeWhere((m) => m.id == movie.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "${movie.title}"')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove item')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        title: Text(widget.listName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
        : _movies.isEmpty
          ? const Center(child: Text('No items', style: TextStyle(color: Colors.white38)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _movies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final movie = _movies[index];
                return _movieListTile(
                  movie: movie,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DetailsScreen(movie: movie),
                  )),
                  onRemove: widget.isUserList ? () => _removeItem(movie) : null,
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHARED MOVIE LIST TILE
// ═══════════════════════════════════════════════════════════════════════════════

Widget _movieListTile({
  required Movie movie,
  required VoidCallback onTap,
  VoidCallback? onRemove,
}) {
  final posterUrl = movie.posterPath.isNotEmpty
      ? TmdbApi.getImageUrl(movie.posterPath)
      : '';

  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: posterUrl.isNotEmpty
              ? Image.network(posterUrl, width: 50, height: 75, fit: BoxFit.cover)
              : Container(
                  width: 50, height: 75,
                  color: Colors.white10,
                  child: const Icon(Icons.movie, color: Colors.white24, size: 24),
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (movie.releaseDate.isNotEmpty)
                      Text(movie.releaseDate.split('-').first,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                    if (movie.mediaType == 'tv') ...[
                      if (movie.releaseDate.isNotEmpty)
                        Text('  •  ', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                      Text('TV', style: TextStyle(color: AppTheme.primaryColor.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                    if (movie.voteAverage > 0) ...[
                      Text('  •  ', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                      const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(movie.voteAverage.toStringAsFixed(1),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: Icon(Icons.remove_circle_outline, color: Colors.redAccent.withValues(alpha: 0.7), size: 22),
              onPressed: onRemove,
            ),
        ],
      ),
    ),
  );
}
