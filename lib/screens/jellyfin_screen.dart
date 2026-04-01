import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import '../utils/app_theme.dart';
import 'jellyfin_details_screen.dart';

class JellyfinScreen extends StatefulWidget {
  const JellyfinScreen({super.key});

  @override
  State<JellyfinScreen> createState() => _JellyfinScreenState();
}

class _JellyfinScreenState extends State<JellyfinScreen>
    with AutomaticKeepAliveClientMixin {
  final JellyfinService _jf = JellyfinService();

  bool _isLoading = true;
  bool _isLoggedIn = false;
  String? _error;

  List<JellyfinItem> _libraries = [];
  List<JellyfinItem> _resumeItems = [];
  List<JellyfinItem> _nextUpItems = [];
  Map<String, List<JellyfinItem>> _latestByLibrary = {};
  final TextEditingController _librarySearchController = TextEditingController();
  final FocusNode _librarySearchFocus = FocusNode();
  Timer? _librarySearchDebounce;

  // Items grid when a library is selected
  String? _selectedLibraryId;
  String? _selectedLibraryName;
  List<JellyfinItem> _allLibraryItems = [];   // items for the current view
  List<JellyfinItem> _libraryItems = [];       // current page / filter slice
  bool _isLoadingLibrary = false;
  String _librarySortBy = 'SortName';
  String _librarySortOrder = 'Ascending';

  // Pagination
  static const int _pageSize = 50;
  int _libraryPage = 0;
  String _librarySearchTerm = '';
  bool _isBackgroundLoading = false;

  // Persistent cache — survives navigating back to home and returning
  final Map<String, List<JellyfinItem>> _libraryCache = {};    // key → items
  final Set<String> _libraryCacheComplete = {};                // keys fully fetched
  final Set<String> _libraryCacheFetching = {};                // keys currently fetching
  final Map<String, int> _libraryFetchGen = {};                // key → gen (cancel stale fetches on sort change)

  String get _currentCacheKey =>
      '${_selectedLibraryId ?? ''}|$_librarySortBy|$_librarySortOrder';
  String _cacheKey(JellyfinItem lib) =>
      '${lib.id}|$_librarySortBy|$_librarySortOrder';

  // Derived helpers
  int get _libraryTotalCount => _librarySearchTerm.isEmpty
      ? _allLibraryItems.length
      : _libraryItems.length;
  int get _totalPages => (_libraryTotalCount / _pageSize).ceil().clamp(1, 99999);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _librarySearchDebounce?.cancel();
    _librarySearchController.dispose();
    _librarySearchFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      final ok = await _jf.loadSavedSession();
      if (ok) {
        _isLoggedIn = true;
        await _loadHomeData();
      }
    } catch (e) {
      debugPrint('[JellyfinScreen] Init error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadHomeData() async {
    try {
      _libraries = await _jf.getLibraries();
      // Filter to video libraries only
      final videoLibraries = _libraries.where((l) =>
          l.collectionType == 'movies' || l.collectionType == 'tvshows' || l.collectionType == null).toList();

      final results = await Future.wait([
        _jf.getResumeItems(limit: 12),
        _jf.getNextUp(limit: 20),
        ...videoLibraries.map((lib) => _jf.getLatestItems(parentId: lib.id, limit: 16)),
      ]);

      _resumeItems = results[0];
      _nextUpItems = results[1];

      _latestByLibrary = {};
      for (var i = 0; i < videoLibraries.length; i++) {
        final items = results[i + 2];
        if (items.isNotEmpty) {
          _latestByLibrary[videoLibraries[i].name] = items;
        }
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load data: $e';
      debugPrint('[JellyfinScreen] Load error: $e');
    }
    if (mounted) setState(() {});
  }

  // ─── filter / page helpers ────────────────────────────────────────────────

  void _applyFilter(String query) {
    _librarySearchTerm = query.trim().toLowerCase();
    _libraryPage = 0;
    _rebuildPage();
  }

  void _rebuildPage() {
    final filtered = _librarySearchTerm.isEmpty
        ? _allLibraryItems
        : _allLibraryItems
            .where((i) => i.name.toLowerCase().contains(_librarySearchTerm))
            .toList();
    if (_librarySearchTerm.isNotEmpty) {
      // Show all matches without pagination when filtering
      _libraryItems = filtered;
    } else {
      final start = _libraryPage * _pageSize;
      final end = (start + _pageSize).clamp(0, filtered.length);
      _libraryItems = filtered.sublist(start, end);
    }
    if (mounted) setState(() {});
  }

  Future<void> _searchLibrary(String query) async {
    _applyFilter(query);
  }

  Future<void> _openLibrary(JellyfinItem library) async {
    _librarySearchController.clear();
    _librarySearchDebounce?.cancel();
    _librarySearchTerm = '';
    _libraryPage = 0;

    final key = _cacheKey(library);

    if (_libraryCache.containsKey(key)) {
      // ── Instant restore from cache ──
      final cached = _libraryCache[key]!;
      final bgLoading = _libraryCacheFetching.contains(key);
      setState(() {
        _selectedLibraryId = library.id;
        _selectedLibraryName = library.name;
        _isLoadingLibrary = false;
        _isBackgroundLoading = bgLoading;
        _allLibraryItems = cached;
      });
      _rebuildPage();
      // Resume background fetch if interrupted and not already running
      if (!_libraryCacheComplete.contains(key) && !_libraryCacheFetching.contains(key)) {
        _fetchLibraryItems(library, key);
      }
    } else {
      // ── First visit ──
      setState(() {
        _selectedLibraryId = library.id;
        _selectedLibraryName = library.name;
        _isLoadingLibrary = true;
        _isBackgroundLoading = false;
        _allLibraryItems = [];
        _libraryItems = [];
      });
      _fetchLibraryItems(library, key);
    }
  }

  Future<void> _fetchLibraryItems(JellyfinItem library, String key) async {
    final gen = (_libraryFetchGen[key] ?? 0) + 1;
    _libraryFetchGen[key] = gen;
    _libraryCacheFetching.add(key);

    final type = library.collectionType == 'movies'
        ? 'Movie'
        : library.collectionType == 'tvshows'
            ? 'Series'
            : null;

    // Helper: is this fetch still valid (not superseded by a sort change)?
    bool valid() => _libraryFetchGen[key] == gen;
    // Helper: is the user currently viewing this library?
    bool viewing() => _selectedLibraryId == library.id && _currentCacheKey == key;

    try {
      // ── Step 1: first page — show grid fast ──
      final first = await _jf.getItemsPaged(
        parentId: library.id,
        includeItemTypes: type,
        sortBy: _librarySortBy,
        sortOrder: _librarySortOrder,
        startIndex: 0,
        limit: _pageSize,
      );
      if (!valid()) { _libraryCacheFetching.remove(key); return; }

      _libraryCache[key] = List.of(first.items);
      if (viewing()) {
        _allLibraryItems = _libraryCache[key]!;
        _rebuildPage();
        if (mounted) setState(() => _isLoadingLibrary = false);
      }

      final total = first.totalCount;
      if (total <= _pageSize) {
        _libraryCacheComplete.add(key);
        _libraryCacheFetching.remove(key);
        if (viewing() && mounted) setState(() => _isBackgroundLoading = false);
        return;
      }

      // ── Step 2: background pages — keep going even if user navigates away ──
      if (viewing() && mounted) setState(() => _isBackgroundLoading = true);

      int fetched = _pageSize;
      while (fetched < total) {
        if (!valid()) { _libraryCacheFetching.remove(key); return; }

        final page = await _jf.getItemsPaged(
          parentId: library.id,
          includeItemTypes: type,
          sortBy: _librarySortBy,
          sortOrder: _librarySortOrder,
          startIndex: fetched,
          limit: 200,
        );
        if (!valid()) { _libraryCacheFetching.remove(key); return; }
        if (page.items.isEmpty) break;

        _libraryCache[key] = [..._libraryCache[key]!, ...page.items];
        fetched += page.items.length;

        // Update view only if user is still on this library
        if (viewing()) {
          _allLibraryItems = _libraryCache[key]!;
          if (mounted) setState(() {});
        }
      }

      _libraryCacheComplete.add(key);
      _libraryCacheFetching.remove(key);
      if (viewing() && mounted) setState(() => _isBackgroundLoading = false);

    } catch (e) {
      if (!valid()) return;
      debugPrint('[JellyfinScreen] Library fetch error: $e');
      _libraryCacheFetching.remove(key);
      if (viewing() && mounted) {
        setState(() { _isLoadingLibrary = false; _isBackgroundLoading = false; });
      }
    }
  }

  Future<void> _loadLibraryPage(int page) async {
    _libraryPage = page;
    _rebuildPage();
  }

  void _openDetails(JellyfinItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JellyfinDetailsScreen(item: item)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Add Account Dialog
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _showAddAccountDialog() async {
    final urlCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isLogging = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withValues(alpha: 0.3),
                        const Color(0xFF00A4DC).withValues(alpha: 0.3),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.dns_rounded, size: 36, color: Color(0xFF00A4DC)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Connect to Jellyfin',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your server details',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
                const SizedBox(height: 24),

                // URL Field
                _buildTextField(urlCtrl, 'Server URL', Icons.link_rounded,
                    hint: 'http://192.168.1.100:8096'),
                const SizedBox(height: 14),

                // Username
                _buildTextField(userCtrl, 'Username', Icons.person_rounded),
                const SizedBox(height: 14),

                // Password
                _buildTextField(passCtrl, 'Password', Icons.lock_rounded,
                    isPassword: true),

                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(dialogError!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Connect Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isLogging
                        ? null
                        : () async {
                            if (urlCtrl.text.trim().isEmpty || userCtrl.text.trim().isEmpty) {
                              setDialogState(() => dialogError = 'Please fill in all fields');
                              return;
                            }
                            setDialogState(() {
                              isLogging = true;
                              dialogError = null;
                            });
                            try {
                              await _jf.login(
                                urlCtrl.text.trim(),
                                userCtrl.text.trim(),
                                passCtrl.text,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() {
                                _isLoggedIn = true;
                                _isLoading = true;
                              });
                              await _loadHomeData();
                              if (mounted) setState(() => _isLoading = false);
                            } catch (e) {
                              setDialogState(() {
                                isLogging = false;
                                dialogError = e.toString().replaceAll('Exception: ', '');
                              });
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A4DC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: isLogging
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Connect',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? hint,
    bool isPassword = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
        prefixIcon: Icon(icon, color: const Color(0xFF00A4DC), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00A4DC)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Future<void> _showAccountManager() async {
    final accounts = await _jf.getSavedAccounts();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.dns_rounded, color: Color(0xFF00A4DC)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Jellyfin Accounts',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddAccountDialog();
                      },
                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00A4DC)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (accounts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 48, color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text('No accounts added',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                else
                  ...accounts.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final acc = entry.value;
                    final isActive =
                        _jf.activeAccount?.normalizedUrl == acc.normalizedUrl &&
                            _jf.activeAccount?.username == acc.username;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF00A4DC).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: isActive
                            ? Border.all(color: const Color(0xFF00A4DC).withValues(alpha: 0.4))
                            : null,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive
                              ? const Color(0xFF00A4DC)
                              : Colors.white.withValues(alpha: 0.1),
                          child: Icon(Icons.person, color: isActive ? Colors.white : Colors.white54),
                        ),
                        title: Text(acc.username,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text(acc.normalizedUrl,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isActive)
                              IconButton(
                                icon: const Icon(Icons.login, color: Color(0xFF00A4DC), size: 20),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  setState(() => _isLoading = true);
                                  try {
                                    await _jf.login(acc.serverUrl, acc.username, acc.password);
                                    _isLoggedIn = true;
                                    await _loadHomeData();
                                  } catch (e) {
                                    _error = e.toString();
                                  }
                                  if (mounted) setState(() => _isLoading = false);
                                },
                              ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Colors.redAccent.withValues(alpha: 0.7), size: 20),
                              onPressed: () async {
                                await _jf.removeAccount(idx);
                                final updated = await _jf.getSavedAccounts();
                                setSheetState(() => accounts
                                  ..clear()
                                  ..addAll(updated));
                                if (!_jf.isLoggedIn) {
                                  setState(() => _isLoggedIn = false);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return Container(
        decoration: AppTheme.backgroundDecoration,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF00A4DC)),
        ),
      );
    }

    if (!_isLoggedIn) return _buildWelcome();

    if (_selectedLibraryId != null) return _buildLibraryView();

    return _buildHome();
  }

  // ─── Welcome / Not Logged In ─────────────────────────────────────────────

  Widget _buildWelcome() {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00A4DC).withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                  radius: 0.8,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.dns_rounded, size: 72, color: Color(0xFF00A4DC)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Jellyfin',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect to your media server',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              onPressed: () => _showAddAccountDialog(),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A4DC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Home View ───────────────────────────────────────────────────────────

  Widget _buildHome() {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: CustomScrollView(
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                const Icon(Icons.dns_rounded, color: Color(0xFF00A4DC), size: 24),
                const SizedBox(width: 10),
                Text(
                  _jf.activeAccount?.username ?? 'Jellyfin',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '• ${_jf.activeAccount?.normalizedUrl.replaceAll(RegExp(r'https?://'), '') ?? ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.manage_accounts_rounded, color: Colors.white70),
                onPressed: () => _showAccountManager(),
                tooltip: 'Accounts',
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                onPressed: () async {
                  setState(() => _isLoading = true);
                  await _loadHomeData();
                  if (mounted) setState(() => _isLoading = false);
                },
                tooltip: 'Refresh',
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ── Home content ──
          ...[
            // ── Libraries ──
            if (_libraries.isNotEmpty)
              SliverToBoxAdapter(child: _buildLibraryChips()),

            // ── Continue Watching ──
            if (_resumeItems.isNotEmpty)
              _buildHorizontalSection('Continue Watching', _resumeItems, showProgress: true),

            // ── Next Up ──
            if (_nextUpItems.isNotEmpty)
              _buildHorizontalSection('Next Up', _nextUpItems, showEpisodeInfo: true),

            // ── Latest by Library ──
            ..._latestByLibrary.entries.map((entry) =>
              _buildHorizontalSection('Latest in ${entry.key}', entry.value)),

            // ── Error ──
            if (_error != null)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ],
      ),
    );
  }

  // ─── Library Chips ─────────────────────────────────────────────────────────

  Widget _buildLibraryChips() {
    final videoLibs = _libraries.where((l) =>
        l.collectionType == 'movies' || l.collectionType == 'tvshows' || l.collectionType == null).toList();
    if (videoLibs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: videoLibs.map((lib) {
          final icon = lib.collectionType == 'movies'
              ? Icons.movie_outlined
              : lib.collectionType == 'tvshows'
                  ? Icons.tv_outlined
                  : Icons.video_library_outlined;
          return ActionChip(
            avatar: Icon(icon, size: 18, color: const Color(0xFF00A4DC)),
            label: Text(lib.name),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            onPressed: () => _openLibrary(lib),
          );
        }).toList(),
      ),
    );
  }

  // ─── Horizontal Section ──────────────────────────────────────────────────

  SliverToBoxAdapter _buildHorizontalSection(
    String title,
    List<JellyfinItem> items, {
    bool showProgress = false,
    bool showEpisodeInfo = false,
  }) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          SizedBox(
            height: showEpisodeInfo ? 230 : 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildPosterCard(item,
                      showProgress: showProgress, showEpisodeInfo: showEpisodeInfo),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Poster Card ─────────────────────────────────────────────────────────

  Widget _buildPosterCard(
    JellyfinItem item, {
    bool showProgress = false,
    bool showEpisodeInfo = false,
    bool inGrid = false,
  }) {
    final imageUrl = item.imageTags.containsKey('Primary')
        ? _jf.getPosterUrl(item.id, tag: item.imageTags['Primary'])
        : (item.seriesId != null
            ? _jf.getPosterUrl(item.seriesId!, maxWidth: 300)
            : null);

    final width = inGrid ? double.infinity : 140.0;

    return GestureDetector(
      onTap: () {
        if (item.type == 'Episode' && item.seriesId != null) {
          // Open the series details, not the episode itself
          _openDetails(JellyfinItem(id: item.seriesId!, name: item.seriesName ?? item.name, type: 'Series'));
        } else {
          _openDetails(item);
        }
      },
      child: SizedBox(
        width: inGrid ? null : width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (c, u) => Shimmer.fromColors(
                          baseColor: AppTheme.bgCard,
                          highlightColor: Colors.white10,
                          child: Container(color: AppTheme.bgCard),
                        ),
                        errorWidget: (c, u, e) =>
                            const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                      )
                    else
                      Center(
                        child: Icon(
                          item.type == 'Series' ? Icons.tv : Icons.movie,
                          size: 40,
                          color: Colors.white24,
                        ),
                      ),

                    // Gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 60,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                    ),

                    // Rating badge
                    if (item.communityRating != null)
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
                              const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFD700)),
                              const SizedBox(width: 2),
                              Text(
                                item.communityRating!.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Played indicator
                    if (item.isPlayed)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A4DC),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00A4DC).withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.check, size: 12, color: Colors.white),
                        ),
                      ),

                    // Unplayed count
                    if (item.unplayedCount > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A4DC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.unplayedCount}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                    // Progress bar
                    if (showProgress && item.playbackProgress > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: item.playbackProgress,
                          minHeight: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF00A4DC)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              showEpisodeInfo && item.seriesName != null ? item.seriesName! : item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (showEpisodeInfo && item.type == 'Episode')
              Text(
                'S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'} • ${item.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              )
            else if (item.productionYear != null)
              Text(
                '${item.productionYear}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Library Items View ──────────────────────────────────────────────────

  Widget _buildLibraryView() {
    final currentPage = _libraryPage + 1;

    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Column(
        children: [
          // Header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () {
                      _librarySearchController.clear();
                      _librarySearchDebounce?.cancel();
                      _librarySearchFocus.unfocus();
                      setState(() {
                        _selectedLibraryId = null;
                        _selectedLibraryName = null;
                        _allLibraryItems = [];
                        _libraryItems = [];
                        _libraryPage = 0;
                        _librarySearchTerm = '';
                        _isBackgroundLoading = false;
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      _selectedLibraryName ?? 'Library',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  // Sort dropdown
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.sort_rounded, color: Colors.white70),
                    color: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      final parts = val.split('|');
                      _librarySortBy = parts[0];
                      _librarySortOrder = parts[1];
                      // Sort changed — invalidate cache for this library and re-fetch
                      if (_selectedLibraryId != null) {
                        final lib = _libraries.firstWhere((l) => l.id == _selectedLibraryId);
                        final oldKeys = _libraryCache.keys
                            .where((k) => k.startsWith('${lib.id}|'))
                            .toList();
                        for (final k in oldKeys) {
                          _libraryCache.remove(k);
                          _libraryCacheComplete.remove(k);
                        }
                        _openLibrary(lib);
                      }
                    },
                    itemBuilder: (_) => [
                      _sortMenuItem('Name (A-Z)', 'SortName|Ascending'),
                      _sortMenuItem('Name (Z-A)', 'SortName|Descending'),
                      _sortMenuItem('Date Added (New)', 'DateCreated|Descending'),
                      _sortMenuItem('Date Added (Old)', 'DateCreated|Ascending'),
                      _sortMenuItem('Release Date (New)', 'PremiereDate|Descending'),
                      _sortMenuItem('Release Date (Old)', 'PremiereDate|Ascending'),
                      _sortMenuItem('Rating (High)', 'CommunityRating|Descending'),
                      _sortMenuItem('Rating (Low)', 'CommunityRating|Ascending'),
                      _sortMenuItem('Runtime (Long)', 'Runtime|Descending'),
                      _sortMenuItem('Runtime (Short)', 'Runtime|Ascending'),
                    ],
                  ),
                  if (_allLibraryItems.isNotEmpty)
                    Text(
                      _librarySearchTerm.isNotEmpty
                          ? '${_libraryItems.length} of ${_allLibraryItems.length}'
                          : '${_allLibraryItems.length} total',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // ── Background-loading progress bar ──
          if (_isBackgroundLoading)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF00A4DC).withValues(alpha: 0.6)),
            ),

          // ── Search Bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _librarySearchController,
              focusNode: _librarySearchFocus,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: (q) {
                setState(() {}); // rebuild suffix icon visibility
                _librarySearchDebounce?.cancel();
                _librarySearchDebounce = Timer(
                  const Duration(milliseconds: 400),
                  () => _searchLibrary(q),
                );
              },
              decoration: InputDecoration(
                hintText: _isBackgroundLoading
                    ? 'Loading all items for search... (${_allLibraryItems.length} so far)'
                    : 'Search ${_selectedLibraryName ?? 'library'}...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF00A4DC), size: 20),
                suffixIcon: _librarySearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                        onPressed: () {
                          _librarySearchController.clear();
                          _librarySearchFocus.unfocus();
                          _applyFilter('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Grid
          Expanded(
            child: _isLoadingLibrary
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A4DC)))
                : _libraryItems.isEmpty
                    ? Center(
                        child: Text(
                          _librarySearchTerm.isNotEmpty
                              ? 'No results for "$_librarySearchTerm"'
                              : 'No items found',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = constraints.maxWidth > 1200
                              ? 8
                              : constraints.maxWidth > 900
                                  ? 6
                                  : constraints.maxWidth > 600
                                      ? 4
                                      : 3;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              childAspectRatio: 0.55,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: _libraryItems.length,
                            itemBuilder: (context, index) =>
                                _buildPosterCard(_libraryItems[index], inGrid: true),
                          );
                        },
                      ),
          ),

          // ── Pagination (hidden when a filter is active since all matches are shown) ──
          if (!_isLoadingLibrary && _librarySearchTerm.isEmpty && _allLibraryItems.length > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Previous
                  IconButton(
                    onPressed: _libraryPage > 0 ? () => _loadLibraryPage(_libraryPage - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: _libraryPage > 0 ? const Color(0xFF00A4DC) : Colors.white24,
                    tooltip: 'Previous page',
                  ),
                  const SizedBox(width: 8),
                  // Page indicator — tappable to jump
                  GestureDetector(
                    onTap: () => _showPageJumpDialog(_totalPages),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Page $currentPage of $_totalPages',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Next
                  IconButton(
                    onPressed: currentPage < _totalPages ? () => _loadLibraryPage(_libraryPage + 1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: currentPage < _totalPages ? const Color(0xFF00A4DC) : Colors.white24,
                    tooltip: 'Next page',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showPageJumpDialog(int totalPages) async {
    final ctrl = TextEditingController(text: '${_libraryPage + 1}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Go to page', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '1 – $totalPages',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Go', style: TextStyle(color: Color(0xFF00A4DC))),
          ),
        ],
      ),
    );
    if (result != null) {
      final page = (result - 1).clamp(0, totalPages - 1);
      _loadLibraryPage(page);
    }
  }

  PopupMenuItem<String> _sortMenuItem(String label, String value) {
    final isActive = value == '$_librarySortBy|$_librarySortOrder';
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: TextStyle(
            color: isActive ? const Color(0xFF00A4DC) : Colors.white,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          )),
    );
  }
}
