import 'package:flutter/material.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../services/xmltv_epg_service.dart';
import '../utils/app_theme.dart';

class _LiveChannel {
  final String addonBaseUrl;
  final String stremioId;
  final String name;

  const _LiveChannel({
    required this.addonBaseUrl,
    required this.stremioId,
    required this.name,
  });

  String get mapKey => SettingsService.xmltvChannelMapKeyFor(
        addonBaseUrl: addonBaseUrl,
        stremioChannelId: stremioId,
      );
}

/// Map XMLTV `<programme channel="...">` ids to Stremio live TV channels for the TV Guide.
class EpgChannelMappingScreen extends StatefulWidget {
  const EpgChannelMappingScreen({super.key});

  @override
  State<EpgChannelMappingScreen> createState() => _EpgChannelMappingScreenState();
}

class _EpgChannelMappingScreenState extends State<EpgChannelMappingScreen> {
  final StremioService _stremio = StremioService();
  final SettingsService _settings = SettingsService();

  bool _loading = true;
  String? _error;
  List<_LiveChannel> _channels = [];
  Map<String, String> _map = {};
  List<String> _epgIds = [];
  bool _epgLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _map = await _settings.getXmltvChannelMap();

      final epgUrl = await _settings.getXmltvEpgUrl();
      final epg = XmltvEpgService.instance;
      if (epgUrl != null && epgUrl.isNotEmpty) {
        _epgLoaded = await epg.loadFromUrl(epgUrl);
        _epgIds = epg.loadedChannelIds;
      } else {
        epg.clear();
        _epgLoaded = false;
        _epgIds = [];
      }

      _channels = await _loadLiveTvChannels(_stremio);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  static Future<List<_LiveChannel>> _loadLiveTvChannels(StremioService stremio) async {
    var catalogs = await stremio.getAllCatalogs();
    catalogs = catalogs.where((c) => StremioService.isLiveTvCatalogType(c['catalogType'])).toList();

    final List<_LiveChannel> out = [];
    final seen = <String>{};
    const maxItems = 200;

    for (final cat in catalogs) {
      if (out.length >= maxItems) break;
      final batch = await stremio.getCatalog(
        baseUrl: cat['addonBaseUrl'],
        type: cat['catalogType'],
        id: cat['catalogId'],
      );
      for (final m in batch) {
        if (out.length >= maxItems) break;
        final base = cat['addonBaseUrl']?.toString() ?? '';
        final id = m['id']?.toString() ?? '';
        if (base.isEmpty || id.isEmpty) continue;
        final key = '$base|$id';
        if (!seen.add(key)) continue;
        final name = m['name']?.toString() ?? 'Channel';
        out.add(_LiveChannel(addonBaseUrl: base, stremioId: id, name: name));
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> _saveMapping(_LiveChannel ch, String epgId) async {
    final trimmed = epgId.trim();
    await _settings.setXmltvChannelMapping(
      addonBaseUrl: ch.addonBaseUrl,
      stremioChannelId: ch.stremioId,
      epgChannelId: trimmed,
    );
    _map = await _settings.getXmltvChannelMap();
    if (mounted) setState(() {});
  }

  void _openEditor(_LiveChannel ch) {
    final current = _map[ch.mapKey] ?? '';
    final controller = TextEditingController(text: current);
    final norm = XmltvEpgService.normalizeKey(current);
    String selectedDropdown = '';
    if (norm.isNotEmpty) {
      for (final id in _epgIds) {
        if (XmltvEpgService.normalizeKey(id) == norm) {
          selectedDropdown = id;
          break;
        }
      }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ch.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ch.stremioId,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (_epgIds.isNotEmpty) ...[
                    Text(
                      'Pick from loaded EPG',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedDropdown.isEmpty ? null : selectedDropdown,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E2E),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      hint: const Text('Select EPG channel id', style: TextStyle(color: Colors.white38)),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('— None —')),
                        ..._epgIds.map(
                          (id) => DropdownMenuItem(
                            value: id,
                            child: Text(id, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        setModal(() {
                          selectedDropdown = v ?? '';
                          if (v != null && v.isNotEmpty) controller.text = v;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    _epgIds.isEmpty
                        ? 'EPG channel id (same as programme channel= in your XMLTV file)'
                        : 'Or type / paste EPG channel id',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. BBCOne.uk',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _saveMapping(ch, '');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Cleared mapping for ${ch.name}')),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _saveMapping(ch, controller.text);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('EPG mapping saved')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('EPG channel mapping'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
                ))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        _epgLoaded
                            ? 'Tap a live channel and link it to an id from your XMLTV file (same value as programme channel="...").'
                            : 'Set an XMLTV URL in Settings first to pick ids from the file. You can still type ids manually.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13, height: 1.35),
                      ),
                    ),
                    Expanded(
                      child: _channels.isEmpty
                          ? Center(
                              child: Text(
                                'No live TV channels found. Install a Stremio live TV addon.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              itemCount: _channels.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, i) {
                                final ch = _channels[i];
                                final mapped = _map[ch.mapKey];
                                return Material(
                                  color: AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    title: Text(
                                      ch.name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      mapped != null && mapped.isNotEmpty
                                          ? 'EPG: $mapped'
                                          : 'Auto-match or not set',
                                      style: TextStyle(
                                        color: mapped != null && mapped.isNotEmpty
                                            ? Colors.greenAccent.withValues(alpha: 0.8)
                                            : Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                                    onTap: () => _openEditor(ch),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
