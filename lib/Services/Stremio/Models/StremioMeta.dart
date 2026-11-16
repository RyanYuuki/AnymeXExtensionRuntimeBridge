import '../../../Models/DEpisode.dart';
import '../../../Models/DMedia.dart';
import 'StremioStream.dart';

class StremioMetaPreview {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? posterShape;
  final String? banner;
  final String? logo;
  final String? description;
  final String? releaseInfo;
  final String? imdbRating;
  final List<String> genres;
  final List<StremioMetaLink> links;

  StremioMetaPreview({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.posterShape,
    this.banner,
    this.logo,
    this.description,
    this.releaseInfo,
    this.imdbRating,
    this.genres = const [],
    this.links = const [],
  });

  factory StremioMetaPreview.fromJson(Map<String, dynamic> json) {
    return StremioMetaPreview(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'movie',
      name: json['name']?.toString() ?? '',
      poster: json['poster']?.toString(),
      posterShape: json['posterShape']?.toString(),
      banner: json['banner']?.toString() ?? json['background']?.toString(),
      logo: json['logo']?.toString(),
      description: json['description']?.toString(),
      releaseInfo: json['releaseInfo']?.toString(),
      imdbRating: json['imdbRating']?.toString(),
      genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
      links: (json['links'] as List?)
              ?.whereType<Map>()
              .map((m) => StremioMetaLink.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          [],
    );
  }

  DMedia toDMedia() {
    return DMedia(
      title: name,
      url: id,
      cover: poster ?? banner ?? '',
      description: description ?? '',
      genre: genres,
      episodes: [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        if (poster != null) 'poster': poster,
        if (posterShape != null) 'posterShape': posterShape,
        if (banner != null) 'banner': banner,
        if (logo != null) 'logo': logo,
        if (description != null) 'description': description,
        if (releaseInfo != null) 'releaseInfo': releaseInfo,
        if (imdbRating != null) 'imdbRating': imdbRating,
        'genres': genres,
        'links': links.map((l) => l.toJson()).toList(),
      };
}

class StremioMetaDetail extends StremioMetaPreview {
  final String? background;
  final String? released;
  final String? runtime;
  final String? country;
  final String? language;
  final String? website;
  final String? awards;
  final List<String> cast;
  final List<String> director;
  final List<String> writer;
  final List<StremioMetaTrailer> trailers;
  final List<StremioMetaVideo> videos;

  StremioMetaDetail({
    required super.id,
    required super.type,
    required super.name,
    super.poster,
    super.posterShape,
    super.banner,
    super.logo,
    super.description,
    super.releaseInfo,
    super.imdbRating,
    super.genres,
    super.links,
    this.background,
    this.released,
    this.runtime,
    this.country,
    this.language,
    this.website,
    this.awards,
    this.cast = const [],
    this.director = const [],
    this.writer = const [],
    this.trailers = const [],
    this.videos = const [],
  });

  factory StremioMetaDetail.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> meta = json;
    if (json.containsKey('meta') && json['meta'] is Map) {
      meta = Map<String, dynamic>.from(json['meta']);
    } else if (json.containsKey('data') && json['data'] is Map) {
      final data = Map<String, dynamic>.from(json['data']);
      if (data.containsKey('meta') && data['meta'] is Map) {
        meta = Map<String, dynamic>.from(data['meta']);
      } else {
        meta = data;
      }
    }

    final rawVideos = meta['videos'] as List? ?? [];
    final videos = rawVideos
        .whereType<Map>()
        .map((m) => StremioMetaVideo.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final rawTrailers = meta['trailers'] as List? ?? [];
    final trailers = rawTrailers
        .whereType<Map>()
        .map((m) => StremioMetaTrailer.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    final preview = StremioMetaPreview.fromJson(meta);

    List<String> parseStringListOrCsv(dynamic val) {
      if (val is List) return val.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      if (val is String) {
        return val.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      return [];
    }

    return StremioMetaDetail(
      id: preview.id,
      type: preview.type,
      name: preview.name,
      poster: preview.poster,
      posterShape: preview.posterShape,
      banner: preview.banner,
      logo: preview.logo,
      description: preview.description,
      releaseInfo: preview.releaseInfo,
      imdbRating: preview.imdbRating,
      genres: preview.genres,
      links: preview.links,
      background: meta['background']?.toString() ?? meta['landscapePoster']?.toString(),
      released: meta['released']?.toString(),
      runtime: meta['runtime']?.toString(),
      country: meta['country']?.toString(),
      language: meta['language']?.toString(),
      website: meta['website']?.toString(),
      awards: meta['awards']?.toString(),
      cast: parseStringListOrCsv(meta['cast']),
      director: parseStringListOrCsv(meta['director']),
      writer: parseStringListOrCsv(meta['writer']),
      trailers: trailers,
      videos: videos,
    );
  }

  @override
  DMedia toDMedia() {
    final episodeList = <DEpisode>[];

    if (videos.isNotEmpty) {
      for (final v in videos) {
        episodeList.add(v.toDEpisode());
      }
    } else {
      episodeList.add(
        DEpisode(
          url: id,
          name: name,
          episodeNumber: '1',
          thumbnail: poster ?? background,
          description: description,
          sortMap: {'season': '1'},
        ),
      );
    }

    return DMedia(
      title: name,
      url: id,
      cover: poster ?? background ?? banner ?? '',
      description: description ?? '',
      author: director.isNotEmpty ? director.join(', ') : null,
      artist: cast.isNotEmpty ? cast.join(', ') : null,
      genre: genres,
      episodes: episodeList,
    );
  }
}

class StremioMetaVideo {
  final String id;
  final String title;
  final String? released;
  final String? thumbnail;
  final int? season;
  final int? episode;
  final String? overview;
  final bool available;
  final List<StreamItem> streams;

  StremioMetaVideo({
    required this.id,
    required this.title,
    this.released,
    this.thumbnail,
    this.season,
    this.episode,
    this.overview,
    this.available = true,
    this.streams = const [],
  });

  factory StremioMetaVideo.fromJson(Map<String, dynamic> json) {
    final rawStreams = json['streams'] as List? ?? [];
    final streams = rawStreams
        .whereType<Map>()
        .map((m) => StreamItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return StremioMetaVideo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? 'Episode',
      released: json['released']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      season: int.tryParse(json['season']?.toString() ?? ''),
      episode: int.tryParse(json['episode']?.toString() ?? ''),
      overview: json['overview']?.toString() ?? json['description']?.toString(),
      available: json['available'] != false,
      streams: streams,
    );
  }

  DEpisode toDEpisode() {
    final epNumStr = episode != null ? episode.toString() : '1';
    final seasonStr = season != null ? season.toString() : '1';

    return DEpisode(
      url: id,
      name: title,
      episodeNumber: epNumStr,
      thumbnail: thumbnail,
      description: overview,
      dateUpload: released ?? '',
      sortMap: {
        'season': seasonStr,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (released != null) 'released': released,
        if (thumbnail != null) 'thumbnail': thumbnail,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        if (overview != null) 'overview': overview,
        'available': available,
        'streams': streams.map((s) => s.toJson()).toList(),
      };
}

class StremioMetaLink {
  final String name;
  final String category;
  final String url;

  StremioMetaLink({
    required this.name,
    required this.category,
    required this.url,
  });

  factory StremioMetaLink.fromJson(Map<String, dynamic> json) {
    return StremioMetaLink(
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'url': url,
      };
}

class StremioMetaTrailer {
  final String source;
  final String type;

  StremioMetaTrailer({
    required this.source,
    required this.type,
  });

  factory StremioMetaTrailer.fromJson(Map<String, dynamic> json) {
    return StremioMetaTrailer(
      source: json['source']?.toString() ?? json['key']?.toString() ?? json['ytId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Trailer',
    );
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'type': type,
      };
}
