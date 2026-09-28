import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import 'package:http/http.dart' as http;

import '../../ExtensionBridge.dart';
import '../../Runtime/RuntimePaths.dart';
import '../Shared/TachiyomiRepo.dart';
import 'Models/Source.dart';
import 'TsundokuSourceMethods.dart';

class TsundokuExtensions extends Extension {
  final http.Client _client = AnymeXExtensionBridge.context.http ?? http.Client();

  @override
  String get id => 'tsundoku';

  @override
  String get name => 'Tsundoku';

  @override
  String get icon =>
      'https://raw.githubusercontent.com/tsundoku-otaku/tsundoku/main/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => true;

  @override
  bool get requiresPlugin => true;

  static const platform = MethodChannel('tsundokuExtensionBridge');

  @override
  SourceMethods createSourceMethods(Source source) =>
      TsundokuSourceMethods(source);

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    final list = await _loadInstalled('getInstalledNovelExtensions', ItemType.novel);
    getInstalledRx(ItemType.novel).value = list;
    final available = getRawAvailableRx(ItemType.novel).value.whereType<TSource>().toList();
    if (available.isNotEmpty) {
      detectTachiyomiUpdates(this, available, ItemType.novel);
    }
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {}

  @override
  Future<void> fetchInstalledMangaExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {
    final repos = getReposRx(ItemType.novel).value;
    final allSources = <Source>[];

    for (final repo in repos) {
      try {
        final index = await fetchTachiyomiRepoIndex(_client, repo.url);
        final parsed = await compute(
          _parseExtensions,
          (index.body, index.url, ItemType.novel),
        );
        allSources.addAll(parsed);
      } catch (e) {
        Logger.log('Tsundoku failed to fetch repo ${repo.url}: $e');
      }
    }

    getRawAvailableRx(ItemType.novel).value = allSources;

    final installedIds = getInstalledRx(ItemType.novel).value.map((e) => e.id).toSet();
    getAvailableRx(ItemType.novel).value =
        allSources.where((s) => !installedIds.contains(s.id)).toList();

    detectTachiyomiUpdates(this, allSources, ItemType.novel);
  }

  @override
  Future<void> fetchAnimeExtensions() async {}

  @override
  Future<void> fetchMangaExtensions() async {}

  Future<List<Source>> _loadInstalled(String method, ItemType type) async {
    try {
      final root = await RuntimePaths().extensionsDir;
      final path = p.join(root.path, 'tsundoku', type.toString());
      final jsonString = await platform.invokeMethod<String>(method, path);

      if (jsonString == null || jsonString.isEmpty) return [];

      final List<dynamic> result = jsonDecode(jsonString);
      return result
          .map((e) => TSource.fromJson(Map<String, dynamic>.from(e))..managerId = id)
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e) {
      Logger.log('Tsundoku loadInstalled error: $e');
      return [];
    }
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) return;

      final normalizedUrl = repoUrl.replaceAll(RegExp(r'/+$'), '');
      final currentRepos = getReposRx(type).value;
      if (currentRepos.any((r) => r.url == normalizedUrl)) return;

      final index = await fetchTachiyomiRepoIndex(_client, normalizedUrl);
      final parsed = await compute(
        _parseExtensions,
        (index.body, index.url, type),
      );

      final repo = Repo(
        name: normalizedUrl.split('/').where((s) => s.isNotEmpty).last,
        url: normalizedUrl,
        extensions: parsed.length.toString(),
        managerId: id,
      );

      final updated = List<Repo>.from(currentRepos)..add(repo);
      getReposRx(type).value = updated;
      await fetchNovelExtensions();
    } catch (e) {
      Logger.log('Tsundoku addRepo error: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    final normalizedUrl = repoUrl.replaceAll(RegExp(r'/+$'), '');
    final current = getReposRx(type).value;
    getReposRx(type).value = current.where((r) => r.url != normalizedUrl).toList();
    await fetchNovelExtensions();
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as TSource;
    final apkUrl = s.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      throw Exception('Source APK URL is missing');
    }

    final packageName = s.pkgName ?? p.basenameWithoutExtension(apkUrl);
    final apkFileName = '$packageName.apk';

    final tempDir = await getTemporaryDirectory();
    final apkFile = File(p.join(tempDir.path, apkFileName));

    await downloadPackageFile(_client, apkUrl, apkFile.path);

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

    final avail = getAvailableRx(ItemType.novel);
    avail.value = avail.value.where((e) => e.id != s.id).toList();
    await fetchInstalledNovelExtensions();
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as TSource;
    final pkg = s.pkgName;
    if (pkg == null || pkg.isEmpty) return;

    try {
      await platform.invokeMethod('uninstallExtension', {'pkgName': pkg});
    } catch (_) {}

    await fetchInstalledNovelExtensions();
  }

  @override
  Future<void> updateSource(Source source) => installSource(source);

  static List<TSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) =>
      parseTachiyomiIndexBytes<TSource>(
        args.$1,
        args.$2,
        args.$3,
        prefixes: const {'Tsundoku: ': ItemType.novel},
        factory: (e) => TSource(
          id: e.id,
          name: e.name,
          pkgName: e.pkgName,
          apkName: e.apkName,
          lang: e.lang,
          version: e.version,
          isNsfw: e.isNsfw,
          itemType: e.itemType,
          repo: e.repo,
          iconUrl: e.iconUrl,
          apkUrlOverride: e.apkUrl,
          jarUrl: e.jarUrl,
        ),
      );
}
