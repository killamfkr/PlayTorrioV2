// Asian Drama — Explore (browse the full kisskh.co/.ovh catalog).
// Mirrors https://kisskh.ovh/Explore: filter chips for type / subtitle /
// country / status / sort order, then a paginated grid of cards with
// Previous / Next page controls at the bottom.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/kisskh_service.dart';
import '../utils/app_theme.dart';
import '../widgets/hover_scale.dart';
import 'asian_drama_details_screen.dart';

class AsianDramaExploreScreen extends StatefulWidget {
  const AsianDramaExploreScreen({super.key});

  @override
  State<AsianDramaExploreScreen> createState() =>
      _AsianDramaExploreScreenState();
}

class _AsianDramaExploreScreenState extends State<AsianDramaExploreScreen> {
  final KissKhService _service = KissKhService();
  final ScrollController _scroll = ScrollController();

  int _type = 0;
  int _sub = 0;
  int _country = 0;
  int _status = 0;
  int _order = 1; // 1 = Popular

  final List<KdramaCard> _items = [];
  static const int _pageSize = 40;
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  String? _error;
  int _filterEpoch = 0;

  int get _totalPages =>
      _total == 0 ? 0 : ((_total + _pageSize - 1) ~/ _pageSize);

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() => _load(1);

  Future<void> _load(int page) async {
    final epoch = ++_filterEpoch;
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
    });
    try {
      final res = await _service.explore(
        page: page,
        type: _type,
        sub: _sub,
        country: _country,
        status: _status,
        order: _order,
        pageSize: _pageSize,
      );
      if (!mounted || epoch != _filterEpoch) return;
      setState(() {
        _items.addAll(res.items);
        _total = res.total;
        _page = res.page;
        _loading = false;
      });
      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    } catch (e) {
      if (!mounted || epoch != _filterEpoch) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _open(KdramaCard a) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AsianDramaDetailsScreen(drama: a),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return ValueListenableBuilder<AppThemePreset>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, _, _) {
        return Scaffold(
          backgroundColor: AppTheme.bgDark,
          appBar: AppBar(
            backgroundColor: AppTheme.bgDark,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Explore',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              if (_total > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      '$_total',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              _buildFilterStrip(),
              const Divider(height: 1, color: Color(0x14FFFFFF)),
              Expanded(child: _buildGrid(isLandscape)),
              if (!_loading && _error == null && _totalPages > 1)
                _buildPager(),
            ],
          ),
        );
      },
    );
  }

  // ─── Filter strip ────────────────────────────────────────────
  Widget _buildFilterStrip() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        physics: const BouncingScrollPhysics(),
        children: [
          _filterButton(
            icon: Icons.category_rounded,
            label: 'Type',
            value: KissKhExploreFilters.types[_type],
            onTap: () => _pickFilter(
              title: 'Type',
              options: KissKhExploreFilters.types,
              current: _type,
              onPick: (v) {
                _type = v;
                _reload();
              },
            ),
          ),
          _filterButton(
            icon: Icons.public_rounded,
            label: 'Region',
            value: KissKhExploreFilters.countries[_country],
            onTap: () => _pickFilter(
              title: 'Region',
              options: KissKhExploreFilters.countries,
              current: _country,
              onPick: (v) {
                _country = v;
                _reload();
              },
            ),
          ),
          _filterButton(
            icon: Icons.subtitles_rounded,
            label: 'Subtitle',
            value: KissKhExploreFilters.subtitles[_sub],
            onTap: () => _pickFilter(
              title: 'Subtitle',
              options: KissKhExploreFilters.subtitles,
              current: _sub,
              onPick: (v) {
                _sub = v;
                _reload();
              },
            ),
          ),
          _filterButton(
            icon: Icons.toggle_on_rounded,
            label: 'Status',
            value: KissKhExploreFilters.statuses[_status],
            onTap: () => _pickFilter(
              title: 'Status',
              options: KissKhExploreFilters.statuses,
              current: _status,
              onPick: (v) {
                _status = v;
                _reload();
              },
            ),
          ),
          _filterButton(
            icon: Icons.sort_rounded,
            label: 'Sort',
            value: KissKhExploreFilters.orders[_order],
            onTap: () => _pickFilter(
              title: 'Sort by',
              options: KissKhExploreFilters.orders.sublist(1),
              current: _order - 1,
              onPick: (v) {
                _order = v + 1;
                _reload();
              },
            ),
          ),
          if (_type != 0 ||
              _sub != 0 ||
              _country != 0 ||
              _status != 0 ||
              _order != 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _type = 0;
                    _sub = 0;
                    _country = 0;
                    _status = 0;
                    _order = 1;
                  });
                  _reload();
                },
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 16),
                label: const Text(
                  'Reset',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterButton({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final active = value != 'All';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: active
            ? AppTheme.primaryColor.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? AppTheme.primaryColor.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: active
                      ? AppTheme.primaryColor
                      : Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  active ? value : label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFilter({
    required String title,
    required List<String> options,
    required int current,
    required ValueChanged<int> onPick,
  }) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final isSel = i == current;
                    return ListTile(
                      title: Text(
                        options[i],
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              isSel ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                      trailing: isSel
                          ? Icon(Icons.check_rounded,
                              color: AppTheme.primaryColor)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(i),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != current) onPick(picked);
  }

  // ─── Grid ────────────────────────────────────────────────────
  Widget _buildGrid(bool isLandscape) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppTheme.primaryColor, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                color: Colors.white.withValues(alpha: 0.25), size: 56),
            const SizedBox(height: 10),
            Text(
              'No results match those filters',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    final cols = isLandscape ? 6 : 3;
    return RefreshIndicator(
      color: AppTheme.primaryColor,
      backgroundColor: AppTheme.bgCard,
      onRefresh: _reload,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.62,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => _card(_items[i]),
      ),
    );
  }

  // ─── Pager ───────────────────────────────────────────────────
  Widget _buildPager() {
    final canPrev = _page > 1;
    final canNext = _page < _totalPages;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0F14),
          border: Border(
            top: BorderSide(color: Color(0x14FFFFFF), width: 1),
          ),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _pagerButton(
              icon: Icons.chevron_left_rounded,
              label: 'Previous',
              enabled: canPrev,
              onTap: () => _load(_page - 1),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 1),
              ),
              child: Text(
                'Page $_page of $_totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const Spacer(),
            _pagerButton(
              icon: Icons.chevron_right_rounded,
              label: 'Next',
              enabled: canNext,
              trailing: true,
              onTap: () => _load(_page + 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pagerButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool trailing = false,
  }) {
    final color = enabled
        ? AppTheme.primaryColor
        : Colors.white.withValues(alpha: 0.18);
    final fg = enabled ? Colors.white : Colors.white.withValues(alpha: 0.35);
    return Material(
      color: enabled
          ? AppTheme.primaryColor.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? onTap : null,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: enabled ? 0.7 : 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: trailing
                ? [
                    Text(label,
                        style: TextStyle(
                            color: fg,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(icon, size: 18, color: fg),
                  ]
                : [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                            color: fg,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _card(KdramaCard a) {
    return HoverScale(
      onTap: () => _open(a),
      radius: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (a.cover.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: a.cover,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.bgCard),
                      errorWidget: (_, _, _) =>
                          Container(color: AppTheme.bgCard),
                    )
                  else
                    Container(color: AppTheme.bgCard),
                  if (a.label != null && a.label!.isNotEmpty)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          a.label!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (a.episodesCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'EP ${a.episodesCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
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
            a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
