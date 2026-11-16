import '../../../Engines/TorrentEngine/TorrServerController.dart';
import '../../../Models/Video.dart';

class StreamItem {
  final String? name;
  final String? title;
  final String? description;
  final String? url;
  final String? ytId;
  final String? infoHash;
  final int? fileIdx;
  final String? externalUrl;
  final List<String> sources;
  final List<StreamSubtitle> subtitles;
  final StreamBehaviorHints? behaviorHints;
  final Map<String, dynamic>? clientResolve;
  final String? addonName;
  final String? addonId;

  StreamItem({
    this.name,
    this.title,
    this.description,
    this.url,
    this.ytId,
    this.infoHash,
    this.fileIdx,
    this.externalUrl,
    this.sources = const [],
    this.subtitles = const [],
    this.behaviorHints,
    this.clientResolve,
    this.addonName,
    this.addonId,
  });

  bool get isTorrent => (infoHash != null && infoHash!.isNotEmpty) ||
      (url != null && (url!.startsWith('magnet:') || url!.startsWith('torrent:')));

  factory StreamItem.fromJson(Map<String, dynamic> json, {String? addonName, String? addonId}) {
    final hintsMap = json['behaviorHints'] is Map ? Map<String, dynamic>.from(json['behaviorHints']) : null;
    final hints = hintsMap != null ? StreamBehaviorHints.fromJson(hintsMap) : null;

    final rawSubtitles = json['subtitles'] as List? ?? [];
    final subtitles = rawSubtitles
        .whereType<Map>()
        .map((m) => StreamSubtitle.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final sources = (json['sources'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return StreamItem(
      name: json['name']?.toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString() ?? json['title']?.toString(),
      url: json['url']?.toString(),
      ytId: json['ytId']?.toString().trim(),
      infoHash: json['infoHash']?.toString().toLowerCase(),
      fileIdx: int.tryParse(json['fileIdx']?.toString() ?? ''),
      externalUrl: json['externalUrl']?.toString(),
      sources: sources,
      subtitles: subtitles,
      behaviorHints: hints,
      clientResolve: json['clientResolve'] is Map ? Map<String, dynamic>.from(json['clientResolve']) : null,
      addonName: addonName ?? json['addonName']?.toString(),
      addonId: addonId ?? json['addonId']?.toString(),
    );
  }

  Video toVideo({TorrServerController? torrServerController}) {
    String playableUrl = '';
    Map<String, String>? headers = behaviorHints?.proxyHeaders?.request;

    if (url != null && url!.isNotEmpty) {
      playableUrl = url!;
    } else if (infoHash != null && infoHash!.isNotEmpty) {
      final hash = infoHash!.toLowerCase();
      final idx = fileIdx ?? 0;
      if (torrServerController != null && torrServerController.isRunning) {
        playableUrl = torrServerController.streamUrl(hash, fileIndex: idx).toString();
      } else {
        final trackers = sources.map((s) => '&tr=${Uri.encodeComponent(s)}').join('');
        playableUrl = 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(title ?? name ?? "Torrent")}$trackers';
      }
    } else if (ytId != null && ytId!.isNotEmpty) {
      playableUrl = 'https://www.youtube.com/watch?v=$ytId';
    } else if (externalUrl != null && externalUrl!.isNotEmpty) {
      playableUrl = externalUrl!;
    }

    final qualityLabel = name ?? 'Default';
    final videoTitle = title ?? name ?? 'Stream';

    final trackSubtitles = subtitles.map((s) => s.toTrack()).toList();

    return Video(
      videoTitle,
      playableUrl,
      qualityLabel,
      headers: headers,
      subtitles: trackSubtitles,
      extraData: {
        'infoHash': infoHash,
        'fileIdx': fileIdx,
        'sources': sources,
        'bingeGroup': behaviorHints?.bingeGroup,
        'filename': behaviorHints?.filename,
        'videoHash': behaviorHints?.videoHash,
        'videoSize': behaviorHints?.videoSize,
        'addonName': addonName,
        'addonId': addonId,
        'clientResolve': clientResolve,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (url != null) 'url': url,
        if (ytId != null) 'ytId': ytId,
        if (infoHash != null) 'infoHash': infoHash,
        if (fileIdx != null) 'fileIdx': fileIdx,
        if (externalUrl != null) 'externalUrl': externalUrl,
        'sources': sources,
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
        if (behaviorHints != null) 'behaviorHints': behaviorHints!.toJson(),
        if (clientResolve != null) 'clientResolve': clientResolve,
        if (addonName != null) 'addonName': addonName,
        if (addonId != null) 'addonId': addonId,
      };
}

class StreamBehaviorHints {
  final bool notWebReady;
  final String? bingeGroup;
  final List<String> countryWhitelist;
  final String? filename;
  final int? videoSize;
  final String? videoHash;
  final StreamProxyHeaders? proxyHeaders;

  StreamBehaviorHints({
    this.notWebReady = false,
    this.bingeGroup,
    this.countryWhitelist = const [],
    this.filename,
    this.videoSize,
    this.videoHash,
    this.proxyHeaders,
  });

  factory StreamBehaviorHints.fromJson(Map<String, dynamic> json) {
    final proxy = json['proxyHeaders'] is Map
        ? StreamProxyHeaders.fromJson(Map<String, dynamic>.from(json['proxyHeaders']))
        : null;

    return StreamBehaviorHints(
      notWebReady: json['notWebReady'] == true || proxy != null,
      bingeGroup: json['bingeGroup']?.toString(),
      countryWhitelist: (json['countryWhitelist'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [],
      filename: json['filename']?.toString(),
      videoSize: int.tryParse(json['videoSize']?.toString() ?? ''),
      videoHash: json['videoHash']?.toString(),
      proxyHeaders: proxy,
    );
  }

  Map<String, dynamic> toJson() => {
        'notWebReady': notWebReady,
        if (bingeGroup != null) 'bingeGroup': bingeGroup,
        'countryWhitelist': countryWhitelist,
        if (filename != null) 'filename': filename,
        if (videoSize != null) 'videoSize': videoSize,
        if (videoHash != null) 'videoHash': videoHash,
        if (proxyHeaders != null) 'proxyHeaders': proxyHeaders!.toJson(),
      };
}

class StreamProxyHeaders {
  final Map<String, String>? request;
  final Map<String, String>? response;

  StreamProxyHeaders({
    this.request,
    this.response,
  });

  factory StreamProxyHeaders.fromJson(Map<String, dynamic> json) {
    Map<String, String>? parseMap(dynamic val) {
      if (val is Map) {
        return val.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return null;
    }

    return StreamProxyHeaders(
      request: parseMap(json['request']),
      response: parseMap(json['response']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (request != null) 'request': request,
        if (response != null) 'response': response,
      };
}

class StreamSubtitle {
  final String? id;
  final String url;
  final String lang;
  final String? label;

  StreamSubtitle({
    this.id,
    required this.url,
    required this.lang,
    this.label,
  });

  factory StreamSubtitle.fromJson(Map<String, dynamic> json) {
    return StreamSubtitle(
      id: json['id']?.toString(),
      url: json['url']?.toString() ?? '',
      lang: json['lang']?.toString() ?? json['language']?.toString() ?? 'unknown',
      label: json['label']?.toString() ?? json['name']?.toString(),
    );
  }

  Track toTrack() {
    return Track(
      file: url,
      label: label ?? lang,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'url': url,
        'lang': lang,
        if (label != null) 'label': label,
      };
}
