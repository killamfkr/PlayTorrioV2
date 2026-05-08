import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../api/comics_service.dart';
import '../api/comic_page_extractor.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';

class ComicReaderScreen extends StatefulWidget {
  final String chapterTitle;
  final String chapterUrl;
  final List<ComicChapter> chapters;
  final int currentChapterIndex;
  final int? resumePageIndex;
  final Comic? comic;

  const ComicReaderScreen({
    super.key,
    required this.chapterTitle,
    required this.chapterUrl,
    required this.chapters,
    required this.currentChapterIndex,
    this.resumePageIndex,
    this.comic,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  final ComicsService _comicsService = ComicsService();
  final ComicPageExtractor _pageExtractor = ComicPageExtractor();
  final TransformationController _transformationController = TransformationController();
  List<String> _pageUrls = [];
  int _currentPageIndex = 0;
  bool _isLoading = true;
  bool _isLoadingPage = false;
  String? _currentImageUrl;
  String? _nextImageUrl; // Cache for next page
  late int _currentChapterIdx;
  double _currentScale = 1.0;
  bool _showZoomControls = true;
  String? _errorMessage;

  static const String _historyKey = 'comic_reading_history';

  @override
  void initState() {
    super.initState();
    _currentChapterIdx = widget.currentChapterIndex;
    _loadPages(widget.chapterUrl);
  }

  @override
  void dispose() {
    _pageExtractor.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _setZoom(double scale) {
    final viewportSize = MediaQuery.of(context).size;
    final centerX = viewportSize.width / 2;
    final centerY = viewportSize.height / 2;
    
    // Calculate the focal point (center of viewport)
    final focalPointX = centerX - (centerX * scale);
    final focalPointY = centerY - (centerY * scale);
    
    // Create transformation matrix without deprecated methods
    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, scale);  // Scale X
    matrix.setEntry(1, 1, scale);  // Scale Y
    matrix.setEntry(0, 3, focalPointX);  // Translate X
    matrix.setEntry(1, 3, focalPointY);  // Translate Y
    
    _transformationController.value = matrix;
    
    setState(() => _currentScale = scale);
  }

  void _zoomIn() {
    final newScale = (_currentScale * 1.5).clamp(1.0, 4.0);
    _setZoom(newScale);
  }

  void _zoomOut() {
    final newScale = (_currentScale / 1.5).clamp(1.0, 4.0);
    _setZoom(newScale);
  }

  void _resetZoom() {
    _setZoom(1.0);
  }

  Future<void> _loadPages(String url) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    // Ensure s2 server is used
    var chapterUrl = url;
    if (!chapterUrl.contains('s=s2')) {
      chapterUrl += chapterUrl.contains('?') ? '&s=s2' : '?s=s2';
    }
    
    try {
      final pages = await _comicsService.getChapterPages(chapterUrl, _pageExtractor);
      if (mounted) {
        setState(() {
          _pageUrls = pages;
          _currentPageIndex = 0;
          _isLoading = false;
          if (pages.isEmpty) {
            _errorMessage = 'No pages found for this chapter. The page extractor returned 0 pages — the site may be blocking requests or the chapter layout changed.';
          }
        });
        
        // Resume to saved page if provided
        if (widget.resumePageIndex != null && widget.resumePageIndex! < _pageUrls.length) {
          setState(() => _currentPageIndex = widget.resumePageIndex!);
        }
        
        // Load the current page image
        if (_pageUrls.isNotEmpty) {
          _loadPageImage(_currentPageIndex);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadPageImage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageUrls.length) return;
    
    setState(() => _isLoadingPage = true);
    
    // Check if we already have this page cached as the next page
    String? imageUrl;
    if (_nextImageUrl != null && pageIndex == _currentPageIndex) {
      imageUrl = _nextImageUrl;
      _nextImageUrl = null; // Clear the cache since we're using it
    } else {
      imageUrl = await _comicsService.getPageImage(_pageUrls[pageIndex], _pageExtractor);
    }
    
    if (mounted) {
      setState(() {
        _currentImageUrl = imageUrl;
        _isLoadingPage = false;
      });
      
      // Prefetch the next page in the background
      _prefetchNextPage(pageIndex);
      
      // Save progress after loading page
      _saveProgress();
    }
  }

  Future<void> _prefetchNextPage(int currentPageIndex) async {
    final nextPageIndex = currentPageIndex + 1;
    
    // Only prefetch if there's a next page
    if (nextPageIndex < _pageUrls.length) {
      // Prefetch in the background without blocking UI
      _comicsService.getPageImage(_pageUrls[nextPageIndex], _pageExtractor).then((url) {
        if (mounted && url != null) {
          _nextImageUrl = url;
          // Also trigger image caching
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      }).catchError((error) {
        // Silently fail prefetch - user can still load it manually
        debugPrint('Failed to prefetch next page: $error');
      });
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Use provided comic or extract from URL
    String comicTitle;
    String comicUrl;
    String comicPoster;
    
    if (widget.comic != null) {
      comicTitle = widget.comic!.title;
      comicUrl = widget.comic!.url;
      comicPoster = widget.comic!.poster;
    } else {
      // Extract comic info from chapter URL
      final chapterUrl = widget.chapters[_currentChapterIdx].url;
      comicUrl = chapterUrl.split('/Issue-')[0].split('/Full')[0];
      comicTitle = comicUrl.split('/').last.replaceAll('-', ' ');
      comicPoster = '';
    }
    
    final progress = {
      'comic': {
        'title': comicTitle,
        'url': comicUrl,
        'poster': comicPoster,
        'status': widget.comic?.status ?? '',
        'publication': widget.comic?.publication ?? '',
        'summary': widget.comic?.summary ?? '',
      },
      'chapterIndex': _currentChapterIdx,
      'pageIndex': _currentPageIndex,
      'chapters': widget.chapters.map((c) => {
        'title': c.title,
        'url': c.url,
        'dateAdded': c.dateAdded,
      }).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    final historyJson = prefs.getStringList(_historyKey) ?? [];
    final history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    
    // Remove existing entry for this comic
    history.removeWhere((h) => h['comic']['url'] == comicUrl);
    
    // Add new entry at the beginning
    history.insert(0, progress);
    
    // Keep only last 10 items
    if (history.length > 10) {
      history.removeRange(10, history.length);
    }
    
    await prefs.setStringList(_historyKey, history.map((e) => jsonEncode(e)).toList());
  }

  void _nextPage() {
    if (_currentPageIndex < _pageUrls.length - 1) {
      setState(() => _currentPageIndex++);
      _loadPageImage(_currentPageIndex);
    } else {
      _nextChapter();
    }
  }

  void _prevPage() {
    if (_currentPageIndex > 0) {
      setState(() {
        _currentPageIndex--;
        _nextImageUrl = null; // Clear next page cache when going backwards
      });
      _loadPageImage(_currentPageIndex);
    } else {
      _prevChapter();
    }
  }

  void _nextChapter() {
    if (_currentChapterIdx > 0) { // Chapters are usually listed newest to oldest
      _currentChapterIdx--;
      _nextImageUrl = null; // Clear cache when changing chapters
      _loadPages(widget.chapters[_currentChapterIdx].url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have reached the last chapter')),
      );
    }
  }

  void _prevChapter() {
    if (_currentChapterIdx < widget.chapters.length - 1) {
      _currentChapterIdx++;
      _nextImageUrl = null; // Clear cache when changing chapters
      _loadPages(widget.chapters[_currentChapterIdx].url);
    }
  }

  Widget _buildErrorWidget() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth <= 400;
    final horizontalPadding = screenWidth <= 600 ? 24.0 : 48.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.redAccent,
            size: isCompact ? 40 : 56,
          ),
          SizedBox(height: isCompact ? 12 : 16),
          Text(
            'Failed to load chapter pages',
            style: TextStyle(
              color: Colors.white,
              fontSize: isCompact ? 15 : 18,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
            child: SingleChildScrollView(
              child: Text(
                _errorMessage ?? 'Unknown error',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: isCompact ? 12 : 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(height: isCompact ? 16 : 24),
          ElevatedButton.icon(
            onPressed: () => _loadPages(widget.chapters[_currentChapterIdx].url),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 20 : 28,
                vertical: isCompact ? 10 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isLoading ? 'Loading...' : widget.chapters[_currentChapterIdx].title,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (!_isLoading && _pageUrls.isNotEmpty)
              Text(
                'Page ${_currentPageIndex + 1} / ${_pageUrls.length}',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
          ],
        ),
        actions: const [],
      ),
      body: Stack(
        children: [
          Center(
            child: _isLoading
                ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                : _pageUrls.isEmpty || _errorMessage != null
                    ? _buildErrorWidget()
                    : _isLoadingPage || _currentImageUrl == null
                        ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                        : TvGestureTap(
                            onTap: () {
                              // Toggle zoom controls on mobile
                              if (MediaQuery.of(context).size.width <= 600) {
                                setState(() => _showZoomControls = !_showZoomControls);
                              }
                            },
                            onHorizontalDragEnd: (details) {
                              // Swipe navigation on mobile when not zoomed
                              if (MediaQuery.of(context).size.width <= 600 && _currentScale <= 1.0) {
                                if (details.primaryVelocity! > 500) {
                                  // Swipe right - previous page
                                  _prevPage();
                                } else if (details.primaryVelocity! < -500) {
                                  // Swipe left - next page
                                  _nextPage();
                                }
                              }
                            },
                            child: InteractiveViewer(
                              transformationController: _transformationController,
                              minScale: 1.0,
                              maxScale: 4.0,
                              panEnabled: true,
                              scaleEnabled: true,
                              onInteractionUpdate: (details) {
                                setState(() {
                                  _currentScale = _transformationController.value.getMaxScaleOnAxis();
                                });
                              },
                              child: CachedNetworkImage(
                                imageUrl: _currentImageUrl!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                errorWidget: (context, url, error) => const Center(
                                  child: Icon(Icons.broken_image, color: Colors.white24, size: 48),
                                ),
                              ),
                            ),
                          ),
          ),
          
          // Zoom Controls - positioned on LEFT side to not block navigation buttons
          if (!_isLoading && _currentImageUrl != null && _showZoomControls)
            Positioned(
              left: 16,
              top: 80,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_in, size: 24),
                      onPressed: _zoomIn,
                      color: Colors.white,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: AppTheme.primaryColor,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppTheme.primaryColor,
                          ),
                          child: Slider(
                            value: _currentScale,
                            min: 1.0,
                            max: 4.0,
                            onChanged: _setZoom,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Icon(Icons.zoom_out, size: 24),
                      onPressed: _zoomOut,
                      color: Colors.white,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 8),
                    IconButton(
                      icon: const Icon(Icons.fit_screen, size: 20),
                      onPressed: _resetZoom,
                      color: Colors.white70,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          
          // Navigation Buttons (Desktop/Tablet) - on RIGHT side
          if (MediaQuery.of(context).size.width > 600) ...[
            Positioned(
              left: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'prev',
                mini: true,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.8),
                onPressed: _prevPage,
                child: const Icon(Icons.arrow_back_ios_new, size: 18),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'next',
                mini: true,
                backgroundColor: AppTheme.primaryColor,
                onPressed: _nextPage,
                child: const Icon(Icons.arrow_forward_ios, size: 18),
              ),
            ),
          ],
          
          // Bottom Progress Indicator (Mobile)
          if (MediaQuery.of(context).size.width <= 600 && !_isLoading && _pageUrls.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                color: Colors.white10,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (_currentPageIndex + 1) / _pageUrls.length,
                  child: Container(color: AppTheme.primaryColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
