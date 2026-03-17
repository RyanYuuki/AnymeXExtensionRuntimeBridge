import 'dart:async';
import 'dart:convert';

import '../../Extensions/SourceMethods.dart';
import '../../Logger.dart';
import '../../Models/DEpisode.dart';
import '../../Models/DMedia.dart';
import '../../Models/Page.dart';
import '../../Models/Pages.dart';
import '../../Models/Source.dart';
import '../../Models/SourcePreference.dart';
import '../../Models/Video.dart';
import '../Mangayomi/http/m_client.dart';
import 'JsEngine/JsEngine.dart';
import 'Models/Source.dart';

class SoraSourceMethods extends SourceMethods {
  @override
  final SSource source;

  late final String module = source.name ?? source.id ?? "";

  SoraSourceMethods(Source source) : source = source as SSource;

  Completer<void>? _initCompleter;

  Future<void> initialize() {
    if (_initCompleter?.isCompleted ?? false) {
      return _initCompleter!.future;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    _doInitialize();

    return _initCompleter!.future;
  }

  Future<void> _doInitialize() async {
    try {
      String code = source.sourceCode ?? "";

      if (code.isEmpty && source.sourceCodeUrl != null) {
        final client = MClient.init();
        final res = await client.get(Uri.parse(source.sourceCodeUrl!));
        if (res.statusCode != 200) {
          throw Exception(
              "Failed to fetch source code from ${source.sourceCodeUrl}: ${res.statusCode}");
        }
        code = res.body;
      }

      if (code.isEmpty) {
        throw Exception("No source code available for ${source.name}");
      }

      await JsExtensionEngine.instance.loadModule(
        moduleName: module,
        sourceCode: code,
      );

      _initCompleter?.complete();
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      _initCompleter = null;
    }
  }

  dynamic _parseJs(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }

    return value;
  }

  Future<dynamic> _call(String method, List params) async {
    await initialize();
    try {
      final res = await JsExtensionEngine.instance.call(
        moduleName: module,
        method: method,
        params: params,
      );

      return _parseJs(res.value);
    } catch (e) {
      Logger.log("Error calling JS method '$method': $e");
      return null;
    }
  }

  bool _isErrorPayload(dynamic data) {
    if (data == null) return true;

    const errorIndicators = [
      "Error",
      "error",
      "Not Found",
      "not found",
      "Failed",
    ];

    if (data is List) {
      if (data.length == 1 && data.first is Map) {
        final map = Map<String, dynamic>.from(data.first);

        return errorIndicators.contains(map["title"]) ||
            errorIndicators.contains(map["id"]) ||
            errorIndicators.contains(map["href"]);
      }
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);

      return errorIndicators.contains(map["title"]) ||
          errorIndicators.contains(map["id"]) ||
          errorIndicators.contains(map["href"]);
    }

    return false;
  }

  void _collectEpisodes(dynamic data, List<DEpisode> episodes) {
    void add(Map e, {String? fallback}) {
      episodes.add(
        DEpisode(
          episodeNumber: e["number"]?.toString() ??
              e["chapter"]?.toString() ??
              fallback ??
              "",
          url: e["href"] ?? e["id"],
          name: e["title"],
          scanlator: e["scanlation_group"] ?? e["scanlator_group"],
        ),
      );
    }

    if (data is List) {
      for (final e in data) {
        if (e is Map) add(Map<String, dynamic>.from(e));
      }
    } else if (data is Map) {
      for (final group in data.values) {
        if (group is List) {
          for (final item in group) {
            if (item is List && item.length >= 2) {
              final number = item[0];
              final list = item[1];

              if (list is List) {
                for (final e in list) {
                  if (e is Map) {
                    add(
                      Map<String, dynamic>.from(e),
                      fallback: number?.toString(),
                    );
                  }
                }
              }
            } else if (item is Map) {
              add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    }
  }

  @override
  Future<DMedia> getDetail(DMedia media) async {
    final rawDetails = await _call("extractDetails", [media.url]);
    Map<String, dynamic> details = {};
    if (!_isErrorPayload(rawDetails)) {
      if (rawDetails is Map) {
        details = Map<String, dynamic>.from(rawDetails);
      } else if (rawDetails is List &&
          rawDetails.isNotEmpty &&
          rawDetails.first is Map) {
        details = Map<String, dynamic>.from(rawDetails.first);
      }
    } else {
      Logger.log("extractDetails returned error");
    }

    final resultMedia = DMedia(
      title: details["title"]?.toString() ?? media.title,
      url: details["url"]?.toString() ?? media.url,
      cover: details["cover"]?.toString() ?? media.cover,
      description: details["description"]?.toString(),
    );

    final method = source.itemType == ItemType.anime
        ? "extractEpisodes"
        : "extractChapters";

    final rawEpisodes = await _call(method, [media.url]);

    if (_isErrorPayload(rawEpisodes)) {
      Logger.log("$method returned error");
      resultMedia.episodes = [];
      return resultMedia;
    }

    final episodes = <DEpisode>[];
    _collectEpisodes(rawEpisodes, episodes);

    resultMedia.episodes = episodes.reversed.toList();

    return resultMedia;
  }

  @override
  Future<Pages> search(String query, int page, List<dynamic> filters) async {
    final raw = await _call("searchResults", [query, page, filters]);

    if (_isErrorPayload(raw) || raw is! List) {
      return Pages(list: []);
    }

    final list = raw.map<DMedia>((e) {
      final map = Map<String, dynamic>.from(e);

      return DMedia(
        title: map['title'],
        url: map['href'] ?? map['id'],
        cover: map['image'] ?? map['imageURL'],
      );
    }).toList();

    return Pages(list: list);
  }

  @override
  Future<Pages> getLatestUpdates(int page) => search("One Piece", page, []);

  @override
  Future<Pages> getPopular(int page) => search("One Piece", page, []);

  @override
  Future<List<PageUrl>> getPageList(DEpisode episode) async {
    final data = await _call("extractImages", [episode.url]);

    if (_isErrorPayload(data)) {
      Logger.log("extractImages returned error");
      return [];
    }

    final pages = <PageUrl>[];

    if (data is List) {
      for (final item in data) {
        if (item is String) {
          pages.add(PageUrl(item));
        }
      }
    }

    return pages;
  }

  @override
  Future<List<Video>> getVideoList(DEpisode episode) async {
    final data = await _call("extractStreamUrl", [episode.url]);

    if (_isErrorPayload(data)) {
      Logger.log("extractStreamUrl returned error");
      return [];
    }

    final client = MClient.init();
    final videos = <Video>[];

    const defaultHeaders = {
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.131 Safari/537.36",
    };

    Future<List<Video>> expandM3U8(
      String title,
      String url,
      Map<String, String> headers,
      List<Track> subtitles,
    ) async {
      try {
        final res = await client.get(Uri.parse(url), headers: headers);
        final body = res.body;

        if (!body.contains("#EXT-X-STREAM-INF")) {
          return [
            Video(title, url, "auto", headers: headers, subtitles: subtitles)
          ];
        }

        final parsed = <Video>[];
        final lines = body.split('\n');

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];

          if (!line.startsWith("#EXT-X-STREAM-INF")) continue;

          final match = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
          final quality = match?.group(1);

          final streamUrl = lines[i + 1].trim();
          final fullUrl = Uri.parse(url).resolve(streamUrl).toString();

          parsed.add(
            Video(
              quality != null ? "$title - ${quality}p" : title,
              fullUrl,
              quality ?? "auto",
              headers: headers,
              subtitles: subtitles,
            ),
          );
        }

        return parsed.isEmpty
            ? [
                Video(title, url, "auto",
                    headers: headers, subtitles: subtitles)
              ]
            : parsed;
      } catch (_) {
        return [
          Video(title, url, "auto", headers: headers, subtitles: subtitles)
        ];
      }
    }

    Future<void> addVideo(
      String title,
      String url, {
      Map<String, String>? headers,
      List<Track>? subtitles,
    }) async {
      final h = headers ?? defaultHeaders;
      final subs = subtitles ?? const <Track>[];

      if (url.contains(".m3u8")) {
        videos.addAll(await expandM3U8(title, url, h, subs));
      } else {
        videos.add(Video(title, url, "auto", headers: h, subtitles: subs));
      }
    }

    if (data is String) {
      await addVideo("Video", data);
    } else if (data is Map) {
      if (data.containsKey("stream")) {
        final subs = data["subtitles"] != null
            ? [Track(file: data["subtitles"], label: "Default")]
            : <Track>[];

        await addVideo("Video", data["stream"], subtitles: subs);
      } else if (data["streams"] is Map) {
        for (final e in (data["streams"] as Map).entries) {
          if (e.value != null) {
            await addVideo(e.key.toString(), e.value.toString());
          }
        }
      } else if (data["streams"] is List) {
        for (final stream in data["streams"]) {
          final url = stream["streamUrl"] ?? stream["url"] ?? stream["stream"];

          if (url == null || url.isEmpty) continue;

          final headers = (stream["headers"] as Map?)?.cast<String, String>();

          final subs = stream["subtitles"] is List
              ? (stream["subtitles"] as List)
                  .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
                  .toList()
              : <Track>[];

          await addVideo(
            stream["title"] ?? "Server",
            url,
            headers: headers,
            subtitles: subs,
          );
        }
      }
    }

    videos.sort((a, b) {
      final qa = int.tryParse(a.quality.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final qb = int.tryParse(b.quality.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return qb.compareTo(qa);
    });

    return videos;
  }

  @override
  Future<List<SourcePreference>> getPreference() => Future.value([]);

  @override
  Future<String?> getNovelContent(String chapterTitle, String chapterId) {
    throw UnimplementedError();
  }

  @override
  Future<bool> setPreference(SourcePreference pref, value) {
    throw UnimplementedError();
  }
}
