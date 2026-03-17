import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../Models/Source.dart';
import 'SourceMethods.dart';

abstract class Extension {
  String get id;
  String get name;

  bool get supportsAnime => true;
  bool get supportsManga => true;
  bool get supportsNovel => true;

  SourceMethods createSourceMethods(Source source);

  final Map<ItemType, Rx<List<Source>>> _installed = {
    ItemType.anime: Rx<List<Source>>([]),
    ItemType.manga: Rx<List<Source>>([]),
    ItemType.novel: Rx<List<Source>>([]),
  };

  final Map<ItemType, Rx<List<Source>>> _available = {
    ItemType.anime: Rx<List<Source>>([]),
    ItemType.manga: Rx<List<Source>>([]),
    ItemType.novel: Rx<List<Source>>([]),
  };
  final Map<ItemType, Rx<List<Source>>> _availableRaw = {
    ItemType.anime: Rx<List<Source>>([]),
    ItemType.manga: Rx<List<Source>>([]),
    ItemType.novel: Rx<List<Source>>([]),
  };
  final Map<ItemType, Rx<List<Repo>>> _repos = {
    ItemType.anime: Rx<List<Repo>>([]),
    ItemType.manga: Rx<List<Repo>>([]),
    ItemType.novel: Rx<List<Repo>>([]),
  };

  @mustCallSuper
  Future<void> initialize() async {
    try {
      if (supportsAnime) {
        unawaited(fetchInstalledAnimeExtensions());
        unawaited(fetchAnimeExtensions());
      }

      if (supportsManga) {
        unawaited(fetchInstalledMangaExtensions());
        unawaited(fetchMangaExtensions());
      }

      if (supportsNovel) {
        unawaited(fetchInstalledNovelExtensions());
        unawaited(fetchNovelExtensions());
      }
    } catch (e, s) {
      debugPrint('Error initializing extension $id: $e\n$s');
    }
  }

  Future<void> addRepo(String repoUrl, ItemType type);

  Future<void> removeRepo(String repoUrl, ItemType type);

  Future<void> installSource(Source source);

  Future<void> uninstallSource(Source source);

  Future<void> updateSource(Source source);

  Future<void> fetchAnimeExtensions();

  Future<void> fetchMangaExtensions();

  Future<void> fetchNovelExtensions();

  Future<void> fetchInstalledAnimeExtensions();

  Future<void> fetchInstalledMangaExtensions();

  Future<void> fetchInstalledNovelExtensions();

  Set<String> get schemes => {};

  void handleSchemes(Uri uri) {}

  /// Helpers
  Rx<List<Source>> getInstalledRx(ItemType type) => _installed[type]!;

  Rx<List<Source>> getAvailableRx(ItemType type) => _available[type]!;
  Rx<List<Source>> getRawAvailableRx(ItemType type) => _availableRaw[type]!;

  Rx<List<Repo>> getReposRx(ItemType type) => _repos[type]!;

  Future<void> setInstalled(ItemType type, List<Source> sources) async {
    getInstalledRx(type).value = sources;
  }

  int compareVersions(String v1, String v2) {
    final a = v1.split('.').map(int.tryParse).toList();
    final b = v2.split('.').map(int.tryParse).toList();

    for (int i = 0; i < a.length || i < b.length; i++) {
      final n1 = i < a.length ? a[i] ?? 0 : 0;
      final n2 = i < b.length ? b[i] ?? 0 : 0;

      if (n1 != n2) return n1.compareTo(n2);
    }

    return 0;
  }
}

class Repo {
  final String url;

  final String? name;
  final String? iconUrl;
  final String? extensions;
  final String? managerId;

  Repo({
    required this.url,
    this.name,
    this.iconUrl,
    this.extensions,
    this.managerId,
  });

  factory Repo.fromJson(Map<String, dynamic> json) {
    return Repo(
      url: json['url'],
      name: json['name'],
      iconUrl: json['iconUrl'],
      extensions: json['extensions'],
      managerId: json['managerId'],
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'iconUrl': iconUrl,
        'extensions': extensions,
        'managerId': managerId,
      };
}
