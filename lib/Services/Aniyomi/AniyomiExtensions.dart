import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import '../../anymex_extension_runtime_bridge.dart';
import '../Mangayomi/http/m_client.dart';
import 'AniyomiSourceMethods.dart';
import 'Models/Source.dart';

class AniyomiExtensions extends Extension {
  final _client = MClient.init();

  @override
  String get id => 'aniyomi';

  @override
  String get name => 'Aniyomi';

  @override
  SourceMethods createSourceMethods(Source source) =>
      AniyomiSourceMethods(source);

  static const platform = MethodChannel('aniyomiExtensionBridge');

  @override
  bool get supportsNovel => false;

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    getInstalledRx(ItemType.anime).value =
        await _loadInstalled('getInstalledAnimeExtensions', ItemType.anime);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    getInstalledRx(ItemType.manga).value =
        await _loadInstalled('getInstalledMangaExtensions', ItemType.manga);
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      final List<dynamic> result = await platform.invokeMethod(method, "");
      final parsed = result
          .map((e) => ASource.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.itemType == type)
          .toList(growable: false);

      final Map<String, List<ASource>> grouped = {};
      for (final s in parsed) {
        final key = s.pkgName ?? s.name ?? "unknown";
        grouped.putIfAbsent(key, () => []).add(s);
      }

      final filtered = <ASource>[];
      for (final group in grouped.values) {
        if (group.length > 1) {
          final allSource = group.firstWhere((s) => s.lang == 'all',
              orElse: () => group.firstWhere((s) => s.lang == 'en',
                  orElse: () => group.first));
          for (final s in group) {
            s.langs = group;
          }
          filtered.add(allSource);
        } else {
          filtered.add(group.first);
        }
      }

      return filtered;
    } catch (e) {
      return [];
    }
  }

  Future<List<Source>> getInstalledAnimeExtensions() async {
    await fetchInstalledAnimeExtensions();
    return getInstalledRx(ItemType.anime).value;
  }

  Future<List<Source>> getInstalledMangaExtensions() async {
    await fetchInstalledMangaExtensions();
    return getInstalledRx(ItemType.manga).value;
  }

  @override
  Future<void> fetchAnimeExtensions() async {
    final res = await _fetchExtensions(ItemType.anime);
    getAvailableRx(ItemType.anime).value = res;
  }

  @override
  Future<void> fetchMangaExtensions() async {
    final res = await _fetchExtensions(ItemType.manga);
    getAvailableRx(ItemType.manga).value = res;
  }

  @override
  Future<void> fetchNovelExtensions() async {}

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final results = await Future.wait(repos.map((r) => _fetchRepo(r, type)));
    final all = results.expand((e) => e).toList(growable: false);

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(all.cast<ASource>(), type);

    getRawAvailableRx(type).value = List.unmodifiable(all);

    return List.unmodifiable(
      all.where((s) => !installedIds.contains(s.id)),
    );
  }

  Future<List<Source>> _fetchRepo(Repo repo, ItemType type) async {
    try {
      final res = await _client.get(Uri.parse(repo.url));
      if (res.statusCode != 200) return const [];
      return compute(_parseExtensions, (res.body, repo.url, type));
    } catch (e) {
      Logger.log("Repo failed ${repo.url}: $e");
      return const [];
    }
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, targetType) = args;

    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];

      final baseIconUrl = repoUrl.replaceAll('/index.min.json', '');
      final sources = <Source>[];

      for (final item in decoded) {
        final map = item as Map<String, dynamic>;
        final name = map['name'] as String? ?? '';

        final detectedType = name.startsWith('Aniyomi: ')
            ? ItemType.anime
            : name.startsWith('Tachiyomi: ')
                ? ItemType.manga
                : null;

        if (detectedType != targetType) continue;

        sources.add(
          ASource(
            id: map["sources"] != null &&
                    map["sources"] is List &&
                    (map["sources"] as List).isNotEmpty
                ? (map["sources"] as List).first['id']?.toString() ?? ''
                : '',
            name: detectedType == ItemType.anime
                ? name.substring(9)
                : name.substring(10),
            pkgName: map['pkg'],
            apkName: map['apk'],
            lang: map['lang'],
            version: map['version'],
            isNsfw: map['isNsfw'] ?? false,
            itemType: detectedType,
            repo: repoUrl,
            iconUrl: "$baseIconUrl/icon/${map['pkg']}.png",
          ),
        );
      }

      final Map<String, List<ASource>> grouped = {};
      for (final s in sources) {
        final key = (s as ASource).pkgName ?? s.name ?? "unknown";
        grouped.putIfAbsent(key, () => []).add(s);
      }

      final filtered = <ASource>[];
      for (final group in grouped.values) {
        if (group.length > 1) {
          final allSource = group.firstWhere((s) => s.lang == 'all',
              orElse: () => group.firstWhere((s) => s.lang == 'en',
                  orElse: () => group.first));
          for (final s in group) {
            s.langs = group;
          }
          filtered.add(allSource);
        } else {
          filtered.add(group.first);
        }
      }

      return List.unmodifiable(filtered);
    } catch (e) {
      Logger.log("Failed to parse extensions from $repoUrl: $e");
      return const [];
    }
  }

  void _detectUpdates(List<ASource> available, ItemType type) {
    final installed = getInstalledRx(type).value as List<ASource>;
    final repoMap = {for (var s in available) s.id: s};

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..apkName = repo.apkName
          ..iconUrl = repo.iconUrl
          ..versionLast = repo.version;

        changed = true;
      }
    }

    if (changed) {
      getInstalledRx(type).value = List.unmodifiable(installed);
    }
  }

  @override
  Future<void> installSource(Source source, {String? customPath}) async {
    var aSource = source as ASource;
    if (aSource.apkUrl == null) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final packageName =
          aSource.apkUrl!.split('/').last.replaceAll('.apk', '');

      final res = await _client.get(Uri.parse(aSource.apkUrl!));

      if (res.statusCode != 200) {
        throw Exception('Failed to download APK: HTTP ${res.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';
      final apkFile = File(path.join(tempDir.path, apkFileName));

      await apkFile.writeAsBytes(res.bodyBytes);

      final result = await InstallPlugin.installApk(
        apkFile.path,
        appId: packageName,
      );

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      if (result['isSuccess'] != true) {
        throw Exception(
          'Installation failed: ${result['errorMessage'] ?? 'Unknown error'}',
        );
      }

      final avail = getAvailableRx(aSource.itemType!);
      avail.value = avail.value.where((e) => e.id != aSource.id).toList();

      switch (aSource.itemType) {
        case ItemType.anime:
          await fetchInstalledAnimeExtensions();
          break;
        case ItemType.manga:
          await fetchInstalledMangaExtensions();
          break;
        case ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }

      Logger.log('Successfully installed package: $packageName');
    } catch (e) {
      Logger.log('Error installing source: $e');
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as ASource;
    final packageName = s.pkgName;
    if (packageName == null || packageName.isEmpty) {
      throw Exception('Source ID is required for uninstallation.');
    }
    final type = source.itemType!;

    try {
      final isInstalled = await DeviceApps.isAppInstalled(packageName);
      if (!isInstalled) {
        getInstalledRx(type).value =
            getInstalledRx(type).value.where((e) => e.id != s.id).toList();
        return;
      }

      final success = await DeviceApps.uninstallApp(packageName);
      if (!success) {
        throw Exception('Failed to initiate uninstallation for: $packageName');
      }

      const timeout = Duration(seconds: 10);
      final start = DateTime.now();

      while (DateTime.now().difference(start) < timeout) {
        final stillInstalled = await DeviceApps.isAppInstalled(packageName);
        if (!stillInstalled) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final finalCheck = await DeviceApps.isAppInstalled(packageName);
      if (finalCheck) {
        throw Exception('Uninstallation timed out or was cancelled by user.');
      }

      final raw = getRawAvailableRx(type).value;
      final installed = getInstalledRx(type).value;
      final installedIds = installed.map((e) => e.id).toSet();

      getAvailableRx(type).value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );

      switch (s.itemType) {
        case ItemType.anime:
          await fetchInstalledAnimeExtensions();
          break;
        case ItemType.manga:
          await fetchInstalledMangaExtensions();
          break;
        case ItemType.novel:
          break;
        default:
          throw Exception('Unsupported item type: ${source.itemType}');
      }

      Logger.log('Successfully uninstalled package: $packageName');
    } catch (e) {
      Logger.log('Error uninstalling $packageName: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
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

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo");
      }

      final repo = Repo(url: repoUrl, managerId: id);
      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);

      final parsed = await compute(
        _parseExtensions,
        (res.body, repoUrl, type),
      );

      final rx = getAvailableRx(type);
      final existing = rx.value;
      final merged = {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values.toList(growable: false);

      rx.value = List.unmodifiable(merged);
      getReposRx(type).value = updatedRepos;
    } catch (e) {
      Logger.log("Failed to add repo $repoUrl: $e");
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

      final rx = getAvailableRx(type);
      rx.value = rx.value.where((s) => s.repo != repoUrl).toList();

      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove repo $repoUrl: $e");
    }
  }

  List<Repo> _loadRepos(ItemType type) {
    final newKey = '$id${type.name}Repos';
    final oldKey = 'aniyomi${type.name}ReposV2';

    final encoded =
        getVal<List<String>>(newKey) ?? getVal<List<String>>(oldKey);
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
  Set<String> get schemes => {"aniyomi", "tachiyomi"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(
        url,
        uri.scheme == "aniyomi" ? ItemType.anime : ItemType.manga,
      );
    }
  }
}
