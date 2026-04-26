import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import '../utils/app_theme.dart';
import 'jellyfin_details_screen.dart';

// ─── Jellyfin Palette ────────────────────────────────────────────────────────
const _jfBlue = Color(0xFF00A4DC);
const _jfBlueDark = Color(0xFF0077B6);
const _jfSurface = Color(0xFF13131E);
const _jfSurfaceLight = Color(0xFF1A1A2E);

// ─── Hover / Press Card ─────────────────────────────────────────────────────
class _HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _HoverCard({required this.child, this.onTap});
  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;
  bool _pressed = false;
  double get _scale => _pressed ? 0.96 : (_hovered ? 1.04 : 1.0);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Jellyfin Screen
// ═════════════════════════════════════════════════════════════════════════════

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

  // Hero carousel
  List<JellyfinItem> _featuredItems = [];
  late final PageController _heroController = PageController();
  Timer? _heroTimer;
  int _heroPage = 0;

  // Library view
  String? _selectedLibraryId;
  String? _selectedLibraryName;
  List<JellyfinItem> _allLibraryItems = [];
  List<JellyfinItem> _libraryItems = [];
  bool _isLoadingLibrary = false;
  String _librarySortBy = 'SortName';
  String _librarySortOrder = 'Ascending';

  static const int _pageSize = 50;
  int _libraryPage = 0;
  String _librarySearchTerm = '';
  bool _isBackgroundLoading = false;

  final Map<String, List<JellyfinItem>> _libraryCache = {};
  final Set<String> _libraryCacheComplete = {};
  final Set<String> _libraryCacheFetching = {};
  final Map<String, int> _libraryFetchGen = {};

  String get _currentCacheKey =>
      '${_selectedLibraryId ?? ''}|$_librarySortBy|$_librarySortOrder';
  String _cacheKey(JellyfinItem lib) =>
      '${lib.id}|$_librarySortBy|$_librarySortOrder';

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
    _heroTimer?.cancel();
    _heroController.dispose();
    _librarySearchDebounce?.cancel();
    _librarySearchController.dispose();
    _librarySearchFocus.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Data Loading
  // ═══════════════════════════════════════════════════════════════════════════

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
      final home = await _jf.loadHomeData();
      _libraries = home.libraries;
      _resumeItems = home.resumeItems;
      _nextUpItems = home.nextUpItems;
      _latestByLibrary = home.latestByLibrary;

      // Build featured items for hero — prefer items with backdrop images
      _featuredItems = [];
      for (final items in _latestByLibrary.values) {
        for (final item in items) {
          if (item.backdropImageTags.isNotEmpty && _featuredItems.length < 6) {
            _featuredItems.add(item);
          }
        }
      }
      if (_featuredItems.isEmpty) {
        for (final items in _latestByLibrary.values) {
          _featuredItems.addAll(items.take(3));
          if (_featuredItems.length >= 6) break;
        }
      }
      _featuredItems = _featuredItems.take(6).toList();
      _startHeroTimer();

      _error = null;
    } catch (e) {
      _error = 'Failed to load: $e';
      debugPrint('[JellyfinScreen] Load error: $e');
    }
    if (mounted) setState(() {});
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    if (_featuredItems.length <= 1) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_heroController.hasClients) return;
      _heroPage = (_heroPage + 1) % _featuredItems.length;
      _heroController.animateToPage(_heroPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Filter / Pagination
  // ═══════════════════════════════════════════════════════════════════════════

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
      _libraryItems = filtered;
    } else {
      final start = _libraryPage * _pageSize;
      final end = (start + _pageSize).clamp(0, filtered.length);
      _libraryItems = filtered.sublist(start, end);
    }
    if (mounted) setState(() {});
  }

  Future<void> _searchLibrary(String query) async => _applyFilter(query);

  Future<void> _openLibrary(JellyfinItem library) async {
    _librarySearchController.clear();
    _librarySearchDebounce?.cancel();
    _librarySearchTerm = '';
    _libraryPage = 0;

    final key = _cacheKey(library);

    if (_libraryCache.containsKey(key)) {
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
      if (!_libraryCacheComplete.contains(key) && !_libraryCacheFetching.contains(key)) {
        _fetchLibraryItems(library, key);
      }
    } else {
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

    bool valid() => _libraryFetchGen[key] == gen;
    bool viewing() => _selectedLibraryId == library.id && _currentCacheKey == key;

    try {
      // Fetch ALL items in a single request (no limit) — matches how
      // jellyfin-web and Findroid handle it. The Jellyfin server has no
      // rate-limiting on the Items endpoint; Limit is purely client-side.
      final result = await _jf.getItemsPaged(
        parentId: library.id,
        includeItemTypes: type,
        sortBy: _librarySortBy,
        sortOrder: _librarySortOrder,
        startIndex: 0,
      );
      if (!valid()) { _libraryCacheFetching.remove(key); return; }

      _libraryCache[key] = List.of(result.items);
      _libraryCacheComplete.add(key);
      _libraryCacheFetching.remove(key);

      if (viewing()) {
        _allLibraryItems = _libraryCache[key]!;
        _rebuildPage();
        if (mounted) {
          setState(() {
            _isLoadingLibrary = false;
            _isBackgroundLoading = false;
          });
        }
      }
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
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => JellyfinDetailsScreen(item: item))).then((_) {
      // Refresh Continue Watching / Next Up after returning from details
      _jf.invalidatePlaybackCache();
      _loadHomeData();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Account Dialogs
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
          backgroundColor: _jfSurfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_jfBlue.withValues(alpha: 0.25), _jfBlueDark.withValues(alpha: 0.15)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.dns_rounded, size: 32, color: _jfBlue),
                ),
                const SizedBox(height: 20),
                const Text('Connect Server',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text('Enter your Jellyfin server details',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                const SizedBox(height: 28),
                _dialogField(urlCtrl, 'Server URL', Icons.link_rounded,
                    hint: 'https://jellyfin.example.com'),
                const SizedBox(height: 14),
                _dialogField(userCtrl, 'Username', Icons.person_outline_rounded),
                const SizedBox(height: 14),
                _dialogField(passCtrl, 'Password', Icons.lock_outline_rounded,
                    isPassword: true),
                if (dialogError != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(dialogError!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLogging
                        ? null
                        : () async {
                            if (urlCtrl.text.trim().isEmpty || userCtrl.text.trim().isEmpty) {
                              setDialogState(() => dialogError = 'Please fill in all required fields');
                              return;
                            }
                            setDialogState(() { isLogging = true; dialogError = null; });
                            try {
                              await _jf.login(urlCtrl.text.trim(), userCtrl.text.trim(), passCtrl.text);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (!mounted) return;
                              setState(() { _isLoggedIn = true; _isLoading = true; });
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
                      backgroundColor: _jfBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isLogging
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Connect',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String label, IconData icon,
      {String? hint, bool isPassword = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
        prefixIcon: Icon(icon, color: _jfBlue, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _jfBlue, width: 1.5),
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: _jfSurfaceLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.dns_rounded, color: _jfBlue, size: 22),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Accounts',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                      _HoverCard(
                        onTap: () { Navigator.pop(ctx); _showAddAccountDialog(); },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _jfBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_rounded, color: _jfBlue, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(children: [
                        Icon(Icons.cloud_off_rounded, size: 44, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text('No accounts', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
                      ]),
                    )
                  else
                    ...accounts.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final acc = entry.value;
                      final isActive = _jf.activeAccount?.normalizedUrl == acc.normalizedUrl &&
                          _jf.activeAccount?.username == acc.username;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isActive ? _jfBlue.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: isActive ? Border.all(color: _jfBlue.withValues(alpha: 0.3), width: 1.5) : null,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: isActive ? _jfBlue : Colors.white.withValues(alpha: 0.08),
                            radius: 20,
                            child: Icon(Icons.person_rounded, color: isActive ? Colors.white : Colors.white38, size: 20),
                          ),
                          title: Text(acc.username,
                              style: TextStyle(color: Colors.white,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                          subtitle: Text(acc.normalizedUrl,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isActive)
                                IconButton(
                                  icon: const Icon(Icons.login_rounded, color: _jfBlue, size: 20),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    if (!mounted) return;
                                    setState(() => _isLoading = true);
                                    try {
                                      await _jf.login(acc.serverUrl, acc.username, acc.password);
                                      _isLoggedIn = true;
                                      await _loadHomeData();
                                    } catch (e) { _error = e.toString(); }
                                    if (mounted) setState(() => _isLoading = false);
                                  },
                                ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    color: Colors.redAccent.withValues(alpha: 0.6), size: 20),
                                onPressed: () async {
                                  await _jf.removeAccount(idx);
                                  final updated = await _jf.getSavedAccounts();
                                  setSheetState(() => accounts..clear()..addAll(updated));
                                  if (!_jf.isLoggedIn) setState(() => _isLoggedIn = false);
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
        child: const Center(child: CircularProgressIndicator(color: _jfBlue)),
      );
    }
    if (!_isLoggedIn) return _buildWelcome();
    if (_selectedLibraryId != null) return _buildLibraryView();
    return _buildHome();
  }

  // ─── Welcome ─────────────────────────────────────────────────────────────

  Widget _buildWelcome() {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Glow orb behind icon
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 160, height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [_jfBlue.withValues(alpha: 0.2), Colors.transparent],
                      ),
                    ),
                  ),
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_jfBlue, _jfBlueDark],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: _jfBlue.withValues(alpha: 0.3), blurRadius: 30, spreadRadius: 2),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 44, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text('Jellyfin',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -1.5)),
              const SizedBox(height: 8),
              Text('Stream your media, anywhere',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15)),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _showAddAccountDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _jfBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 22),
                      SizedBox(width: 10),
                      Text('Connect Server', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _showAccountManager,
                child: Text('Manage Accounts',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Home ────────────────────────────────────────────────────────────────

  Widget _buildHome() {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: RefreshIndicator(
        color: _jfBlue,
        backgroundColor: _jfSurface,
        onRefresh: () async {
          await _loadHomeData();
          if (mounted) setState(() {});
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // App bar
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 64,
              title: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_jfBlue, _jfBlueDark]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_jf.activeAccount?.username ?? 'Jellyfin',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                                color: Colors.white, letterSpacing: -0.3)),
                        Text(
                          _jf.activeAccount?.normalizedUrl.replaceAll(RegExp(r'https?://'), '') ?? '',
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.manage_accounts_rounded, color: Colors.white.withValues(alpha: 0.6)),
                  onPressed: _showAccountManager,
                  tooltip: 'Accounts',
                ),
                const SizedBox(width: 4),
              ],
            ),

            // Hero section
            if (_featuredItems.isNotEmpty)
              SliverToBoxAdapter(child: _buildHeroSection()),

            // Libraries
            if (_libraries.isNotEmpty)
              SliverToBoxAdapter(child: _buildLibraryRow()),

            // Continue Watching
            if (_resumeItems.isNotEmpty)
              SliverToBoxAdapter(child: _buildLandscapeSection(
                  'Continue Watching', _resumeItems, showProgress: true)),

            // Next Up
            if (_nextUpItems.isNotEmpty)
              SliverToBoxAdapter(child: _buildLandscapeSection(
                  'Next Up', _nextUpItems, showEpisodeInfo: true)),

            // Latest per library
            ..._latestByLibrary.entries.map((entry) =>
              SliverToBoxAdapter(child: _buildPosterSection('Latest in ${entry.key}', entry.value))),

            // Error
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ─── Hero Carousel ───────────────────────────────────────────────────────

  Widget _buildHeroSection() {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final heroHeight = isPhone ? 280.0 : 360.0;

    return Column(
      children: [
        SizedBox(
          height: heroHeight,
          child: PageView.builder(
            controller: _heroController,
            itemCount: _featuredItems.length,
            onPageChanged: (i) => setState(() => _heroPage = i),
            itemBuilder: (context, index) {
              final item = _featuredItems[index];
              final backdropUrl = item.backdropImageTags.isNotEmpty
                  ? _jf.getBackdropUrl(item.id, tag: item.backdropImageTags.first)
                  : (item.imageTags.containsKey('Primary')
                      ? _jf.getPosterUrl(item.id, tag: item.imageTags['Primary'], maxWidth: 1200)
                      : null);

              return _HoverCard(
                onTap: () => _openDetails(item),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: _jfSurface,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Backdrop
                      if (backdropUrl != null)
                        CachedNetworkImage(
                          imageUrl: backdropUrl,
                          fit: BoxFit.cover,
                          placeholder: (c, u) => Shimmer.fromColors(
                            baseColor: _jfSurface, highlightColor: _jfSurfaceLight,
                            child: Container(color: _jfSurface)),
                          errorWidget: (c, u, e) => Container(color: _jfSurface),
                        )
                      else
                        Container(color: _jfSurface),

                      // Cinematic gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.7),
                              Colors.black.withValues(alpha: 0.9),
                            ],
                            stops: const [0.0, 0.3, 0.65, 1.0],
                          ),
                        ),
                      ),

                      // Content at bottom
                      Positioned(
                        bottom: 20, left: 20, right: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Type badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _jfBlue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _jfBlue.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                item.type == 'Series' ? 'SERIES' : 'MOVIE',
                                style: const TextStyle(color: _jfBlue, fontSize: 10,
                                    fontWeight: FontWeight.w700, letterSpacing: 1),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Title
                            Text(item.name,
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                                    color: Colors.white, letterSpacing: -0.5, height: 1.15)),
                            const SizedBox(height: 8),
                            // Meta row
                            Row(
                              children: [
                                if (item.productionYear != null)
                                  _heroBadge('${item.productionYear}'),
                                if (item.communityRating != null) ...[
                                  const SizedBox(width: 8),
                                  _heroBadge('★ ${item.communityRating!.toStringAsFixed(1)}'),
                                ],
                                if (item.runtime.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _heroBadge(item.runtime),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Page dots
        if (_featuredItems.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_featuredItems.length, (i) =>
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _heroPage ? 24 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _heroPage ? _jfBlue : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _heroBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  // ─── Library Row ────────────────────────────────────────────────────────

  Widget _buildLibraryRow() {
    final videoLibs = _libraries.where((l) =>
        l.collectionType == 'movies' || l.collectionType == 'tvshows' || l.collectionType == null).toList();
    if (videoLibs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: videoLibs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final lib = videoLibs[i];
            final icon = lib.collectionType == 'movies'
                ? Icons.movie_rounded
                : lib.collectionType == 'tvshows'
                    ? Icons.live_tv_rounded
                    : Icons.video_library_rounded;
            return _HoverCard(
              onTap: () => _openLibrary(lib),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: _jfBlue),
                    const SizedBox(width: 10),
                    Text(lib.name, style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white.withValues(alpha: 0.3)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Section Header ────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
      child: Row(
        children: [
          Container(
            width: 4, height: 18,
            decoration: BoxDecoration(
              color: _jfBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: Colors.white, letterSpacing: -0.3)),
        ],
      ),
    );
  }

  // ─── Landscape Section (Continue Watching / Next Up) ───────────────────

  Widget _buildLandscapeSection(String title, List<JellyfinItem> items,
      {bool showProgress = false, bool showEpisodeInfo = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        SizedBox(
          height: showEpisodeInfo ? 180 : 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildLandscapeCard(items[i],
                  showProgress: showProgress, showEpisodeInfo: showEpisodeInfo),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeCard(JellyfinItem item,
      {bool showProgress = false, bool showEpisodeInfo = false}) {
    // Use backdrop or primary image
    final imageUrl = item.backdropImageTags.isNotEmpty
        ? _jf.getBackdropUrl(item.id, tag: item.backdropImageTags.first, maxWidth: 600)
        : (item.imageTags.containsKey('Primary')
            ? _jf.getPosterUrl(item.id, tag: item.imageTags['Primary'], maxWidth: 500)
            : (item.seriesId != null
                ? _jf.getPosterUrl(item.seriesId!, maxWidth: 500)
                : null));

    return _HoverCard(
      onTap: () {
        if (item.type == 'Episode' && item.seriesId != null) {
          _openDetails(JellyfinItem(id: item.seriesId!, name: item.seriesName ?? item.name, type: 'Series'));
        } else {
          _openDetails(item);
        }
      },
      child: SizedBox(
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (16:9)
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _jfSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (c, u) => Shimmer.fromColors(
                          baseColor: _jfSurface, highlightColor: _jfSurfaceLight,
                          child: Container(color: _jfSurface)),
                        errorWidget: (c, u, e) => _emptyThumb(item),
                      )
                    else
                      _emptyThumb(item),

                    // Bottom gradient
                    Positioned(
                      bottom: 0, left: 0, right: 0, height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                          ),
                        ),
                      ),
                    ),

                    // Play overlay
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                      ),
                    ),

                    // Played badge
                    if (item.isPlayed)
                      Positioned(
                        top: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _jfBlue,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: _jfBlue.withValues(alpha: 0.4), blurRadius: 8)],
                          ),
                          child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                        ),
                      ),

                    // Progress
                    if (showProgress && item.playbackProgress > 0)
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(14)),
                          child: LinearProgressIndicator(
                            value: item.playbackProgress,
                            minHeight: 3,
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation(_jfBlue),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              showEpisodeInfo && item.seriesName != null ? item.seriesName! : item.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (showEpisodeInfo && item.type == 'Episode')
              Text(
                'S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'} · ${item.name}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
              )
            else if (item.productionYear != null)
              Text('${item.productionYear}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _emptyThumb(JellyfinItem item) {
    return Center(
      child: Icon(
        item.type == 'Series' || item.type == 'Episode' ? Icons.live_tv_rounded : Icons.movie_rounded,
        size: 32, color: Colors.white.withValues(alpha: 0.15)),
    );
  }

  // ─── Poster Section (Latest in Library) ────────────────────────────────

  Widget _buildPosterSection(String title, List<JellyfinItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(width: 130, child: _buildPosterCard(items[i])),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Poster Card ─────────────────────────────────────────────────────────

  Widget _buildPosterCard(JellyfinItem item, {bool inGrid = false}) {
    final imageUrl = item.imageTags.containsKey('Primary')
        ? _jf.getPosterUrl(item.id, tag: item.imageTags['Primary'])
        : (item.seriesId != null ? _jf.getPosterUrl(item.seriesId!, maxWidth: 300) : null);

    return _HoverCard(
      onTap: () {
        if (item.type == 'Episode' && item.seriesId != null) {
          _openDetails(JellyfinItem(id: item.seriesId!, name: item.seriesName ?? item.name, type: 'Series'));
        } else {
          _openDetails(item);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _jfSurface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
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
                        baseColor: _jfSurface, highlightColor: _jfSurfaceLight,
                        child: Container(color: _jfSurface)),
                      errorWidget: (c, u, e) => _emptyThumb(item),
                    )
                  else
                    _emptyThumb(item),

                  // Subtle bottom gradient for text readability
                  Positioned(
                    bottom: 0, left: 0, right: 0, height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter
                          , end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                        ),
                      ),
                    ),
                  ),

                  // Rating badge
                  if (item.communityRating != null)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFD700)),
                            const SizedBox(width: 3),
                            Text(item.communityRating!.toStringAsFixed(1),
                                style: const TextStyle(color: Colors.white, fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),

                  // Played indicator
                  if (item.isPlayed)
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: _jfBlue,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: _jfBlue.withValues(alpha: 0.4), blurRadius: 6)],
                        ),
                        child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                      ),
                    ),

                  // Unplayed count badge
                  if (!item.isPlayed && item.unplayedCount > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _jfBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${item.unplayedCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          if (item.productionYear != null)
            Text('${item.productionYear}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
        ],
      ),
    );
  }

  // ─── Library View ────────────────────────────────────────────────────────

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_selectedLibraryName ?? 'Library',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                                color: Colors.white, letterSpacing: -0.3)),
                        if (_allLibraryItems.isNotEmpty)
                          Text(
                            _librarySearchTerm.isNotEmpty
                                ? '${_libraryItems.length} of ${_allLibraryItems.length} items'
                                : '${_allLibraryItems.length} items',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.sort_rounded, color: Colors.white.withValues(alpha: 0.6)),
                    color: _jfSurfaceLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    onSelected: (val) {
                      final parts = val.split('|');
                      _librarySortBy = parts[0];
                      _librarySortOrder = parts[1];
                      if (_selectedLibraryId != null) {
                        final lib = _libraries.firstWhere((l) => l.id == _selectedLibraryId);
                        final oldKeys = _libraryCache.keys.where((k) => k.startsWith('${lib.id}|')).toList();
                        for (final k in oldKeys) {
                          _libraryCache.remove(k);
                          _libraryCacheComplete.remove(k);
                        }
                        _openLibrary(lib);
                      }
                    },
                    itemBuilder: (_) => [
                      _sortItem('Name (A-Z)', 'SortName|Ascending'),
                      _sortItem('Name (Z-A)', 'SortName|Descending'),
                      _sortItem('Date Added ↓', 'DateCreated|Descending'),
                      _sortItem('Date Added ↑', 'DateCreated|Ascending'),
                      _sortItem('Release Date ↓', 'PremiereDate|Descending'),
                      _sortItem('Release Date ↑', 'PremiereDate|Ascending'),
                      _sortItem('Rating ↓', 'CommunityRating|Descending'),
                      _sortItem('Rating ↑', 'CommunityRating|Ascending'),
                      _sortItem('Runtime ↓', 'Runtime|Descending'),
                      _sortItem('Runtime ↑', 'Runtime|Ascending'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Loading bar
          if (_isBackgroundLoading)
            LinearProgressIndicator(minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(_jfBlue.withValues(alpha: 0.5))),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _librarySearchController,
              focusNode: _librarySearchFocus,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: (q) {
                setState(() {});
                _librarySearchDebounce?.cancel();
                _librarySearchDebounce = Timer(
                  const Duration(milliseconds: 400),
                  () => _searchLibrary(q),
                );
              },
              decoration: InputDecoration(
                hintText: _isBackgroundLoading
                    ? 'Loading items... (${_allLibraryItems.length} so far)'
                    : 'Search ${_selectedLibraryName ?? 'library'}...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                prefixIcon: const Icon(Icons.search_rounded, color: _jfBlue, size: 20),
                suffixIcon: _librarySearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                        onPressed: () {
                          _librarySearchController.clear();
                          _librarySearchFocus.unfocus();
                          _applyFilter('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Grid
          Expanded(
            child: _isLoadingLibrary
                ? const Center(child: CircularProgressIndicator(color: _jfBlue))
                : _libraryItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48,
                                color: Colors.white.withValues(alpha: 0.1)),
                            const SizedBox(height: 12),
                            Text(
                              _librarySearchTerm.isNotEmpty
                                  ? 'No results for "$_librarySearchTerm"'
                                  : 'No items found',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                            ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = constraints.maxWidth > 1200 ? 8
                              : constraints.maxWidth > 900 ? 6
                              : constraints.maxWidth > 600 ? 4 : 3;

                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              childAspectRatio: 0.55,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 12,
                            ),
                            itemCount: _libraryItems.length,
                            itemBuilder: (_, i) => _buildPosterCard(_libraryItems[i], inGrid: true),
                          );
                        },
                      ),
          ),

          // Pagination
          if (!_isLoadingLibrary && _librarySearchTerm.isEmpty && _allLibraryItems.length > _pageSize)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _jfSurface.withValues(alpha: 0.8),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _paginationButton(Icons.chevron_left_rounded,
                      enabled: _libraryPage > 0,
                      onTap: () => _loadLibraryPage(_libraryPage - 1)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _showPageJumpDialog(_totalPages),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$currentPage / $_totalPages',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _paginationButton(Icons.chevron_right_rounded,
                      enabled: currentPage < _totalPages,
                      onTap: () => _loadLibraryPage(_libraryPage + 1)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _paginationButton(IconData icon, {required bool enabled, required VoidCallback onTap}) {
    return _HoverCard(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled ? _jfBlue.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: enabled ? _jfBlue : Colors.white24, size: 22),
      ),
    );
  }

  Future<void> _showPageJumpDialog(int totalPages) async {
    final ctrl = TextEditingController(text: '${_libraryPage + 1}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _jfSurfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Go to page', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '1 – $totalPages',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5)))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Go', style: TextStyle(color: _jfBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result != null) {
      _loadLibraryPage((result - 1).clamp(0, totalPages - 1));
    }
  }

  PopupMenuItem<String> _sortItem(String label, String value) {
    final isActive = value == '$_librarySortBy|$_librarySortOrder';
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: TextStyle(
            color: isActive ? _jfBlue : Colors.white,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            fontSize: 13,
          )),
    );
  }
}
