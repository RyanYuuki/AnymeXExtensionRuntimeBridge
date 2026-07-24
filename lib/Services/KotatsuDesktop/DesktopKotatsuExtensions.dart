import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../Logger.dart';
import '../../anymex_extension_runtime_bridge.dart';
import '../../Settings/KvStore.dart';
import '../Mangayomi/http/m_client.dart';

class DesktopKotatsuExtensions extends DesktopExtensionBase {
  @override
  String get id => 'kotatsu-desktop';

  @override
  String get name => 'Kotatsu (Desktop)';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  bool get requiresPlugin => true;

  @override
  SourceMethods createSourceMethods(Source source) =>
      DesktopKotatsuSourceMethods(source);

  Future<String> _getExtensionsPath() async {
    return getExtensionsPath('Kotatsu');
  }

  List<Repo> _loadRepos(ItemType type) {
    final key = '$id${type.name}Repos';
    final encoded = getVal<List<String>>(key);
    if (encoded == null || encoded.isEmpty) return const [];
    return encoded
        .map((e) => Repo.fromJson(jsonDecode(e)))
        .toSet()
        .toList(growable: false);
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    final key = '$id${type.name}Repos';
    setVal(
      key,
      repos.toSet().map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL");
      }

      final repos = _loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) return;

      final extPath = await _getExtensionsPath();
      final jarFile = File(p.join(extPath, 'plugin.jar'));
      final markerFile = File(p.join(extPath, '.plugin_jar_converted'));

      if (await markerFile.exists()) {
        await markerFile.delete();
      }
      final cacheFile = File(p.join(extPath, 'kotatsu_extensions_cache.json'));
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }

      final client = MClient.init();
      final res = await client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to download plugin jar");
      }

      final dir = Directory(extPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await jarFile.writeAsBytes(res.bodyBytes);

      final repo = Repo(url: repoUrl, managerId: id);
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);

      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    } catch (e) {
      Logger.log("Failed to add Desktop Kotatsu repo $repoUrl: $e");
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    try {
      final repos = _loadRepos(type)
          .where((r) => r.url != repoUrl)
          .toList(growable: false);
      _saveRepos(repos, type);

      final extPath = await _getExtensionsPath();
      final jarFile = File(p.join(extPath, 'plugin.jar'));
      if (await jarFile.exists()) {
        await jarFile.delete();
      }

      final markerFile = File(p.join(extPath, '.plugin_jar_converted'));
      if (await markerFile.exists()) {
        await markerFile.delete();
      }
      final cacheFile = File(p.join(extPath, 'kotatsu_extensions_cache.json'));
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }

      setVal('kotatsu_active_sources', <String>[]);

      await setInstalled(ItemType.manga, const []);
      getAvailableRx(ItemType.manga).value = const [];
      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove Desktop Kotatsu repo $repoUrl: $e");
    }
  }

  @override
  Future<void> fetchAnimeExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {}

  @override
  Future<void> fetchInstalledAnimeExtensions() async {}

  @override
  Future<void> fetchInstalledNovelExtensions() async {}
  Future<void> _ensureDexConverted(String extPath, File jarFile) async {}

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    try {
      final repos = _loadRepos(ItemType.manga);
      getReposRx(ItemType.manga).value = repos;

      if (repos.isEmpty) {
        await setInstalled(ItemType.manga, const []);
        return;
      }

      final extPath = await _getExtensionsPath();
      final jarFile = File(p.join(extPath, 'plugin.jar'));
      if (!await jarFile.exists()) {
        try {
          Logger.log(
              'Kotatsu plugin.jar missing but repo exists. Downloading...');
          final client = MClient.init();
          final res = await client.get(Uri.parse(repos.first.url));
          if (res.statusCode == 200) {
            final dir = Directory(extPath);
            if (!await dir.exists()) {
              await dir.create(recursive: true);
            }
            await jarFile.writeAsBytes(res.bodyBytes);
            Logger.log('Kotatsu plugin.jar downloaded successfully.');
          } else {
            Logger.log(
                'Failed to download Kotatsu plugin.jar: HTTP ${res.statusCode}');
            await setInstalled(ItemType.manga, const []);
            return;
          }
        } catch (e) {
          Logger.log('Error downloading Kotatsu plugin.jar: $e');
          await setInstalled(ItemType.manga, const []);
          return;
        }
      }

      await _ensureDexConverted(extPath, jarFile);

      final result =
          await BridgeDispatcher().invokeMethod('kotatsuLoadExtensions', {
        'folderPath': extPath,
      });

      var data = result;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data == null || data is! List) {
        await setInstalled(ItemType.manga, const []);
        return;
      }

      final allSources = data.map((e) {
        final src = KotatsuSource.fromJson(Map<String, dynamic>.from(e));
        src.managerId = id;
        return src;
      }).toList();

      final activeIds = getVal<List<String>>('kotatsu_active_sources') ?? [];
      final activeSet = activeIds.toSet();

      final installedSources =
          allSources.where((s) => activeSet.contains(s.id)).toList();
      await setInstalled(ItemType.manga, installedSources);
    } catch (e) {
      Logger.log('Failed to fetch installed Desktop Kotatsu extensions: $e');
      await setInstalled(ItemType.manga, const []);
    }
  }

  @override
  Future<void> fetchMangaExtensions() async {
    try {
      final repos = _loadRepos(ItemType.manga);
      getReposRx(ItemType.manga).value = repos;

      if (repos.isEmpty) {
        getAvailableRx(ItemType.manga).value = const [];
        return;
      }

      final extPath = await _getExtensionsPath();
      final jarFile = File(p.join(extPath, 'plugin.jar'));
      if (!await jarFile.exists()) {
        getAvailableRx(ItemType.manga).value = const [];
        return;
      }

      await _ensureDexConverted(extPath, jarFile);

      final result =
          await BridgeDispatcher().invokeMethod('kotatsuLoadExtensions', {
        'folderPath': extPath,
      });

      var data = result;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data == null || data is! List) {
        getAvailableRx(ItemType.manga).value = const [];
        return;
      }

      final allSources = data.map((e) {
        final src = KotatsuSource.fromJson(Map<String, dynamic>.from(e));
        src.managerId = id;
        return src;
      }).toList();

      final activeIds = getVal<List<String>>('kotatsu_active_sources') ?? [];
      final activeSet = activeIds.toSet();

      final availableSources =
          allSources.where((s) => !activeSet.contains(s.id)).toList();
      getAvailableRx(ItemType.manga).value = availableSources;
    } catch (e) {
      Logger.log('Failed to fetch available Desktop Kotatsu extensions: $e');
      getAvailableRx(ItemType.manga).value = const [];
    }
  }

  @override
  Future<void> installSource(Source source) async {
    final activeIds = getVal<List<String>>('kotatsu_active_sources') ?? [];
    if (!activeIds.contains(source.id)) {
      final updated = List<String>.from(activeIds)..add(source.id!);
      setVal('kotatsu_active_sources', updated);
    }
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final activeIds = getVal<List<String>>('kotatsu_active_sources') ?? [];
    if (activeIds.contains(source.id)) {
      final updated = List<String>.from(activeIds)..remove(source.id);
      setVal('kotatsu_active_sources', updated);
    }
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }

  @override
  Future<void> updateSource(Source source) async {
    await fetchInstalledMangaExtensions();
    await fetchMangaExtensions();
  }
}
