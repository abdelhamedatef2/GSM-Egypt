import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vodafone Sites',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SiteRecord {
  final String siteId;
  final double latitude;
  final double longitude;

  const SiteRecord({
    required this.siteId,
    required this.latitude,
    required this.longitude,
  });
}

class SitesDb {
  SitesDb._(this._db);
  final Database _db;

  static const _assetDbPath = 'assets/vodafone_sites.db';
  static const _dbFileName = 'vodafone_sites.db';

  static Future<SitesDb> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbFileName);

    final exists = await File(dbPath).exists();
    if (!exists) {
      // Copy prebuilt DB from assets into app storage
      final data = await rootBundle.load(_assetDbPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(
      dbPath,
      readOnly: false,
      version: 1,
    );
    return SitesDb._(db);
  }

  Future<SiteRecord?> findExact(String siteId) async {
    final rows = await _db.query(
      'sites',
      columns: ['site_id', 'latitude', 'longitude'],
      where: 'site_id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SiteRecord(
      siteId: (r['site_id'] as String),
      latitude: (r['latitude'] as num).toDouble(),
      longitude: (r['longitude'] as num).toDouble(),
    );
  }

  Future<List<String>> suggest(String query, {int limit = 10}) async {
    // Prefix suggestion. Using LIKE is OK here because we have an index on site_id
    final rows = await _db.query(
      'sites',
      columns: ['site_id'],
      where: 'site_id LIKE ?',
      whereArgs: ['$query%'],
      orderBy: 'site_id ASC',
      limit: limit,
    );
    return rows.map((e) => e['site_id'] as String).toList();
  }

  Future<void> close() => _db.close();
}


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    // Small delay for branding + DB init starts in HomePage
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE50000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', width: 140, height: 140),
            const SizedBox(height: 16),
            const Text(
              'Vodafone Sites',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Offline lookup',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  Timer? _debounce;

  SitesDb? _db;
  bool _loadingDb = true;

  SiteRecord? _result;
  String? _error;

  List<String> _suggestions = const [];
  List<String> _recent = const [];

  static const _recentKey = 'recent_site_ids';
  static const _recentMax = 10;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentKey) ?? <String>[];

    final db = await SitesDb.open();

    if (!mounted) return;
    setState(() {
      _db = db;
      _loadingDb = false;
      _recent = recent;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _db?.close();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _suggestions = const [];
        _result = null;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final db = _db;
      if (db == null) return;
      final suggestions = await db.suggest(q, limit: 10);
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
      });
    });
  }

  Future<void> _searchExact(String siteId) async {
    final db = _db;
    if (db == null) return;

    final q = siteId.trim();
    if (q.isEmpty) return;

    setState(() {
      _error = null;
      _result = null;
      _suggestions = const [];
      _controller.text = q;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
    });

    final rec = await db.findExact(q);
    if (!mounted) return;

    if (rec == null) {
      setState(() {
        _error = 'Site ID مش موجود';
        _result = null;
      });
      return;
    }

    await _pushRecent(q);
    setState(() {
      _error = null;
      _result = rec;
    });
  }

  Future<void> _pushRecent(String siteId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(_recent);
    list.remove(siteId);
    list.insert(0, siteId);
    if (list.length > _recentMax) {
      list.removeRange(_recentMax, list.length);
    }
    await prefs.setStringList(_recentKey, list);
    if (!mounted) return;
    setState(() => _recent = list);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }


  String _mapsLink(double lat, double lon) {
    final q = Uri.encodeComponent('$lat,$lon');
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  String _shareMessage(SiteRecord r) {
    return 'Site ID: ${r.siteId}\nLat: ${r.latitude}\nLon: ${r.longitude}\nMaps: ${_mapsLink(r.latitude, r.longitude)}';
  }

  Future<void> _shareOnWhatsApp(SiteRecord r) async {
    final msg = Uri.encodeComponent(_shareMessage(r));
    final url = Uri.parse('https://wa.me/?text=$msg');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مش قادر أفتح واتساب')),
      );
    }
  }

  Future<void> _shareSheet(SiteRecord r) async {
    await Share.share(_shareMessage(r));
  }

  Future<void> _openMaps(double lat, double lon, {String? label}) async {
    final q = Uri.encodeComponent('$lat,$lon');
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مش قادر أفتح Maps')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vodafone Sites Lookup (Offline)'),
      ),
      body: _loadingDb
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: 'Site ID',
                      hintText: 'اكتب كود الموقع',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _searchExact(_controller.text),
                      ),
                    ),
                    onChanged: _onChanged,
                    onSubmitted: _searchExact,
                    textInputAction: TextInputAction.search,
                  ),
                  const SizedBox(height: 8),
                  if (_suggestions.isNotEmpty) ...[
                    _SuggestionList(
                      items: _suggestions,
                      onTap: _searchExact,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                  ],
                  if (result != null) ...[
                    _ResultCard(
                      rec: result,
                      onCopyCoord: () => _copy('${result.latitude}, ${result.longitude}'),
                      onCopyLat: () => _copy(result.latitude.toString()),
                      onCopyLon: () => _copy(result.longitude.toString()),
                      onOpenMaps: () => _openMaps(result.latitude, result.longitude, label: result.siteId),
                      onShareWhatsApp: () => _shareOnWhatsApp(result),
                      onShare: () => _shareSheet(result),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  _RecentList(
                    items: _recent,
                    onTap: _searchExact,
                    onClear: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(_recentKey);
                      if (!mounted) return;
                      setState(() => _recent = const []);
                    },
                  ),
                  const Spacer(),
                  Text(
                    'DB loaded offline.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.items, required this.onTap});
  final List<String> items;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final id = items[i];
          return ListTile(
            dense: true,
            title: Text(id),
            onTap: () => onTap(id),
          );
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.rec,
    required this.onCopyCoord,
    required this.onCopyLat,
    required this.onCopyLon,
    required this.onOpenMaps,
    required this.onShareWhatsApp,
    required this.onShare,
  });

  final SiteRecord rec;
  final VoidCallback onCopyCoord;
  final VoidCallback onCopyLat;
  final VoidCallback onCopyLon;
  final VoidCallback onOpenMaps;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rec.siteId,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Lat: ${rec.latitude}')),
                IconButton(onPressed: onCopyLat, icon: const Icon(Icons.copy)),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('Lon: ${rec.longitude}')),
                IconButton(onPressed: onCopyLon, icon: const Icon(Icons.copy)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onOpenMaps,
                  icon: const Icon(Icons.map),
                  label: const Text('Open in Maps'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopyCoord,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy lat,lon'),
                ),
                OutlinedButton.icon(
                  onPressed: onShareWhatsApp,
                  icon: const Icon(Icons.chat),
                  label: const Text('Share WhatsApp'),
                ),
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.items, required this.onTap, required this.onClear});
  final List<String> items;
  final void Function(String) onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: items.isEmpty ? null : onClear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('مفيش عمليات بحث لسه'),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final id = items[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: Text(id),
                    onTap: () => onTap(id),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
