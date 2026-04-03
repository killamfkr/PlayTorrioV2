import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/tmdb_api.dart';
import '../api/settings_service.dart';
import '../models/movie.dart';
import '../services/my_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/performance_tuning.dart';
import 'details_screen.dart';
import 'streaming_details_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with AutomaticKeepAliveClientMixin {
  final TmdbApi _api = TmdbApi();
  final ScrollController _scrollController = ScrollController();
  
  // State
  List<Movie> _movies = [];
  bool _isLoading = false;
  int _currentPage = 1;
  
  // Filters
  String _selectedType = "Movies"; // Movies, TV Shows, All
  final List<String> _selectedGenreNames = [];
  final List<int> _selectedYears = [];
  double _minRating = 0;
  String? _selectedLanguage; // ISO 639-1 code

  // Genre Maps
  final Map<String, int> _movieGenreMap = {};
  final Map<String, int> _tvGenreMap = {};
  List<String> _allGenreNames = [];

  // Language map (display name -> ISO 639-1 code)
  static const Map<String, String> _languageMap = {
    'English': 'en',
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Italian': 'it',
    'Portuguese': 'pt',
    'Russian': 'ru',
    'Japanese': 'ja',
    'Korean': 'ko',
    'Chinese': 'zh',
    'Hindi': 'hi',
    'Arabic': 'ar',
    'Turkish': 'tr',
    'Thai': 'th',
    'Swedish': 'sv',
    'Danish': 'da',
    'Norwegian': 'no',
    'Finnish': 'fi',
    'Dutch': 'nl',
    'Polish': 'pl',
    'Czech': 'cs',
    'Romanian': 'ro',
    'Hungarian': 'hu',
    'Greek': 'el',
    'Hebrew': 'he',
    'Indonesian': 'id',
    'Malay': 'ms',
    'Vietnamese': 'vi',
    'Tagalog': 'tl',
    'Ukrainian': 'uk',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGenres();
    _loadData();
  }

  Future<void> _loadGenres() async {
    try {
      final mGenres = await _api.getMovieGenres();
      final tGenres = await _api.getTvGenres();
      
      final Set<String> names = {};
      
      for (var g in mGenres) {
        _movieGenreMap[g['name']] = g['id'];
        names.add(g['name']);
      }
      for (var g in tGenres) {
        _tvGenreMap[g['name']] = g['id'];
        names.add(g['name']);
      }
      
      if (mounted) {
        setState(() {
          _allGenreNames = names.toList()..sort();
        });
      }
    } catch (e) {
      debugPrint("Error loading genres: $e");
    }
  }

  Future<void> _loadData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      List<Movie> results = [];
      
      // Determine years to fetch (default to null if empty, otherwise iterate)
      final yearsToFetch = _selectedYears.isEmpty ? [null] : _selectedYears;
      
      List<Future<List<Movie>>> tasks = [];

      for (var year in yearsToFetch) {
        // Movies
        if (_selectedType == "Movies" || _selectedType == "All") {
          final genreIds = _selectedGenreNames.map((n) => _movieGenreMap[n]).whereType<int>().toList();
          tasks.add(_api.discoverMovies(
            page: _currentPage,
            genres: genreIds,
            year: year,
            minRating: _minRating > 0 ? _minRating : null,
            language: _selectedLanguage,
          ));
        }
        
        // TV Shows
        if (_selectedType == "TV Shows" || _selectedType == "All") {
          final genreIds = _selectedGenreNames.map((n) => _tvGenreMap[n]).whereType<int>().toList();
          tasks.add(_api.discoverTvShows(
            page: _currentPage,
            genres: genreIds,
            year: year,
            minRating: _minRating > 0 ? _minRating : null,
            language: _selectedLanguage,
          ));
        }
      }

      final responses = await Future.wait(tasks);
      for (var list in responses) {
        results.addAll(list);
      }

      // Shuffle if "All" or multiple years to mix results
      if (_selectedType == "All" || yearsToFetch.length > 1) {
        results.shuffle();
      }

      if (mounted) {
        setState(() {
          _movies = results;
          _isLoading = false;
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    } catch (e) {
      debugPrint("Error loading discover: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _nextPage() {
    setState(() => _currentPage++);
    _loadData();
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      _loadData();
    }
  }

  void _showTypeMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _CompactFilterDialog(
        title: 'Content Type',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['All', 'Movies', 'TV Shows'].map((type) {
            final isSelected = _selectedType == type;
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(type, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
              trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20) : null,
              onTap: () {
                setState(() { _selectedType = type; _currentPage = 1; });
                Navigator.pop(context);
                _loadData();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showGenreMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _CompactFilterDialog(
              title: 'Select Genres',
              maxHeight: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _allGenreNames.map((name) {
                          final isSelected = _selectedGenreNames.contains(name);
                          return FilterChip(
                            label: Text(name, style: const TextStyle(fontSize: 12)),
                            selected: isSelected,
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) { _selectedGenreNames.add(name); } else { _selectedGenreNames.remove(name); }
                              });
                            },
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            selectedColor: AppTheme.primaryColor,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _currentPage = 1);
                        _loadData();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: const Text("Apply", style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showYearMenu() {
    final currentYear = DateTime.now().year;
    final years = List.generate(100, (index) => currentYear - index);

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _CompactFilterDialog(
              title: 'Select Years',
              maxHeight: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: years.map((y) {
                          final isSelected = _selectedYears.contains(y);
                          return FilterChip(
                            label: Text(y.toString(), style: const TextStyle(fontSize: 12)),
                            selected: isSelected,
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) { _selectedYears.add(y); } else { _selectedYears.remove(y); }
                              });
                            },
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            selectedColor: AppTheme.primaryColor,
                            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _currentPage = 1);
                        _loadData();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: const Text("Apply", style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLanguageMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final languages = _languageMap.keys.toList();
            return _CompactFilterDialog(
              title: 'Select Language',
              maxHeight: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          FilterChip(
                            label: const Text('Any', style: TextStyle(fontSize: 12)),
                            selected: _selectedLanguage == null,
                            onSelected: (_) => setDialogState(() => _selectedLanguage = null),
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            selectedColor: AppTheme.primaryColor,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(color: _selectedLanguage == null ? Colors.white : Colors.white70),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          ...languages.map((name) {
                            final code = _languageMap[name]!;
                            final isSelected = _selectedLanguage == code;
                            return FilterChip(
                              label: Text(name, style: const TextStyle(fontSize: 12)),
                              selected: isSelected,
                              onSelected: (_) => setDialogState(() => _selectedLanguage = isSelected ? null : code),
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              selectedColor: AppTheme.primaryColor,
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _currentPage = 1);
                        _loadData();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: const Text("Apply", style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRatingMenu() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        double localRating = _minRating;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return _CompactFilterDialog(
              title: 'Minimum Rating',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${localRating.toStringAsFixed(1)}+", style: const TextStyle(color: Colors.amber, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppTheme.primaryColor,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: AppTheme.primaryColor,
                      overlayColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: localRating,
                      min: 0,
                      max: 9,
                      divisions: 9,
                      onChanged: (v) => setDialogState(() => localRating = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text("Cancel", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() { _minRating = localRating; _currentPage = 1; });
                            Navigator.pop(context);
                            _loadData();
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(vertical: 10)),
                          child: const Text("Apply", style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openDetails(Movie movie) async {
    final settings = SettingsService();
    final isStreaming = await settings.isStreamingModeEnabled();
    
    if (!mounted) return;

    if (isStreaming) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => StreamingDetailsScreen(movie: movie)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(movie: movie)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 6 : (width > 900 ? 5 : (width > 600 ? 4 : 3));

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
            color: AppTheme.bgCard,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterButton(label: "Type: $_selectedType", onTap: _showTypeMenu, isActive: true),
                        _FilterButton(label: "Genres", onTap: _showGenreMenu, isActive: _selectedGenreNames.isNotEmpty),
                        _FilterButton(label: "Year", onTap: _showYearMenu, isActive: _selectedYears.isNotEmpty),
                        _FilterButton(label: "Rating", onTap: _showRatingMenu, isActive: _minRating > 0),
                        _FilterButton(label: _selectedLanguage != null ? "Lang: ${_languageMap.entries.firstWhere((e) => e.value == _selectedLanguage, orElse: () => MapEntry(_selectedLanguage!, _selectedLanguage!)).key}" : "Language", onTap: _showLanguageMenu, isActive: _selectedLanguage != null),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Grid
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
              : _movies.isEmpty 
                ? const Center(child: Text("No results found", style: TextStyle(color: Colors.white54)))
                : GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 2 / 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _movies.length,
                    itemBuilder: (context, index) {
                      final movie = _movies[index];
                      return _DiscoverCard(movie: movie, onTap: () => _openDetails(movie));
                    },
                  ),
          ),

          // Pagination
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.bgCard,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _currentPage > 1 ? _prevPage : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                  child: const Text("Previous", style: TextStyle(color: Colors.white)),
                ),
                Text("Page $_currentPage", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: _movies.isNotEmpty ? _nextPage : null,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  child: const Text("Next", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _FilterButton({required this.label, required this.onTap, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
        backgroundColor: isActive ? AppTheme.primaryColor : Colors.white10,
        labelStyle: TextStyle(color: isActive ? Colors.white : Colors.white70, fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _CompactFilterDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final double? maxHeight;

  const _CompactFilterDialog({required this.title, required this.child, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight ?? 500),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: PerformanceTuning.skipBackdropBlur
              ? _buildDialogBody(context)
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: _buildDialogBody(context),
                ),
        ),
      ),
    );
  }

  Widget _buildDialogBody(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: AppTheme.isLightMode ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: -5)],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close, color: Colors.white54, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const _DiscoverCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = movie.posterPath.isNotEmpty ? TmdbApi.getImageUrl(movie.posterPath) : '';

    return FocusableControl(
      onTap: onTap,
      borderRadius: 12,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppTheme.isLightMode ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: AppTheme.bgCard),
                errorWidget: (c, u, e) => const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
              )
            else
              Center(child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(movie.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              )),
            
            // Rating Badge
            Positioned(
              top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 10),
                    const SizedBox(width: 4),
                    Text(movie.voteAverage.toStringAsFixed(1), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),

            // My List add/remove button
            Positioned(
              top: 8, left: 8,
              child: _AddToMyListButton(movie: movie),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddToMyListButton extends StatelessWidget {
  final Movie movie;
  const _AddToMyListButton({required this.movie});

  @override
  Widget build(BuildContext context) {
    final uid = MyListService.movieId(movie.id, movie.mediaType);
    return ValueListenableBuilder<int>(
      valueListenable: MyListService.changeNotifier,
      builder: (context, _, _) {
        final inList = MyListService().contains(uid);
        return GestureDetector(
          onTap: () async {
            final added = await MyListService().toggleMovie(
              tmdbId: movie.id,
              imdbId: movie.imdbId,
              title: movie.title,
              posterPath: movie.posterPath,
              mediaType: movie.mediaType,
              voteAverage: movie.voteAverage,
              releaseDate: movie.releaseDate,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(added ? 'Added to My List' : 'Removed from My List'),
                duration: const Duration(seconds: 1),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              inList ? Icons.bookmark : Icons.add,
              size: 16,
              color: inList ? AppTheme.primaryColor : Colors.white70,
            ),
          ),
        );
      },
    );
  }
}
