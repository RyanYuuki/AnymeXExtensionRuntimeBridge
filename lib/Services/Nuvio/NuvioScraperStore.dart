import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NuvioScraperStore {
  static final Map<String, String> _memoryCache = {};
  static Directory? _scrapersDir;

  static Future<Directory> _getDirectory() async {
    if (_scrapersDir != null) return _scrapersDir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'nuvio_scrapers'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _scrapersDir = dir;
    return dir;
  }

  static String _fileKey(String scraperId) {
    return sha256.convert(scraperId.toLowerCase().codeUnits).toString();
  }

  static String? getScraperCode(String scraperId) {
    final lower = scraperId.toLowerCase();
    return _memoryCache[lower] ?? _memoryCache[scraperId];
  }

  static Future<void> saveCode(String scraperId, String code) async {
    final lower = scraperId.toLowerCase();
    _memoryCache[lower] = code;
    _memoryCache[scraperId] = code;
    try {
      final dir = await _getDirectory();
      final file = File(p.join(dir.path, '${_fileKey(scraperId)}.js'));
      await file.writeAsString(code, flush: true);
    } catch (_) {}
  }

  static Future<String?> loadCode(String scraperId) async {
    final cached = getScraperCode(scraperId);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    try {
      final dir = await _getDirectory();
      final file = File(p.join(dir.path, '${_fileKey(scraperId)}.js'));
      if (await file.exists()) {
        final code = await file.readAsString();
        if (code.isNotEmpty) {
          final lower = scraperId.toLowerCase();
          _memoryCache[lower] = code;
          _memoryCache[scraperId] = code;
          return code;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> downloadAndStoreScraper(String scraperId, String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(cleanUrl)).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        await saveCode(scraperId, res.body);
        return res.body;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> deleteCode(String scraperId) async {
    _memoryCache.remove(scraperId.toLowerCase());
    _memoryCache.remove(scraperId);
    try {
      final dir = await _getDirectory();
      final file = File(p.join(dir.path, '${_fileKey(scraperId)}.js'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static void clearMemoryCache() {
    _memoryCache.clear();
  }
}
