import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../Models/Source.dart';
import 'Models/Source.dart';

List<Source> parseLnReaderManifest(String body, String repoUrl) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    final sources = <Source>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();

      final scriptUrl = e['url']?.toString();
      if (scriptUrl == null || scriptUrl.isEmpty) continue;

      final version = e['version']?.toString() ?? '1.0.0';

      sources.add(
        LSource(
          id: e['id']?.toString() ?? e['name']?.toString(),
          name: e['name']?.toString(),
          baseUrl: e['site']?.toString(),
          lang: e['lang']?.toString(),
          version: version,
          versionLast: version,
          iconUrl: e['iconUrl']?.toString(),
          itemType: ItemType.novel,
          repo: repoUrl,
          sourceCodeUrl: scriptUrl,
          customCssUrl: e['customCSS']?.toString(),
        ),
      );
    }
    return sources;
  } catch (e) {
    debugPrint('Failed to parse LNReader manifest from $repoUrl: $e');
    return const [];
  }
}
