import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/iptv_service.dart';
import '../models/iptv_category.dart';
import '../models/iptv_series.dart';
import 'series_detail_screen.dart';

class IptvShowsScreen extends StatefulWidget {
  const IptvShowsScreen({super.key});

  @override
  State<IptvShowsScreen> createState() => _IptvShowsScreenState();
}

class _IptvShowsScreenState extends State<IptvShowsScreen> {
  final _iptvService = IptvService();
  final _searchController = TextEditingController();
  final _categoryScrollController = ScrollController();

  List<IptvCategory> _categories = [];
  List<IptvSeries> _series = [];
  String? _selectedCategory;
  String _searchQuery = '';
  bool _loadingCategories = true;
  bool _loadingSeries = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() { _loadingCategories = true; _error = null; });
      _categories = await _iptvService.getSeriesCategories();
      setState(() => _loadingCategories = false);
      _loadSeries();
    } catch (e) {
      setState(() { _loadingCategories = false; _error = e.toString(); });
    }
  }

  Future<void> _loadSeries() async {
    try {
      setState(() { _loadingSeries = true; _error = null; });
      _series = await _iptvService.getSeries(categoryId: _selectedCategory);
      setState(() => _loadingSeries = false);
    } catch (e) {
      setState(() { _loadingSeries = false; _error = e.toString(); });
    }
  }

  List<IptvSeries> get _filteredSeries {
    if (_searchQuery.isEmpty) return _series;
    final q = _searchQuery.toLowerCase();
    return _series.where((s) => s.name.toLowerCase().contains(q)).toList();
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
            colors: [Color(0xFF1A0A1A), Color(0xFF0A0A0F)],
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
                    const Icon(Icons.tv, color: Color(0xFF880E4F), size: 24),
                    const SizedBox(width: 8),
                    Text('TV SHOWS', style: GoogleFonts.bebasNeue(fontSize: 26, color: Colors.white, letterSpacing: 3)),
                    const Spacer(),
                    if (!_loadingSeries)
                      Text('${_filteredSeries.length} series', style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
                    hintText: 'Search TV shows...',
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
                                  _loadSeries();
                                },
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                                selectedColor: const Color(0xFF4A148C),
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
    if (_loadingCategories || _loadingSeries) return _buildShimmerGrid();
    if (_error != null) return _buildError();
    final series = _filteredSeries;
    if (series.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_off, size: 64, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text('No TV shows found', style: TextStyle(color: Colors.white.withValues(alpha: 0.3))),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: series.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        childAspectRatio: 0.52,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) => _SeriesCard(
        series: series[index],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series[index])),
        ),
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
          Text('Failed to load TV shows', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadCategories(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A148C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  final IptvSeries series;
  final VoidCallback onTap;

  const _SeriesCard({required this.series, required this.onTap});

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
                  series.cover != null && series.cover!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: series.cover!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Center(child: Icon(Icons.tv, color: Colors.white12, size: 36)),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Center(child: Icon(Icons.tv, color: Colors.white12, size: 36)),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: const Center(child: Icon(Icons.tv, color: Colors.white12, size: 36)),
                        ),
                  if (series.rating != null && series.rating!.isNotEmpty && series.rating != '0')
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
                            Text(series.rating!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
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
            series.name,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (series.genre != null && series.genre!.isNotEmpty)
            Text(
              series.genre!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
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
