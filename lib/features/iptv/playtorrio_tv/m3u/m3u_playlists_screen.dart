// Screen for managing M3U / M3U8 IPTV playlists.
// Lets the user add a playlist by URL or upload a local file, browse the
// channels inside, and delete playlists. Tapping a channel hands off to the
// existing IptvPtPlayerScreen — same player, watchdog, recovery, etc.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/iptv_pt_player_screen.dart';
import 'm3u_models.dart';
import 'm3u_parser.dart';
import 'm3u_store.dart';

class M3uPlaylistsScreen extends StatefulWidget {
  const M3uPlaylistsScreen({super.key});

  @override
  State<M3uPlaylistsScreen> createState() => _M3uPlaylistsScreenState();
}

class _M3uPlaylistsScreenState extends State<M3uPlaylistsScreen> {
  List<M3uPlaylist> _playlists = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await M3uStore.loadAll();
    if (!mounted) return;
    setState(() {
      _playlists = list;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await M3uStore.saveAll(_playlists);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Add by URL
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _showAddUrlDialog() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String? localError;
    bool busy = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: Text('Add M3U Playlist',
              style: GoogleFonts.bebasNeue(
                  color: Colors.white, fontSize: 26, letterSpacing: 1.4)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input(nameCtrl, 'My Playlist (optional)', 'Display name'),
                const SizedBox(height: 8),
                _input(urlCtrl, 'https://example.com/playlist.m3u', 'URL'),
                if (localError != null) ...[
                  const SizedBox(height: 10),
                  Text(localError!,
                      style: GoogleFonts.poppins(
                          color: const Color(0xFFEF4444), fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white70)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0)),
              onPressed: busy
                  ? null
                  : () async {
                      final url = urlCtrl.text.trim();
                      if (url.isEmpty) {
                        setLocal(() => localError = 'URL is required');
                        return;
                      }
                      final parsed = Uri.tryParse(url);
                      if (parsed == null ||
                          (parsed.scheme != 'http' &&
                              parsed.scheme != 'https')) {
                        setLocal(() =>
                            localError = 'URL must start with http:// or https://');
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        localError = null;
                      });
                      try {
                        final channels = await M3uFetcher.fetchAndParse(url);
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final playlist = M3uPlaylist(
                          id: M3uStore.newId(),
                          name: nameCtrl.text.trim().isNotEmpty
                              ? nameCtrl.text.trim()
                              : _deriveNameFromUrl(url),
                          sourceUrl: url,
                          addedAt: now,
                          updatedAt: now,
                          channels: channels,
                        );
                        if (!mounted) return;
                        setState(() {
                          _playlists = [playlist, ..._playlists];
                        });
                        await _persist();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          localError = _friendlyError(e);
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Add',
                      style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Upload from file
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _pickAndImportFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      final f = result.files.single;
      String content;
      if (f.bytes != null) {
        content = String.fromCharCodes(f.bytes!);
      } else if (f.path != null) {
        content = await File(f.path!).readAsString();
      } else {
        throw const FormatException('Could not read file contents');
      }
      final channels = M3uParser.parse(content);
      final now = DateTime.now().millisecondsSinceEpoch;
      final baseName = f.name.replaceAll(
          RegExp(r'\.(m3u8?|txt)$', caseSensitive: false), '');
      final playlist = M3uPlaylist(
        id: M3uStore.newId(),
        name: baseName.isEmpty ? 'Uploaded Playlist' : baseName,
        sourceUrl: null,
        addedAt: now,
        updatedAt: now,
        channels: channels,
      );
      if (!mounted) return;
      setState(() {
        _playlists = [playlist, ..._playlists];
        _error = null;
      });
      await _persist();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Refresh / delete
  // ──────────────────────────────────────────────────────────────────────
  Future<void> _refresh(M3uPlaylist p) async {
    final url = p.sourceUrl;
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final channels = await M3uFetcher.fetchAndParse(url);
      final updated = p.copyWith(
        channels: channels,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _playlists = [
          for (final x in _playlists) x.id == p.id ? updated : x,
        ];
        _error = null;
      });
      await _persist();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refreshed "${p.name}" — ${channels.length} channels')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(M3uPlaylist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: Text('Delete playlist?',
            style: GoogleFonts.bebasNeue(
                color: Colors.white, fontSize: 24, letterSpacing: 1.2)),
        content: Text(
          '"${p.name}" will be removed. ${p.sourceUrl == null ? "You'll need to re-upload the file to add it again." : "You can re-add it from the URL anytime."}',
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _playlists = _playlists.where((x) => x.id != p.id).toList();
    });
    await _persist();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────
  static String _deriveNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        final last = segs.last
            .replaceAll(RegExp(r'\.(m3u8?|txt)$', caseSensitive: false), '');
        if (last.isNotEmpty) return last;
      }
      return uri.host.isNotEmpty ? uri.host : 'Playlist';
    } catch (_) {
      return 'Playlist';
    }
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.length > 200) return s.substring(0, 200);
    return s;
  }

  // ──────────────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0F), Color(0xFF0E1428), Color(0xFF06070C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              if (_error != null) _buildErrorBanner(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00E5FF)))
                    : _playlists.isEmpty
                        ? _buildEmpty()
                        : _buildList(),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'M3U Playlists',
                  style: GoogleFonts.bebasNeue(
                    color: Colors.white,
                    fontSize: 28,
                    letterSpacing: 1.6,
                  ),
                ),
                Text(
                  _playlists.isEmpty
                      ? 'No playlists yet'
                      : '${_playlists.length} playlist${_playlists.length == 1 ? "" : "s"}',
                  style: GoogleFonts.poppins(
                      color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF00E5FF)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.poppins(
                  color: const Color(0xFFEF4444), fontSize: 12),
            ),
          ),
          IconButton(
            iconSize: 18,
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close, color: Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_play_rounded,
                size: 80, color: Color(0xFF00E5FF)),
            const SizedBox(height: 24),
            Text('No playlists yet',
                style: GoogleFonts.bebasNeue(
                    color: Colors.white,
                    fontSize: 36,
                    letterSpacing: 1.6)),
            const SizedBox(height: 8),
            Text(
              'Add an M3U / M3U8 playlist by URL,\nor upload one from your device.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _playlists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = _playlists[i];
        return _PlaylistCard(
          playlist: p,
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => M3uChannelsScreen(playlist: p),
            ));
          },
          onRefresh: p.sourceUrl == null ? null : () => _refresh(p),
          onDelete: () => _delete(p),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PrimaryBtn(
              icon: Icons.link_rounded,
              label: 'Add from URL',
              onPressed: _busy ? null : _showAddUrlDialog,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PrimaryBtn(
              icon: Icons.upload_file_rounded,
              label: 'Upload File',
              subtle: true,
              onPressed: _busy ? null : _pickAndImportFile,
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, String hint, String label) {
    return TextField(
      controller: c,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final M3uPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback? onRefresh;
  final VoidCallback onDelete;
  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14213A), Color(0xFF0E1428)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    p.sourceUrl == null
                        ? Icons.insert_drive_file_rounded
                        : Icons.cloud_rounded,
                    color: const Color(0xFF00E5FF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.sourceUrl ?? 'Uploaded file',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            color: Colors.white54, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p.channels.length} channels',
                        style: GoogleFonts.poppins(
                            color: const Color(0xFF00E5FF), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh from URL',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70),
                  ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool subtle;
  final VoidCallback? onPressed;
  const _PrimaryBtn({
    required this.icon,
    required this.label,
    this.subtle = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: subtle
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CHANNELS SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class M3uChannelsScreen extends StatefulWidget {
  final M3uPlaylist playlist;
  const M3uChannelsScreen({super.key, required this.playlist});

  @override
  State<M3uChannelsScreen> createState() => _M3uChannelsScreenState();
}

class _M3uChannelsScreenState extends State<M3uChannelsScreen> {
  String _query = '';
  String? _group; // null = "All"
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _groupScrollCtrl = ScrollController();

  /// Whether the group strip currently has room to scroll left / right.
  /// Used to show/hide the arrow buttons.
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  late final List<String> _groups;

  @override
  void initState() {
    super.initState();
    final groupSet = <String>{};
    for (final c in widget.playlist.channels) {
      if (c.group.isNotEmpty) groupSet.add(c.group);
    }
    final sorted = groupSet.toList()..sort();
    _groups = sorted;
    _groupScrollCtrl.addListener(_updateScrollArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollArrows());
  }

  void _updateScrollArrows() {
    if (!_groupScrollCtrl.hasClients) return;
    final pos = _groupScrollCtrl.position;
    final left = pos.pixels > 1.0;
    final right = pos.pixels < pos.maxScrollExtent - 1.0;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollGroups({required bool forward}) {
    if (!_groupScrollCtrl.hasClients) return;
    const step = 220.0;
    final pos = _groupScrollCtrl.position;
    final target = (_groupScrollCtrl.offset + (forward ? step : -step))
        .clamp(0.0, pos.maxScrollExtent);
    _groupScrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _groupScrollCtrl.removeListener(_updateScrollArrows);
    _groupScrollCtrl.dispose();
    super.dispose();
  }

  List<M3uChannel> get _filtered {
    final q = _query.trim().toLowerCase();
    return widget.playlist.channels.where((c) {
      if (_group != null && c.group != _group) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.tvgName.toLowerCase().contains(q) ||
          c.group.toLowerCase().contains(q);
    }).toList();
  }

  void _play(M3uChannel ch) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => IptvPtPlayerScreen(
        sources: [
          IptvPlaySource(url: ch.url, label: widget.playlist.name),
        ],
        title: ch.name,
        subtitle: ch.group.isNotEmpty ? ch.group : widget.playlist.name,
        logoUrl: ch.logo.isEmpty ? null : ch.logo,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0F), Color(0xFF0E1428), Color(0xFF06070C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              _buildSearchAndGroup(),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          'No channels match your filter',
                          style: GoogleFonts.poppins(color: Colors.white60),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) =>
                            _ChannelTile(channel: list[i], onTap: () => _play(list[i])),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bebasNeue(
                      color: Colors.white,
                      fontSize: 26,
                      letterSpacing: 1.4),
                ),
                Text(
                  '${widget.playlist.channels.length} channels',
                  style: GoogleFonts.poppins(
                      color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndGroup() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white54, size: 20),
              hintText: 'Search channels...',
              hintStyle:
                  GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          if (_groups.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  _updateScrollArrows();
                  return false;
                },
                child: Stack(
                  children: [
                    ListView.separated(
                      controller: _groupScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      itemCount: _groups.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _GroupChip(
                            label: 'All',
                            selected: _group == null,
                            onTap: () => setState(() => _group = null),
                          );
                        }
                        final g = _groups[i - 1];
                        return _GroupChip(
                          label: g,
                          selected: _group == g,
                          onTap: () => setState(() => _group = g),
                        );
                      },
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: _ScrollArrow(
                        icon: Icons.chevron_left_rounded,
                        visible: _canScrollLeft,
                        onTap: () => _scrollGroups(forward: false),
                        alignLeft: true,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: _ScrollArrow(
                        icon: Icons.chevron_right_rounded,
                        visible: _canScrollRight,
                        onTap: () => _scrollGroups(forward: true),
                        alignLeft: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GroupChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF00E5FF)])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;
  final bool alignLeft;
  const _ScrollArrow({
    required this.icon,
    required this.visible,
    required this.onTap,
    required this.alignLeft,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin:
                  alignLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: alignLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                const Color(0xFF06070C),
                const Color(0xFF06070C).withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final M3uChannel channel;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                _ChannelLogo(url: channel.logo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      if (channel.group.isNotEmpty)
                        Text(
                          channel.group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.play_arrow_rounded,
                    color: Color(0xFF00E5FF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  final String url;
  const _ChannelLogo({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (ctx, child, prog) {
          if (prog == null) return child;
          return _placeholder();
        },
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.live_tv_rounded,
          color: Colors.white38, size: 20),
    );
  }
}
