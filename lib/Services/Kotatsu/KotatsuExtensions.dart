import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../anymex_extension_runtime_bridge.dart';
import '../Mangayomi/http/m_client.dart';

class KotatsuExtensions extends Extension {
  @override
  String get id => 'kotatsu';

  @override
  String get name => 'Kotatsu';

  @override
  String get icon =>
      'https://raw.githubusercontent.com/KotatsuApp/Kotatsu/devel/metadata/en-US/icon.png';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsNovel => false;

  @override
  bool get requiresPlugin => true;

  @override
  SourceMethods createSourceMethods(Source source) =>
      KotatsuSourceMethods(source);

  static const platform = MethodChannel('kotatsuExtensionBridge');

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

      final extDir =
          await AnymeXExtensionBridge.context.getKotatsuPluginDirectory();
      if (extDir == null) {
        throw Exception("Could not get Kotatsu plugins directory");
      }

      final jarFile = File(p.join(extDir.path, 'plugin.jar'));
      final client = MClient.init();
      final res = await client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to download plugin jar");
      }

      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }
      await jarFile.writeAsBytes(res.bodyBytes);

      final cacheFile = File(p.join(extDir.path, 'kotatsu_extensions_cache.json'));
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }

      final repo = Repo(url: repoUrl, managerId: id);
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);

      await fetchInstalledMangaExtensions();
      await fetchMangaExtensions();
    } catch (e) {
      Logger.log("Failed to add Kotatsu repo $repoUrl: $e");
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

      final extDir =
          await AnymeXExtensionBridge.context.getKotatsuPluginDirectory();
      if (extDir != null) {
        final jarFile = File(p.join(extDir.path, 'plugin.jar'));
        if (await jarFile.exists()) {
          await jarFile.delete();
        }
        final cacheFile = File(p.join(extDir.path, 'kotatsu_extensions_cache.json'));
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
      }

      setVal('kotatsu_active_sources', <String>[]);

      await setInstalled(ItemType.manga, const []);
      getAvailableRx(ItemType.manga).value = const [];
      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove Kotatsu repo $repoUrl: $e");
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

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    final repos = _loadRepos(ItemType.manga);
    getReposRx(ItemType.manga).value = repos;

    if (repos.isEmpty) {
      await setInstalled(ItemType.manga, const []);
      return;
    }

    final extDir =
        await AnymeXExtensionBridge.context.getKotatsuPluginDirectory();
    if (extDir == null) {
      await setInstalled(ItemType.manga, const []);
      return;
    }

    final jarFile = File(p.join(extDir.path, 'plugin.jar'));
    if (!await jarFile.exists()) {
      try {
        Logger.log(
            'Kotatsu plugin.jar missing but repo exists. Downloading...');
        final client = MClient.init();
        final res = await client.get(Uri.parse(repos.first.url));
        if (res.statusCode == 200) {
          if (!await extDir.exists()) {
            await extDir.create(recursive: true);
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

    try {
      final List<dynamic>? result =
          await platform.invokeMethod('loadExtensions', {
        'folderPath': extDir.path,
      });

      if (result == null) {
        await setInstalled(ItemType.manga, const []);
        return;
      }

      final allSources = result.map((e) {
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
      Logger.log('Failed to fetch installed Kotatsu extensions: $e');
      await setInstalled(ItemType.manga, const []);
    }
  }

  @override
  Future<void> fetchMangaExtensions() async {
    final repos = _loadRepos(ItemType.manga);
    getReposRx(ItemType.manga).value = repos;

    if (repos.isEmpty) {
      getAvailableRx(ItemType.manga).value = const [];
      return;
    }

    final extDir =
        await AnymeXExtensionBridge.context.getKotatsuPluginDirectory();
    if (extDir == null) {
      getAvailableRx(ItemType.manga).value = const [];
      return;
    }

    final jarFile = File(p.join(extDir.path, 'plugin.jar'));
    if (!await jarFile.exists()) {
      getAvailableRx(ItemType.manga).value = const [];
      return;
    }

    try {
      final List<dynamic>? result =
          await platform.invokeMethod('loadExtensions', {
        'folderPath': extDir.path,
      });

      if (result == null) {
        getAvailableRx(ItemType.manga).value = const [];
        return;
      }

      final allSources = result.map((e) {
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
      Logger.log('Failed to fetch available Kotatsu extensions: $e');
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
