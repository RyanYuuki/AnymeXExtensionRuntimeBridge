import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../../anymex_extension_runtime_bridge.dart';
import '../Aniyomi/Models/Source.dart';
import '../../Logger.dart';

class DesktopAniyomiSourceMethods extends SourceMethods {
  @override
  final ASource source;

  DesktopAniyomiSourceMethods(Source source) : source = source as ASource;

  bool get isAnime => source.itemType == ItemType.anime;

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    final result = await JniBridge().invokeMethod('getDetail', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'media': {
        'title': media.title,
        'url': media.url,
        'thumbnail_url': media.cover,
        'description': media.description,
        'author': media.author,
        'artist': media.artist,
        'genre': media.genre,
      },
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      DMedia.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    final result = await JniBridge().invokeMethod('getLatestUpdates', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    final result = await JniBridge().invokeMethod('getPopular', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'page': page,
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters}) async {
    final result = await JniBridge().invokeMethod('getVideoList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': {
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      },
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    print(result);

    return await compute(parseVideos, List<dynamic>.from(result));
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters}) async {
    final result = await JniBridge().invokeMethod('getPageList', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'episode': {
        'name': episode.name,
        'url': episode.url,
        'date_upload': episode.dateUpload,
        'description': episode.description,
        'episode_number': episode.episodeNumber,
        'scanlator': episode.scanlator,
      },
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return compute(parsePageUrls, List<dynamic>.from(result));
  }

  @override
  Future<Pages> search(String query, int page, List filters,
      {SourceParams? parameters}) async {
    final result = await JniBridge().invokeMethod('search', {
      'sourceId': source.id,
      'isAnime': isAnime,
      'query': query,
      'page': page,
      if (parameters != null) 'parameters': parameters.toJson(),
    });

    return await compute(
      Pages.fromJson,
      Map<String, dynamic>.from(result as Map),
    );
  }

  List<Video> parseVideos(List<dynamic> list) {
    return list
        .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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
    try {
      final params = {
        'sourceId': source.id,
        'isAnime': isAnime,
      };
      final String result = await JniBridge().invokeMethod('aniyomiGetPreferences', params);
      print("params => $params & result: $result");
      final List<dynamic> decoded = jsonDecode(result);
      return decoded
          .map((e) =>
              SourcePreference.fromAniyomiDesktopJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      Logger.log("AnymeX Bridge: Failed to get desktop preferences for ${source.name}: $e");
      return [];
    }
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    try {
      final result = await JniBridge().invokeMethod('aniyomiSavePreference', {
        'sourceId': source.id,
        'key': pref.key,
        'value': value,
        'isAnime': isAnime,
      });
      return result ?? false;
    } catch (e) {
      Logger.log("AnymeX Bridge: Failed to save desktop preference ${pref.key} for ${source.name}: $e");
      return false;
    }
  }
}
