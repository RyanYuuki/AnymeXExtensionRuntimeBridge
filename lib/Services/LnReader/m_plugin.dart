class ChapterItem {
  String name;
  String path;
  String? releaseTime;
  int? chapterNumber;
  String? page;

  ChapterItem({
    required this.name,
    required this.path,
    this.releaseTime,
    this.chapterNumber,
    this.page,
  });

  factory ChapterItem.fromJson(Map<String, dynamic> json) {
    return ChapterItem(
      name: (json['name'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      releaseTime: json['releaseTime']?.toString(),
      chapterNumber: json['chapterNumber'] != null
          ? (json['chapterNumber'] is num
              ? (json['chapterNumber'] as num).toInt()
              : int.tryParse(json['chapterNumber'].toString()))
          : null,
      page: json['page']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'releaseTime': releaseTime,
      'chapterNumber': chapterNumber,
      'page': page,
    };
  }
}

class NovelItem {
  String name;
  String path;
  String? cover;

  NovelItem({required this.name, required this.path, this.cover});

  factory NovelItem.fromJson(Map<String, dynamic> json, [String? fallbackPath]) {
    return NovelItem(
      name: (json['name'] ?? '').toString(),
      path: (json['path'] ?? fallbackPath ?? '').toString(),
      cover: json['cover']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'path': path, 'cover': cover};
  }
}

class SourceNovel extends NovelItem {
  String? genres;
  String? summary;
  String? author;
  String? artist;
  String? status;
  double? rating;
  List<ChapterItem>? chapters;

  SourceNovel({
    required super.name,
    required super.path,
    super.cover,
    this.genres,
    this.summary,
    this.author,
    this.artist,
    this.status,
    this.rating,
    this.chapters,
  });

  factory SourceNovel.fromJson(Map<String, dynamic> json, [String? fallbackPath]) {
    final novelPath = (json['path'] ?? fallbackPath ?? '').toString();
    return SourceNovel(
      name: (json['name'] ?? '').toString(),
      path: novelPath,
      cover: json['cover']?.toString(),
      genres: json['genres'] is List
          ? (json['genres'] as List).join(',')
          : json['genres']?.toString(),
      summary: json['summary']?.toString(),
      author: json['author']?.toString(),
      artist: json['artist']?.toString(),
      status: json['status']?.toString(),
      rating: json['rating'] is num
          ? (json['rating'] as num).toDouble()
          : double.tryParse(json['rating']?.toString() ?? ''),
      chapters: (json['chapters'] as List<dynamic>?)
          ?.whereType<Map>()
          .map((item) => ChapterItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'cover': cover,
      'genres': genres,
      'summary': summary,
      'author': author,
      'artist': artist,
      'status': status,
      'rating': rating,
      'chapters': chapters?.map((item) => item.toJson()).toList(),
    };
  }
}

class SourcePage {
  List<ChapterItem> chapters;

  SourcePage({required this.chapters});

  factory SourcePage.fromJson(Map<String, dynamic> json) {
    return SourcePage(
      chapters: (json['chapters'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((item) => ChapterItem.fromJson(Map<String, dynamic>.from(item)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'chapters': chapters.map((item) => item.toJson()).toList()};
  }
}
