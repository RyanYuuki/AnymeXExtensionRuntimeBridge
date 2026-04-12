import 'package:flutter/foundation.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/SourceParams.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../../Extensions/SourceMethods.dart';
import '../../Models/Source.dart';
import '../../Runtime/Bridge/BridgeDispatcher.dart';

class DesktopCloudStreamSourceMethods extends SourceMethods {
  @override
  final Source source;
  DesktopCloudStreamSourceMethods(this.source);

  @override
  Future<Pages> getPopular(int page, {SourceParams? parameters}) async {
    return _callSearch("", page); 
  }

  @override
  Future<Pages> getLatestUpdates(int page, {SourceParams? parameters}) async {
    return _callSearch("", page);
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters,
      {SourceParams? parameters}) async {
    return _callSearch(query, page);
  }

  Future<Pages> _callSearch(String query, int page) async {
    try {
      final res = await BridgeDispatcher().invokeMethod('csSearch', {
        'sourceId': source.id,
        'query': query,
        'page': page,
      });
      
      return await compute(
        Pages.fromJson,
        Map<String, dynamic>.from(res as Map),
      );
    } catch (e) {
      Logger.log('DesktopCloudStreamSourceMethods _callSearch error: $e');
      return Pages(list: [], hasNextPage: false);
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media, {SourceParams? parameters}) async {
    try {
      final res = await BridgeDispatcher().invokeMethod('csGetDetail', {
        'sourceId': source.id,
        'url': media.url,
      });
      print("Detail response: $res");
      return await compute(
        DMedia.fromCs,
        Map<String, dynamic>.from(res as Map),
      );
    } catch (e) {
      Logger.log('DesktopCloudStreamSourceMethods fetchDetails error: $e');
      return DMedia(url: media.url, title: media.title);
    }
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode,
      {SourceParams? parameters}) async {
    try {
      final res = await BridgeDispatcher().invokeMethod('csGetVideoList', {
        'sourceId': source.id,
        'url': episode.url,
      });
      
      final list = res as List;
      return await compute(parseVideos, list);
    } catch (e) {
      Logger.log('DesktopCloudStreamSourceMethods fetchVideoList error: $e');
      return [];
    }
  }

  @override
  Stream<Video> getVideoListStream(DEpisode episode,
      {SourceParams? parameters}) {
    return BridgeDispatcher().invokeStreamMethod('csGetVideoListStream', {
      'sourceId': source.id,
      'url': episode.url,
    }).map((e) => Video.fromCs(Map<String, dynamic>.from(e as Map)));
  }

  List<Video> parseVideos(List<dynamic> list) {
    return list
        .map((e) => Video.fromCs(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode,
      {SourceParams? parameters}) async {
    return [];
  }

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId,
      {SourceParams? parameters}) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelRequest(String token) async {}

  @override
  Future<List<SourcePreference>> getPreference() async {
    return [];
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    return false;
  }
}
