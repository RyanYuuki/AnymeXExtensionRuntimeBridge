import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:get/get.dart';
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
  bool get requiresPlugin => true;

  @override
  Map<String, ExtensionSetting>? get settings => {
        'use_internal_anime_extension_loading': ExtensionSetting(
          label: 'Aniyomi Internal Anime Extensions',
          description: 'Install anime extensions only to AnymeX (No Package Manager)',
          value: getVal<bool>('use_internal_anime_extension_loading', defaultValue: false) ?? false,
          type: 'bool',
          onChanged: (val) {
            setVal('use_internal_anime_extension_loading', val as bool);
          },
        ),
        'use_internal_manga_extension_loading': ExtensionSetting(
          label: 'Aniyomi Internal Manga Extensions',
          description: 'Install manga extensions only to AnymeX (No Package Manager)',
          value: getVal<bool>('use_internal_manga_extension_loading', defaultValue: false) ?? false,
          type: 'bool',
          onChanged: (val) {
            setVal('use_internal_manga_extension_loading', val as bool);
          },
        ),
        'custom_anime_apk_path': ExtensionSetting(
          label: 'Custom Anime APK Path',
          description: 'Custom path to load anime extension APKs from',
          value: getVal<String>('custom_anime_apk_path', defaultValue: '') ?? '',
          type: 'string',
          onChanged: (val) {
            setVal('custom_anime_apk_path', val as String);
          },
        ),
        'custom_manga_apk_path': ExtensionSetting(
          label: 'Custom Manga APK Path',
          description: 'Custom path to load manga extension APKs from',
          value: getVal<String>('custom_manga_apk_path', defaultValue: '') ?? '',
          type: 'string',
          onChanged: (val) {
            setVal('custom_manga_apk_path', val as String);
          },
        ),
      };

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    final path = getVal<String>('custom_anime_apk_path', defaultValue: '') ?? '';
    getInstalledRx(ItemType.anime).value =
        await _loadInstalled('getInstalledAnimeExtensions', ItemType.anime, path);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    final path = getVal<String>('custom_manga_apk_path', defaultValue: '') ?? '';
    getInstalledRx(ItemType.manga).value =
        await _loadInstalled('getInstalledMangaExtensions', ItemType.manga, path);
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {}

  Future<List<Source>> _loadInstalled(String method, ItemType type, String path) async {
    try {
      final List<dynamic> result = await platform.invokeMethod(method, path);
      final parsed = result
          .map((e) => ASource.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.itemType == type)
          .toList(growable: false);

      final Map<String, List<ASource>> grouped = {};
      for (final s in parsed) {
        if (s.pkgName != null && s.pkgName!.isNotEmpty) {
          try {
            final isSys = await DeviceApps.isAppInstalled(s.pkgName!);
            s.isPrivate = !isSys;
          } catch (_) {}
        }
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

    _detectUpdates(all.whereType<ASource>().toList(), type);

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
    final installed = getInstalledRx(type).value.whereType<ASource>().toList();

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = available.firstWhereOrNull((s) {
        if (inst.pkgName != null && inst.pkgName!.isNotEmpty) {
          return s.pkgName == inst.pkgName;
        }
        return s.id == inst.id || s.name == inst.name;
      });

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

    final allAvailable = [
      ...getAvailableRx(ItemType.anime).value.whereType<ASource>(),
      ...getAvailableRx(ItemType.manga).value.whereType<ASource>(),
    ];

    final repoMatch = allAvailable.firstWhereOrNull((s) {
      if (aSource.pkgName != null && aSource.pkgName!.isNotEmpty) {
        return s.pkgName == aSource.pkgName;
      }
      return s.id == aSource.id || s.name == aSource.name;
    });

    if (repoMatch != null) {
      aSource.apkName ??= repoMatch.apkName;
      aSource.iconUrl ??= repoMatch.iconUrl;
      aSource.itemType ??= repoMatch.itemType;
      aSource.pkgName ??= repoMatch.pkgName;
    }

    if (aSource.apkUrl == null || aSource.apkUrl!.isEmpty) {
      return Future.error('Source APK URL is required for installation.');
    }

    try {
      final packageName =
          aSource.apkUrl!.split('/').last.replaceAll('.apk', '');

      final res = await _client.get(Uri.parse(aSource.apkUrl!));

      if (res.statusCode != 200) {
        throw Exception('Failed to download APK: HTTP ${res.statusCode}');
      }

      final defaultTempDir = await getTemporaryDirectory();
      final apkFileName = '$packageName.apk';

      String? targetDir = customPath;
      if (targetDir == null || targetDir.isEmpty) {
        if (aSource.itemType == ItemType.anime) {
          targetDir = getVal<String>('custom_anime_apk_path', defaultValue: '') ?? '';
        } else if (aSource.itemType == ItemType.manga) {
          targetDir = getVal<String>('custom_manga_apk_path', defaultValue: '') ?? '';
        }
      }

      File apkFile;
      bool isCustomPath = false;

      if (targetDir != null && targetDir.isNotEmpty) {
        try {
          final dir = Directory(targetDir);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          apkFile = File(path.join(dir.path, apkFileName));
          await apkFile.writeAsBytes(res.bodyBytes);
          isCustomPath = true;
          Logger.log('Saved APK to custom storage path: ${apkFile.path}');
        } catch (e) {
          Logger.log('Permission issue or write failure at custom path "$targetDir": $e. Falling back to default temporary directory.');
          apkFile = File(path.join(defaultTempDir.path, apkFileName));
          await apkFile.writeAsBytes(res.bodyBytes);
        }
      } else {
        apkFile = File(path.join(defaultTempDir.path, apkFileName));
        await apkFile.writeAsBytes(res.bodyBytes);
      }

      final useInternalSetting = aSource.itemType == ItemType.anime
          ? (getVal<bool>('use_internal_anime_extension_loading', defaultValue: false) ?? false)
          : (getVal<bool>('use_internal_manga_extension_loading', defaultValue: false) ?? false);

      final allInstalled = [
        ...getInstalledRx(ItemType.anime).value.whereType<ASource>(),
        ...getInstalledRx(ItemType.manga).value.whereType<ASource>(),
      ];
      final currentlyInstalled = allInstalled.firstWhereOrNull((s) =>
          (s.pkgName != null && aSource.pkgName != null && s.pkgName == aSource.pkgName) ||
          s.id == aSource.id ||
          s.name == aSource.name);

      bool isSystemInstalled = false;
      if (aSource.pkgName != null && aSource.pkgName!.isNotEmpty) {
        try {
          isSystemInstalled = await DeviceApps.isAppInstalled(aSource.pkgName!);
        } catch (_) {}
      }

      final bool shouldInstallInternal;
      if (isSystemInstalled) {
        shouldInstallInternal = false;
      } else if (currentlyInstalled != null && currentlyInstalled.isPrivate != null) {
        shouldInstallInternal = currentlyInstalled.isPrivate!;
      } else if (aSource.isPrivate != null) {
        shouldInstallInternal = aSource.isPrivate!;
      } else {
        shouldInstallInternal = useInternalSetting;
      }

      if (shouldInstallInternal) {
        final success = await installSourceInternal(source, apkFile.path);
        if (!success) {
          throw Exception('Internal installation failed for ${aSource.name}');
        }
      } else {
        final result = await InstallPlugin.installApk(
          apkFile.path,
          appId: packageName,
        );

        if (result['isSuccess'] != true) {
          throw Exception(
            'Installation failed: ${result['errorMessage'] ?? 'Unknown error'}',
          );
        }
      }

      if (!isCustomPath) {
        if (await apkFile.exists()) {
          await apkFile.delete();
        }
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

  Future<bool> installSourceInternal(Source source, String apkPath) async {
    final s = source as ASource;
    try {
      final success = await platform.invokeMethod<bool>('installSourceInternal', {
        'apkPath': apkPath,
        'isAnime': s.itemType == ItemType.anime,
      });
      return success ?? false;
    } catch (e) {
      Logger.log('Error in installSourceInternal: $e');
      return false;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as ASource;
    final packageName = s.pkgName;
    if (packageName == null || packageName.isEmpty) {
      throw Exception('Source ID is required for uninstallation.');
    }
    final type = source.itemType ??
        (packageName.contains('animeextension') ? ItemType.anime : ItemType.manga);

    try {
      try {
        await platform.invokeMethod<bool>('uninstallSourceInternal', {
          'packageName': packageName,
          'isAnime': type == ItemType.anime,
        });
      } catch (_) {}

      final isSystemInstalled = await DeviceApps.isAppInstalled(packageName);
      if (isSystemInstalled) {
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
      }

      getInstalledRx(type).value =
          getInstalledRx(type).value.where((e) => e.id != s.id && (e is ASource ? e.pkgName : null) != packageName).toList();

      switch (type) {
        case ItemType.anime:
          await fetchInstalledAnimeExtensions();
          break;
        case ItemType.manga:
          await fetchInstalledMangaExtensions();
          break;
        default:
          break;
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
  Future<void> cancelRequest(String token) async {
    await AnymeXRuntimeBridge.cancelRequest(token);
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
