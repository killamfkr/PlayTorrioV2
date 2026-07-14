import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/movie_download_service.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';
import 'player_screen.dart';

class MovieDownloadsScreen extends StatefulWidget {
  const MovieDownloadsScreen({super.key});

  @override
  State<MovieDownloadsScreen> createState() => _MovieDownloadsScreenState();
}

class _MovieDownloadsScreenState extends State<MovieDownloadsScreen> {
  final _svc = MovieDownloadService();
  List<DownloadedMovie> _items = [];
  bool _loading = true;
  String? _folder;

  @override
  void initState() {
    super.initState();
    _svc.activeDownloads.addListener(_onActive);
    _reload();
  }

  @override
  void dispose() {
    _svc.activeDownloads.removeListener(_onActive);
    super.dispose();
  }

  void _onActive() {
    if (!mounted) return;
    setState(() {});
    final actives = _svc.activeDownloads.value.values;
    if (actives.any((a) => a.status == 'completed')) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final items = await _svc.listDownloaded();
    final folder = await _svc.downloadsDirectoryPath();
    if (!mounted) return;
    setState(() {
      _items = items;
      _folder = folder;
      _loading = false;
    });
  }

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final active = _svc.activeDownloads.value.values.toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Movie Downloads'),
        actions: [
          if (_folder != null)
            IconButton(
              tooltip: 'Copy folder path',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _folder!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Folder: $_folder')),
                );
              },
              icon: const Icon(Icons.folder_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (active.isNotEmpty) ...[
                    const Text(
                      'In progress',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...active.map(_buildActiveTile),
                    const SizedBox(height: 20),
                  ],
                  const Text(
                    'Downloaded',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No downloads yet.\nTap the download icon on a Stremio stream.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, height: 1.4),
                        ),
                      ),
                    )
                  else
                    ..._items.map(_buildDownloadedTile),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveTile(MovieDownloadProgress item) {
    final isErr = item.status == 'error' || item.status == 'cancelled';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.status == 'downloading')
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => _svc.cancel(item.id),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (item.status == 'downloading') ...[
            LinearProgressIndicator(
              value: item.totalBytes != null && item.totalBytes! > 0
                  ? item.progress
                  : null,
              color: AppTheme.primaryColor,
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 6),
            Text(
              item.totalBytes != null && item.totalBytes! > 0
                  ? '${_fmtBytes(item.downloadedBytes)} / ${_fmtBytes(item.totalBytes!)}'
                  : '${_fmtBytes(item.downloadedBytes)} downloaded…',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ] else
            Text(
              isErr ? (item.error ?? item.status) : item.status,
              style: TextStyle(
                color: isErr ? Colors.redAccent : Colors.greenAccent,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDownloadedTile(DownloadedMovie item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          item.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            _fmtBytes(item.sizeBytes),
            if (item.sourceLabel != null && item.sourceLabel!.isNotEmpty)
              item.sourceLabel!,
          ].join(' · '),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvInkWell(
              onTap: () {
                if (!File(item.filePath).existsSync()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('File missing on disk')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      streamUrl: Uri.file(item.filePath).toString(),
                      title: item.displayTitle,
                    ),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.play_arrow_rounded, color: AppTheme.primaryColor),
              ),
            ),
            TvInkWell(
              onTap: () async {
                final ok = await _svc.deleteDownload(item.id);
                if (!mounted) return;
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Deleted')),
                  );
                  _reload();
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.delete_outline, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
