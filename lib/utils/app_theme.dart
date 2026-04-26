import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/settings_service.dart';
import 'device_profile.dart';

/// A single color theme preset with its own personality.
class AppThemePreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color bgDark;
  final Color bgCard;
  final Color primaryColor;
  final Color accentColor;
  final Color gradientTint;

  const AppThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.bgDark,
    required this.bgCard,
    required this.primaryColor,
    required this.accentColor,
    required this.gradientTint,
  });

  BoxDecoration get backgroundDecoration => BoxDecoration(
    color: bgDark,
    gradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.5,
      colors: [gradientTint, bgDark],
      stops: const [0.0, 0.7],
    ),
  );

  BoxDecoration get backgroundDecorationFlat => BoxDecoration(color: bgDark);
}

class AppTheme {
  // ═══════════════════════════════════════════════════════════════════════════
  // Theme Presets
  // ═══════════════════════════════════════════════════════════════════════════

  static const List<AppThemePreset> presets = [
    AppThemePreset(
      id: 'cinematic',
      name: 'Cinematic',
      description: 'Electric violet & cyan — the original vibe',
      icon: Icons.movie_filter,
      bgDark: Color(0xFF0B0B12),
      bgCard: Color(0xFF15151E),
      primaryColor: Color(0xFF7C4DFF),
      accentColor: Color(0xFF00E5FF),
      gradientTint: Color(0xFF1F1F2E),
    ),
    AppThemePreset(
      id: 'midnight',
      name: 'Midnight Black',
      description: 'Pure AMOLED black — sleek and minimal',
      icon: Icons.dark_mode,
      bgDark: Color(0xFF000000),
      bgCard: Color(0xFF0D0D0D),
      primaryColor: Color(0xFFB0B0B0),
      accentColor: Color(0xFF4A4A4A),
      gradientTint: Color(0xFF0A0A0A),
    ),
    AppThemePreset(
      id: 'royal_purple',
      name: 'Royal Purple',
      description: 'Deep purple with hot pink sparks',
      icon: Icons.auto_awesome,
      bgDark: Color(0xFF0D0518),
      bgCard: Color(0xFF170B28),
      primaryColor: Color(0xFFBB86FC),
      accentColor: Color(0xFFFF4081),
      gradientTint: Color(0xFF1A0B2E),
    ),
    AppThemePreset(
      id: 'crimson',
      name: 'Crimson',
      description: 'Dark and intense — blood red energy',
      icon: Icons.local_fire_department,
      bgDark: Color(0xFF0C0404),
      bgCard: Color(0xFF1A0A0A),
      primaryColor: Color(0xFFFF1744),
      accentColor: Color(0xFFFF6D00),
      gradientTint: Color(0xFF1E0808),
    ),
    AppThemePreset(
      id: 'ocean',
      name: 'Ocean',
      description: 'Deep navy tones with teal highlights',
      icon: Icons.water,
      bgDark: Color(0xFF040D14),
      bgCard: Color(0xFF0A1520),
      primaryColor: Color(0xFF00BCD4),
      accentColor: Color(0xFF26C6DA),
      gradientTint: Color(0xFF0B1929),
    ),
    AppThemePreset(
      id: 'emerald',
      name: 'Emerald',
      description: 'Dark forest vibes with neon green',
      icon: Icons.park,
      bgDark: Color(0xFF040D08),
      bgCard: Color(0xFF0A1A10),
      primaryColor: Color(0xFF00E676),
      accentColor: Color(0xFF69F0AE),
      gradientTint: Color(0xFF0B1E12),
    ),
    AppThemePreset(
      id: 'sunset',
      name: 'Sunset',
      description: 'Warm amber tones with golden glow',
      icon: Icons.wb_twilight,
      bgDark: Color(0xFF0F0804),
      bgCard: Color(0xFF1A1008),
      primaryColor: Color(0xFFFFAB00),
      accentColor: Color(0xFFFF6D00),
      gradientTint: Color(0xFF1E150A),
    ),
  ];

  /// Notifier that broadcasts the current theme preset.
  static final ValueNotifier<AppThemePreset> themeNotifier =
      ValueNotifier<AppThemePreset>(presets.first);

  /// Current active preset (shorthand).
  static AppThemePreset get current => themeNotifier.value;

  // ═══════════════════════════════════════════════════════════════════════════
  // Backward-compatible const accessors (used in const contexts throughout the app)
  // These always return the default cinematic theme colors.
  // For theme-aware colors, use Theme.of(context).colorScheme or AppTheme.current.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Default primary color (const). For dynamic theme color, use `current.primaryColor`.
  static const Color primaryColor = Color(0xFF7C4DFF); // Electric Violet
  /// Default accent color (const). For dynamic theme color, use `current.accentColor`.
  static const Color accentColor = Color(0xFF00E5FF); // Cyan Accent

  static Color get bgDark => current.bgDark;
  static Color get bgCard => current.bgCard;

  /// Whether light mode is currently active (cached from notifier).
  static bool get isLightMode => SettingsService.lightModeNotifier.value;

  static BoxDecoration get backgroundDecoration => current.backgroundDecoration;
  static BoxDecoration get backgroundDecorationFlat => current.backgroundDecorationFlat;

  /// Returns the correct background based on light mode state.
  static BoxDecoration get effectiveBackground =>
      isLightMode ? backgroundDecorationFlat : backgroundDecoration;

  static ThemeData get themeData {
    final preset = current;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: preset.bgDark,
      primaryColor: preset.primaryColor,
      colorScheme: ColorScheme.dark(
        primary: preset.primaryColor,
        secondary: preset.accentColor,
        surface: preset.bgCard,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.bebasNeue(fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white),
        displayMedium: GoogleFonts.bebasNeue(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white),
        titleLarge: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        bodyMedium: GoogleFonts.roboto(fontSize: 14, color: Colors.white70),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
    );
  }

  /// Hydrate the current theme from saved settings at app startup.
  static Future<void> initTheme() async {
    final id = await SettingsService().getThemePreset();
    final match = presets.where((p) => p.id == id);
    if (match.isNotEmpty) {
      themeNotifier.value = match.first;
    }
  }

  /// Change the theme and persist the choice.
  static Future<void> setPreset(String id) async {
    final match = presets.where((p) => p.id == id);
    if (match.isNotEmpty) {
      themeNotifier.value = match.first;
      await SettingsService().setThemePreset(id);
    }
  }
}

class FocusableControl extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autoFocus;
  final double borderRadius;
  final Color? glowColor;
  final double scaleOnFocus;

  const FocusableControl({
    super.key,
    required this.child,
    this.onTap,
    this.autoFocus = false,
    this.borderRadius = 12.0,
    this.glowColor,
    this.scaleOnFocus = 1.0, // Changed default from 1.05 to 1.0 (no zoom)
  });

  @override
  State<FocusableControl> createState() => _FocusableControlState();
}

class _FocusableControlState extends State<FocusableControl> with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: widget.scaleOnFocus).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateState(bool active) {
    if (active) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lightMode = AppTheme.isLightMode;
    final tv = DeviceProfile.isAndroidTv;
    // TV D-pad: cheap border focus only (no blur-radius shadows or scale).
    if (tv) {
      return Focus(
        autofocus: widget.autoFocus,
        onFocusChange: (f) => setState(() => _isFocused = f),
        onKeyEvent: (node, event) {
          if (widget.onTap != null &&
              event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select)) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isFocused
                    ? (widget.glowColor ?? AppTheme.primaryColor)
                        .withValues(alpha: 0.95)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.child,
          ),
        ),
      );
    }

    return Focus(
      autofocus: widget.autoFocus,
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        _updateState(f || _isHovered);
      },
      onKeyEvent: (node, event) {
        if (widget.onTap != null && event is KeyDownEvent && 
           (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select)) {
             widget.onTap!(); 
             return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
          _updateState(true);
        },
        onExit: (_) {
          setState(() => _isHovered = false);
          _updateState(_isFocused);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: lightMode
              // Light mode: no scale animation, no glow
              ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                  ),
                  child: widget.child,
                )
              : AnimatedBuilder(
                  animation: _scale,
                  builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      boxShadow: (_isFocused || _isHovered) ? [
                        BoxShadow(
                          color: (widget.glowColor ?? AppTheme.primaryColor).withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ] : [],
                    ),
                    child: widget.child,
                  ),
                ),
        ),
      ),
    );
  }
}
