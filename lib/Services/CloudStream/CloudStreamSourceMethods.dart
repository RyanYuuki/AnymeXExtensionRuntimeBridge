import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../anymex_extension_runtime_bridge.dart';

class CloudStreamSourceMethods extends SourceMethods {
  @override
  final CloudStreamSource source;

  CloudStreamSourceMethods(Source source)
      : source = source as CloudStreamSource;

  static const platform = MethodChannel('cloudstreamExtensionBridge');

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final result = await platform.invokeMethod('getDetail', {
      'apiName': source.id,
      'url': media.url,
    });

    // print(result.toString());

    return await compute(
      DMedia.fromCs,
      Map<String, dynamic>.from(result as Map),
    );
  }

  @override
  Future<Pages> getLatestUpdates(int page) async {
    return Pages(list: [], hasNextPage: false);
  }

  @override
  Future<Pages> getPopular(int page) async {
    return Pages(
      list: [],
      hasNextPage: false,
    );
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final result = await platform.invokeMethod('getVideoList', {
      'apiName': source.id,
      'url': episode.url,
    });

    print(result.toString());

    return await compute(parseVideos, List<dynamic>.from(result));
  }

  static const videoStreamChannel =
      EventChannel('cloudstreamExtensionBridge/videoStream');

  @override
  Stream<Video>? getVideoListStream(DEpisode episode) {
    final controller = StreamController<Video>();

    final subscription = videoStreamChannel.receiveBroadcastStream({
      'apiName': source.id,
      'url': episode.url,
    }).listen(
      (event) {
        try {
          final Map<String, dynamic> data =
              Map<String, dynamic>.from(event as Map);
          final video = Video.fromJson(data);

          if (!controller.isClosed) {
            controller.add(video);
          }
        } catch (e) {
          debugPrint("Error parsing video stream event: $e");
        }
      },
      onError: (error) {
        debugPrint("Video stream error: $error");
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
      cancelOnError: false,
    );

    controller.onCancel = () {
      subscription.cancel();
    };

    return controller.stream;
  }

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) {
    return Future.value([]);
  }

  @override
  Future<Pages> search(String query, int page, List filters) async {
    final result = await platform.invokeMethod('search', {
      'apiName': source.id,
      'query': query,
      'page': page,
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

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId) {
    throw UnimplementedError();
  }

  @override
  Future<List<SourcePreference>> getPreference() async {
    return [];
  }

  @override
  Future<bool> setPreference(SourcePreference pref, dynamic value) async {
    return false;
  }
}
