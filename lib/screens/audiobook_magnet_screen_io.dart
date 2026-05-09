import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../api/audiobook_service.dart';
import '../api/torrent_stream_service.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';

String? _hashFromMagnet(String magnet) {
  final match = RegExp(r'btih:([0-9a-fA-F]{40})').firstMatch(magnet);
  return match?.group(1)?.toLowerCase();
}

bool _isAudioFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.mp3') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.m4b') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.opus') ||
      lower.endsWith('.wav');
}

/// Paste a magnet, pick audio files in order, return an [Audiobook] for the hub.
class AudiobookMagnetScreen extends StatefulWidget {
  const AudiobookMagnetScreen({super.key});

  @override
  State<AudiobookMagnetScreen> createState() => _AudiobookMagnetScreenState();
}

class _AudiobookMagnetScreenState extends State<AudiobookMagnetScreen> {
  final _magnetController = TextEditingController();
  final _titleController = TextEditingController();
  final _torrent = TorrentStreamService();

  bool _loading = false;
  String? _error;
  List<FileInfo> _audioFiles = [];
  final Set<int> _selectedFileIndexes = {};

  @override
  void dispose() {
    _magnetController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _fetchAudioFiles() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty || !magnet.startsWith('magnet:')) {
      setState(() => _error = 'Enter a valid magnet link');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _audioFiles = [];
      _selectedFileIndexes.clear();
    });

    try {
      if (!await _torrent.start()) {
        throw Exception('Torrent engine failed to start');
      }

      final torrentId = LibtorrentFlutter.instance.addMagnet(magnet, null, true);

      final files = await _waitForFiles(torrentId);
      if (files == null || files.isEmpty) {
        throw Exception('No files — metadata timeout');
      }

      final audio = files
          .where((f) => f.isStreamable && _isAudioFileName(f.name))
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));

      if (audio.isEmpty) {
        throw Exception(
          'No streamable audio files (.mp3, .m4b, .flac, …) in this torrent',
        );
      }

      var titleGuess = 'Magnet audiobook';
      try {
        final upd = await LibtorrentFlutter.instance.torrentUpdates
            .firstWhere(
              (u) =>
                  u.containsKey(torrentId) &&
                  (u[torrentId]?.hasMetadata ?? false),
            )
            .timeout(const Duration(seconds: 3));
        final ti = upd[torrentId];
        if (ti != null && ti.name.isNotEmpty) titleGuess = ti.name;
      } catch (_) {}

      _titleController.text = titleGuess;

      setState(() {
        _audioFiles = audio;
        for (final f in audio) {
          _selectedFileIndexes.add(f.index);
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<List<FileInfo>?> _waitForFiles(int torrentId) async {
    try {
      final files = LibtorrentFlutter.instance.getFiles(torrentId);
      if (files.isNotEmpty) return files;
    } catch (_) {}

    final completer = Completer<List<FileInfo>?>();
    StreamSubscription<Map<int, TorrentInfo>>? sub;
    final timer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        sub?.cancel();
        completer.complete(null);
      }
    });

    sub = LibtorrentFlutter.instance.torrentUpdates.listen((updates) {
      if (completer.isCompleted) return;
      if (updates.containsKey(torrentId)) {
        final info = updates[torrentId]!;
        if (info.hasMetadata) {
          timer.cancel();
          sub?.cancel();
          final files = LibtorrentFlutter.instance.getFiles(torrentId);
          if (!completer.isCompleted) completer.complete(files);
        }
      }
    });

    return completer.future;
  }

  void _toggleFile(int index) {
    setState(() {
      if (_selectedFileIndexes.contains(index)) {
        _selectedFileIndexes.remove(index);
      } else {
        _selectedFileIndexes.add(index);
      }
    });
  }

  void _confirmAdd() {
    final magnet = _magnetController.text.trim();
    final hash = _hashFromMagnet(magnet);
    if (hash == null) {
      setState(() => _error = 'Magnet has no btih hash');
      return;
    }
    final selected = _audioFiles
        .where((f) => _selectedFileIndexes.contains(f.index))
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (selected.isEmpty) {
      setState(() => _error = 'Select at least one audio file');
      return;
    }

    final title = _titleController.text.trim().isEmpty
        ? 'Magnet audiobook'
        : _titleController.text.trim();

    final book = Audiobook(
      uuid: 'magnet_$hash',
      audioBookId: 'magnet_$hash',
      dynamicSlugId: '',
      title: title,
      coverImage: '',
      source: 'magnet',
      magnetLink: magnet,
      magnetTracks:
          selected.map((f) => {'title': f.name, 'fileIndex': f.index}).toList(),
    );
    Navigator.pop(context, book);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    TvInkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        final m = _magnetController.text.trim();
                        if (m.startsWith('magnet:') && _audioFiles.isNotEmpty) {
                          TorrentStreamService().removeTorrent(m);
                        }
                        Navigator.pop(context);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child:
                            Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Magnet audiobook',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _magnetController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Paste magnet link…',
                          hintStyle:
                              TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                          filled: true,
                          fillColor: AppTheme.bgCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          suffixIcon: IconButton(
                            icon:
                                const Icon(Icons.paste_rounded, color: Colors.white38),
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null) {
                                _magnetController.text = data!.text!;
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _loading ? null : _fetchAudioFiles,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Fetch'),
                    ),
                  ],
                ),
              ),
              if (_audioFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              Expanded(
                child: _audioFiles.isEmpty
                    ? Center(
                        child: Text(
                          'Paste a magnet for an audiobook torrent,\n'
                          'tap Fetch, choose files, then add.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: _audioFiles.length,
                        itemBuilder: (_, i) {
                          final f = _audioFiles[i];
                          final on = _selectedFileIndexes.contains(f.index);
                          return Card(
                            color: AppTheme.bgCard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color:
                                    on ? AppTheme.primaryColor : Colors.white12,
                              ),
                            ),
                            child: TvInkWell(
                              onTap: () => _toggleFile(f.index),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(
                                      on
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: on
                                          ? AppTheme.primaryColor
                                          : Colors.white38,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        f.name,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      _formatSize(f.size),
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_audioFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: ElevatedButton.icon(
                    onPressed: _confirmAdd,
                    icon: const Icon(Icons.menu_book_rounded),
                    label: const Text('Add to audiobooks & play'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
