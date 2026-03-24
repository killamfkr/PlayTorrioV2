import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/iptv_service.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../../../api/settings_service.dart';
import '../../../screens/player_screen.dart';
import 'iptv_epg_guide_screen.dart';

class IptvLiveScreen extends StatefulWidget {
  const IptvLiveScreen({super.key});

  @override
  State<IptvLiveScreen> createState() => _IptvLiveScreenState();
}

class _IptvLiveScreenState extends State<IptvLiveScreen> {
  final _iptvService = IptvService();
  final _searchController = TextEditingController();
  final _categoryScrollController = ScrollController();

  List<IptvCategory> _categories = [];
  List<IptvChannel> _channels = [];
  String? _selectedCategory;
  String _searchQuery = '';
  bool _loadingCategories = true;
  bool _loadingChannels = false;
  String? _error;
  bool _playlistCompact = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadPlaylistLayoutPref();
  }

  Future<void> _loadPlaylistLayoutPref() async {
    final compact = await SettingsService().getIptvLivePlaylistCompact();
    if (mounted) setState(() => _playlistCompact = compact);
  }

  Future<void> _togglePlaylistCompact() async {
    final next = !_playlistCompact;
    await SettingsService().setIptvLivePlaylistCompact(next);
    if (mounted) setState(() => _playlistCompact = next);
  }

  void _openTvGuide() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IptvEpgGuideScreen(initialCategoryId: _selectedCategory),
      ),
    );
  }

  Future<void> _loadCategories() async {
    try {
      setState(() { _loadingCategories = true; _error = null; });
      _categories = await _iptvService.getLiveCategories();
      setState(() => _loadingCategories = false);
      // Load first category or all
      _loadChannels();
    } catch (e) {
      setState(() { _loadingCategories = false; _error = e.toString(); });
    }
  }

  Future<void> _loadChannels() async {
    try {
      setState(() { _loadingChannels = true; _error = null; });
      _channels = await _iptvService.getLiveStreams(categoryId: _selectedCategory);
      setState(() => _loadingChannels = false);
    } catch (e) {
      setState(() { _loadingChannels = false; _error = e.toString(); });
    }
  }

  List<IptvChannel> get _filteredChannels {
    if (_searchQuery.isEmpty) return _channels;
    final q = _searchQuery.toLowerCase();
    return _channels.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _playChannel(IptvChannel channel) async {
    final url = _iptvService.getLiveStreamUrl(channel);
    final captionsOn = await SettingsService().getIptvCaptionsEnabled();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: channel.name,
          captionsEnabled: captionsOn,
        ),
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
            colors: [Color(0xFF0D1B2A), Color(0xFF0A0A0F)],
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
                    Icon(Icons.live_tv, color: const Color(0xFF1565C0), size: 24),
                    const SizedBox(width: 8),
                    Text('LIVE TV', style: GoogleFonts.bebasNeue(fontSize: 26, color: Colors.white, letterSpacing: 3)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'TV guide',
                      icon: const Icon(Icons.view_timeline_rounded, color: Color(0xFF7C3AED), size: 26),
                      onPressed: _openTvGuide,
                    ),
                    IconButton(
                      tooltip: _playlistCompact ? 'Expand playlist' : 'Shrink playlist',
                      icon: Icon(
                        _playlistCompact ? Icons.unfold_more_rounded : Icons.view_sidebar_rounded,
                        color: Colors.white54,
                        size: 24,
                      ),
                      onPressed: _togglePlaylistCompact,
                    ),
                    if (!_loadingChannels)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '${_filteredChannels.length}',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search channels...',
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
                        onTap: () {
                          if (!_categoryScrollController.hasClients) return;
                          _categoryScrollController.animateTo(
                            (_categoryScrollController.offset - 200).clamp(0.0, _categoryScrollController.position.maxScrollExtent),
                            duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
                          );
                        },
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
                                  _loadChannels();
                                },
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                                selectedColor: const Color(0xFF1565C0),
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
                        onTap: () {
                          if (!_categoryScrollController.hasClients) return;
                          _categoryScrollController.animateTo(
                            (_categoryScrollController.offset + 200).clamp(0.0, _categoryScrollController.position.maxScrollExtent),
                            duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
                          );
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // Content
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loadingCategories || _loadingChannels) {
      return _buildShimmer();
    }
    if (_error != null) {
      return _buildError();
    }
    final channels = _filteredChannels;
    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_outlined, size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text('No channels found', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))),
          ],
        ),
      );
    }
    if (_playlistCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 118,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              itemCount: channels.length,
              itemBuilder: (context, index) => _CompactChannelStripTile(
                channel: channels[index],
                onTap: () => _playChannel(channels[index]),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swipe_rounded, size: 44, color: Colors.white.withValues(alpha: 0.2)),
                    const SizedBox(height: 14),
                    Text(
                      'Compact playlist',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scroll the channel strip above to pick a channel, open the TV guide for schedules, or tap the sidebar icon to show the full list again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: channels.length,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemBuilder: (context, index) => _ChannelTile(
        channel: channels[index],
        onTap: () => _playChannel(channels[index]),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: ListView.builder(
        itemCount: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemBuilder: (_, _) => Container(
          height: 72,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
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
          Text('Failed to load channels', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadCategories,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final IptvChannel channel;
  final VoidCallback onTap;

  const _ChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: channel.streamIcon != null && channel.streamIcon!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.streamIcon!,
                            fit: BoxFit.contain,
                            placeholder: (_, _) => Container(
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.live_tv, color: Colors.white24, size: 24),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.live_tv, color: Colors.white24, size: 24),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(Icons.live_tv, color: Colors.white24, size: 24),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (channel.categoryName != null)
                        Text(
                          channel.categoryName!,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                        ),
                    ],
                  ),
                ),
                // Live badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                      ),
                      const SizedBox(width: 4),
                      const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_circle_filled, color: Color(0xFF1565C0), size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactChannelStripTile extends StatelessWidget {
  final IptvChannel channel;
  final VoidCallback onTap;

  const _CompactChannelStripTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 86,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: channel.streamIcon != null && channel.streamIcon!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.streamIcon!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.live_tv, color: Colors.white24, size: 22),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.live_tv, color: Colors.white24, size: 22),
                            ),
                          )
                        : Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(Icons.live_tv, color: Colors.white24, size: 22),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  channel.name,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
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
