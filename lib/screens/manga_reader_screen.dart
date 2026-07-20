import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../api/manga_service.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';

class MangaReaderScreen extends StatefulWidget {
  final Manga manga;
  final List<MangaChapter> chapters;
  final int currentChapterIndex;
  final int? resumePageIndex;

  const MangaReaderScreen({
    super.key,
    required this.manga,
    required this.chapters,
    required this.currentChapterIndex,
    this.resumePageIndex,
  });

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends State<MangaReaderScreen> {
  final MangaService _mangaService = MangaService();
  final TransformationController _transformationController = TransformationController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  List<String> _pageUrls = [];
  int _currentPageIndex = 0;
  int _currentChapterIndex = 0;
  bool _isLoading = true;
  bool _isLoadingPage = false;
  String? _currentImageUrl;
  double _currentScale = 1.0;
  bool _continuousScrollMode = false;
  bool _showZoomControls = true;
  
  static const String _historyKey = 'manga_reading_history';

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.currentChapterIndex;
    _loadChapter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (_continuousScrollMode) {
        // In continuous scroll mode, arrows scroll the view
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _scrollController.animateTo(
            _scrollController.offset + 200,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _scrollController.animateTo(
            _scrollController.offset - 200,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      } else {
        // In page-by-page mode
        if (_currentScale > 1.0) {
          // When zoomed in, up/down pan the view
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final currentMatrix = _transformationController.value;
            final newMatrix = currentMatrix.clone() * Matrix4.translationValues(0.0, -100.0, 0.0);
            _transformationController.value = newMatrix;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final currentMatrix = _transformationController.value;
            final newMatrix = currentMatrix.clone() * Matrix4.translationValues(0.0, 100.0, 0.0);
            _transformationController.value = newMatrix;
          }
        }
        // Left/right always navigate pages
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _nextPage();
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _prevPage();
        }
      }
    }
  }

  void _toggleScrollMode() {
    final previousPage = _currentPageIndex;
    setState(() {
      _continuousScrollMode = !_continuousScrollMode;
      _resetZoom();
    });
    
    // Scroll to the current page position in continuous mode
    if (_continuousScrollMode && _pageUrls.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          // Calculate approximate position based on page index
          // Assuming average image height of 1200px
          final targetPosition = previousPage * 1200.0;
          _scrollController.animateTo(
            targetPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    
    final progress = {
      'manga': widget.manga.toJson(),
      'chapterIndex': _currentChapterIndex,
      'pageIndex': _currentPageIndex,
      'chapters': widget.chapters.map((c) => c.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    final historyJson = prefs.getStringList(_historyKey) ?? [];
    final history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    
    // Remove existing entry for this manga
    history.removeWhere((h) => h['manga']['id'] == widget.manga.id);
    
    // Add new entry at the beginning
    history.insert(0, progress);
    
    // Keep only last 10 items
    if (history.length > 10) {
      history.removeRange(10, history.length);
    }
    
    await prefs.setStringList(_historyKey, history.map((e) => jsonEncode(e)).toList());
  }

  void _setZoom(double scale) {
    final viewportSize = MediaQuery.of(context).size;
    final centerX = viewportSize.width / 2;
    final centerY = viewportSize.height / 2;
    
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
    final newScale = (_currentScale * 1.5).clamp(1.0, 8.0);
    _setZoom(newScale);
  }

  void _zoomOut() {
    final newScale = (_currentScale / 1.5).clamp(1.0, 8.0);
    _setZoom(newScale);
  }

  void _resetZoom() {
    _setZoom(1.0);
  }

  Future<void> _loadChapter() async {
    setState(() => _isLoading = true);
    
    final chapter = widget.chapters[_currentChapterIndex];
    debugPrint('[MangaReader] Loading chapter ${chapter.number}');
    final images = await _mangaService.getChapterImages(chapter.id);
    
    debugPrint('[MangaReader] Received ${images.length} images');
    if (images.isNotEmpty) {
      debugPrint('[MangaReader] First image: ${images.first}');
    }
    
    if (mounted) {
      setState(() {
        _pageUrls = images;
        _currentPageIndex = 0;
        _isLoading = false;
      });
      
      debugPrint('[MangaReader] State updated, _pageUrls.length = ${_pageUrls.length}');
      
      // Resume to saved page if provided and this is the initial load
      if (widget.resumePageIndex != null && 
          _currentChapterIndex == widget.currentChapterIndex &&
          widget.resumePageIndex! < _pageUrls.length) {
        setState(() => _currentPageIndex = widget.resumePageIndex!);
        debugPrint('[MangaReader] Resuming to page ${widget.resumePageIndex}');
      }
      
      if (_pageUrls.isNotEmpty) {
        _loadPageImage(_currentPageIndex);
      }
    }
  }

  Future<void> _loadPageImage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageUrls.length) return;
    
    debugPrint('[MangaReader] Loading page $pageIndex: ${_pageUrls[pageIndex]}');
    setState(() => _isLoadingPage = true);
    
    final imageUrl = _pageUrls[pageIndex];
    
    if (mounted) {
      setState(() {
        _currentImageUrl = imageUrl;
        _isLoadingPage = false;
      });
      debugPrint('[MangaReader] Image URL set: $_currentImageUrl');
    }
  }

  void _nextPage() {
    if (_currentPageIndex < _pageUrls.length - 1) {
      setState(() => _currentPageIndex++);
      _loadPageImage(_currentPageIndex);
      _saveProgress();
    } else {
      _nextChapter();
    }
  }

  void _prevPage() {
    if (_currentPageIndex > 0) {
      setState(() => _currentPageIndex--);
      _loadPageImage(_currentPageIndex);
      _saveProgress();
    } else {
      _prevChapter();
    }
  }

  void _nextChapter() {
    if (_currentChapterIndex > 0) {
      _currentChapterIndex--;
      _loadChapter();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have reached the last chapter')),
      );
    }
  }

  void _prevChapter() {
    if (_currentChapterIndex < widget.chapters.length - 1) {
      _currentChapterIndex++;
      _loadChapter();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapters[_currentChapterIndex];
    final chapterTitle = chapter.name.isNotEmpty 
        ? 'Chapter ${chapter.number} - ${chapter.name}' 
        : 'Chapter ${chapter.number}';

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.8),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isLoading ? 'Loading...' : chapterTitle,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!_isLoading && _pageUrls.isNotEmpty)
                Text(
                  _continuousScrollMode 
                      ? 'All Pages (${_pageUrls.length})'
                      : 'Page ${_currentPageIndex + 1} / ${_pageUrls.length}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
            ],
          ),
          actions: [
            if (!_isLoading && _pageUrls.isNotEmpty)
              IconButton(
                icon: Icon(
                  _continuousScrollMode ? Icons.view_carousel : Icons.view_stream,
                  color: Colors.white,
                ),
                tooltip: _continuousScrollMode ? 'Page by Page' : 'Continuous Scroll',
                onPressed: _toggleScrollMode,
              ),
          ],
        ),
        body: Stack(
          children: [
            if (_continuousScrollMode)
              _buildContinuousScrollView()
            else
              _buildPageByPageView(),
            
            // Zoom Controls (available in both modes)
            if (!_isLoading && (_currentImageUrl != null || _continuousScrollMode) && _showZoomControls)
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
                              max: 8.0,
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
            
            // Navigation Buttons (Desktop/Tablet, page-by-page mode)
            if (!_continuousScrollMode && MediaQuery.of(context).size.width > 600) ...[
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
            
            // Next Chapter Button (on last page)
            if (!_continuousScrollMode && !_isLoading && _pageUrls.isNotEmpty && 
                _currentPageIndex == _pageUrls.length - 1 && _currentChapterIndex > 0)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _nextChapter,
                    icon: const Icon(Icons.skip_next),
                    label: Text('Next Chapter: ${widget.chapters[_currentChapterIndex - 1].number}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                    ),
                  ),
                ),
              ),
            
            // Bottom Progress Indicator (Mobile, page-by-page mode)
            if (!_continuousScrollMode && MediaQuery.of(context).size.width <= 600 && !_isLoading && _pageUrls.isNotEmpty)
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
      ),
    );
  }

  Widget _buildPageByPageView() {
    return Center(
      child: _isLoading
          ? const CircularProgressIndicator(color: AppTheme.primaryColor)
          : _pageUrls.isEmpty
              ? const Text('Failed to load pages', style: TextStyle(color: Colors.white70))
              : _isLoadingPage || _currentImageUrl == null
                  ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                  : GestureDetector(
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
                        maxScale: 8.0,
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
    );
  }

  Widget _buildContinuousScrollView() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    if (_pageUrls.isEmpty) {
      return const Center(
        child: Text('Failed to load pages', style: TextStyle(color: Colors.white70)),
      );
    }

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1.0,
      maxScale: 8.0,
      panEnabled: _currentScale > 1.0,
      scaleEnabled: true,
      boundaryMargin: const EdgeInsets.all(100),
      onInteractionUpdate: (details) {
        setState(() {
          _currentScale = _transformationController.value.getMaxScaleOnAxis();
        });
      },
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 12,
        radius: const Radius.circular(8),
        child: ListView.builder(
          controller: _scrollController,
          physics: _currentScale > 1.0 ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
          itemCount: _pageUrls.length,
          itemBuilder: (context, index) {
            return Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                child: CachedNetworkImage(
                  imageUrl: _pageUrls[index],
                  placeholder: (context, url) => Container(
                    width: MediaQuery.of(context).size.width,
                    height: 800,
                    color: Colors.grey[900],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Loading page ${index + 1}...',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: MediaQuery.of(context).size.width,
                    height: 400,
                    color: Colors.grey[900],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.broken_image, color: Colors.white24, size: 48),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load page ${index + 1}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
