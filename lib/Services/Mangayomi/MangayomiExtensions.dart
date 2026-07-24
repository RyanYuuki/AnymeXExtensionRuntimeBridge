import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import '../Mangayomi/http/m_client.dart';
import 'MangayomiSourceMethods.dart';
import 'Models/Source.dart';
import 'Util/lib.dart';

class MangayomiExtensions extends Extension {
  static final _client = MClient.init();

  @override
  String get id => 'mangayomi';

  @override
  String get name => 'Mangayomi';

  @override
  SourceMethods createSourceMethods(Source source) =>
      MangayomiSourceMethods(source);

  @override
  Future<void> fetchAnimeExtensions() async {
    final res = await _fetchExtensions(ItemType.anime);
    _detectUpdates(res, ItemType.anime);
  }

  @override
  Future<void> fetchMangaExtensions() async {
    final res = await _fetchExtensions(ItemType.manga);
    _detectUpdates(res, ItemType.manga);
  }

  @override
  Future<void> fetchNovelExtensions() async {
    final res = await _fetchExtensions(ItemType.novel);
    _detectUpdates(res, ItemType.novel);
  }

  Future<List<Source>> fetchExtensions(ItemType type) async {
    return _fetchExtensions(type);
  }

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    final allSources = <Source>[];

    for (final repo in repos) {
      final sources = await _fetchRepoSources(repo, type);
      allSources.addAll(sources);
    }

    final rawRx = getRawAvailableRx(type);
    rawRx.value = List.unmodifiable(allSources);

    final installed = _loadInstalled(type);
    final installedIds = installed.map((e) => e.id).toSet();

    final filtered =
        allSources.where((s) => !installedIds.contains(s.id)).toList();

    getAvailableRx(type).value = List.unmodifiable(filtered);
    return filtered;
  }

  Future<List<Source>> _fetchRepoSources(Repo repo, ItemType type) async {
    try {
      final res = await _client.get(Uri.parse(repo.url));
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo");
      }

      final parsed = await compute(
        _parseExtensions,
        (res.body, repo.url, type),
      );

      return parsed;
    } catch (e) {
      Logger.log("Repo failed ${repo.url}: $e");
      return const [];
    }
  }

  @override
  Future<void> fetchInstalledAnimeExtensions() async {
    getInstalledRx(ItemType.anime).value = _loadInstalled(ItemType.anime);
  }

  @override
  Future<void> fetchInstalledMangaExtensions() async {
    getInstalledRx(ItemType.manga).value = _loadInstalled(ItemType.manga);
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    getInstalledRx(ItemType.novel).value = _loadInstalled(ItemType.novel);
  }

  @override
  Future<void> installSource(Source source) async {
    final m = source as MSource;
    final type = m.itemType ?? ItemType.manga;

    final available = getAvailableRx(type).value.whereType<MSource>();
    final repoMatch = available.firstWhereOrNull((s) => s.id == m.id);

    if (repoMatch?.sourceCodeUrl != null && repoMatch!.sourceCodeUrl!.isNotEmpty) {
      m.sourceCodeUrl ??= repoMatch.sourceCodeUrl;
    }

    if (m.sourceCodeUrl == null || m.sourceCodeUrl!.isEmpty) {
      throw Exception("Extension source URL is required for installation.");
    }

    try {
      final res = await _client.get(Uri.parse(m.sourceCodeUrl!));

      print("Installing source: ${m.id} => ${m.sourceCodeUrl}");

      if (res.statusCode != 200) {
        throw Exception("Extension download failed");
      }

      if (m.versionLast != null && m.versionLast!.isNotEmpty) {
        m.version = m.versionLast;
      } else if (repoMatch?.version != null && repoMatch!.version!.isNotEmpty) {
        m.version = repoMatch.version;
      }
      m.hasUpdate = false;

      final installed = m
        ..sourceCode = res.body
        ..headers = jsonEncode(
          getExtensionService(m).getHeaders(),
        );

      final list = _loadInstalled(m.itemType!);

      list.removeWhere((e) => e.id == m.id);
      list.add(installed);

      _saveInstalled(list, m.itemType!);

      getInstalledRx(m.itemType!).value = List.unmodifiable(list);

      final avail = getAvailableRx(m.itemType!);
      avail.value = avail.value.where((e) => e.id != m.id).toList();
    } catch (e) {
      Logger.log("Install failed ${m.id}: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as MSource;

    try {
      final type = s.itemType!;
      final installed = _loadInstalled(type);

      installed.removeWhere((e) => e.id == s.id);

      _saveInstalled(installed, type);
      getInstalledRx(type).value = List.unmodifiable(installed);

      final raw = getRawAvailableRx(type).value;
      final installedIds = installed.map((e) => e.id).toSet();

      getAvailableRx(type).value = List.unmodifiable(
        raw.where((e) => !installedIds.contains(e.id)),
      );
    } catch (e) {
      Logger.log("Uninstall failed ${s.id}: $e");
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  void _detectUpdates(List<Source> available, ItemType type) {
    final installed = _loadInstalled(type);

    final repoMap = {for (var s in available) s.id: s};

    bool changed = false;

    for (var i = 0; i < installed.length; i++) {
      final inst = installed[i];
      final repo = repoMap[inst.id];

      if (repo == null) continue;

      if (compareVersions(repo.version ?? "0", inst.version ?? "0") > 0) {
        installed[i] = inst
          ..hasUpdate = true
          ..versionLast = repo.version;
        changed = true;
      }
    }

    if (changed) {
      _saveInstalled(installed, type);
      getInstalledRx(type).value = List.unmodifiable(installed);
    }
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid URL");
      }

      final repos = _loadRepos(type);

      if (repos.any((r) => r.url == repoUrl)) {
        return;
      }

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

  static List<Source> _parseExtensions(
      (String body, String repoUrl, ItemType itemType) args) {
    final (body, repoUrl, itemType) = args;

    final decoded = jsonDecode(body);

    if (decoded is! List) return const [];

    final sources = <Source>[];

    for (final e in decoded) {
      final ext = Map<String, dynamic>.from(e);

      sources.add(
        MSource.fromJson(ext)..repo = repoUrl,
      );
    }

    return sources.where((s) => s.itemType == itemType).toList(growable: false);
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

  List<MSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null) return [];

    return encoded.map((e) => MSource.fromJson(jsonDecode(e))).toList();
  }

  void _saveInstalled(List<MSource> list, ItemType type) {
    setVal(
      '$id-Installed-${type.name}',
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  List<Repo> _loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('$id${type.name}Repos');
    if (encoded == null) return [];

    return encoded.map((e) => Repo.fromJson(jsonDecode(e))).toList();
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    setVal(
      '$id${type.name}Repos',
      repos.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  String _convertLang(String lang) {
    switch (lang) {
      case "English":
        return "en";
      case "Français":
        return "fr";
      case "Español":
        return "es";
      case "Português":
        return "pt";
      case "Русский":
        return "ru";
      case "日本語":
        return "ja";
      case "中文, 汉语, 漢語":
        return "zh";
      default:
        return "all";
    }
  }

  @override
  Set<String> get schemes => {"dar", "anymex", "sugoireads", "mangayomi"};

  @override
  void handleSchemes(Uri uri) {
    final qp = uri.queryParameters;

    if (uri.host == "add-repo") {
      final repoUrl = qp["repo_url"] ?? qp['url'] ?? qp['anime_url'];
      final mangaUrl = qp["manga_url"];
      final novelUrl = qp["novel_url"];

      if (mangaUrl != null && mangaUrl.isNotEmpty) {
        addRepo(mangaUrl, ItemType.manga);
      }

      if (novelUrl != null && novelUrl.isNotEmpty) {
        addRepo(novelUrl, ItemType.novel);
      }

      if (repoUrl != null && repoUrl.isNotEmpty) {
        addRepo(repoUrl, ItemType.anime);
      }
    }
  }
}
