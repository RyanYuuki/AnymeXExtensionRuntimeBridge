import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../ExtensionBridge.dart';
import '../../Extensions/Extensions.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import '../../Settings/KvStore.dart';
import 'LnReaderSourceMethods.dart';
import 'Manifest.dart';
import 'Models/Source.dart';

class LnReaderExtensions extends Extension {
  static http.Client get _client => AnymeXExtensionBridge.context.http ?? http.Client();

  @override
  String get id => 'lnreader';

  @override
  String get name => 'LNReader';

  @override
  String get icon =>
      'https://raw.githubusercontent.com/LNReader/lnreader/master/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

  @override
  bool get supportsAnime => false;

  @override
  bool get supportsManga => false;

  @override
  bool get supportsNovel => true;

  @override
  SourceMethods createSourceMethods(Source source) =>
      LnReaderSourceMethods(source);

  void dispose() {
    LnReaderSourceMethods.disposeAll();
  }

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
        throw Exception("Invalid repo URL");
      }

      final repos = _loadRepos(type);
      if (repos.any((r) => r.url == repoUrl)) return;

      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw Exception("Failed to fetch repo (${res.statusCode})");
      }

      final parsed = await compute(_parseExtensions, (
        res.body,
        repoUrl,
        type,
      ));

      String? repoName;
      if (uri.pathSegments.isNotEmpty) {
        repoName = uri.pathSegments.last.replaceAll('.json', '');
      }

      final repo = Repo(
        url: repoUrl,
        name: repoName ?? 'LNReader Repo',
        extensions: parsed.length.toString(),
        managerId: id,
      );

      final updatedRepos = List<Repo>.from(repos)..add(repo);
      _saveRepos(updatedRepos, type);
      getReposRx(type).value = updatedRepos;

      final rx = getAvailableRx(type);
      final existing = rx.value;
      final merged = {
        for (final s in existing) s.id: s,
        for (final s in parsed) s.id: s,
      }.values.toList(growable: false);

      rx.value = List.unmodifiable(merged);
    } catch (e) {
      Logger.log("Failed to add LNReader repo $repoUrl: $e");
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
      Logger.log("Failed to remove LNReader repo $repoUrl: $e");
    }
  }

  static List<Source> _parseExtensions(
    (String body, String repoUrl, ItemType itemType) args,
  ) {
    final (body, repoUrl, itemType) = args;
    if (itemType != ItemType.novel) return const [];
    return parseLnReaderManifest(body, repoUrl);
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source is LSource ? source : LSource.fromJson(source.toJson());
    final type = s.itemType ?? ItemType.novel;

    try {
      if (s.sourceCodeUrl == null) throw Exception("Missing plugin URL");

      final res = await _client.get(Uri.parse(s.sourceCodeUrl!));
      if (res.statusCode != 200) {
        throw Exception("Plugin download failed (${res.statusCode})");
      }
      s.sourceCode = res.body;

      if (s.customCssUrl != null && s.customCssUrl!.isNotEmpty) {
        try {
          final css = await _client.get(Uri.parse(s.customCssUrl!));
          if (css.statusCode == 200) s.customCss = css.body;
        } catch (_) {}
      }

      final list = _loadInstalled(type)..removeWhere((e) => e.id == s.id);
      list.add(s);
      _saveInstalled(list, type);
      getInstalledRx(type).value = List.unmodifiable(list);

      final avail = getAvailableRx(type);
      avail.value = avail.value.where((e) => e.id != s.id).toList();
    } catch (e) {
      Logger.log("Install failed ${s.id}: $e");
      rethrow;
    }
  }

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as LSource;
    final type = s.itemType ?? ItemType.novel;

    try {
      final list = _loadInstalled(type)..removeWhere((e) => e.id == s.id);
      _saveInstalled(list, type);
      getInstalledRx(type).value = List.unmodifiable(list);

      final installedIds = list.map((e) => e.id).toSet();
      final raw = getRawAvailableRx(type).value;
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

  Future<List<Source>> _fetchExtensions(ItemType type) async {
    final repos = _loadRepos(type);
    if (repos.isEmpty) return const [];

    getReposRx(type).value = repos;

    final results = await Future.wait(repos.map((r) => _fetchRepo(r, type)));
    final allSources = results.expand((e) => e).toList(growable: false);

    final installed = getInstalledRx(type).value;
    final installedIds = installed.map((e) => e.id).toSet();

    getRawAvailableRx(type).value = List.unmodifiable(allSources);
    return List.unmodifiable(
      allSources.where((s) => !installedIds.contains(s.id)),
    );
  }

  Future<List<Source>> _fetchRepo(Repo repo, ItemType type) async {
    try {
      final res = await _client
          .get(Uri.parse(repo.url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];

      return compute(_parseExtensions, (res.body, repo.url, type));
    } catch (e) {
      Logger.log("LNReader repo failed ${repo.url}: $e");
      return const [];
    }
  }

  List<LSource> _loadInstalled(ItemType type) {
    final encoded = getVal<List<String>>('$id-Installed-${type.name}');
    if (encoded == null || encoded.isEmpty) return [];

    final list = <LSource>[];
    for (final e in encoded) {
      try {
        list.add(LSource.fromJson(jsonDecode(e))..managerId = id);
      } catch (_) {}
    }
    return list;
  }

  void _saveInstalled(List<LSource> list, ItemType type) {
    setVal(
      '$id-Installed-${type.name}',
      list.map((e) => jsonEncode(e.toJson())).toList(growable: false),
    );
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

  @override
  Set<String> get schemes => {"lnreader"};

  @override
  void handleSchemes(Uri uri) {
    final url = uri.queryParameters["url"];
    if (url != null && url.isNotEmpty) {
      addRepo(url, ItemType.novel);
    }
  }
}
