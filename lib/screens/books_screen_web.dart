import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// EPUB / local book reading uses file system APIs not available in the browser.
class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Books require the mobile or desktop app (local EPUB files).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
