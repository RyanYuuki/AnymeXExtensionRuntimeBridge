import 'dart:convert';
import 'dart:developer';

class DEpisode {
  String? url;
  String? name;
  String? dateUpload;
  String? scanlator;
  String? thumbnail;
  String? description;
  bool? filler;
  String episodeNumber;
  Map<String, String>? sortMap;

  DEpisode({
    this.url,
    this.name,
    this.dateUpload,
    this.scanlator,
    this.thumbnail,
    this.description,
    this.filler,
    this.sortMap,
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
    return DEpisode(
        url: json['dataUrl'] ?? json['url'],
        name: json['name'],
        dateUpload: json['dateUpload']?.toString() ??
            json['date_upload']?.toString() ??
            '',
        scanlator: json['scanlator'],
        thumbnail: json['thumbnail'] ??
            json['posterUrl'] ??
            json['extraData']?['thumbnail'],
        description: json['description'],
        filler: json['filler'],
        episodeNumber: json['episodeNumber']?.toString() ?? '1',
        sortMap: {
          "season": json['extraData']?['season']?.toString() ?? '',
          "type": json['extraData']?['episodeGroup']?.toString() ?? ''
        });
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
