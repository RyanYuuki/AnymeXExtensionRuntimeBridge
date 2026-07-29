import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../anymex_extension_runtime_bridge.dart';

class KotatsuSourceMethods extends SourceMethods {
  @override
  final KotatsuSource source;

  KotatsuSourceMethods(Source source) : source = source as KotatsuSource;

  static const platform = MethodChannel('kotatsuExtensionBridge');

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final result = await platform.invokeMethod('getDetail', {
      'sourceId': source.id,
      'url': media.url,
      'title': media.title,
      'cover': media.cover,
    });

    final dMedia = await compute(
      DMedia.fromJson,
      Map<String, dynamic>.from(result as Map),
    );

    if (dMedia.episodes != null) {
      dMedia.episodes = dMedia.episodes!.reversed.toList();
    }

    return dMedia;
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    final result = await platform.invokeMethod('getLatestUpdates', {
      'sourceId': source.id,
      'page': page,
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    final result = await platform.invokeMethod('getPopular', {
      'sourceId': source.id,
      'page': page,
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters}) async {
    return const [];
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters}) async {
    final result = await platform.invokeMethod('getPageList', {
      'sourceId': source.id,
      'url': episode.url,
      'name': episode.name,
    });

    return compute(parsePageUrls, List<dynamic>.from(result));
  }

  @override
  Future<Pages> search(String query, int page, List filters,
      {SourceParams? parameters}) async {
    final result = await platform.invokeMethod('search', {
      'sourceId': source.id,
      'query': query,
      'page': page,
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  List<PageUrl> parsePageUrls(List<dynamic> list) {
    return list
        .map((e) => PageUrl.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters}) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelRequest(String token) async {
    await AnymeXRuntimeBridge.cancelRequest(token);
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    return const [];
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    return false;
  }
}
