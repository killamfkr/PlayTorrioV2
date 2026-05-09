// Asian Drama search — kisskh.co
// Debounced TextField in the AppBar feeds `KissKhService.search()`.
// Results displayed as a responsive grid of landscape thumbnail cards.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/kisskh_service.dart';
import '../utils/app_theme.dart';
import '../widgets/hover_scale.dart';
import 'asian_drama_details_screen.dart';

class AsianDramaSearchScreen extends StatefulWidget {
  const AsianDramaSearchScreen({super.key});

  @override
  State<AsianDramaSearchScreen> createState() =>
      _AsianDramaSearchScreenState();
}

class _AsianDramaSearchScreenState extends State<AsianDramaSearchScreen> {
  final KissKhService _service = KissKhService();
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<KdramaCard> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      _runSearch(v.trim());
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.search(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _query != q) return;
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
            titleSpacing: 0,
            title: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (v) => _runSearch(v.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: AppTheme.primaryColor,
              decoration: InputDecoration(
                hintText: 'Search dramas, movies…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 15,
                ),
                border: InputBorder.none,
              ),
            ),
            actions: [
              if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () {
                    _ctrl.clear();
                    _onChanged('');
                  },
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: _buildBody(isLandscape),
        );
      },
    );
  }

  Widget _buildBody(bool isLandscape) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppTheme.primaryColor,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
                onPressed: () => _runSearch(_query),
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
    if (_query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 60, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text(
              'Start typing to search',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.theater_comedy_outlined,
                size: 60, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text(
              'No results for "$_query"',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    final cols = isLandscape ? 4 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) => _resultCard(_results[i]),
    );
  }

  Widget _resultCard(KdramaCard a) {
    return HoverScale(
      onTap: () => _open(a),
      radius: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (a.cover.isNotEmpty)
              CachedNetworkImage(
                imageUrl: a.cover,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.bgCard),
                errorWidget: (_, _, _) => Container(color: AppTheme.bgCard),
              )
            else
              Container(color: AppTheme.bgCard),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
            if (a.episodesCount > 0)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'EP ${a.episodesCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (a.label != null && a.label!.isNotEmpty)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    a.label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                a.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
