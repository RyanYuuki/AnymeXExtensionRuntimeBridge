import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Runtime/Bridge/BridgeDispatcher.dart';
import '../../Runtime/DesktopExtensionBase.dart';
import 'package:http/http.dart' as http;

import '../../ExtensionBridge.dart';
import '../../Runtime/RuntimePaths.dart';
import '../Shared/TachiyomiJniDesktopExtension.dart';
import '../Shared/TachiyomiRepo.dart';
import 'Models/Source.dart';
import 'IReaderSourceMethods.dart';

class DesktopIReaderExtensions extends DesktopExtensionBase
    with TachiyomiJniDesktopExtension {
  final http.Client _client = AnymeXExtensionBridge.context.http ?? http.Client();

  @override
  String get id => 'ireader-desktop';

  @override
  String get name => 'IReader (Desktop)';

  @override
  String get icon =>
      'https://raw.githubusercontent.com/IReaderOrg/IReader/master/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => true;

  @override
  bool get requiresPlugin => true;

  @override
  String get jniDataDir => 'ireader';

  @override
  http.Client get repoClient => _client;

  @override
  SourceMethods createSourceMethods(Source source) =>
      IReaderSourceMethods(source);

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    final list = await _loadInstalled('getInstalledNovelExtensions', ItemType.novel);
    getInstalledRx(ItemType.novel).value = list;
    final available = getRawAvailableRx(ItemType.novel).value.whereType<IdSource>().toList();
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
        Logger.log('Desktop IReader failed to fetch repo ${repo.url}: $e');
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
      final dir = Directory(p.join(root.path, jniDataDir, type.toString()));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final result = await BridgeDispatcher().invokeMethod(method, {
        'path': dir.path,
      });

      if (result == null) return [];

      final List<dynamic> list = result is String ? jsonDecode(result) : result as List<dynamic>;

      return list
          .map((e) => IdSource.fromJson(Map<String, dynamic>.from(e as Map))..managerId = id)
          .where((s) => s.itemType == type)
          .toList(growable: false);
    } catch (e) {
      Logger.log('Desktop IReader loadInstalled error: $e');
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
      Logger.log('Desktop IReader addRepo error: $e');
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

  static List<IdSource> _parseExtensions(
    (Uint8List body, String repoUrl, ItemType itemType) args,
  ) =>
      parseTachiyomiIndexBytes<IdSource>(
        args.$1,
        args.$2,
        args.$3,
        prefixes: const {'': ItemType.novel},
        factory: (e) => IdSource(
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
