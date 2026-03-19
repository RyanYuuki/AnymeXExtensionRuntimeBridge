import 'dart:convert';

class DEpisode {
  String? url;
  String? name;
  String? dateUpload;
  String? scanlator;
  String? thumbnail;
  String? description;
  bool? filler;
  String episodeNumber;
  String? sortKey;

  DEpisode({
    this.url,
    this.name,
    this.dateUpload,
    this.scanlator,
    this.thumbnail,
    this.description,
    this.filler,
    this.sortKey,
    required this.episodeNumber,
  });

  factory DEpisode.fromJson(Map<String, dynamic> json) {
    double? episodeNum =
        double.tryParse(json['episodeNumber']?.toString() ?? '') ??
            double.tryParse(json['episode_number']?.toString() ?? '');

    String episodeStr;
    if (episodeNum != null) {
      episodeStr = episodeNum == episodeNum.toInt()
          ? episodeNum.toInt().toString()
          : episodeNum.toString();
    } else {
      episodeStr = '';
    }
    return DEpisode(
      url: json['url'],
      name: json['name'],
      dateUpload: json['dateUpload']?.toString() ??
          json['date_upload']?.toString() ??
          '',
      scanlator: json['scanlator'],
      thumbnail: json['thumbnail'],
      description: json['description'],
      filler: json['filler'],
      episodeNumber: episodeStr,
    );
  }

  factory DEpisode.fromCs(Map<String, dynamic> json) {
    var idJson;
    try {
      final data = jsonDecode(json['url']);
      idJson = data['isDub'] ? "DUB" : "SUB";
    } catch (e) {}
    double? episodeNum =
        double.tryParse(json['episodeNumber']?.toString() ?? '') ??
            double.tryParse(json['episode_number']?.toString() ?? '');

    String episodeStr;
    if (episodeNum != null) {
      episodeStr = episodeNum == episodeNum.toInt()
          ? episodeNum.toInt().toString()
          : episodeNum.toString();
    } else {
      episodeStr = '';
    }
    return DEpisode(
        url: json['url'],
        name: json['name'],
        dateUpload: json['dateUpload']?.toString() ??
            json['date_upload']?.toString() ??
            '',
        scanlator: json['scanlator'],
        thumbnail: json['thumbnail'],
        description: json['description'],
        filler: json['filler'],
        episodeNumber: episodeStr,
        sortKey: idJson);
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'dateUpload': dateUpload,
        'scanlator': scanlator,
        'thumbnail': thumbnail,
        'description': description,
        'filler': filler,
        'episodeNumber': episodeNumber,
      };

  static int compareByEpisodeNumber(DEpisode a, DEpisode b) {
    final aNum = double.tryParse(a.episodeNumber);
    final bNum = double.tryParse(b.episodeNumber);

    if (aNum != null && bNum != null) {
      return aNum.compareTo(bNum);
    }
    if (aNum != null) return -1;
    if (bNum != null) return 1;
    return (a.name ?? '').compareTo(b.name ?? '');
  }
}
