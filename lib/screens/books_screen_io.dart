import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/books_service.dart';
import '../services/book_progress_service.dart';
import '../utils/app_theme.dart';
import 'book_reader_screen.dart';

class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  final BooksService _service = BooksService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<BookResult> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String _lastQuery = '';

  // ── Continue-reading state ─────────────────────────────────────────────────
  List<BookProgress> _reading = [];

  @override
  void initState() {
    super.initState();
    _loadReadingList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadReadingList() async {
    final entries = await BookProgressService.instance.loadAll();
    if (mounted) setState(() => _reading = entries);
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  Future<void> _search(String query) async {
    query = query.trim();
    if (query.isEmpty || query == _lastQuery) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _lastQuery = query;
      _results = [];
    });

    final results = await _service.search(query);

    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    }
  }

  // ── Download + open flow ───────────────────────────────────────────────────

  Future<void> _showDownloadDialog(BookResult book, {int resumeChapter = 0}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadDialog(
        service: _service,
        book: book,
        onFileReady: (file) {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookReaderScreen(
                file: file,
                title: book.title,
                bookResult: book,
                initialChapter: resumeChapter,
              ),
            ),
          ).then((_) => _loadReadingList());
        },
      ),
    );
  }

  // ── Resume / re-download ──────────────────────────────────────────────────

  Future<void> _resumeBook(BookProgress entry) async {
    final file = File(entry.filePath);
    if (file.existsSync() && file.lengthSync() > 1000) {
      // File still on disk — open directly
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookReaderScreen(
            file: file,
            title: entry.book.title,
            bookResult: entry.book,
            initialChapter: entry.chapter,
          ),
        ),
      );
      _loadReadingList();
    } else {
      // File was deleted — re-download then resume
      _showDownloadDialog(entry.book, resumeChapter: entry.chapter);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _deleteBook(BookProgress entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Book',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Delete "${entry.book.title}" and its reading progress?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await BookProgressService.instance.delete(entry.book.editionId);
      _loadReadingList();
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.import_contacts_rounded,
                color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Books',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5)),
              Text('Search & download ebooks (EPUB)',
                  style: TextStyle(fontSize: 12, color: Colors.white38)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        decoration: InputDecoration(
          hintText: 'Search by title, author, ISBN…',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _hasSearched = false;
                      _lastQuery = '';
                    });
                  },
                ),
              IconButton(
                icon: const Icon(Icons.search, color: AppTheme.primaryColor),
                onPressed: () => _search(_searchController.text),
              ),
            ],
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.07),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppTheme.primaryColor, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryColor),
            SizedBox(height: 16),
            Text('Searching LibGen…',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      );
    }

    if (_hasSearched) {
      if (_results.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              Text('No EPUB results for "$_lastQuery"',
                  style: const TextStyle(color: Colors.white54, fontSize: 15)),
              const SizedBox(height: 8),
              const Text('Try a different title or author',
                  style: TextStyle(color: Colors.white30, fontSize: 13)),
            ],
          ),
        );
      }

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Text('${_results.length} EPUB results',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
                const Spacer(),
                Text('for "$_lastQuery"',
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 11,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: _results.length,
              itemBuilder: (context, index) =>
                  _buildBookCard(_results[index]),
            ),
          ),
        ],
      );
    }

    // ── Default: Continue Reading + empty state ─────────────────────────────
    if (_reading.isEmpty) return _buildEmptyState();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Text('Continue Reading',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3)),
        ),
        ..._reading.map(_buildContinueCard),
      ],
    );
  }

  // ── Continue Reading card ──────────────────────────────────────────────────

  Widget _buildContinueCard(BookProgress entry) {
    final book = entry.book;
    final ago = _timeAgo(entry.lastReadTimestamp);
    return Dismissible(
      key: ValueKey(book.editionId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.redAccent, size: 28),
      ),
      confirmDismiss: (_) async {
        await _deleteBook(entry);
        return false; // we handle removal via _loadReadingList
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _resumeBook(entry),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Book icon
                Container(
                  width: 52,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.auto_stories_rounded,
                      color: AppTheme.primaryColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (book.series.isNotEmpty)
                        Text(book.series,
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.accentColor,
                                letterSpacing: 0.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      Text(book.title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      if (book.author.isNotEmpty)
                        Text(book.author,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white60),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _chip(Icons.bookmark_rounded,
                              'Chapter ${entry.chapter + 1}'),
                          const SizedBox(width: 6),
                          _chip(Icons.access_time_rounded, ago),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  children: [
                    const Icon(Icons.play_circle_fill_rounded,
                        color: AppTheme.primaryColor, size: 28),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _deleteBook(entry),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white24, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timeAgo(int ts) {
    final diff = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.import_contacts_rounded,
                  size: 64, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 24),
            const Text('Search for Books',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 10),
            const Text(
              'Search LibGen to find and download EPUB ebooks by title, author, or ISBN.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white38, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(BookResult book) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDownloadDialog(book),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 70,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: AppTheme.primaryColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book.series.isNotEmpty)
                      Text(book.series,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.accentColor,
                              letterSpacing: 0.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    Text(book.title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    if (book.author.isNotEmpty)
                      Text(book.author,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white60),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (book.year.isNotEmpty)
                          _chip(Icons.calendar_today_rounded, book.year),
                        if (book.language.isNotEmpty)
                          _chip(Icons.language_rounded, book.language),
                        if (book.pages.isNotEmpty)
                          _chip(Icons.article_rounded, '${book.pages} pp'),
                        if (book.size.isNotEmpty)
                          _chip(Icons.sd_card_rounded, book.size),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('EPUB',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent)),
                  ),
                  const SizedBox(height: 12),
                  const Icon(Icons.download_rounded,
                      color: AppTheme.primaryColor, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white38),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Download dialog — resolves edition → MD5 → URL → downloads to persistent dir
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadDialog extends StatefulWidget {
  final BooksService service;
  final BookResult book;
  final void Function(File file) onFileReady;

  const _DownloadDialog({
    required this.service,
    required this.book,
    required this.onFileReady,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  String _status = 'Resolving download link…';
  bool _failed = false;
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      // ── Step 1: Check persistent cache ─────────────────────────────────────
      final filePath = await BookProgressService.instance
          .bookFilePath(widget.book.editionId);
      final cacheFile = File(filePath);

      if (cacheFile.existsSync() && cacheFile.lengthSync() > 1000) {
        if (mounted) widget.onFileReady(cacheFile);
        return;
      }

      // ── Step 2: Resolve MD5 → download URL ────────────────────────────────
      if (mounted) setState(() => _status = 'Resolving download link…');
      final downloadUrl =
          await widget.service.resolveDownloadUrl(widget.book.editionId);
      if (downloadUrl == null) {
        if (mounted) {
          setState(() {
            _status = 'Could not resolve download link. Try again later.';
            _failed = true;
          });
        }
        return;
      }

      // ── Step 3: Download file with progress ───────────────────────────────
      if (mounted) {
        setState(() {
          _status = 'Downloading…';
          _downloadProgress = 0;
        });
      }

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request);
      final total = response.contentLength ?? 0;
      int received = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      }

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _status = 'Download failed (HTTP ${response.statusCode})';
            _failed = true;
          });
        }
        return;
      }

      // ── Step 4: Save to persistent dir and open ───────────────────────────
      if (mounted) setState(() => _status = 'Opening book…');
      await cacheFile.writeAsBytes(bytes);

      if (mounted) widget.onFileReady(cacheFile);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A0B2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.menu_book_rounded, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              book.title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.author.isNotEmpty)
            _infoRow(Icons.person_rounded, book.author),
          if (book.year.isNotEmpty)
            _infoRow(Icons.calendar_today_rounded, book.year),
          if (book.publisher.isNotEmpty)
            _infoRow(Icons.business_rounded, book.publisher),
          if (book.pages.isNotEmpty)
            _infoRow(Icons.article_rounded, '${book.pages} pages'),
          if (book.size.isNotEmpty)
            _infoRow(Icons.sd_card_rounded, book.size),
          if (book.language.isNotEmpty)
            _infoRow(Icons.language_rounded, book.language),
          if (book.isbn.isNotEmpty)
            _infoRow(Icons.qr_code_rounded, 'ISBN: ${book.isbn}'),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          if (_failed)
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_status,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.redAccent)),
                ),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        value: _downloadProgress,
                        color: AppTheme.primaryColor,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_status,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white54)),
                    ),
                    if (_downloadProgress != null)
                      Text(
                        '${(_downloadProgress! * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
                if (_downloadProgress != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor),
                      minHeight: 4,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
      actions: [
        if (_failed)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close',
                style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
