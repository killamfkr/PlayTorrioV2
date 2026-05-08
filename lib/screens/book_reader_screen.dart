import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../api/books_service.dart';
import '../services/book_progress_service.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';

class BookReaderScreen extends StatefulWidget {
  final File file;
  final String title;
  final BookResult? bookResult;
  final int initialChapter;

  const BookReaderScreen({
    super.key,
    required this.file,
    required this.title,
    this.bookResult,
    this.initialChapter = 0,
  });

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen>
    with SingleTickerProviderStateMixin {
  // ── Core state ─────────────────────────────────────────────────────────────
  List<_Chapter> _chapters = [];
  int _currentChapter = 0;
  InAppWebViewController? _webController;
  bool _loading = true;
  String? _error;
  int _fontSize = 16;
  bool _isDarkMode = true;
  bool _showToolbar = true;

  // ── Focus-mode state ───────────────────────────────────────────────────────
  bool _focusMode = false;
  int _focusLineCount = 0;
  int _focusLineIndex = 0;

  // ── Focus node for keyboard events ─────────────────────────────────────────
  late final FocusNode _keyFocus;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _keyFocus = FocusNode();
    debugPrint('[BookReader] initState — file: ${widget.file.path}');
    debugPrint('[BookReader] file exists: ${widget.file.existsSync()}');
    if (widget.file.existsSync()) {
      debugPrint('[BookReader] file size: ${widget.file.lengthSync()} bytes');
    }
    _extractAndParse();
  }

  @override
  void dispose() {
    _saveProgress();
    _keyFocus.dispose();
    _webController = null;
    super.dispose();
  }

  // ── Progress persistence ───────────────────────────────────────────────────

  void _saveProgress() {
    if (widget.bookResult == null || _chapters.isEmpty) return;
    BookProgressService.instance.saveProgress(
      book: widget.bookResult!,
      chapter: _currentChapter,
      scrollFraction: _lastScrollFraction,
      filePath: widget.file.path,
    );
  }

  double _lastScrollFraction = 0.0;

  // ── EPUB extraction & parsing ──────────────────────────────────────────────

  Future<void> _extractAndParse() async {
    try {
      final bytes = await widget.file.readAsBytes();
      debugPrint('[BookReader] read ${bytes.length} bytes');

      final archive = ZipDecoder().decodeBytes(bytes);
      debugPrint('[BookReader] ZIP: ${archive.length} entries');

      final normalPath =
          widget.file.path.replaceAll('/', Platform.pathSeparator);
      final epubName = normalPath
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.epub', '');
      final extractDir = Directory(
        '${widget.file.parent.path}${Platform.pathSeparator}epub_$epubName',
      );

      if (!extractDir.existsSync()) {
        extractDir.createSync(recursive: true);
        for (final entry in archive) {
          final entryName = entry.name.replaceAll('\\', '/');
          if (entryName.endsWith('/') || !entry.isFile) {
            final dir = Directory('${extractDir.path}/$entryName');
            if (!dir.existsSync()) dir.createSync(recursive: true);
            continue;
          }
          final outPath = '${extractDir.path}/$entryName';
          final f = File(outPath);
          f.createSync(recursive: true);
          f.writeAsBytesSync(entry.content as List<int>);
        }
        debugPrint('[BookReader] extracted → ${extractDir.path}');
      } else {
        debugPrint('[BookReader] cached → ${extractDir.path}');
      }

      // container.xml → OPF
      final containerFile =
          File('${extractDir.path}/META-INF/container.xml');
      if (!containerFile.existsSync()) {
        throw Exception('Invalid EPUB — META-INF/container.xml missing');
      }
      final containerXml =
          XmlDocument.parse(await containerFile.readAsString());
      final opfPath = containerXml
          .findAllElements('rootfile')
          .first
          .getAttribute('full-path')!;
      debugPrint('[BookReader] OPF: $opfPath');

      final opfFile = File('${extractDir.path}/$opfPath');
      final opfXml = XmlDocument.parse(await opfFile.readAsString());
      final opfDir = _dirName(opfPath);

      // Manifest
      final manifestEl = opfXml.findAllElements('manifest').first;
      final manifest = <String, _ManifestItem>{};
      for (final el in manifestEl.findAllElements('item')) {
        final id = el.getAttribute('id');
        final href = el.getAttribute('href');
        final mt = el.getAttribute('media-type') ?? '';
        final props = el.getAttribute('properties') ?? '';
        if (id != null && href != null) {
          manifest[id] = _ManifestItem(
            id: id,
            href: href,
            mediaType: mt,
            properties: props,
          );
        }
      }

      // TOC labels
      final tocLabels = <String, String>{};
      final spineEl = opfXml.findAllElements('spine').first;

      // EPUB 2 NCX
      final tocId = spineEl.getAttribute('toc');
      if (tocId != null && manifest.containsKey(tocId)) {
        final ncxHref = manifest[tocId]!.href;
        final ncxPath = opfDir.isEmpty ? ncxHref : '$opfDir/$ncxHref';
        final ncxFile = File('${extractDir.path}/$ncxPath');
        if (ncxFile.existsSync()) {
          try {
            final ncx = XmlDocument.parse(await ncxFile.readAsString());
            for (final np in ncx.findAllElements('navPoint')) {
              final label =
                  np.findAllElements('text').firstOrNull?.innerText;
              final src = np
                  .findAllElements('content')
                  .firstOrNull
                  ?.getAttribute('src');
              if (label != null && src != null) {
                final clean = src.contains('#')
                    ? src.substring(0, src.indexOf('#'))
                    : src;
                tocLabels.putIfAbsent(clean, () => label.trim());
              }
            }
          } catch (_) {}
        }
      }

      // EPUB 3 nav
      for (final item in manifest.values) {
        if (item.properties.contains('nav')) {
          final navPath =
              opfDir.isEmpty ? item.href : '$opfDir/${item.href}';
          final navFile = File('${extractDir.path}/$navPath');
          if (navFile.existsSync()) {
            try {
              final navHtml = await navFile.readAsString();
              final re = RegExp(
                  r'<a[^>]+href="([^"]*)"[^>]*>(.*?)</a>',
                  dotAll: true);
              for (final m in re.allMatches(navHtml)) {
                final href = m.group(1)!;
                final title = m
                    .group(2)!
                    .replaceAll(RegExp(r'<[^>]*>'), '')
                    .trim();
                final clean = href.contains('#')
                    ? href.substring(0, href.indexOf('#'))
                    : href;
                if (title.isNotEmpty) {
                  tocLabels.putIfAbsent(clean, () => title);
                }
              }
            } catch (_) {}
          }
          break;
        }
      }

      debugPrint('[BookReader] TOC: ${tocLabels.length} labels');

      // Spine → chapters
      final chapters = <_Chapter>[];
      for (final ref in spineEl.findAllElements('itemref')) {
        final idref = ref.getAttribute('idref')!;
        final item = manifest[idref];
        if (item == null) continue;
        if (!item.mediaType.contains('html') &&
            !item.mediaType.contains('xml')) {
          continue;
        }
        final href = item.href;
        final fullPath = opfDir.isEmpty ? href : '$opfDir/$href';
        final filePath = '${extractDir.path}/$fullPath';
        final title = tocLabels[href] ?? tocLabels[fullPath] ?? '';
        chapters.add(_Chapter(
          filePath: filePath.replaceAll('\\', '/'),
          title:
              title.isNotEmpty ? title : 'Chapter ${chapters.length + 1}',
          href: href,
        ));
      }

      debugPrint('[BookReader] spine: ${chapters.length} chapters');
      if (chapters.isEmpty) throw Exception('No readable chapters found');

      if (mounted) {
        setState(() {
          _chapters = chapters;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('[BookReader] PARSE ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // ── Chapter loading ────────────────────────────────────────────────────────

  void _loadChapter(int index) {
    if (index < 0 || index >= _chapters.length || _webController == null) {
      return;
    }
    // Save progress before leaving current chapter
    _saveProgress();

    final chapter = _chapters[index];
    setState(() {
      _currentChapter = index;
      _lastScrollFraction = 0.0;
      _focusLineIndex = 0;
      _focusLineCount = 0;
    });
    final uri = Uri.file(chapter.filePath, windows: Platform.isWindows);
    debugPrint('[BookReader] → ch $index "${chapter.title}" ($uri)');
    _webController!.loadUrl(
      urlRequest: URLRequest(url: WebUri(uri.toString())),
    );
  }

  // ── Font-size helper (safe in focus mode) ───────────────────────────────

  void _applyFontSize() {
    if (_focusMode) {
      // Only update font-size; don't re-inject full theme which would
      // override focus-mode colours.
      _webController?.evaluateJavascript(source: '''
(function(){
  document.body.style.fontSize='${_fontSize}px';
})();
''');
    } else {
      _injectTheme();
    }
  }

  // ── Theme injection ────────────────────────────────────────────────────────

  void _injectTheme() {
    final bg = _isDarkMode ? '#0B0B12' : '#ffffff';
    final fg = _isDarkMode ? '#e0e0e0' : '#1a1a1a';
    final link = _isDarkMode ? '#bb86fc' : '#6200ee';
    final border = _isDarkMode ? '#333' : '#ccc';

    _webController?.evaluateJavascript(source: '''
(function(){
  var s=document.getElementById('_rt');
  if(!s){s=document.createElement('style');s.id='_rt';document.head.appendChild(s);}
  s.textContent=
    'body,html{background:$bg!important;color:$fg!important;'
   +'font-size:${_fontSize}px!important;line-height:1.8!important;'
   +'padding:20px!important;margin:0!important;'
   +'font-family:Georgia,serif!important;'
   +'word-wrap:break-word!important;overflow-wrap:break-word!important}'
   +'*{color:inherit!important;border-color:$border!important}'
   +'a{color:$link!important}'
   +'img{max-width:100%!important;height:auto!important}'
   +'pre,code{white-space:pre-wrap!important}'
   +'table{max-width:100%!important}';
})();
''');

    _webController?.evaluateJavascript(source: '''
(function(){
  if(window._rtBound) return;
  window._rtBound=true;
  document.addEventListener('click',function(e){
    if(!e.target.closest('a')){
      window.flutter_inappwebview.callHandler('toggleBar');
    }
  });
})();
''');
  }

  // ── Focus-mode JS injection ────────────────────────────────────────────────
  //
  // Per-text-node approach: for each text node, measure char Y positions to
  // find visual line breaks, then split forward and wrap each line in a span.
  // Result: each _fl span = exactly one rendered screen line.

  void _injectFocusMode() {
    _webController?.evaluateJavascript(source: '''
(function(){
  if(window._focusInit) return;
  window._focusInit=true;

  // ── Collect text nodes ─────────────────────────────────────────────────
  var tns=[];
  (function collect(n){
    if(n.nodeType===3){
      if(n.textContent.length>0) tns.push(n);
    } else if(n.nodeType===1 && !/^(SCRIPT|STYLE|NOSCRIPT|SVG)\$/.test(n.tagName)){
      for(var c=n.firstChild;c;c=c.nextSibling) collect(c);
    }
  })(document.body);

  var lineSpans=[];
  var range=document.createRange();
  var TH=3; // Y-tolerance in px

  // ── Process each text node independently ───────────────────────────────
  for(var i=0;i<tns.length;i++){
    var tn=tns[i];
    if(tn.length===0) continue;

    // Measure Y of each character
    var breaks=[0]; // indices where new visual lines start
    var prevY=null;

    for(var c=0;c<tn.length;c++){
      range.setStart(tn,c);
      range.setEnd(tn,Math.min(c+1,tn.length));
      var rects=range.getClientRects();
      if(rects.length===0) continue;
      var y=Math.round(rects[0].top);
      if(prevY===null){ prevY=y; continue; }
      if(Math.abs(y-prevY)>TH){
        breaks.push(c);
        prevY=y;
      }
    }

    // If only one line, wrap the whole node
    if(breaks.length===1){
      if(tn.textContent.trim().length>0){
        var s=document.createElement('span');
        s.className='_fl';
        tn.parentNode.insertBefore(s,tn);
        s.appendChild(tn);
        lineSpans.push(s);
      }
      continue;
    }

    // Multiple lines: split forward at break points
    // breaks = [0, b1, b2, ...] — indices into the ORIGINAL text
    // We split from the end to preserve indices
    var pieces=[]; // text nodes, one per visual line
    var currentNode=tn;

    // Split at each break point (skip index 0)
    // Work forward: split at offset relative to currentNode
    var consumed=0;
    for(var b=1;b<breaks.length;b++){
      var splitAt=breaks[b]-consumed;
      if(splitAt>0 && splitAt<currentNode.length){
        var rest=currentNode.splitText(splitAt);
        pieces.push(currentNode);
        consumed=breaks[b];
        currentNode=rest;
      }
    }
    pieces.push(currentNode); // last piece

    // Wrap each piece in a span
    for(var p=0;p<pieces.length;p++){
      var piece=pieces[p];
      if(piece.textContent.trim().length===0) continue;
      var s=document.createElement('span');
      s.className='_fl';
      piece.parentNode.insertBefore(s,piece);
      s.appendChild(piece);
      lineSpans.push(s);
    }
  }

  window._focusLines=lineSpans;

  // ── Merge pass — group spans on the same visual line ───────────────────
  // Multiple text nodes (e.g. plain + <em> + plain) on one screen line
  // become separate spans. Group them by Y so they highlight together.
  var groups=[];  // each group = array of span indices
  var usedY=null;
  var TH2=4;

  for(var g=0;g<lineSpans.length;g++){
    var rect=lineSpans[g].getBoundingClientRect();
    var y=Math.round(rect.top);
    if(groups.length===0 || Math.abs(y-usedY)>TH2){
      groups.push([g]);
      usedY=y;
    } else {
      groups[groups.length-1].push(g);
    }
  }

  window._focusGroups=groups;
  window.flutter_inappwebview.callHandler('focusLineCount',groups.length);

  // ── Style ──────────────────────────────────────────────────────────────
  var fs=document.getElementById('_focus_style');
  if(!fs){fs=document.createElement('style');fs.id='_focus_style';document.head.appendChild(fs);}
  fs.textContent=
    'body,html{background:#111118!important;overflow-x:hidden!important}'
   +'span._fl{color:#444!important;opacity:0.35;transition:color 0.25s ease,opacity 0.25s ease,background 0.25s ease,box-shadow 0.25s ease,text-shadow 0.25s ease;display:inline;border-radius:6px;padding:2px 0}'
   +'span._fl._active,span._fl._active *{color:#e8e8e8!important;opacity:1.0!important;background:linear-gradient(135deg,rgba(255,255,255,0.10) 0%,rgba(255,255,255,0.04) 100%)!important;border:1px solid rgba(255,255,255,0.12);box-shadow:0 0 0 6px rgba(255,255,255,0.05),0 2px 12px rgba(0,0,0,0.3),inset 0 1px 0 rgba(255,255,255,0.08);backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);-webkit-box-decoration-break:clone;box-decoration-break:clone;text-shadow:0 0 20px rgba(255,255,255,0.15)}';

  // ── Highlight first line group ─────────────────────────────────────────
  if(groups.length>0){
    groups[0].forEach(function(idx){ lineSpans[idx].classList.add('_active'); });
    lineSpans[groups[0][0]].scrollIntoView({behavior:'smooth',block:'center'});
  }
})();
''');
  }

  void _focusMoveTo(int index) {
    if (_focusLineCount <= 0) return;
    final clamped = index.clamp(0, _focusLineCount - 1);
    setState(() => _focusLineIndex = clamped);

    _webController?.evaluateJavascript(source: '''
(function(){
  var lines=window._focusLines;
  var groups=window._focusGroups;
  if(!lines||!groups) return;

  // Remove all active
  for(var i=0;i<lines.length;i++) lines[i].classList.remove('_active');

  // Activate all spans in the target group
  var grp=groups[$clamped];
  if(grp){
    grp.forEach(function(idx){ lines[idx].classList.add('_active'); });
    lines[grp[0]].scrollIntoView({behavior:'smooth',block:'center'});
  }
})();
''');
  }

  void _exitFocusMode() {
    _webController?.evaluateJavascript(source: '''
(function(){
  window._focusInit=false;
  var fs=document.getElementById('_focus_style');
  if(fs) fs.remove();
  var lines=window._focusLines||[];
  for(var i=0;i<lines.length;i++){
    lines[i].classList.remove('_active');
    lines[i].style.color='';
    lines[i].style.opacity='';
  }
  window._focusLines=null;
})();
''');
    setState(() {
      _focusMode = false;
      _focusLineIndex = 0;
      _focusLineCount = 0;
    });
    _injectTheme();
  }

  void _toggleFocusMode() {
    if (_focusMode) {
      _exitFocusMode();
    } else {
      setState(() => _focusMode = true);
      _injectFocusMode();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _dirName(String p) {
    final i = p.lastIndexOf('/');
    return i >= 0 ? p.substring(0, i) : '';
  }

  bool get _isPhone {
    final s = MediaQuery.of(context).size.shortestSide;
    return s < 600;
  }

  Color get _iconColor =>
      _isDarkMode ? Colors.white70 : Colors.black54;

  Color get _textColor =>
      _isDarkMode ? Colors.white : Colors.black87;

  Color get _subtextColor =>
      _isDarkMode ? Colors.white38 : Colors.black38;

  Color get _barBg =>
      _isDarkMode ? const Color(0xFF0B0B12) : Colors.white;

  Color get _scaffoldBg =>
      _isDarkMode ? const Color(0xFF0B0B12) : Colors.white;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _focusMode ? const Color(0xFF111118) : _scaffoldBg,
      body: KeyboardListener(
        focusNode: _keyFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildReader(),
      ),
    );
  }

  // ── Keyboard handler ───────────────────────────────────────────────────────

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    if (_focusMode) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _focusMoveTo(_focusLineIndex + 1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _focusMoveTo(_focusLineIndex - 1);
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _exitFocusMode();
      }
    } else {
      // Normal mode: left/right for chapters
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          _currentChapter > 0) {
        _loadChapter(_currentChapter - 1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          _currentChapter < _chapters.length - 1) {
        _loadChapter(_currentChapter + 1);
      }
    }
  }

  // ── Loading / Error ────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Container(
      color: const Color(0xFF0B0B12),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryColor),
            SizedBox(height: 16),
            Text('Opening book…',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text('Failed to open book',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reader ─────────────────────────────────────────────────────────────────

  Widget _buildReader() {
    return Stack(
      children: [
        // ── WebView ────────────────────────────────────────────────────────
        Positioned.fill(
          child: InAppWebView(
            initialSettings: InAppWebViewSettings(
              isInspectable: kDebugMode,
              javaScriptEnabled: true,
              transparentBackground: false,
              supportZoom: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              verticalScrollBarEnabled: false,
              horizontalScrollBarEnabled: false,
              disableVerticalScroll: false,
              disableHorizontalScroll: true,
            ),
            onWebViewCreated: (controller) {
              debugPrint('[BookReader] WebView created');
              _webController = controller;

              // Toggle toolbar
              controller.addJavaScriptHandler(
                handlerName: 'toggleBar',
                callback: (_) {
                  if (mounted && !_focusMode) {
                    setState(() => _showToolbar = !_showToolbar);
                  }
                },
              );

              // Focus-mode receives line count
              controller.addJavaScriptHandler(
                handlerName: 'focusLineCount',
                callback: (args) {
                  final count = (args.isNotEmpty ? args[0] : 0) as int;
                  debugPrint('[BookReader] focus lines: $count');
                  if (mounted) {
                    setState(() {
                      _focusLineCount = count;
                      _focusLineIndex = 0;
                    });
                  }
                },
              );

              // ── Track scroll for progress saving ──────────────────
              controller.addJavaScriptHandler(
                handlerName: 'scrollProgress',
                callback: (args) {
                  if (args.isNotEmpty) {
                    _lastScrollFraction = (args[0] as num).toDouble();
                  }
                },
              );

              _loadChapter(widget.initialChapter);
            },
            onLoadStop: (controller, url) async {
              debugPrint('[BookReader] loaded: $url');
              if (_focusMode) {
                _injectFocusMode();
              } else {
                _injectTheme();
              }
              // ── Inject scroll tracker ────────────────────────────────────
              controller.evaluateJavascript(source: '''
(function(){
  if(window._scrollBound) return;
  window._scrollBound=true;
  var t=null;
  window.addEventListener('scroll',function(){
    clearTimeout(t);
    t=setTimeout(function(){
      var h=Math.max(document.body.scrollHeight-window.innerHeight,1);
      var f=window.scrollY/h;
      window.flutter_inappwebview.callHandler('scrollProgress',f);
    },300);
  });
})();
''');
            },
            onConsoleMessage: (controller, msg) {
              if (kDebugMode) {
                debugPrint('[BookReader-JS] ${msg.message}');
              }
            },
            onReceivedError: (controller, req, err) {
              debugPrint('[BookReader] webview error: ${err.description}');
            },
          ),
        ),

        // ── Focus-mode tap zones (phones) ──────────────────────────────────
        if (_focusMode)
          Positioned.fill(
            child: Column(
              children: [
                // Top half → previous line
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _focusMoveTo(_focusLineIndex - 1),
                    child: const SizedBox.expand(),
                  ),
                ),
                // Bottom half → next line
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _focusMoveTo(_focusLineIndex + 1),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),

        // ── Focus-mode exit button & progress (always visible) ─────────────
        if (_focusMode)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    _iconBtn(
                      Icons.close_rounded,
                      onTap: _exitFocusMode,
                      color: Colors.white54,
                    ),
                    const Spacer(),
                    if (_focusLineCount > 0)
                      Text(
                        '${_focusLineIndex + 1} / $_focusLineCount',
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 11),
                      ),
                    const Spacer(),
                    // Chapter navigation in focus mode
                    _iconBtn(
                      Icons.chevron_left_rounded,
                      onTap: _currentChapter > 0
                          ? () => _loadChapter(_currentChapter - 1)
                          : null,
                      color: _currentChapter > 0
                          ? Colors.white54
                          : Colors.white12,
                    ),
                    _iconBtn(
                      Icons.chevron_right_rounded,
                      onTap: _currentChapter < _chapters.length - 1
                          ? () => _loadChapter(_currentChapter + 1)
                          : null,
                      color: _currentChapter < _chapters.length - 1
                          ? Colors.white54
                          : Colors.white12,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Top bar (normal mode) ──────────────────────────────────────────
        if (_showToolbar && !_focusMode)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _barBg.withValues(alpha: 0.97),
                    _barBg.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: _iconColor),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                color: _textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_chapters.isNotEmpty)
                              Text(
                                _chapters[_currentChapter].title,
                                style: TextStyle(
                                    color: _subtextColor, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Focus mode toggle
                      IconButton(
                        icon: Icon(Icons.center_focus_strong_rounded,
                            color: _iconColor),
                        onPressed: _toggleFocusMode,
                        tooltip: 'Focus mode',
                      ),
                      // Dark/Light toggle
                      IconButton(
                        icon: Icon(
                          _isDarkMode
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          color: _iconColor,
                        ),
                        onPressed: () {
                          setState(() => _isDarkMode = !_isDarkMode);
                          _injectTheme();
                        },
                        tooltip:
                            _isDarkMode ? 'Light mode' : 'Dark mode',
                      ),
                      // Chapters
                      if (_chapters.length > 1)
                        IconButton(
                          icon:
                              Icon(Icons.list_rounded, color: _iconColor),
                          onPressed: _showChapterSheet,
                          tooltip: 'Chapters',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Bottom bar (normal mode) ─────────────────────────────────────
        if (_showToolbar && !_focusMode)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    _barBg.withValues(alpha: 0.97),
                    _barBg.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _isPhone ? 12 : 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pill(
                        icon: Icons.chevron_left_rounded,
                        onTap: _currentChapter > 0
                            ? () => _loadChapter(_currentChapter - 1)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      _pill(
                        icon: Icons.text_decrease_rounded,
                        onTap: _fontSize > 10
                            ? () {
                                setState(() => _fontSize -= 2);
                                _applyFontSize();
                              }
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Text('${_fontSize}px',
                          style: TextStyle(
                              color: _subtextColor, fontSize: 11)),
                      const SizedBox(width: 4),
                      _pill(
                        icon: Icons.text_increase_rounded,
                        onTap: _fontSize < 56
                            ? () {
                                setState(() => _fontSize += 2);
                                _applyFontSize();
                              }
                            : null,
                      ),
                      const SizedBox(width: 12),
                      _pill(
                        icon: Icons.chevron_right_rounded,
                        onTap: _currentChapter < _chapters.length - 1
                            ? () => _loadChapter(_currentChapter + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _pill({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: (_isDarkMode ? Colors.white : Colors.black)
          .withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(24),
      child: TvInkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon,
              color: onTap != null ? _iconColor : _iconColor.withValues(alpha: 0.3),
              size: _isPhone ? 20 : 22),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon,
      {VoidCallback? onTap, Color? color}) {
    return IconButton(
      icon: Icon(icon, color: color ?? _iconColor, size: 20),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showChapterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  const Icon(Icons.list_rounded,
                      color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 10),
                  Text('Chapters (${_chapters.length})',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _chapters.length,
                itemBuilder: (_, i) {
                  final chapter = _chapters[i];
                  final isCurrent = i == _currentChapter;
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor:
                        AppTheme.primaryColor.withValues(alpha: 0.1),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: isCurrent
                          ? AppTheme.primaryColor
                          : AppTheme.primaryColor
                              .withValues(alpha: 0.2),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: isCurrent
                              ? Colors.white
                              : AppTheme.primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      chapter.title,
                      style: TextStyle(
                        color: isCurrent
                            ? AppTheme.primaryColor
                            : Colors.white,
                        fontSize: 13,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _loadChapter(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Models ───────────────────────────────────────────────────────────────────

class _Chapter {
  final String filePath;
  final String title;
  final String href;
  const _Chapter({
    required this.filePath,
    required this.title,
    required this.href,
  });
}

class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final String properties;
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });
}
