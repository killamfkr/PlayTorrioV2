import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/hardcoded_channels.dart';
import '../data/iptv_network.dart';
import '../data/models.dart';
import '../data/storage.dart';

enum IptvView {
  portalList,
  sectionPick,
  browser,
  episodeList,
  channelsHub,
  channelResults,
}

/// Central controller for the entire PT IPTV experience.
/// Mirrors IptvViewModel.kt; uses ChangeNotifier for Flutter rebuilds.
class IptvController extends ChangeNotifier {
  // ── Top-level view ──
  IptvView view = IptvView.portalList;

  // ── Portal-list state ──
  bool isScraping = false;
  String statusText = '';
  List<VerifiedPortal> verified = const [];
  bool canGetMore = false;
  String? _scrapeAfter;
  /// Set of credKeys (user|pass) already verified — used to dedupe portals.
  /// Same credentials on a different URL still counts as a duplicate.
  final Set<String> _verifiedKeys = {};

  /// Untested portals scraped on previous Get-More presses.
  /// Consumed first before scraping a fresh page — never wasted.
  final List<IptvPortal> _pendingPortals = [];
  final Set<String> _pendingKeys = {};

  /// Favorite portal keys — pinned to the top of the list.
  final Set<String> _favoritePortals = {};
  bool isFavoritePortal(String key) => _favoritePortals.contains(key);

  // Manual edit
  bool editMode = false;
  final Set<String> selected = {};
  bool showAddDialog = false;
  bool isAdding = false;
  String? addError;

  // ── Browsing state ──
  VerifiedPortal? activePortal;
  IptvSection? activeSection;
  IptvStream? activeSeries;

  bool isLoading = false;
  List<IptvCategory> categories = const [];
  List<IptvStream> browserAllStreams = const [];
  List<IptvEpisode> episodes = const [];
  String? error;

  String? browserSelectedCategoryId;
  String browserSearch = '';

  // ── Live alive checking ──
  bool liveOnly = false;
  Set<String> aliveStreamIds = const {};
  bool isVerifyingAlive = false;
  int aliveChecked = 0;
  int aliveTotal = 0;
  int aliveCount = 0;
  int? aliveCheckedAt;
  bool _aliveCancel = false;

  // ── EPG cache (live section only) ──
  /// Memoised `get_short_epg` results per stream for the current portal+section.
  /// Key = streamId. `null` value means "fetch in flight or finished with no
  /// data"; absent key means "not yet requested". Cleared on portal/section
  /// change. Wrapped in a Future so concurrent card builds dedupe to one call.
  final Map<String, Future<List<EpgEntry>>> _epgCache = {};

  /// Lazy EPG fetch for a live stream. Returns the cached future (or fires a
  /// new request) so multiple `_StreamCard`s for the same id share one call.
  /// Safe to call from `FutureBuilder` — the Future is stable across rebuilds.
  Future<List<EpgEntry>> epgFor(IptvStream s) {
    final p = activePortal;
    if (p == null || s.kind != 'live' || s.streamId.isEmpty) {
      return Future.value(const []);
    }
    return _epgCache.putIfAbsent(
      s.streamId,
      () => IptvClient.shortEpg(p.portal, s.streamId, limit: 2),
    );
  }

  /// EPG cache for ChannelHit cards (Channels Hub). Keyed by
  /// `portal.key|streamId` because hits come from many different portals.
  /// Lives for the controller's lifetime — re-running a scan on the same
  /// channel typically yields overlapping hits, so reuse is desirable.
  final Map<String, Future<List<EpgEntry>>> _hitEpgCache = {};

  /// Lazy EPG fetch for a hardcoded-channel hit. Same dedupe semantics as
  /// [epgFor] but keyed per (portal, stream).
  Future<List<EpgEntry>> epgForHit(ChannelHit h) {
    if (h.stream.kind != 'live' || h.stream.streamId.isEmpty) {
      return Future.value(const []);
    }
    final key = '${h.portal.key}|${h.stream.streamId}';
    return _hitEpgCache.putIfAbsent(
      key,
      () => IptvClient.shortEpg(h.portal.portal, h.stream.streamId, limit: 2),
    );
  }

  // ── Channels Hub ──
  HardcodedChannel? activeHardcoded;
  String channelStatus = '';
  bool channelIsRunning = false;
  List<ChannelHit> channelResults = const [];
  bool _channelCancel = false;

  /// Favorite channel-hit URLs per channelId — pinned to the top.
  final Map<String, Set<String>> _favoriteHits = {};
  bool isFavoriteHit(String channelId, ChannelHit h) =>
      _favoriteHits[channelId]?.contains(h.streamUrl) ?? false;

  // Per-channel scan state (resumable)
  final Map<String, Set<String>> _channelAttempted = {}; // channelId → portalKey set
  final Map<String, String?> _channelCatalogAfter = {}; // channelId → catalog cursor
  final Map<String, List<IptvPortal>> _channelScrapedPool = {};

  /// Per-channel queue of UN-verified portals scraped from previous Get-More
  /// presses. Drained first before fetching a fresh catalog page so we never
  /// throw away portals we already paid the network cost to find.
  final Map<String, List<IptvPortal>> _channelPendingPortals = {};
  final Map<String, Set<String>> _channelPendingKeys = {};

  // ── Init ──
  Future<void> init() async {
    final stored = await IptvStore.load();
    _favoritePortals
      ..clear()
      ..addAll(await IptvStore.loadFavorites());
    verified = _sortFavoritesFirst(stored);
    _verifiedKeys
      ..clear()
      ..addAll(stored.map((v) => v.credKey));
    notifyListeners();
  }

  List<VerifiedPortal> _sortFavoritesFirst(List<VerifiedPortal> list) {
    final favs = <VerifiedPortal>[];
    final rest = <VerifiedPortal>[];
    for (final v in list) {
      if (_favoritePortals.contains(v.key)) {
        favs.add(v);
      } else {
        rest.add(v);
      }
    }
    return [...favs, ...rest];
  }

  List<ChannelHit> _sortHitsFavoritesFirst(
      String channelId, List<ChannelHit> list) {
    final favs = _favoriteHits[channelId] ?? const <String>{};
    if (favs.isEmpty) return list;
    final f = <ChannelHit>[];
    final r = <ChannelHit>[];
    for (final h in list) {
      if (favs.contains(h.streamUrl)) {
        f.add(h);
      } else {
        r.add(h);
      }
    }
    return [...f, ...r];
  }

  Future<void> toggleFavoritePortal(String key) async {
    if (_favoritePortals.contains(key)) {
      _favoritePortals.remove(key);
    } else {
      _favoritePortals.add(key);
    }
    verified = _sortFavoritesFirst(verified);
    await IptvStore.saveFavorites(_favoritePortals);
    notifyListeners();
  }

  Future<void> toggleFavoriteHit(ChannelHit h) async {
    final ch = activeHardcoded;
    if (ch == null) return;
    final set = _favoriteHits.putIfAbsent(ch.id, () => <String>{});
    if (set.contains(h.streamUrl)) {
      set.remove(h.streamUrl);
    } else {
      set.add(h.streamUrl);
    }
    channelResults = _sortHitsFavoritesFirst(ch.id, channelResults);
    await IptvChannelFavoritesStore.save(ch.id, set);
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Portal-list actions
  // ────────────────────────────────────────────────────────────────────────
  Future<void> scrape() async {
    if (isScraping) return;
    isScraping = true;
    statusText = 'Finding portals…';
    canGetMore = false;
    notifyListeners();
    await _scrapeAndVerify(reset: true);
  }

  Future<void> getMore() async {
    if (isScraping) return;
    isScraping = true;
    statusText = 'Searching for more…';
    notifyListeners();
    await _scrapeAndVerify(reset: false);
  }

  Future<void> _scrapeAndVerify({required bool reset}) async {
    try {
      // ── Step 1: only fetch a fresh catalog page when our local pending
      //         queue is empty (or caller forced a reset). This avoids
      //         throwing away portals we already scraped on a previous press.
      final shouldFetchPage = reset || _pendingPortals.isEmpty;
      ScrapePage? page;
      if (shouldFetchPage) {
        if (reset) {
          _scrapeAfter = null;
          _pendingPortals.clear();
          _pendingKeys.clear();
        }
        page = await IptvScraper.scrapeCatalogPage(
          maxResults: 50,
          after: _scrapeAfter,
        );
        _scrapeAfter = page.nextAfter;
        // Add only portals we haven't already verified or queued.
        // Dedup is by credentials (user|pass) — same login on a different
        // host still counts as a duplicate.
        for (final p in page.portals) {
          if (_verifiedKeys.contains(p.credKey)) continue;
          if (_pendingKeys.contains(p.credKey)) continue;
          _pendingKeys.add(p.credKey);
          _pendingPortals.add(p);
        }
      }

      if (_pendingPortals.isEmpty) {
        statusText = (page != null && page.portals.isEmpty)
            ? 'No portals found. Try Get More.'
            : 'All on this page already verified.';
        canGetMore = page?.hasMore ?? canGetMore;
        isScraping = false;
        notifyListeners();
        return;
      }

      statusText = 'Verifying ${_pendingPortals.length} portals…';
      notifyListeners();

      // Snapshot the queue: workers consume by index. We mark portals
      // attempted (-> remove from pending) as the verifier drains them.
      final snapshot = List<IptvPortal>.from(_pendingPortals);
      final newAlive = <VerifiedPortal>[];
      await IptvVerifier.verifyUntil(
        portals: snapshot,
        target: 5,
        onAttempted: (p) {
          if (_pendingKeys.remove(p.credKey)) {
            _pendingPortals.removeWhere((x) => x.credKey == p.credKey);
          }
        },
        onProgress: (c, t, a) {
          statusText = 'Verifying $c / $t  ·  alive $a';
          notifyListeners();
        },
        onAlive: (v) {
          if (_verifiedKeys.add(v.credKey)) {
            newAlive.add(v);
            verified = _sortFavoritesFirst([...verified, v]);
            notifyListeners();
          }
        },
      );

      if (newAlive.isNotEmpty) await IptvStore.save(verified);
      // Get-More is meaningful if either (a) we still have queued portals
      // we haven't verified yet, or (b) the catalog has more pages.
      canGetMore = _pendingPortals.isNotEmpty ||
          (page?.hasMore ?? canGetMore);
      statusText = newAlive.isEmpty
          ? (canGetMore
              ? 'No new live portals. Try Get More.'
              : 'No new live portals.')
          : 'Found ${newAlive.length} new portals.'
              '${_pendingPortals.isNotEmpty ? ' (${_pendingPortals.length} more queued)' : ''}';
    } catch (e) {
      statusText = 'Scrape failed: $e';
    } finally {
      isScraping = false;
      notifyListeners();
    }
  }

  Future<void> runVerification() async {
    if (verified.isEmpty) return;
    statusText = 'Re-checking saved portals…';
    notifyListeners();
    final updated = <VerifiedPortal>[];
    for (final v in verified) {
      final fresh = await IptvClient.verifyOrNull(v.portal);
      if (fresh != null) updated.add(fresh);
    }
    verified = _sortFavoritesFirst(updated);
    _verifiedKeys
      ..clear()
      ..addAll(updated.map((v) => v.credKey));
    await IptvStore.save(verified);
    statusText = '${updated.length} portals still alive.';
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Edit / select / delete portals
  // ────────────────────────────────────────────────────────────────────────
  void toggleEditMode() {
    editMode = !editMode;
    if (!editMode) selected.clear();
    notifyListeners();
  }

  void toggleSelect(String key) {
    if (selected.contains(key)) {
      selected.remove(key);
    } else {
      selected.add(key);
    }
    notifyListeners();
  }

  void toggleSelectAll() {
    if (selected.length == verified.length) {
      selected.clear();
    } else {
      selected
        ..clear()
        ..addAll(verified.map((v) => v.key));
    }
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    if (selected.isEmpty) return;
    final keep = verified.where((v) => !selected.contains(v.key)).toList();
    verified = keep;
    _verifiedKeys
      ..clear()
      ..addAll(keep.map((v) => v.credKey));
    selected.clear();
    editMode = false;
    await IptvStore.save(keep);
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Add manual portal
  // ────────────────────────────────────────────────────────────────────────
  void openAddDialog() {
    showAddDialog = true;
    addError = null;
    notifyListeners();
  }

  void dismissAddDialog() {
    if (isAdding) return;
    showAddDialog = false;
    addError = null;
    notifyListeners();
  }

  Future<void> addManual({
    required String url,
    required String username,
    required String password,
  }) async {
    final cleanUrl = normalizeUrl(url);
    if (cleanUrl.isEmpty || username.isEmpty || password.isEmpty) {
      addError = 'All fields required';
      notifyListeners();
      return;
    }
    isAdding = true;
    addError = null;
    notifyListeners();
    final p = IptvPortal(
      url: cleanUrl,
      username: username.trim(),
      password: password.trim(),
      source: 'Manual',
    );
    if (_verifiedKeys.contains(p.credKey)) {
      addError = 'Portal already added (same username & password)';
      isAdding = false;
      notifyListeners();
      return;
    }
    final v = await IptvClient.verifyOrNull(p);
    isAdding = false;
    if (v == null) {
      addError = 'Login failed — wrong credentials or dead portal.';
      notifyListeners();
      return;
    }
    verified = _sortFavoritesFirst([v, ...verified]);
    _verifiedKeys.add(v.credKey);
    await IptvStore.save(verified);
    showAddDialog = false;
    notifyListeners();
  }

  String normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Open portal / sections
  // ────────────────────────────────────────────────────────────────────────
  void openPortal(VerifiedPortal p) {
    activePortal = p;
    activeSection = null;
    activeSeries = null;
    view = IptvView.sectionPick;
    notifyListeners();
  }

  Future<void> openSection(IptvSection section) async {
    final p = activePortal;
    if (p == null) return;
    activeSection = section;
    view = IptvView.browser;
    isLoading = true;
    error = null;
    categories = const [];
    browserAllStreams = const [];
    browserSelectedCategoryId = null;
    browserSearch = '';
    aliveStreamIds = const {};
    aliveCheckedAt = null;
    _epgCache.clear();
    notifyListeners();
    try {
      final cats = await IptvClient.categories(p.portal, section);
      final streams = await IptvClient.streams(p.portal, section, '');
      categories = [const IptvCategory(id: '', name: 'All'), ...cats];
      browserAllStreams = streams;
      // Default to first non-"All" category if available, else "All"
      browserSelectedCategoryId = cats.isNotEmpty ? cats.first.id : '';

      if (section == IptvSection.live) {
        final key = IptvAliveStore.portalKey(p.portal);
        liveOnly = await IptvAliveStore.loadLiveOnly(key);
        final snap = await IptvAliveStore.load(key);
        if (snap != null) {
          aliveStreamIds = snap.aliveIds;
          aliveCheckedAt = snap.checkedAt;
        }
      } else {
        liveOnly = false;
      }
    } catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectBrowserCategory(String id) {
    browserSelectedCategoryId = id;
    notifyListeners();
  }

  void setBrowserSearch(String q) {
    browserSearch = q;
    notifyListeners();
  }

  Future<void> setLiveOnly(bool enabled) async {
    final p = activePortal;
    if (p == null) return;
    liveOnly = enabled;
    await IptvAliveStore.saveLiveOnly(IptvAliveStore.portalKey(p.portal), enabled);
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Alive checking (Live category)
  // ────────────────────────────────────────────────────────────────────────
  Future<void> startAliveCheck({bool force = false}) async {
    final p = activePortal;
    final section = activeSection;
    if (p == null || section != IptvSection.live) return;
    if (isVerifyingAlive) return;
    if (!force && aliveCheckedAt != null) return;

    final pkey = IptvAliveStore.portalKey(p.portal);
    final entries = browserAllStreams
        .map((s) => MapEntry(s.streamId, IptvClient.streamUrl(p.portal, s)))
        .toList();
    if (entries.isEmpty) return;

    isVerifyingAlive = true;
    aliveChecked = 0;
    aliveTotal = entries.length;
    aliveCount = 0;
    final aliveSet = <String>{};
    _aliveCancel = false;
    notifyListeners();

    await IptvAliveChecker.launchCheck(
      streams: entries,
      onResult: (id, alive) async {
        if (alive) aliveSet.add(id);
      },
      onProgress: (prog) async {
        aliveChecked = prog.checked;
        aliveTotal = prog.total;
        aliveCount = prog.alive;
        notifyListeners();
      },
      onDone: () async {
        aliveStreamIds = aliveSet;
        aliveCheckedAt = DateTime.now().millisecondsSinceEpoch;
        await IptvAliveStore.save(
          pkey,
          AliveSnapshot(
            checkedAt: aliveCheckedAt!,
            aliveIds: aliveSet,
          ),
        );
        isVerifyingAlive = false;
        notifyListeners();
      },
      isCancelled: () => _aliveCancel,
    );
    if (_aliveCancel) {
      isVerifyingAlive = false;
      notifyListeners();
    }
  }

  void stopAliveCheck() {
    _aliveCancel = true;
    isVerifyingAlive = false;
    notifyListeners();
  }

  Future<void> recheckAlive() async {
    final p = activePortal;
    if (p == null) return;
    await IptvAliveStore.clear(IptvAliveStore.portalKey(p.portal));
    aliveStreamIds = const {};
    aliveCheckedAt = null;
    notifyListeners();
    await startAliveCheck(force: true);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Series
  // ────────────────────────────────────────────────────────────────────────
  Future<void> openSeries(IptvStream s) async {
    final p = activePortal;
    if (p == null) return;
    activeSeries = s;
    view = IptvView.episodeList;
    isLoading = true;
    error = null;
    episodes = const [];
    notifyListeners();
    try {
      episodes = await IptvClient.seriesEpisodes(p.portal, s.streamId);
    } catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Channels Hub
  // ────────────────────────────────────────────────────────────────────────
  void openChannelsHub() {
    activeHardcoded = null;
    channelResults = const [];
    channelStatus = '';
    view = IptvView.channelsHub;
    notifyListeners();
  }

  void stopChannelSearch() {
    _channelCancel = true;
    channelIsRunning = false;
    channelStatus = 'Stopped.';
    notifyListeners();
  }

  Future<void> openHardcodedChannel(HardcodedChannel ch) async {
    activeHardcoded = ch;
    view = IptvView.channelResults;
    channelResults = const [];
    channelStatus = '';
    notifyListeners();
    final stored = await IptvChannelResultsStore.load(ch.id);
    final favs = await IptvChannelFavoritesStore.load(ch.id);
    _favoriteHits[ch.id] = favs;
    channelResults = _sortHitsFavoritesFirst(
      ch.id,
      stored
          .map((h) => ChannelHit(
              portal: VerifiedPortal(
                portal: IptvPortal(
                  url: h.portalUrl,
                  username: h.portalUser,
                  password: h.portalPass,
                  source: 'Saved',
                ),
                name: h.portalName,
                expiry: '',
                maxConnections: '1',
                activeConnections: '0',
              ),
              stream: IptvStream(
                streamId: h.streamId,
                name: h.streamName,
                icon: h.streamIcon,
                categoryId: h.streamCategoryId,
                containerExt: h.streamContainerExt,
                kind: h.streamKind,
              ),
              streamUrl: h.streamUrl,
            ))
        .toList(),
    );
    notifyListeners();
    if (channelResults.isEmpty) {
      await runChannelScan(ch);
    }
  }

  Future<void> searchAgainChannel() async {
    final ch = activeHardcoded;
    if (ch == null) return;
    _channelAttempted.remove(ch.id);
    _channelCatalogAfter.remove(ch.id);
    _channelScrapedPool.remove(ch.id);
    channelResults = const [];
    await IptvChannelResultsStore.clear(ch.id);
    notifyListeners();
    await runChannelScan(ch);
  }

  Future<void> getMoreChannels() async {
    final ch = activeHardcoded;
    if (ch == null) return;
    await runChannelScan(ch, scrapeMore: true);
  }

  Future<void> deleteChannelHit(int index) async {
    final ch = activeHardcoded;
    if (ch == null) return;
    if (index < 0 || index >= channelResults.length) return;
    final updated = [...channelResults]..removeAt(index);
    channelResults = updated;
    await _saveChannelHits(ch.id, updated);
    notifyListeners();
  }

  Future<void> deleteChannelHits(Set<int> indices) async {
    final ch = activeHardcoded;
    if (ch == null) return;
    final keep = <ChannelHit>[];
    for (var i = 0; i < channelResults.length; i++) {
      if (!indices.contains(i)) keep.add(channelResults[i]);
    }
    channelResults = keep;
    await _saveChannelHits(ch.id, keep);
    notifyListeners();
  }

  Future<void> _saveChannelHits(String channelId, List<ChannelHit> hits) async {
    final stored = hits
        .map((h) => StoredHit(
              portalUrl: h.portal.portal.url,
              portalUser: h.portal.portal.username,
              portalPass: h.portal.portal.password,
              portalName: h.portal.name,
              streamId: h.stream.streamId,
              streamName: h.stream.name,
              streamIcon: h.stream.icon,
              streamCategoryId: h.stream.categoryId,
              streamContainerExt: h.stream.containerExt,
              streamKind: h.stream.kind,
              streamUrl: h.streamUrl,
            ))
        .toList();
    await IptvChannelResultsStore.save(channelId, stored);
  }

  /// Mirrors the Android TV `runChannelScan` exactly:
  ///   1. Bootstrap: seed the per-channel pool with all saved verified portals.
  ///   2. (Only if [scrapeMore] OR no portals at all) fetch one fresh catalog
  ///      page and verify-until 5 are alive — newly verified portals are added
  ///      to the user's library *and* the pool.
  ///   3. Take the next 8 portals from the pool, mark them attempted.
  ///   4. **In parallel** fetch live streams from all 8 portals at once,
  ///      filter by channel keywords → one big candidate list (deduped by URL).
  ///   5. Hand the entire candidate list to the 24-wide alive-checker. Hits
  ///      stream in via callback and are saved/notified live.
  Future<void> runChannelScan(HardcodedChannel ch, {bool scrapeMore = false}) async {
    if (channelIsRunning) return;
    channelIsRunning = true;
    _channelCancel = false;
    notifyListeners();

    final attempted = _channelAttempted.putIfAbsent(ch.id, () => <String>{});
    final pool = _channelScrapedPool.putIfAbsent(ch.id, () => []);

    // ── 1. Bootstrap pool from globally-verified portals ──
    final poolKeys = pool.map((p) => p.key).toSet();
    for (final vp in verified) {
      if (!attempted.contains(vp.key) && !poolKeys.contains(vp.key)) {
        pool.add(vp.portal);
      }
    }

    // ── 2. Scrape fresh portals if requested or we're empty ──
    final needsBootstrap =
        verified.isEmpty && pool.every((p) => attempted.contains(p.key));
    if (scrapeMore || needsBootstrap) {
      final pendingQueue =
          _channelPendingPortals.putIfAbsent(ch.id, () => <IptvPortal>[]);
      final pendingKeys =
          _channelPendingKeys.putIfAbsent(ch.id, () => <String>{});

      // Drop anything from the queue that we've since verified or attempted
      // through another channel's scan.
      pendingQueue.removeWhere((p) =>
          _verifiedKeys.contains(p.credKey) || attempted.contains(p.key));
      pendingKeys
        ..clear()
        ..addAll(pendingQueue.map((p) => p.credKey));

      // Only fetch a new catalog page when the queue is empty — otherwise
      // we'd be throwing away the un-tested portals from previous presses.
      if (pendingQueue.isEmpty) {
        channelStatus = 'Looking for more portals…';
        notifyListeners();
        try {
          final after = _channelCatalogAfter[ch.id];
          final page = await IptvScraper.scrapeCatalogPage(
              maxResults: 60, after: after);
          _channelCatalogAfter[ch.id] = page.nextAfter;
          final knownKeys = {
            ...pool.map((p) => p.key),
            ...attempted,
          };
          for (final p in page.portals) {
            if (_verifiedKeys.contains(p.credKey)) continue;
            if (knownKeys.contains(p.key)) continue;
            if (pendingKeys.add(p.credKey)) pendingQueue.add(p);
          }
          if (pendingQueue.isEmpty &&
              !page.hasMore &&
              channelResults.isEmpty) {
            channelIsRunning = false;
            channelStatus = 'No more portals available.';
            notifyListeners();
            return;
          }
        } catch (_) {}
      }

      if (pendingQueue.isNotEmpty) {
        final snapshot = List<IptvPortal>.from(pendingQueue);
        channelStatus = 'Verifying ${snapshot.length} new portal'
            '${snapshot.length == 1 ? '' : 's'}…';
        notifyListeners();
        await IptvVerifier.verifyUntil(
          portals: snapshot,
          target: 5,
          onAttempted: (p) {
            if (pendingKeys.remove(p.credKey)) {
              pendingQueue.removeWhere((x) => x.credKey == p.credKey);
            }
          },
          onAlive: (v) async {
            if (_verifiedKeys.add(v.credKey)) {
              verified = _sortFavoritesFirst([...verified, v]);
              await IptvStore.save(verified);
              if (!attempted.contains(v.key) &&
                  !pool.any((p) => p.key == v.key)) {
                pool.add(v.portal);
              }
            }
          },
          onProgress: (c, t, a) {
            channelStatus = 'Verifying portals $c/$t · $a working'
                '${pendingQueue.isNotEmpty ? ' · ${pendingQueue.length} queued' : ''}';
            notifyListeners();
          },
        );
      }
    }

    if (_channelCancel) {
      channelIsRunning = false;
      channelStatus = 'Stopped.';
      notifyListeners();
      return;
    }

    // ── 3. Take next 8 portals from the pool ──
    final toScan = pool.take(8).toList();
    if (toScan.isEmpty) {
      channelIsRunning = false;
      channelStatus = channelResults.isEmpty
          ? 'No working portals available. Tap Get More.'
          : '${channelResults.length} alive · no more portals to scan.';
      notifyListeners();
      return;
    }

    channelStatus = 'Searching ${toScan.length} portal'
        '${toScan.length == 1 ? '' : 's'}…';
    notifyListeners();

    // Mark attempted up-front so re-entry skips them
    for (final p in toScan) {
      attempted.add(p.key);
    }
    pool.removeWhere((p) => attempted.contains(p.key));

    // ── 4. Fan out: fetch live streams from all 8 portals IN PARALLEL ──
    final verifiedByKey = {for (final v in verified) v.key: v};
    final candidatesByPortal =
        await Future.wait(toScan.map((p) async {
      final vp = verifiedByKey[p.key] ??
          VerifiedPortal(
            portal: p,
            name: p.url,
            expiry: '',
            maxConnections: '1',
            activeConnections: '0',
          );
      try {
        final streams =
            await IptvClient.streams(vp.portal, IptvSection.live, '');
        return streams
            .where((s) =>
                HardcodedChannels.matches(s.name, ch.keywords, ch.exclude))
            .map((s) => _Candidate(
                  portal: vp,
                  stream: s,
                  url: IptvClient.streamUrl(vp.portal, s),
                ))
            .toList();
      } catch (_) {
        return <_Candidate>[];
      }
    }));

    // Flatten + dedupe by URL + drop ones we already have
    final have = channelResults.map((h) => h.streamUrl).toSet();
    final seen = <String>{};
    final newCandidates = <_Candidate>[];
    for (final list in candidatesByPortal) {
      for (final c in list) {
        if (c.url.isEmpty) continue;
        if (have.contains(c.url)) continue;
        if (!seen.add(c.url)) continue;
        newCandidates.add(c);
      }
    }

    if (newCandidates.isEmpty || _channelCancel) {
      channelIsRunning = false;
      channelStatus = channelResults.isEmpty
          ? 'No matching channels found. Try Get More.'
          : '${channelResults.length} alive · no new matches.';
      notifyListeners();
      return;
    }

    // ── 5. ONE 24-wide alive-check pass across ALL candidates ──
    final byUrl = {for (final c in newCandidates) c.url: c};
    channelStatus = 'Found ${newCandidates.length} candidate'
        '${newCandidates.length == 1 ? '' : 's'} · verifying…';
    notifyListeners();

    await IptvAliveChecker.launchCheck(
      streams: newCandidates.map((c) => MapEntry(c.url, c.url)).toList(),
      isCancelled: () => _channelCancel,
      onResult: (id, alive) async {
        if (!alive) return;
        final c = byUrl[id];
        if (c == null) return;
        if (channelResults.any((h) => h.streamUrl == c.url)) return;
        final hit = ChannelHit(portal: c.portal, stream: c.stream, streamUrl: c.url);
        channelResults =
            _sortHitsFavoritesFirst(ch.id, [...channelResults, hit]);
        await _saveChannelHits(ch.id, channelResults);
        notifyListeners();
      },
      onProgress: (p) async {
        channelStatus = 'Verifying ${p.checked}/${p.total} · '
            '${channelResults.length} alive';
        notifyListeners();
      },
      onDone: () async {
        channelIsRunning = false;
        channelStatus = channelResults.isEmpty
            ? 'No alive streams for ${ch.name}. Try Get More.'
            : '${channelResults.length} alive stream'
                '${channelResults.length == 1 ? '' : 's'} saved.';
        notifyListeners();
      },
    );
    if (_channelCancel) {
      channelIsRunning = false;
      channelStatus = 'Stopped.';
      notifyListeners();
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Navigation
  // ────────────────────────────────────────────────────────────────────────
  void back() {
    switch (view) {
      case IptvView.portalList:
        // nothing
        break;
      case IptvView.sectionPick:
        view = IptvView.portalList;
        activePortal = null;
        break;
      case IptvView.browser:
        if (activeSection != null) {
          view = IptvView.sectionPick;
          activeSection = null;
          stopAliveCheck();
        }
        break;
      case IptvView.episodeList:
        view = IptvView.browser;
        activeSeries = null;
        episodes = const [];
        break;
      case IptvView.channelsHub:
        view = IptvView.portalList;
        activeHardcoded = null;
        break;
      case IptvView.channelResults:
        stopChannelSearch();
        view = IptvView.channelsHub;
        activeHardcoded = null;
        channelResults = const [];
        channelStatus = '';
        break;
    }
    notifyListeners();
  }
}

class _Candidate {
  final VerifiedPortal portal;
  final IptvStream stream;
  final String url;
  const _Candidate({
    required this.portal,
    required this.stream,
    required this.url,
  });
}
