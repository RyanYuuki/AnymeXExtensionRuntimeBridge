import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import 'LegadoSourceMethods.dart';
import 'Models/LegadoSource.dart';

class LegadoExtensions extends Extension {
  static final http.Client _client = http.Client();

  @override
  String get id => 'legado';

  @override
  String get name => 'Legado';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => true;

  @override
  bool get requiresPlugin => false;

  @override
  SourceMethods createSourceMethods(Source source) => LegadoSourceMethods(source);

  @override
  Future<void> fetchAnimeExtensions() async {}

  @override
  Future<void> fetchMangaExtensions() async {}

  @override
  Future<void> fetchInstalledAnimeExtensions() async {}

  @override
  Future<void> fetchInstalledMangaExtensions() async {}

  @override
  Future<void> fetchNovelExtensions() async {
    final res = await _fetchExtensions(ItemType.novel);
    getAvailableRx(ItemType.novel).value = res;
  }

  @override
  Future<void> fetchInstalledNovelExtensions() async {
    final installed = _loadInstalled(ItemType.novel);
    getInstalledRx(ItemType.novel).value = installed;
  }

  @override
  Future<void> addRepo(String repoUrl, ItemType type) async {
    if (type != ItemType.novel) return;

    try {
      final uri = Uri.tryParse(repoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception("Invalid repo URL: $repoUrl");
      }

      final repos = _loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) {
        return;
      }

      final res = await _client.get(uri);
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo: ${res.statusCode}");
      }

      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      final parsed = await compute(_parseExtensions, (body, repoUrl, id));

      String? repoName;
      if (uri.pathSegments.isNotEmpty) {
        repoName = uri.pathSegments.last.replaceAll('.json', '');
      }

      final repo = Repo(
        url: repoUrl,
        name: repoName ?? 'Legado Repo',
        iconUrl: 'https://raw.githubusercontent.com/gedoor/legado/master/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
        managerId: id,
        extensions: parsed.length.toString(),
      );

      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);

      final rx = getAvailableRx(type);
      final existing = rx.value;

      final merged = {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values.toList(growable: false);

      rx.value = List.unmodifiable(merged);
      getReposRx(type).value = updatedRepos;
    } catch (e, st) {
      Logger.log("Failed to add Legado repo $repoUrl: $e\n$st");
      rethrow;
    }
  }

  @override
  Future<void> removeRepo(String repoUrl, ItemType type) async {
    if (type != ItemType.novel) return;

    try {
      final repos = _loadRepos(type)
          .where((r) => r.url != repoUrl)
          .toList(growable: false);

      _saveRepos(repos, type);

      final rx = getAvailableRx(type);
      rx.value = rx.value.where((s) => s.repo != repoUrl).toList();

      getReposRx(type).value = repos;
    } catch (e) {
      Logger.log("Failed to remove Legado repo $repoUrl: $e");
    }
  }

  @override
  Future<void> installSource(Source source) async {
    try {
      final type = ItemType.novel;
      final installed = _loadInstalled(type);

      if (installed.any((s) => s.id == source.id)) return;

      final legadoSource = source is LegadoSource
          ? source
          : LegadoSource.fromJson(source.toJson());

      final updated = List<LegadoSource>.from(installed)..add(legadoSource);
      _saveInstalled(updated, type);

      getInstalledRx(type).value = List.unmodifiable(updated);

      final available = getAvailableRx(type);
      available.value = available.value.where((s) => s.id != source.id).toList();
    } catch (e) {
      Logger.log("Failed to install Legado source ${source.id}: $e");
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    try {
      final type = ItemType.novel;
      final installed = _loadInstalled(type)
          .where((s) => s.id != source.id)
          .toList(growable: false);

      _saveInstalled(installed, type);
      getInstalledRx(type).value = List.unmodifiable(installed);

      final rawAvailable = getRawAvailableRx(type).value;
      final restored = rawAvailable.firstWhere(
        (s) => s.id == source.id,
        orElse: () => source,
      );

      final available = getAvailableRx(type);
      if (!available.value.any((s) => s.id == source.id)) {
        available.value = List.unmodifiable([...available.value, restored]);
      }
    } catch (e) {
      Logger.log("Failed to uninstall Legado source ${source.id}: $e");
    }
  }

  @override
  Future<void> updateSource(Source source) async {
    await installSource(source);
  }

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final results = await Future.wait(
      repos.map((r) => _fetchRepo(r)),
    );

    final allSources = results.expand((e) => e).toList(growable: false);

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    _detectUpdates(allSources, type);
    getRawAvailableRx(type).value = List.unmodifiable(allSources);

    return List.unmodifiable(
      allSources.where((s) => !installedIds.contains(s.id)),
    );
  }

  Future<List<Source>> _fetchRepo(Repo repo) async {
    try {
      final res = await _client.get(Uri.parse(repo.url));
      if (res.statusCode != 200) return const [];

      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      return compute(_parseExtensions, (body, repo.url, id));
    } catch (e) {
      Logger.log("Legado repo fetch failed ${repo.url}: $e");
      return const [];
    }
  }

  static List<Source> _parseExtensions((String body, String repoUrl, String managerId) args) {
    final (body, repoUrl, managerId) = args;

    try {
      final decoded = jsonDecode(body);
      Iterable<dynamic> rawList = [];

      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map && decoded['sources'] is List) {
        rawList = decoded['sources'];
      } else if (decoded is Map && decoded['data'] is List) {
        rawList = decoded['data'];
      } else if (decoded is Map) {
        rawList = [decoded];
      }

      final sources = <Source>[];
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          sources.add(LegadoSource.fromLegadoJson(item, repoUrl: repoUrl));
        } else if (item is Map) {
          sources.add(LegadoSource.fromLegadoJson(Map<String, dynamic>.from(item), repoUrl: repoUrl));
        }
      }

      return sources;
    } catch (e) {
      Logger.log("Failed to parse Legado extensions: $e");
      return const [];
    }
  }

  void _detectUpdates(List<Source> available, ItemType type) {
    final installed = getInstalledRx(type).value;
    if (installed.isEmpty) return;

    final availableMap = {for (final s in available) s.id: s};

    for (final inst in installed) {
      final match = availableMap[inst.id];
      if (match == null) continue;

      final hasUpdate = _isNewer(match.version, inst.version);
      inst.hasUpdate = hasUpdate;
      inst.versionLast = match.version;
    }

    getInstalledRx(type).refresh();
  }

  bool _isNewer(String? remote, String? local) {
    if (remote == null || local == null) return false;
    return remote.compareTo(local) > 0;
  }

  List<Repo> _loadRepos(ItemType type) {
    final encoded = getVal<List<String>>('$id${type.name}Repos');
    if (encoded == null || encoded.isEmpty) return const [];

    return encoded
        .map((e) => Repo.fromJson(jsonDecode(e)))
        .toList(growable: false);
  }

  void _saveRepos(List<Repo> repos, ItemType type) {
    final key = '$id${type.name}Repos';
    setVal(
      key,
      repos.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }

  List<LegadoSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null || encoded.isEmpty) return [];

    final list = <LegadoSource>[];
    for (final e in encoded) {
      try {
        list.add(LegadoSource.fromJson(jsonDecode(e))..managerId = id);
      } catch (_) {}
    }

    return list;
  }

  void _saveInstalled(List<LegadoSource> list, ItemType type) {
    final key = '$id-Installed-${type.name}';
    setVal(
      key,
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
  }
}
