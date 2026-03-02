import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/tmdb_api.dart';
import '../api/settings_service.dart';
import '../models/movie.dart';
import '../services/my_list_service.dart';
import '../utils/app_theme.dart';
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

  // Genre Maps
  final Map<String, int> _movieGenreMap = {};
  final Map<String, int> _tvGenreMap = {};
  List<String> _allGenreNames = [];

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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypeTile("All"),
          _buildTypeTile("Movies"),
          _buildTypeTile("TV Shows"),
        ],
      ),
    );
  }

  Widget _buildTypeTile(String type) {
    return ListTile(
      title: Text(type, style: const TextStyle(color: Colors.white)),
      trailing: _selectedType == type ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
      onTap: () {
        setState(() {
          _selectedType = type;
          _currentPage = 1;
        });
        Navigator.pop(context);
        _loadData();
      },
    );
  }

  void _showGenreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text("Select Genres", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allGenreNames.map((name) {
                        final isSelected = _selectedGenreNames.contains(name);
                        return FilterChip(
                          label: Text(name),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                _selectedGenreNames.add(name);
                              } else {
                                _selectedGenreNames.remove(name);
                              }
                            });
                          },
                          backgroundColor: Colors.white10,
                          selectedColor: AppTheme.primaryColor,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _currentPage = 1);
                        _loadData();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                      child: const Text("Apply", style: TextStyle(color: Colors.white)),
                    )
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showYearMenu() {
    final currentYear = DateTime.now().year;
    final years = List.generate(100, (index) => currentYear - index);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text("Select Years", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: years.map((y) {
                        final isSelected = _selectedYears.contains(y);
                        return FilterChip(
                          label: Text(y.toString()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                _selectedYears.add(y);
                              } else {
                                _selectedYears.remove(y);
                              }
                            });
                          },
                          backgroundColor: Colors.white10,
                          selectedColor: AppTheme.primaryColor,
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _currentPage = 1);
                        _loadData();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                      child: const Text("Apply", style: TextStyle(color: Colors.white)),
                    )
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showRatingMenu() {
    showDialog(
      context: context,
      builder: (context) {
        double localRating = _minRating;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: const Text("Minimum Rating", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${localRating.toStringAsFixed(1)}+ ⭐", style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
                  Slider(
                    value: localRating,
                    min: 0,
                    max: 9,
                    divisions: 9,
                    thumbColor: AppTheme.primaryColor,
                    onChanged: (v) => setDialogState(() => localRating = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _minRating = localRating;
                      _currentPage = 1;
                    });
                    Navigator.pop(context);
                    _loadData();
                  },
                  child: const Text("Apply", style: TextStyle(color: AppTheme.primaryColor)),
                ),
              ],
            );
          }
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
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
      builder: (context, _, __) {
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
