import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import 'Services/Aniyomi/AniyomiExtensions.dart';
import 'Services/Aniyomi/Models/Source.dart';
import 'Services/CloudStream/CloudStreamExtensions.dart';
import 'Services/Mangayomi/MangayomiExtensions.dart';
import 'Services/Sora/Models/Source.dart';
import 'Services/Sora/SoraExtensions.dart';
import 'anymex_extension_runtime_bridge.dart';

class ExtensionManager extends GetxController {
  final managers = <Extension>[].obs;

  final installedAnimeExtensions = <Source>[].obs;
  final installedMangaExtensions = <Source>[].obs;
  final installedNovelExtensions = <Source>[].obs;

  final availableAnimeExtensions = <Source>[].obs;
  final availableMangaExtensions = <Source>[].obs;
  final availableNovelExtensions = <Source>[].obs;

  final _workers = <Worker>[];
  final _pendingAggregations = <ItemType>{};
  Timer? _aggregateTimer;

  @override
  void onInit() {
    super.onInit();
    _initDefaultManagers();
  }

  Future<void> _initDefaultManagers() async {
    await _registerAndInitializeManagers([
      SoraExtensions(),
      MangayomiExtensions(),
    ]);

    await onRuntimeBridgeInitialization();
  }

  Future<void> onRuntimeBridgeInitialization({
    Function(String managerId)? onManagerInitializing,
  }) async {
    final isAnymeXRuntimeHostLoaded = await AnymeXRuntimeBridge.isLoaded();
    if (isAnymeXRuntimeHostLoaded) {
      await _registerAndInitializeManagers(
        [
          AniyomiExtensions(),
          CloudStreamExtensions(),
        ],
        insertAtStart: true,
        onManagerInitializing: onManagerInitializing,
      );
    }
  }

  Future<void> _registerAndInitializeManagers(
    List<Extension> newManagers, {
    bool insertAtStart = false,
    Function(String managerId)? onManagerInitializing,
  }) async {
    bool listChanged = false;
    int insertIndex = 0;

    for (final manager in newManagers) {
      if (managers.any((m) => m.runtimeType == manager.runtimeType)) continue;

      onManagerInitializing?.call(manager.id);

      if (insertAtStart) {
        managers.insert(insertIndex++, manager);
      } else {
        managers.add(manager);
      }

      listChanged = true;

      await manager.initialize();

      for (final type in ItemType.values) {
        _workers.addAll([
          ever(
            manager.getInstalledRx(type),
            (_) => _scheduleAggregatedUpdate(type),
          ),
          ever(
            manager.getAvailableRx(type),
            (_) => _scheduleAggregatedUpdate(type),
          ),
        ]);
      }
    }

    if (listChanged) {
      _refreshAllAggregatedLists();
    }
  }

  @override
  void onClose() {
    _aggregateTimer?.cancel();
    for (final worker in _workers) {
      worker.dispose();
    }
    super.onClose();
  }

  void _scheduleAggregatedUpdate(ItemType type) {
    _pendingAggregations.add(type);
    _aggregateTimer?.cancel();
    _aggregateTimer = Timer(const Duration(milliseconds: 50), () {
      for (final pendingType in _pendingAggregations) {
        _updateAggregatedLists(pendingType);
      }
      _pendingAggregations.clear();
    });
  }

  void _refreshAllAggregatedLists() {
    for (final type in ItemType.values) {
      _updateAggregatedLists(type);
    }
  }

  void _updateAggregatedLists(ItemType type) {
    final installedList =
        managers.expand((m) => m.getInstalledRx(type).value).toList();
    final availableList =
        managers.expand((m) => m.getAvailableRx(type).value).toList();

    switch (type) {
      case ItemType.anime:
        installedAnimeExtensions.assignAll(installedList);
        availableAnimeExtensions.assignAll(availableList);
        break;
      case ItemType.manga:
        installedMangaExtensions.assignAll(installedList);
        availableMangaExtensions.assignAll(availableList);
        break;
      case ItemType.novel:
        installedNovelExtensions.assignAll(installedList);
        availableNovelExtensions.assignAll(availableList);
        break;
    }
  }

  Future<void> refreshExtensions({bool refreshAvailableSource = false}) async {
    if (!refreshAvailableSource) {
      _refreshAllAggregatedLists();
      return;
    }

    final futures = <Future>[];
    for (final manager in managers) {
      if (manager.supportsAnime) futures.add(manager.fetchAnimeExtensions());
      if (manager.supportsManga) futures.add(manager.fetchMangaExtensions());
      if (manager.supportsNovel) futures.add(manager.fetchNovelExtensions());
    }

    await Future.wait(futures);
    _refreshAllAggregatedLists();
  }

  Future<void> refreshManagerType(
    String managerId,
    ItemType type, {
    bool refreshAvailableSource = true,
    bool refreshInstalledSource = true,
  }) async {
    final manager = findById(managerId);
    if (manager == null) return;

    final futures = <Future>[];

    if (refreshInstalledSource) {
      futures.add(_refreshInstalledForType(manager, type));
    }
    if (refreshAvailableSource) {
      futures.add(_refreshAvailableForType(manager, type));
    }

    await Future.wait(futures);
    _updateAggregatedLists(type);
  }

  Future<void> _refreshInstalledForType(
      Extension manager, ItemType type) async {
    switch (type) {
      case ItemType.anime:
        if (manager.supportsAnime) {
          await manager.fetchInstalledAnimeExtensions();
        }
        break;
      case ItemType.manga:
        if (manager.supportsManga) {
          await manager.fetchInstalledMangaExtensions();
        }
        break;
      case ItemType.novel:
        if (manager.supportsNovel) {
          await manager.fetchInstalledNovelExtensions();
        }
        break;
    }
  }

  Future<void> _refreshAvailableForType(
      Extension manager, ItemType type) async {
    switch (type) {
      case ItemType.anime:
        if (manager.supportsAnime) await manager.fetchAnimeExtensions();
        break;
      case ItemType.manga:
        if (manager.supportsManga) await manager.fetchMangaExtensions();
        break;
      case ItemType.novel:
        if (manager.supportsNovel) await manager.fetchNovelExtensions();
        break;
    }
  }

  T? find<T extends Extension>() {
    for (final manager in managers) {
      if (manager is T) return manager;
    }
    return null;
  }

  T get<T extends Extension>() {
    final result = find<T>();
    if (result == null) {
      throw Exception(
        'Extension manager of type $T not registered\n'
        'Perhaps $T is not supported on ${Platform.operatingSystem}?',
      );
    }
    return result;
  }

  Extension? findById(String id) =>
      managers.firstWhereOrNull((m) => m.id == id);

  Future<void> addRepo(String url, ItemType type, String managerId) async {
    final manager = findById(managerId);
    if (manager != null) await manager.addRepo(url, type);
  }

  Future<void> addRepos(
      List<String> urls, ItemType type, String managerId) async {
    final manager = findById(managerId);
    if (manager == null) return;

    final validUrls = urls.map((u) => u.trim()).where((u) => u.isNotEmpty);
    await Future.wait(validUrls.map((url) => manager.addRepo(url, type)));
  }

  Future<void> removeRepo(Repo repo, ItemType type) async {
    final manager = findById(repo.managerId ?? '');
    if (manager != null) await manager.removeRepo(repo.url, type);
  }

  List<Repo> getAllRepos(ItemType type) =>
      managers.expand((m) => m.getReposRx(type).value).toList();

  Rx<List<Repo>> getReposRx(ItemType type, String managerId) =>
      findById(managerId)?.getReposRx(type) ?? Rx<List<Repo>>([]);

  Future<void> updateAll() async {
    final updateTasks = <Future>[];

    for (final type in ItemType.values) {
      for (final src in _getInstalledList(type)) {
        if (src.hasUpdate ?? false) {
          updateTasks.add(src.update());
        }
      }
    }

    await Future.wait(updateTasks);
  }

  List<Source> _getInstalledList(ItemType type) {
    switch (type) {
      case ItemType.anime:
        return installedAnimeExtensions;
      case ItemType.manga:
        return installedMangaExtensions;
      case ItemType.novel:
        return installedNovelExtensions;
    }
  }
}

extension SourceExecution on Source {
  SourceMethods get methods {
    if (this is SourceMethods) return this as SourceMethods;
    return getSourceManager(this).createSourceMethods(this);
  }

  String get extensionType => getSourceManager(this).id;

  String get managerIcon => switch (this) {
        ASource _ => 'https://aniyomi.org/img/logo-128px.png',
        MSource _ =>
          'https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png',
        SSource _ => 'https://static.everythingmoe.com/icons/sora.png',
        CloudStreamSource _ =>
          'https://static.everythingmoe.com/icons/cloudstream.png',
        _ => 'mangayomi',
      };

  Future<void> install() async => getSourceManager(this).installSource(this);
  Future<void> uninstall() async =>
      getSourceManager(this).uninstallSource(this);
  Future<void> update() async => getSourceManager(this).updateSource(this);
}

Extension getSourceManager(Source source) {
  final em = Get.find<ExtensionManager>();

  if (source is ASource) return em.findById('aniyomi')!;
  if (source is MSource) return em.findById('mangayomi')!;
  if (source is SSource) return em.findById('sora')!;
  if (source is CloudStreamSource) return em.findById('cloudstream')!;

  return em.findById('mangayomi')!;
}
