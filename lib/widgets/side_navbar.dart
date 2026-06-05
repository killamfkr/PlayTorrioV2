import 'package:flutter/material.dart';
import '../api/settings_service.dart';
import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/discover_screen.dart';
import 'tv_interactive.dart';

class SideNavbar extends StatefulWidget {
  final String activeItem;
  final bool isMobile;
  const SideNavbar({super.key, required this.activeItem, this.isMobile = false});

  @override
  State<SideNavbar> createState() => _SideNavbarState();
}

class _SideNavbarState extends State<SideNavbar> {
  bool _isStreamingMode = false;

  final Map<String, bool> _navbarItems = {
    'Home': true,
    'Discover': true,
    'Library': true,
    'Search': true,
    'Manga': true,
    'Comics': true,
    'AudioBooks': true,
    'Books': true,
    'Media Downloader': true,
    'Games Downloader': true,
    'IPTV': true,
    'Live TV': true,
    'Music': true,
    'Play Magnet': true,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await SettingsService().isStreamingModeEnabled();
    if (mounted) {
      setState(() {
        _isStreamingMode = enabled;
      });
    }
  }

  void _showSettingsMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A0B2E),
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Colors.deepPurpleAccent),
                  SizedBox(width: 12),
                  Text('Settings', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Streaming Mode', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Extract direct links from web providers', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    value: _isStreamingMode,
                    activeThumbColor: Colors.deepPurpleAccent,
                    onChanged: (value) async {
                      await SettingsService().setStreamingMode(value);
                      setDialogState(() => _isStreamingMode = value);
                      setState(() => _isStreamingMode = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNavbarContextMenu(Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1A0B2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: _navbarItems.keys.map((item) {
        return PopupMenuItem(
          child: Row(
            children: [
              Icon(
                _navbarItems[item]! ? Icons.check_box : Icons.check_box_outline_blank,
                color: Colors.deepPurpleAccent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(item, style: const TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () {
            setState(() {
              _navbarItems[item] = !_navbarItems[item]!;
            });
          },
        );
      }).toList(),
    );
  }

  IconData _getIconForItem(String item) {
    switch (item) {
      case 'Home': return Icons.home;
      case 'Discover': return Icons.explore;
      case 'Library': return Icons.video_library;
      case 'Search': return Icons.search;
      case 'Manga': return Icons.menu_book;
      case 'Comics': return Icons.auto_stories;
      case 'AudioBooks': return Icons.headphones;
      case 'Books': return Icons.book;
      case 'Media Downloader': return Icons.download;
      case 'Games Downloader': return Icons.sports_esports;
      case 'IPTV': return Icons.live_tv;
      case 'Live TV': return Icons.tv;
      case 'Music': return Icons.music_note;
      case 'Play Magnet': return Icons.link;
      default: return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.isMobile ? 60.0 : 80.0;
    
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showNavbarContextMenu(details.globalPosition);
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A0B2E), // Dark purple
              Color(0xFF0F0418), // Very dark purple
              Color(0xFF0A0520), // Dark blue-purple
            ],
          ),
          border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        child: ClipRect(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3), // Glass effect
            ),
            child: Column(
              children: [
                SizedBox(height: widget.isMobile ? 10 : 20),
                Expanded(
                  child: ListView(
                    children: _navbarItems.entries
                        .where((entry) => entry.value)
                        .map((entry) => _buildNavItem(entry.key, _getIconForItem(entry.key)))
                        .toList(),
                  ),
                ),
                _buildNavItem('Settings', Icons.settings, onTap: _showSettingsMenu),
                SizedBox(height: widget.isMobile ? 10 : 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(String label, IconData icon, {VoidCallback? onTap}) {
    final isActive = widget.activeItem == label;
    final iconSize = widget.isMobile ? 20.0 : 24.0;
    final fontSize = widget.isMobile ? 8.0 : 9.0;
    final height = widget.isMobile ? 56.0 : 64.0;
    
    return Tooltip(
      message: label,
      child: TvInkWell(
        onTap: onTap ?? () {
          if (isActive) return;
          if (label == 'Home') {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          } else if (label == 'Discover') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DiscoverScreen()),
            );
          } else if (label == 'Search') {
             Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchScreen()),
            );
          }
        },
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(vertical: widget.isMobile ? 6 : 8, horizontal: widget.isMobile ? 2 : 4),
          decoration: isActive ? BoxDecoration(
            border: const Border(left: BorderSide(color: Colors.deepPurpleAccent, width: 3)),
            gradient: LinearGradient(
              colors: [Colors.deepPurpleAccent.withValues(alpha: 0.2), Colors.transparent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ) : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon, 
                color: isActive ? Colors.deepPurpleAccent : Colors.white70, 
                size: iconSize
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70, 
                    fontSize: fontSize,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
