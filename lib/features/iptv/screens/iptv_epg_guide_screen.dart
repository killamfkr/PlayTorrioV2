import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../api/settings_service.dart';
import '../../../screens/player_screen.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/iptv_epg_listing.dart';
import '../services/iptv_service.dart';

String _formatEpgClock(DateTime? t) {
  if (t == null) return '—';
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// TV guide using Xtream short EPG (M3U playlists have no server EPG here).
class IptvEpgGuideScreen extends StatefulWidget {
  final String? initialCategoryId;

  const IptvEpgGuideScreen({super.key, this.initialCategoryId});

  @override
  State<IptvEpgGuideScreen> createState() => _IptvEpgGuideScreenState();
}

class _IptvEpgGuideScreenState extends State<IptvEpgGuideScreen> {
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

  bool get _isXtream => _iptvService.isXtream;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategoryId;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loadingCategories = true;
        _error = null;
      });
      _categories = await _iptvService.getLiveCategories();
      setState(() => _loadingCategories = false);
      _loadChannels();
    } catch (e) {
      setState(() {
        _loadingCategories = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadChannels() async {
    try {
      setState(() {
        _loadingChannels = true;
        _error = null;
      });
      _channels = await _iptvService.getLiveStreams(categoryId: _selectedCategory);
      setState(() => _loadingChannels = false);
    } catch (e) {
      setState(() {
        _loadingChannels = false;
        _error = e.toString();
      });
    }
  }

  List<IptvChannel> get _filteredChannels {
    if (_searchQuery.isEmpty) return _channels;
    final q = _searchQuery.toLowerCase();
    return _channels.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _playChannel(IptvChannel channel) async {
    final url = _iptvService.getLiveStreamUrl(channel);
    final caps = await SettingsService().getIptvCaptionsEnabled();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: channel.name,
          captionsEnabled: caps,
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1B2A), Color(0xFF0A0A0F), Color(0xFF1A0A2E)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TV GUIDE',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 26,
                            color: Colors.white,
                            letterSpacing: 3,
                          ),
                        ),
                        Text(
                          _isXtream ? 'Upcoming programmes from your provider' : 'Xtream Codes only — M3U has no server EPG',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: _isXtream ? 0.45 : 0.65),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search channels…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_categories.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      _GuideArrow(
                        icon: Icons.chevron_left,
                        onTap: () {
                          if (!_categoryScrollController.hasClients) return;
                          _categoryScrollController.animateTo(
                            (_categoryScrollController.offset - 200).clamp(
                              0.0,
                              _categoryScrollController.position.maxScrollExtent,
                            ),
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOut,
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
                            final isSelected =
                                isAll ? _selectedCategory == null : _selectedCategory == cat!.categoryId;
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
                                selectedColor: const Color(0xFF7C3AED),
                                checkmarkColor: Colors.white,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            );
                          },
                        ),
                      ),
                      _GuideArrow(
                        icon: Icons.chevron_right,
                        onTap: () {
                          if (!_categoryScrollController.hasClients) return;
                          _categoryScrollController.animateTo(
                            (_categoryScrollController.offset + 200).clamp(
                              0.0,
                              _categoryScrollController.position.maxScrollExtent,
                            ),
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingCategories || _loadingChannels) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadCategories,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              ),
            ],
          ),
        ),
      );
    }
    final list = _filteredChannels;
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No channels',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: list.length,
      itemBuilder: (context, index) {
        return _EpgChannelCard(
          key: ValueKey(list[index].streamId),
          channel: list[index],
          iptvService: _iptvService,
          isXtream: _isXtream,
          onPlay: () => _playChannel(list[index]),
        );
      },
    );
  }
}

class _EpgChannelCard extends StatefulWidget {
  final IptvChannel channel;
  final IptvService iptvService;
  final bool isXtream;
  final VoidCallback onPlay;

  const _EpgChannelCard({
    super.key,
    required this.channel,
    required this.iptvService,
    required this.isXtream,
    required this.onPlay,
  });

  @override
  State<_EpgChannelCard> createState() => _EpgChannelCardState();
}

class _EpgChannelCardState extends State<_EpgChannelCard> {
  late Future<List<IptvEpgListing>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.isXtream
        ? widget.iptvService.getShortEpgListings(widget.channel, limit: 10)
        : Future.value(const []);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: widget.channel.streamIcon != null &&
                                widget.channel.streamIcon!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.channel.streamIcon!,
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.channel.name,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.channel.categoryName != null)
                            Text(
                              widget.channel.categoryName!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: widget.onPlay,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<IptvEpgListing>>(
                  future: _future,
                  builder: (context, snap) {
                    if (!widget.isXtream) {
                      return Text(
                        'No EPG for M3U in this app — use an Xtream playlist for the guide.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                      );
                    }
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading schedule…',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }
                    final items = snap.data ?? [];
                    if (items.isEmpty) {
                      return Text(
                        'No programme data for this channel.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                      );
                    }
                    return SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final e = items[i];
                          return _ProgramPill(listing: e);
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgramPill extends StatelessWidget {
  final IptvEpgListing listing;

  const _ProgramPill({required this.listing});

  @override
  Widget build(BuildContext context) {
    final start = _formatEpgClock(listing.start);
    final end = _formatEpgClock(listing.end);
    final time = listing.end != null ? '$start – $end' : start;
    final title = listing.title.isNotEmpty ? listing.title : 'Programme';

    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0D1520),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: TextStyle(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GuideArrow({required this.icon, required this.onTap});

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
