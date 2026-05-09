import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// KissKh / WebView flows are not compiled for web targets.
class AsianDramaScreen extends StatelessWidget {
  const AsianDramaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Asian Drama (KissKh) is available in the Android, iOS, and desktop apps.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
