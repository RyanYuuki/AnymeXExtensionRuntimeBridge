import 'DEpisode.dart';

class DMedia {
  String? title;
  String? url;
  String? cover;
  String? description;
  String? author;
  String? artist;
  List<String>? genre;
  List<DEpisode>? episodes;

  DMedia({
    this.title,
    this.url,
    this.cover,
    this.description,
    this.author,
    this.artist,
    this.genre,
    this.episodes,
  });

  factory DMedia.fromJson(Map<String, dynamic> json) {
    final parsedEpisodes = json['episodes'] != null
        ? (json['episodes'] as List)
            .map((e) => DEpisode.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <DEpisode>[];
    parsedEpisodes.sort(DEpisode.compareByEpisodeNumber);

    return DMedia(
      title: json['title'],
      url: json['url'],
      cover: json['cover'] ?? json['thumbnail_url'],
      description: json['description'],
      artist: json['artist'],
      author: json['author'],
      genre: json['genre'] != null ? List<String>.from(json['genre']) : [],
      episodes: parsedEpisodes,
    );
  }

  factory DMedia.fromCs(Map<String, dynamic> json) {
    final parsedEpisodes = json['episodes'] != null
        ? (json['episodes'] as List)
            .map((e) => DEpisode.fromCs(Map<String, dynamic>.from(e)))
            .toList()
        : <DEpisode>[];
    parsedEpisodes.sort(DEpisode.compareByEpisodeNumber);

    return DMedia(
      title: json['title'],
      url: json['url'],
      cover: json['cover'] ?? json['thumbnail_url'],
      description: json['description'],
      artist: json['artist'],
      author: json['author'],
      genre: json['genre'] != null ? List<String>.from(json['genre']) : [],
      episodes: (parsedEpisodes[0].episodeNumber != '0') ||
              (parsedEpisodes[0].episodeNumber != '1')
          ? parsedEpisodes.reversed.toList()
          : parsedEpisodes,
    );
  }

  factory DMedia.withUrl(String url) {
    return DMedia(
      title: '',
      url: url,
      cover: '',
      description: '',
      artist: '',
      author: '',
      genre: [],
      episodes: [],
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'cover': cover,
        'description': description,
        'author': author,
        'artist': artist,
        'genre': genre,
        'episodes': episodes?.map((e) => e.toJson()).toList(),
      };
}
