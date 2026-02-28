import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../api/music_service.dart';
import '../api/music_player_service.dart';
import '../api/music_storage_service.dart';
import '../api/music_downloader_service.dart';
import '../utils/app_theme.dart';
import 'music_player_screen.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

enum MusicView { main, playlists, albums, liked, downloaded, search, playlistDetail, albumDetail }

class _MusicScreenState extends State<MusicScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final MusicService _musicService = MusicService();
  final MusicPlayerService _playerService = MusicPlayerService();
  final MusicStorageService _storageService = MusicStorageService();
  final MusicDownloaderService _downloader = MusicDownloaderService();
  final TextEditingController _searchController = TextEditingController();

  MusicView _currentView = MusicView.main;
  List<MusicTrack> _searchResultsTracks = [];
  List<MusicTrack> _trendingTracks = [];
  List<MusicAlbum> _searchResultsAlbums = [];
  List<MusicPlaylist> _userPlaylists = [];
  List<MusicAlbum> _userAlbums = [];

  MusicPlaylist? _selectedPlaylist;
  MusicAlbum? _selectedAlbum;
  List<MusicTrack> _selectedAlbumTracks = [];

  bool _isLoading = false;
  int _currentMusicOffset = 0;
  final int _musicLimit = 20;

  // Palette colors for dynamic theming
  static const Color _accentGlow = Color(0xFF7C4DFF);

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    if (hour < 21) return 'Good Evening';
    return 'Late Night Vibes';
  }

  bool get _isDesktop => MediaQuery.of(context).size.width > 900;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _loadTrendingTracks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUserData() async {
    final playlists = await _storageService.getPlaylists();
    final albums = await _storageService.getSavedAlbums();
    if (!mounted) return;
    setState(() {
      _userPlaylists = playlists;
      _userAlbums = albums;
    });
  }

  Future<void> _loadTrendingTracks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final tracks = await _musicService.getTrendingTracks(index: _currentMusicOffset, limit: _musicLimit);
    if (!mounted) return;
    setState(() {
      _trendingTracks = tracks;
      _isLoading = false;
    });
  }

  void _nextMusicPage() {
    setState(() => _currentMusicOffset += _musicLimit);
    _loadTrendingTracks();
  }

  void _prevMusicPage() {
    if (_currentMusicOffset >= _musicLimit) {
      setState(() => _currentMusicOffset -= _musicLimit);
      _loadTrendingTracks();
    }
  }

  void _onSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _currentView = MusicView.main);
      return;
    }
    setState(() {
      _isLoading = true;
      _currentView = MusicView.search;
    });
    try {
      final tracks = await _musicService.searchTracks(query);
      final albums = await _musicService.searchAlbums(query);
      if (!mounted) return;
      setState(() {
        _searchResultsTracks = tracks;
        _searchResultsAlbums = albums;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _openFullPlayer() {
    _playerService.isFullScreenVisible.value = true;
    if (Platform.isWindows || MediaQuery.of(context).size.width > 900) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const MusicPlayerScreen(),
            ),
          ),
        ),
      ).then((_) => _playerService.isFullScreenVisible.value = false);
    } else {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MusicPlayerScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      ).then((_) => _playerService.isFullScreenVisible.value = false);
    }
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D0D1A),
              Color(0xFF0A0A14),
              Color(0xFF080812),
            ],
          ),
        ),
        child: SafeArea(
          child: _isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  DESKTOP LAYOUT
  // ─────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _buildDesktopSidebar(),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                      child: _buildSearchBar(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: _buildBody(),
                      ),
                    ),
                    if (_currentView == MusicView.main)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: _buildPagination(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildMiniPlayer(),
      ],
    );
  }

  Widget _buildDesktopSidebar() {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo / Brand
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 4),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFB47CFF)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Music', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
            child: Text(_greeting, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 16),

          _sidebarItem('Home', Icons.home_rounded, MusicView.main),
          _sidebarItem('Liked Songs', Icons.favorite_rounded, MusicView.liked, color: Colors.pinkAccent),
          _sidebarItem('Downloads', Icons.download_done_rounded, MusicView.downloaded, color: Colors.tealAccent),

          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text('LIBRARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: Colors.white.withValues(alpha: 0.25))),
          ),
          const SizedBox(height: 12),
          _sidebarItem('Playlists', Icons.queue_music_rounded, MusicView.playlists),
          _sidebarItem('Albums', Icons.album_rounded, MusicView.albums, color: Colors.amberAccent),

          const Spacer(),

          // Now playing indicator at bottom of sidebar
          ValueListenableBuilder<MusicTrack?>(
            valueListenable: _playerService.currentTrack,
            builder: (context, track, _) {
              if (track == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accentGlow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accentGlow.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildCoverImage(track.cover, width: 40, height: 40),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem(String label, IconData icon, MusicView view, {Color? color}) {
    final isActive = _currentView == view;
    final itemColor = color ?? AppTheme.primaryColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _currentView = view),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
          decoration: BoxDecoration(
            color: isActive ? itemColor.withValues(alpha: 0.1) : Colors.transparent,
            border: Border(left: BorderSide(
              color: isActive ? itemColor : Colors.transparent,
              width: 3,
            )),
          ),
          child: Row(
            children: [
              Icon(icon, color: isActive ? itemColor : Colors.white.withValues(alpha: 0.35), size: 20),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.5),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  MOBILE LAYOUT
  // ─────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Greeting
                  if (_currentView == MusicView.main) ...[
                    Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFFB47CFF)]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Text(_greeting, style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.3,
                          foreground: Paint()..shader = const LinearGradient(
                            colors: [Colors.white, Color(0xFFB8B8D0)],
                          ).createShader(const Rect.fromLTWH(0, 0, 200, 30)),
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildSearchBar(),
                  const SizedBox(height: 14),
                  if (_currentView == MusicView.main) _buildMobileCategories(),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildBody(),
              ),
            ),
          ],
        ),
        // Bottom: Mini player + pagination
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMiniPlayer(),
              if (_currentView == MusicView.main)
                _buildPagination(),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  SEARCH BAR
  // ─────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: _searchController,
        onSubmitted: _onSearch,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search songs, albums, artists...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 15),
          prefixIcon: _currentView == MusicView.search
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _currentView = MusicView.main);
                  })
              : Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.3)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white38),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _currentView = MusicView.main);
                  })
              : null,
          filled: false,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  MOBILE CATEGORY CHIPS
  // ─────────────────────────────────────────────

  Widget _buildMobileCategories() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildChip('Liked', Icons.favorite_rounded, MusicView.liked, Colors.pinkAccent),
          _buildChip('Downloads', Icons.download_done_rounded, MusicView.downloaded, const Color(0xFF4DD0E1)),
          _buildChip('Playlists', Icons.queue_music_rounded, MusicView.playlists, AppTheme.primaryColor),
          _buildChip('Albums', Icons.album_rounded, MusicView.albums, Colors.amberAccent),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, MusicView view, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _currentView = view),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  MAIN BODY ROUTER
  // ─────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingShimmer();

    switch (_currentView) {
      case MusicView.main:
        return _buildTrendingView();
      case MusicView.playlists:
        return _buildPlaylistsView();
      case MusicView.liked:
        return _buildLikedView();
      case MusicView.downloaded:
        return _buildDownloadedView();
      case MusicView.albums:
        return _buildAlbumsView();
      case MusicView.search:
        return _buildSearchResults();
      case MusicView.playlistDetail:
        return _buildPlaylistDetail();
      case MusicView.albumDetail:
        return _buildAlbumDetail();
    }
  }

  // ─────────────────────────────────────────────
  //  TRENDING VIEW
  // ─────────────────────────────────────────────

  Widget _buildTrendingView() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth > 1400) { crossAxisCount = 6; }
    else if (screenWidth > 1100) { crossAxisCount = 5; }
    else if (screenWidth > 900) { crossAxisCount = 4; }
    else if (screenWidth > 600) { crossAxisCount = 3; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
          child: Row(
            children: [
              Container(
                width: 4, height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text('Trending Now', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Page ${(_currentMusicOffset / _musicLimit).floor() + 1}',
                  style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 180),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.72,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: _trendingTracks.length,
            itemBuilder: (context, index) => _buildTrackCard(_trendingTracks[index], _trendingTracks, index: index),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  LIKED VIEW
  // ─────────────────────────────────────────────

  Widget _buildLikedView() {
    return ValueListenableBuilder<List<MusicTrack>>(
      valueListenable: _storageService.likedSongs,
      builder: (context, liked, _) {
        return Column(
          children: [
            _buildSectionHeader(
              'Liked Songs',
              icon: Icons.favorite_rounded,
              iconColor: Colors.pinkAccent,
              subtitle: '${liked.length} songs',
              onBack: () => setState(() => _currentView = MusicView.main),
              actions: [
                if (liked.isNotEmpty)
                  _buildActionButton(Icons.shuffle_rounded, 'Shuffle', () {
                    _playerService.isShuffleEnabled.value = true;
                    _playerService.playTrack(liked[0], newPlaylist: List.from(liked));
                  }),
              ],
            ),
            Expanded(
              child: liked.isEmpty
                  ? _buildEmptyState(Icons.favorite_border_rounded, 'No liked songs yet', 'Songs you love will appear here')
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 180),
                      itemCount: liked.length,
                      itemBuilder: (context, index) => _buildTrackTile(liked[index], liked, index: index),
                    ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  DOWNLOADED VIEW
  // ─────────────────────────────────────────────

  Widget _buildDownloadedView() {
    return ValueListenableBuilder<List<MusicTrack>>(
      valueListenable: _storageService.downloadedTracks,
      builder: (context, downloaded, _) {
        return Column(
          children: [
            _buildSectionHeader(
              'Downloads',
              icon: Icons.download_done_rounded,
              iconColor: const Color(0xFF4DD0E1),
              subtitle: '${downloaded.length} songs',
              onBack: () => setState(() => _currentView = MusicView.main),
              actions: [
                if (downloaded.isNotEmpty) ...[
                  _buildActionButton(Icons.shuffle_rounded, 'Shuffle', () {
                    _playerService.isShuffleEnabled.value = true;
                    _playerService.playTrack(downloaded[0], newPlaylist: List.from(downloaded));
                  }),
                  const SizedBox(width: 8),
                  _buildActionButton(Icons.folder_open_rounded, 'Folder', () => _openDownloadFolder(downloaded)),
                ],
              ],
            ),
            Expanded(
              child: downloaded.isEmpty
                  ? _buildEmptyState(Icons.cloud_download_outlined, 'No downloads yet', 'Downloaded songs play offline')
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 180),
                      itemCount: downloaded.length,
                      itemBuilder: (context, index) => _buildTrackTile(downloaded[index], downloaded, index: index),
                    ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  PLAYLISTS VIEW
  // ─────────────────────────────────────────────

  Widget _buildPlaylistsView() {
    return Column(
      children: [
        _buildSectionHeader(
          'Your Playlists',
          icon: Icons.queue_music_rounded,
          iconColor: AppTheme.primaryColor,
          subtitle: '${_userPlaylists.length} playlists',
          onBack: () => setState(() => _currentView = MusicView.main),
          actions: [
            _buildActionButton(Icons.add_rounded, 'New', _createPlaylist),
          ],
        ),
        Expanded(
          child: _userPlaylists.isEmpty
              ? _buildEmptyState(Icons.playlist_add_rounded, 'No playlists yet', 'Create one to organize your music')
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 180),
                  itemCount: _userPlaylists.length,
                  itemBuilder: (context, index) {
                    final p = _userPlaylists[index];
                    return _buildPlaylistTile(p);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlaylistTile(MusicPlaylist playlist) {
    final coverUrl = playlist.tracks.isNotEmpty ? playlist.tracks.first.cover : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _HoverScaleCard(
        onTap: () => setState(() {
          _selectedPlaylist = playlist;
          _currentView = MusicView.playlistDetail;
        }),
        borderRadius: 14,
        hoverScale: 1.0,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
            child: Row(
              children: [
                // Playlist cover grid or single cover
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primaryColor.withValues(alpha: 0.3), AppTheme.primaryColor.withValues(alpha: 0.1)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: coverUrl.isNotEmpty
                      ? _buildCoverImage(coverUrl, width: 56, height: 56)
                      : const Icon(Icons.music_note_rounded, color: Colors.white38),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${playlist.tracks.length} tracks', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.2)),
              ],
            ),
          ),
        ),
    );
  }

  // ─────────────────────────────────────────────
  //  ALBUMS VIEW
  // ─────────────────────────────────────────────

  Widget _buildAlbumsView() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth > 1400) { crossAxisCount = 6; }
    else if (screenWidth > 1100) { crossAxisCount = 5; }
    else if (screenWidth > 900) { crossAxisCount = 4; }
    else if (screenWidth > 600) { crossAxisCount = 3; }

    return Column(
      children: [
        _buildSectionHeader(
          'Saved Albums',
          icon: Icons.album_rounded,
          iconColor: Colors.amberAccent,
          subtitle: '${_userAlbums.length} albums',
          onBack: () => setState(() => _currentView = MusicView.main),
        ),
        Expanded(
          child: _userAlbums.isEmpty
              ? _buildEmptyState(Icons.album_outlined, 'No saved albums', 'Albums you save will appear here')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 180),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: _userAlbums.length,
                  itemBuilder: (context, index) => _buildAlbumCard(_userAlbums[index], () => _openAlbum(_userAlbums[index])),
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  SEARCH RESULTS
  // ─────────────────────────────────────────────

  Widget _buildSearchResults() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth > 1400) { crossAxisCount = 6; }
    else if (screenWidth > 1100) { crossAxisCount = 5; }
    else if (screenWidth > 900) { crossAxisCount = 4; }
    else if (screenWidth > 600) { crossAxisCount = 3; }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [
                Tab(text: 'Tracks'),
                Tab(text: 'Albums'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _searchResultsTracks.isEmpty
                    ? _buildEmptyState(Icons.search_off_rounded, 'No tracks found', 'Try a different search')
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 180),
                        itemCount: _searchResultsTracks.length,
                        itemBuilder: (context, index) => _buildTrackTile(_searchResultsTracks[index], _searchResultsTracks, index: index),
                      ),
                _searchResultsAlbums.isEmpty
                    ? _buildEmptyState(Icons.search_off_rounded, 'No albums found', 'Try a different search')
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 180),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: _searchResultsAlbums.length,
                        itemBuilder: (context, index) {
                          final a = _searchResultsAlbums[index];
                          return _buildAlbumCard(a, () => _openAlbum(a));
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAlbum(MusicAlbum album) async {
    setState(() {
      _isLoading = true;
      _selectedAlbum = album;
    });
    final tracks = await _musicService.getAlbumTracks(album.id);
    if (!mounted) return;
    setState(() {
      _selectedAlbumTracks = tracks;
      _isLoading = false;
      _currentView = MusicView.albumDetail;
    });
  }

  // ─────────────────────────────────────────────
  //  PLAYLIST DETAIL
  // ─────────────────────────────────────────────

  Widget _buildPlaylistDetail() {
    final p = _selectedPlaylist!;
    final coverUrl = p.tracks.isNotEmpty ? p.tracks.first.cover : '';

    return CustomScrollView(
      slivers: [
        // Hero header
        SliverToBoxAdapter(child: _buildDetailHero(
          title: p.name,
          subtitle: '${p.tracks.length} tracks',
          coverUrl: coverUrl,
          onBack: () => setState(() => _currentView = MusicView.playlists),
          onShuffle: p.tracks.isNotEmpty ? () {
            _playerService.isShuffleEnabled.value = true;
            _playerService.playTrack(p.tracks[0], newPlaylist: List.from(p.tracks));
          } : null,
          onPlayAll: p.tracks.isNotEmpty ? () {
            _playerService.playTrack(p.tracks[0], newPlaylist: List.from(p.tracks));
          } : null,
          extraActions: [
            _buildActionButton(Icons.delete_outline_rounded, 'Delete', () async {
              final shouldDelete = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1030),
                  title: const Text('Delete Playlist?'),
                  content: Text('Are you sure you want to delete "${p.name}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (shouldDelete == true) {
                await _storageService.deletePlaylist(p.name);
                await _loadUserData();
                if (mounted) {
                  setState(() => _currentView = MusicView.playlists);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Playlist deleted'),
                      backgroundColor: const Color(0xFF1A1030),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }
            }),
          ],
        )),
        // Track list
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 180),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildTrackTile(p.tracks[index], p.tracks, index: index, showNumber: true, fromPlaylist: p),
              childCount: p.tracks.length,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  ALBUM DETAIL
  // ─────────────────────────────────────────────

  Widget _buildAlbumDetail() {
    final a = _selectedAlbum!;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildDetailHero(
          title: a.title,
          subtitle: a.artist,
          coverUrl: a.cover,
          onBack: () => setState(() => _currentView = MusicView.albums),
          onShuffle: _selectedAlbumTracks.isNotEmpty ? () {
            _playerService.isShuffleEnabled.value = true;
            _playerService.playTrack(_selectedAlbumTracks[0], newPlaylist: List.from(_selectedAlbumTracks));
          } : null,
          onPlayAll: _selectedAlbumTracks.isNotEmpty ? () {
            _playerService.playTrack(_selectedAlbumTracks[0], newPlaylist: List.from(_selectedAlbumTracks));
          } : null,
          extraActions: [
            _buildActionButton(Icons.favorite_border_rounded, 'Save', () async {
              await _storageService.saveAlbum(a);
              await _loadUserData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Album saved!'),
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.9),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            }),
          ],
        )),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 180),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildTrackTile(
                _selectedAlbumTracks[index], _selectedAlbumTracks,
                index: index, showNumber: true,
              ),
              childCount: _selectedAlbumTracks.length,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  DETAIL HERO HEADER
  // ─────────────────────────────────────────────

  Widget _buildDetailHero({
    required String title,
    required String subtitle,
    required String coverUrl,
    VoidCallback? onBack,
    VoidCallback? onShuffle,
    VoidCallback? onPlayAll,
    List<Widget>? extraActions,
  }) {
    return Container(
      height: 280,
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          if (coverUrl.isNotEmpty)
            Positioned.fill(
              child: _buildCoverImage(coverUrl),
            ),
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.4),
                        const Color(0xFF0D0D1A),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Cover
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: coverUrl.isNotEmpty
                            ? _buildCoverImage(coverUrl, width: 140, height: 140)
                            : Container(
                                width: 140, height: 140,
                                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                child: const Icon(Icons.album_rounded, size: 56, color: Colors.white38),
                              ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.55))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Action buttons
                Row(
                  children: [
                    if (onShuffle != null)
                      _buildPillButton(Icons.shuffle_rounded, 'Shuffle', onShuffle, filled: false),
                    if (onShuffle != null) const SizedBox(width: 10),
                    if (onPlayAll != null)
                      _buildPillButton(Icons.play_arrow_rounded, 'Play All', onPlayAll, filled: true),
                    const Spacer(),
                    if (extraActions != null) ...extraActions,
                  ],
                ),
              ],
            ),
          ),
          // Back button
          if (onBack != null)
            Positioned(
              top: 8, left: 8,
              child: IconButton(
                onPressed: onBack,
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPillButton(IconData icon, String label, VoidCallback? onTap, {bool filled = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: filled ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  TRACK CARD (Grid item)
  // ─────────────────────────────────────────────

  Widget _buildTrackCard(MusicTrack track, List<MusicTrack> queue, {int? index}) {
    return _HoverScaleCard(
      onTap: () => _playerService.playTrack(track, newPlaylist: queue),
      onLongPress: () => _showTrackMenu(track),
      borderRadius: 16,
      hoverScale: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCoverImage(track.cover),
                  // Gradient overlay
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                        ),
                      ),
                    ),
                  ),
                  // Ranking badge
                  if (index != null && _currentView == MusicView.main)
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${index + 1 + _currentMusicOffset}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                      ),
                    ),
                  // Duration badge
                  if (track.duration > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatDuration(Duration(seconds: track.duration)),
                          style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  // Play button
                  Positioned(
                    bottom: 8, right: 8,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF9C6FFF)]),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: -0.1)),
                  const SizedBox(height: 2),
                  Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  TRACK TILE (List item)
  // ─────────────────────────────────────────────

  Widget _buildTrackTile(MusicTrack track, List<MusicTrack> queue, {int? index, bool showNumber = false, MusicPlaylist? fromPlaylist}) {
    return ValueListenableBuilder<MusicTrack?>(
      valueListenable: _playerService.currentTrack,
      builder: (context, currentTrack, _) {
        final isPlaying = currentTrack?.id == track.id;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _playerService.playTrack(track, newPlaylist: queue),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isPlaying ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: isPlaying ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)) : Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    // Number or playing indicator
                    if (showNumber)
                      SizedBox(
                        width: 32,
                        child: isPlaying
                            ? Icon(Icons.equalizer_rounded, color: AppTheme.primaryColor, size: 20)
                            : Text(
                                '${(index ?? 0) + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                      ),
                    // Cover art
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isPlaying
                            ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 12)]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildCoverImage(track.cover, width: 50, height: 50),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Title & Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14,
                              color: isPlaying ? AppTheme.primaryColor : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                          ),
                        ],
                      ),
                    ),
                    // Duration
                    if (track.duration > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          _formatDuration(Duration(seconds: track.duration)),
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ),
                    // More button
                    IconButton(
                      icon: Icon(Icons.more_horiz_rounded, color: Colors.white.withValues(alpha: 0.3), size: 22),
                      onPressed: () => _showTrackMenu(track, fromPlaylist: fromPlaylist),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  ALBUM CARD
  // ─────────────────────────────────────────────

  Widget _buildAlbumCard(MusicAlbum album, VoidCallback onTap) {
    final isSaved = _userAlbums.any((a) => a.id == album.id);
    
    return _HoverScaleCard(
      onTap: onTap,
      borderRadius: 16,
      hoverScale: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: album.cover,
                    fit: BoxFit.cover,
                    errorWidget: (c, u, e) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.album_rounded, color: Colors.white24, size: 48),
                    ),
                  ),
                  // Subtle overlay
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                        ),
                      ),
                    ),
                  ),
                  // Save/Unsave button
                  Positioned(
                    top: 8, right: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          if (isSaved) {
                            await _storageService.unsaveAlbum(album.id);
                          } else {
                            await _storageService.saveAlbum(album);
                          }
                          await _loadUserData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isSaved ? 'Album removed' : 'Album saved!'),
                                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.9),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isSaved ? Colors.amberAccent : Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Track count
                  if (album.nbTracks != null)
                    Positioned(
                      bottom: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${album.nbTracks} tracks', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  MINI PLAYER
  // ─────────────────────────────────────────────

  Widget _buildMiniPlayer() {
    return ValueListenableBuilder<bool>(
      valueListenable: _playerService.isFullScreenVisible,
      builder: (context, isFullScreen, _) {
        if (isFullScreen) return const SizedBox.shrink();

        return ValueListenableBuilder<MusicTrack?>(
          valueListenable: _playerService.currentTrack,
          builder: (context, track, _) {
            if (track == null) return const SizedBox.shrink();

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: GestureDetector(
                    onTap: _openFullPlayer,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF140E24).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                              BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.08), blurRadius: 30),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Progress bar
                              ValueListenableBuilder<Duration>(
                                valueListenable: _playerService.position,
                                builder: (context, pos, _) {
                                  return ValueListenableBuilder<Duration>(
                                    valueListenable: _playerService.duration,
                                    builder: (context, dur, _) {
                                      final progress = dur.inMilliseconds > 0
                                          ? pos.inMilliseconds / dur.inMilliseconds
                                          : 0.0;
                                      return Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 3,
                                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              // Player content
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      // Album art
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2), blurRadius: 10)],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: _buildCoverImage(track.cover, width: 48, height: 48),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      // Track info
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                            const SizedBox(height: 1),
                                            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
                                          ],
                                        ),
                                      ),
                                      // Controls
                                      IconButton(
                                        icon: Icon(Icons.skip_previous_rounded, color: Colors.white.withValues(alpha: 0.6), size: 24),
                                        onPressed: () => _playerService.previous(),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: _playerService.isBuffering,
                                        builder: (context, buffering, _) {
                                          if (buffering) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8),
                                              child: SizedBox(
                                                width: 24, height: 24,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                                              ),
                                            );
                                          }
                                          return ValueListenableBuilder<bool>(
                                            valueListenable: _playerService.isPlaying,
                                            builder: (context, playing, _) => Container(
                                              width: 40, height: 40,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF9C6FFF)]),
                                                shape: BoxShape.circle,
                                              ),
                                              child: IconButton(
                                                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                                onPressed: () => _playerService.togglePlay(),
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.skip_next_rounded, color: Colors.white.withValues(alpha: 0.6), size: 24),
                                        onPressed: () => _playerService.next(),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.25), size: 18),
                                        onPressed: () => _playerService.stop(),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  PAGINATION
  // ─────────────────────────────────────────────

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildPaginationButton('Previous', Icons.chevron_left_rounded,
              _currentMusicOffset > 0 ? _prevMusicPage : null),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Page ${(_currentMusicOffset / _musicLimit).floor() + 1}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          _buildPaginationButton('Next', Icons.chevron_right_rounded, _nextMusicPage, trailing: true),
        ],
      ),
    );
  }

  Widget _buildPaginationButton(String label, IconData icon, VoidCallback? onTap, {bool trailing = false}) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled
                ? (trailing ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.12))
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!trailing) Icon(icon, size: 18, color: isEnabled ? Colors.white : Colors.white24),
              if (!trailing) const SizedBox(width: 4),
              Text(label, style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                color: isEnabled ? Colors.white : Colors.white24,
              )),
              if (trailing) const SizedBox(width: 4),
              if (trailing) Icon(icon, size: 18, color: isEnabled ? Colors.white : Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  SECTION HEADER
  // ─────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    VoidCallback? onBack,
    List<Widget>? actions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Row(
        children: [
          if (onBack != null && !_isDesktop)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              visualDensity: VisualDensity.compact,
            ),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35))),
              ],
            ),
          ),
          if (actions != null) ...actions,
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  EMPTY STATE
  // ─────────────────────────────────────────────

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: Colors.white.withValues(alpha: 0.2)),
          ),
          const SizedBox(height: 20),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5))),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.25))),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  LOADING SHIMMER
  // ─────────────────────────────────────────────

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  TRACK MENU (Bottom Sheet)
  // ─────────────────────────────────────────────

  void _showTrackMenu(MusicTrack track, {MusicPlaylist? fromPlaylist}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141020),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
            // Track header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2), blurRadius: 15)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildCoverImage(track.cover, width: 64, height: 64),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(track.artist, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            // Menu items
            if (fromPlaylist != null)
              _buildMenuItem(Icons.playlist_remove_rounded, 'Remove from Playlist', Colors.redAccent, () async {
                Navigator.pop(context);
                final updatedTracks = List<MusicTrack>.from(fromPlaylist.tracks)..removeWhere((t) => t.id == track.id);
                final updatedPlaylist = MusicPlaylist(name: fromPlaylist.name, tracks: updatedTracks);
                await _storageService.savePlaylist(updatedPlaylist);
                await _loadUserData();
                if (mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _selectedPlaylist = updatedPlaylist);
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Removed from playlist'),
                      backgroundColor: const Color(0xFF1A1030),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }),
            _buildMenuItem(Icons.playlist_add_rounded, 'Add to Playlist', AppTheme.primaryColor, () {
              Navigator.pop(context);
              _showPlaylistPicker(track);
            }),
            ValueListenableBuilder<List<MusicTrack>>(
              valueListenable: _storageService.likedSongs,
              builder: (context, liked, _) {
                final isLiked = liked.any((s) => s.id == track.id);
                return _buildMenuItem(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  isLiked ? 'Remove from Liked' : 'Like Song',
                  isLiked ? Colors.pinkAccent : Colors.white54,
                  () async {
                    final navigator = Navigator.of(context);
                    if (isLiked) {
                      await _storageService.removeLikedSong(track.id);
                    } else {
                      await _storageService.saveLikedSong(track);
                    }
                    if (!mounted) return;
                    navigator.pop();
                  },
                );
              },
            ),
            ValueListenableBuilder<List<MusicTrack>>(
              valueListenable: _storageService.downloadedTracks,
              builder: (context, downloaded, _) {
                final isDownloaded = downloaded.any((s) => s.id == track.id);
                return _buildMenuItem(
                  isDownloaded ? Icons.delete_outline_rounded : Icons.download_rounded,
                  isDownloaded ? 'Delete Download' : 'Download',
                  isDownloaded ? Colors.redAccent : Colors.white54,
                  () async {
                    Navigator.pop(context);
                    if (isDownloaded) {
                      final downloadedTrack = downloaded.firstWhere((s) => s.id == track.id);
                      if (downloadedTrack.localPath != null) {
                        final file = File(downloadedTrack.localPath!);
                        if (await file.exists()) await file.delete();
                      }
                      if (!downloadedTrack.cover.startsWith('http')) {
                        final coverFile = File(downloadedTrack.cover);
                        if (await coverFile.exists()) await coverFile.delete();
                      }
                      await _storageService.removeDownloadedTrack(track.id);
                    } else {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await _downloader.downloadTrack(track);
                      if (mounted) {
                        messenger.showSnackBar(SnackBar(
                          content: Text(success ? 'Added to download queue...' : 'Already in download queue'),
                          backgroundColor: const Color(0xFF1A1030),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ));
                      }
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, Color iconColor, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  PLAYLIST PICKER
  // ─────────────────────────────────────────────

  void _showPlaylistPicker(MusicTrack track) async {
    final playlists = await _storageService.getPlaylists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Create a playlist first!'),
        backgroundColor: const Color(0xFF1A1030),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141020),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Add to Playlist', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ...playlists.map((p) => Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  p.tracks.add(track);
                  await _storageService.savePlaylist(p);
                  await _loadUserData();
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(SnackBar(
                    content: Text('Added to ${p.name}'),
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.9),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.queue_music_rounded, color: AppTheme.primaryColor, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(p.name, style: const TextStyle(fontSize: 15))),
                      Text('${p.tracks.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
                    ],
                  ),
                ),
              ),
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  CREATE PLAYLIST DIALOG
  // ─────────────────────────────────────────────

  void _createPlaylist() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF141020),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.playlist_add_rounded, color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text('New Playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Playlist name...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        if (controller.text.isNotEmpty) {
                          final navigator = Navigator.of(context);
                          final newPlaylist = MusicPlaylist(name: controller.text, tracks: []);
                          await _storageService.savePlaylist(newPlaylist);
                          await _loadUserData();
                          if (!mounted) return;
                          navigator.pop();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF9C6FFF)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Create', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  DOWNLOAD FOLDER DIALOG
  // ─────────────────────────────────────────────

  void _openDownloadFolder(List<MusicTrack> downloaded) async {
    if (downloaded.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No downloads to show'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    final path = downloaded.first.localPath ?? 'Android/media/com.example.play_torrio_native/Music';
    final dirPath = File(path).parent.path;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF141020),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4DD0E1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.folder_open_rounded, color: Color(0xFF4DD0E1), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text('Downloads Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              Text('Android restricts apps from opening folders directly.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
              const SizedBox(height: 16),
              const Text('Your music is saved at:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Text(dirPath, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.primaryColor)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: Colors.greenAccent.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Songs are added to your system music library!',
                      style: TextStyle(color: Colors.greenAccent.withValues(alpha: 0.7), fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: dirPath));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Path copied!'),
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.9),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ));
                      Navigator.pop(context);
                    },
                    child: const Text('Copy Path', style: TextStyle(color: AppTheme.primaryColor)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────

  Widget _buildCoverImage(String cover, {double? width, double? height}) {
    if (cover.isEmpty) {
      return Container(
        width: width, height: height,
        color: Colors.white.withValues(alpha: 0.05),
        child: const Icon(Icons.music_note_rounded, color: Colors.white24),
      );
    }
    if (cover.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: cover,
        width: width, height: height,
        fit: BoxFit.cover,
        errorWidget: (c, u, e) => Container(
          width: width, height: height,
          color: Colors.white.withValues(alpha: 0.05),
          child: const Icon(Icons.music_note_rounded, color: Colors.white24),
        ),
      );
    }
    return Image.file(
      File(cover),
      width: width, height: height,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => Container(
        width: width, height: height,
        color: Colors.white.withValues(alpha: 0.05),
        child: const Icon(Icons.music_note_rounded, color: Colors.white24),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ═══════════════════════════════════════════════
//  HOVER CARD WIDGET (scale + glow on hover)
// ═══════════════════════════════════════════════

class _HoverScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final double hoverScale;

  const _HoverScaleCard({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 16,
    this.hoverScale = 1.04,
  });

  @override
  State<_HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<_HoverScaleCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: widget.hoverScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter() {
    setState(() => _isHovered = true);
    _controller.forward();
  }

  void _onExit() {
    setState(() => _isHovered = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(
            scale: _scale.value,
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
