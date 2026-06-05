import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path/path.dart' as p;

import '../api/torrent_stream_service.dart';
import '../utils/app_theme.dart';
import 'player_screen.dart';
import '../widgets/tv_interactive.dart';

String? _btihFromMagnet(String magnet) {
  final m = RegExp(r'btih:([0-9a-fA-F]{40})').firstMatch(magnet);
  return m?.group(1)?.toLowerCase();
}

bool _looksLikeTorrentBytes(Uint8List bytes) =>
    bytes.isNotEmpty && bytes[0] == 0x64; // bencode dict 'd'

Future<Uint8List?> _downloadTorrentFromMirrors(String hash40) async {
  final urls = <String>[
    'https://itorrents.org/torrent/$hash40.torrent',
    'https://torrage.info/torrent/$hash40',
  ];
  final headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/x-bittorrent,*/*',
  };
  final client = http.Client();
  try {
    for (final url in urls) {
      try {
        final res = await client
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 18));
        if (res.statusCode == 200 &&
            res.bodyBytes.length > 64 &&
            _looksLikeTorrentBytes(res.bodyBytes)) {
          return res.bodyBytes;
        }
      } catch (_) {}
    }
  } finally {
    client.close();
  }
  return null;
}

String _sanitizeFileBase(String raw) {
  var s = raw.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
  if (s.length > 120) s = s.substring(0, 120);
  if (s.isEmpty) s = 'torrent';
  return s;
}

class MagnetPlayerScreen extends StatefulWidget {
  const MagnetPlayerScreen({super.key});

  @override
  State<MagnetPlayerScreen> createState() => _MagnetPlayerScreenState();
}

class _MagnetPlayerScreenState extends State<MagnetPlayerScreen> {
  final _magnetController = TextEditingController();
  final _torrent = TorrentStreamService();

  bool _loading = false;
  String? _error;
  int? _torrentId;
  List<FileInfo> _files = [];
  int? _streamingIndex;
  bool _savingTorrent = false;

  @override
  void dispose() {
    _magnetController.dispose();
    super.dispose();
  }

  // ── Fetch metadata ─────────────────────────────────────────────────────
  Future<void> _fetchFiles() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty || !magnet.startsWith('magnet:')) {
      setState(() => _error = 'Please enter a valid magnet link');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _files = [];
      _torrentId = null;
    });

    try {
      // Ensure engine is running
      if (!await _torrent.start()) {
        throw Exception('Failed to start torrent engine');
      }

      final torrentId = LibtorrentFlutter.instance.addMagnet(magnet, null, true);
      _torrentId = torrentId;

      // Wait for metadata with timeout
      final files = await _waitForFiles(torrentId);
      if (files == null || files.isEmpty) {
        throw Exception('No files found — metadata timeout');
      }

      setState(() {
        _files = files;
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
    // Try immediate
    try {
      final files = LibtorrentFlutter.instance.getFiles(torrentId);
      if (files.isNotEmpty) return files;
    } catch (_) {}

    // Poll via updates stream
    final completer = Completer<List<FileInfo>?>();
    StreamSubscription? sub;

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

  // ── Play a file ─────────────────────────────────────────────────────────
  Future<void> _playFile(FileInfo file) async {
    if (_torrentId == null) return;
    setState(() {
      _streamingIndex = file.index;
      _error = null;
    });

    try {
      final magnet = _magnetController.text.trim();
      final url = await _torrent.streamTorrent(magnet, fileIdx: file.index);
      if (url == null) throw Exception('Failed to start stream');

      if (mounted) {
        setState(() => _streamingIndex = null);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: url,
              title: file.name,
              magnetLink: magnet,
              activeProvider: 'torrent',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _streamingIndex = null;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String _suggestedTorrentSaveName() {
    FileInfo? pick;
    for (final f in _files) {
      if (!f.isStreamable) continue;
      final lower = f.name.toLowerCase();
      final video = lower.endsWith('.mkv') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.avi') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.mov');
      if (!video) continue;
      if (pick == null || f.size > pick.size) pick = f;
    }
    pick ??= _files.isNotEmpty ? _files.first : null;
    final base =
        pick != null ? p.basenameWithoutExtension(pick.name) : 'torrent';
    return '${_sanitizeFileBase(base)}.torrent';
  }

  Future<void> _saveTorrentFile() async {
    final magnet = _magnetController.text.trim();
    if (!magnet.startsWith('magnet:')) {
      setState(() => _error = 'Enter a magnet link first');
      return;
    }
    final hash = _btihFromMagnet(magnet);
    if (hash == null) {
      setState(() => _error = 'Magnet has no btih (info hash)');
      return;
    }
    if (_files.isEmpty || _torrentId == null) {
      setState(() => _error = 'Fetch torrent metadata before saving');
      return;
    }

    final suggested = _suggestedTorrentSaveName();
    final pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save torrent file',
      fileName: suggested,
      type: FileType.any,
    );
    if (!mounted || pickedPath == null) return;

    setState(() {
      _savingTorrent = true;
      _error = null;
    });

    try {
      Uint8List? torrentBytes = await _downloadTorrentFromMirrors(hash);
      final targetTorrent = File(pickedPath);
      if (torrentBytes != null &&
          torrentBytes.isNotEmpty &&
          _looksLikeTorrentBytes(torrentBytes)) {
        await targetTorrent.writeAsBytes(torrentBytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved .torrent to ${p.basename(pickedPath)}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        var magnetPath = pickedPath;
        if (magnetPath.toLowerCase().endsWith('.torrent')) {
          magnetPath =
              '${magnetPath.substring(0, magnetPath.length - 8)}.magnet';
        } else if (!magnetPath.toLowerCase().endsWith('.magnet')) {
          magnetPath = '$magnetPath.magnet';
        }
        await File(magnetPath).writeAsString(magnet, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Online .torrent cache unavailable — saved magnet link as ${p.basename(magnetPath)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _savingTorrent = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mkv') || lower.endsWith('.mp4') || lower.endsWith('.avi') ||
        lower.endsWith('.webm') || lower.endsWith('.mov')) {
      return Icons.movie_outlined;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.flac') || lower.endsWith('.aac') ||
        lower.endsWith('.ogg') || lower.endsWith('.wav')) {
      return Icons.music_note_outlined;
    }
    if (lower.endsWith('.srt') || lower.endsWith('.ass') || lower.endsWith('.sub') ||
        lower.endsWith('.vtt')) {
      return Icons.subtitles_outlined;
    }
    if (lower.endsWith('.nfo') || lower.endsWith('.txt')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, color: AppTheme.accentColor, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Magnet Player',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Input area ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _magnetController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Paste magnet link here...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: AppTheme.bgCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primaryColor),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste_rounded, color: Colors.white38),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null) {
                              _magnetController.text = data!.text!;
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : () => _fetchFiles(),
                      icon: _loading
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search_rounded, size: 20),
                      label: Text(_loading ? 'Loading...' : 'Fetch',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Error ──
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
              ),

            // ── Loading indicator ──
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primaryColor),
                    const SizedBox(height: 16),
                    Text('Fetching torrent metadata...',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
                  ],
                ),
              ),

            // ── File list ──
            if (_files.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Text('${_files.length} files',
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _savingTorrent ? null : _saveTorrentFile,
                      icon: _savingTorrent
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt_rounded, size: 18),
                      label: Text(_savingTorrent ? 'Saving…' : 'Save torrent…'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Total: ${_formatSize(_files.fold<int>(0, (sum, f) => sum + f.size))}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final isStreaming = _streamingIndex == file.index;
                    final isVideo = file.isStreamable;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: TvInkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: isVideo && !isStreaming ? () => _playFile(file) : null,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isStreaming
                                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                  : AppTheme.bgCard,
                              border: Border.all(
                                color: isStreaming
                                    ? AppTheme.primaryColor.withValues(alpha: 0.4)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _fileIcon(file.name),
                                  color: isVideo
                                      ? AppTheme.accentColor
                                      : Colors.white24,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        file.name,
                                        style: TextStyle(
                                          color: isVideo ? Colors.white : Colors.white38,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatSize(file.size),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.35),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isStreaming)
                                  const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppTheme.primaryColor),
                                  )
                                else if (isVideo)
                                  const Icon(Icons.play_circle_outlined,
                                      color: AppTheme.primaryColor, size: 28),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // ── Empty state ──
            if (!_loading && _files.isEmpty && _error == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_rounded,
                          size: 64, color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'Paste a magnet link and tap Fetch\nto browse and play files',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
