import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/settings_service.dart';
import 'device_profile.dart';

class AppTheme {
  // Cinematic Dark Theme
  static const Color bgDark = Color(0xFF0B0B12);
  static const Color bgCard = Color(0xFF15151E);
  static const Color primaryColor = Color(0xFF7C4DFF); // Electric Violet
  static const Color accentColor = Color(0xFF00E5FF); // Cyan Accent

  /// Whether light mode is currently active (cached from notifier).
  static bool get isLightMode => SettingsService.lightModeNotifier.value;
  
  static const BoxDecoration backgroundDecoration = BoxDecoration(
    color: bgDark,
    gradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.5,
      colors: [
        Color(0xFF1F1F2E), // Subtle blue-purple tint
        bgDark,
      ],
      stops: [0.0, 0.7],
    ),
  );

  /// A flat bg decoration with no gradient — used in light mode.
  static const BoxDecoration backgroundDecorationFlat = BoxDecoration(
    color: bgDark,
  );

  /// Returns the correct background based on light mode state.
  static BoxDecoration get effectiveBackground =>
      isLightMode ? backgroundDecorationFlat : backgroundDecoration;

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: bgCard,
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
