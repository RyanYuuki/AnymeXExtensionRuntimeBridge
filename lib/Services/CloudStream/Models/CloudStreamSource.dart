import '../../../Models/Source.dart';

class CloudStreamSource extends Source {
  String? internalName;
  String? pluginUrl;

  CloudStreamSource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType,
    super.repo,
    super.managerId,
    super.hasUpdate,
    this.internalName,
    this.pluginUrl,
  });

  factory CloudStreamSource.fromJson(Map<String, dynamic> json) {
    // print('FROM JSONING CS SOURCE => ${json.toString()}');
    return CloudStreamSource(
      id: json['id']?.toString().toLowerCase() ??
          json['name']?.toString().toLowerCase() ??
          '',
      name: json['name'],
      baseUrl: json['url'],
      lang: json['language'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'] ?? false,
      version: json['version']?.toString() ?? "1.0.0",
      versionLast: json['versionLast'] ?? "1.0.0",
      repo: json['repo'],
      managerId: 'cloudstream',
      hasUpdate: json['hasUpdate'] ?? false,
      itemType: ItemType.anime,
      internalName: json['internalName'] ?? json['name'],
      pluginUrl: json['pluginUrl'] ?? json['plugin'] ?? json['url'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['internalName'] = internalName;
    map['plugin'] = pluginUrl;
    return map;
  }
}
