import 'package:flutter/material.dart';

import '../api/webstreamr_service.dart';
import '../api/webstreamr_settings.dart';

/// Settings UI for the local WebStreamr port — country toggles, MFP,
/// FlareSolverr, per-extractor disable, resolution exclusion, TMDB token.
class WebStreamrSettingsScreen extends StatefulWidget {
  const WebStreamrSettingsScreen({super.key});

  @override
  State<WebStreamrSettingsScreen> createState() =>
      _WebStreamrSettingsScreenState();
}

class _WebStreamrSettingsScreenState extends State<WebStreamrSettingsScreen> {
  bool _loading = true;
  Set<String> _enabledCountries = {};
  Set<String> _disabledExtractors = {};
  Set<String> _excludedResolutions = {};
  final _mfpUrl = TextEditingController();
  final _mfpPwd = TextEditingController();
  final _flareUrl = TextEditingController();
  final _tmdbTok = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cc = await WebStreamrSettings.getEnabledCountryCodes();
    final ex = await WebStreamrSettings.getDisabledExtractors();
    final res = await WebStreamrSettings.getExcludedResolutions();
    _mfpUrl.text = await WebStreamrSettings.getMediaFlowProxyUrl() ?? '';
    _mfpPwd.text = await WebStreamrSettings.getMediaFlowProxyPassword() ?? '';
    _flareUrl.text = await WebStreamrSettings.getFlareSolverrUrl() ?? '';
    _tmdbTok.text = await WebStreamrSettings.getTmdbAccessToken() ?? '';
    if (!mounted) return;
    setState(() {
      _enabledCountries = cc.toSet();
      _disabledExtractors = ex.toSet();
      _excludedResolutions = res.toSet();
      _loading = false;
    });
  }

  Future<void> _save() async {
    await WebStreamrSettings.setEnabledCountryCodes(_enabledCountries.toList());
    await WebStreamrSettings.setDisabledExtractors(_disabledExtractors.toList());
    await WebStreamrSettings.setExcludedResolutions(_excludedResolutions.toList());
    await WebStreamrSettings.setMediaFlowProxyUrl(_mfpUrl.text.trim());
    await WebStreamrSettings.setMediaFlowProxyPassword(_mfpPwd.text);
    await WebStreamrSettings.setFlareSolverrUrl(_flareUrl.text.trim());
    await WebStreamrSettings.setTmdbAccessToken(_tmdbTok.text.trim());
    // Re-apply env (TMDB token / flare URL).
    await WebStreamrService.init();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WebStreamr settings saved.')),
    );
  }

  @override
  void dispose() {
    _mfpUrl.dispose();
    _mfpPwd.dispose();
    _flareUrl.dispose();
    _tmdbTok.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebStreamr'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _loading ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('Country Sources',
                    'Pick which language/region sources to query.'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final cc in WebStreamrSettings.allCountryCodes)
                      FilterChip(
                        label: Text(cc.toUpperCase()),
                        selected: _enabledCountries.contains(cc),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _enabledCountries.add(cc);
                          } else {
                            _enabledCountries.remove(cc);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _section('Disabled Extractors',
                    'Tap to disable. The "external" fallback always stays on.'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final id in WebStreamrSettings.allExtractorIds)
                      FilterChip(
                        label: Text(id),
                        selected: _disabledExtractors.contains(id),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _disabledExtractors.add(id);
                          } else {
                            _disabledExtractors.remove(id);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _section('Excluded Resolutions',
                    'Streams matching these resolutions are filtered out.'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final r in WebStreamrSettings.allResolutions)
                      FilterChip(
                        label: Text(r),
                        selected: _excludedResolutions.contains(r),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _excludedResolutions.add(r);
                          } else {
                            _excludedResolutions.remove(r);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _section('MediaFlow Proxy', 'Optional — enables MFP-routed extractors (Voe etc.).'),
                TextField(
                  controller: _mfpUrl,
                  decoration: const InputDecoration(
                    labelText: 'MFP URL',
                    hintText: 'https://your-mfp.example.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _mfpPwd,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'MFP Password'),
                ),
                const SizedBox(height: 24),
                _section('FlareSolverr',
                    'Optional — used for Cloudflare-protected hosts.'),
                TextField(
                  controller: _flareUrl,
                  decoration: const InputDecoration(
                    labelText: 'FlareSolverr URL',
                    hintText: 'http://localhost:8191/v1',
                  ),
                ),
                const SizedBox(height: 24),
                _section('TMDB Access Token',
                    'Required for sources that translate IMDb→TMDB locally.'),
                TextField(
                  controller: _tmdbTok,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'TMDB v4 Bearer token',
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: _save,
                ),
              ],
            ),
    );
  }

  Widget _section(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    )),
            const SizedBox(height: 8),
          ],
        ),
      );
}
