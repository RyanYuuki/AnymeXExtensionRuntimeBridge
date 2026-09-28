import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../Extensions/Extensions.dart';
import '../../Logger.dart';
import '../../Models/Source.dart';
import 'PackagedSource.dart';
import 'ProtoReader.dart';

String tachiyomiIndexUrl(String repoUrl) {
  if (repoUrl.endsWith('index.min.json') || repoUrl.endsWith('.pb')) {
    return repoUrl;
  }
  final trimmed = repoUrl.replaceAll(RegExp(r'/+$'), '');
  return '$trimmed/index.min.json';
}

String? tachiyomiFallbackRepoUrl(String repoUrl) {
  try {
    final stripped = repoUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');

    final parts = stripped.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 3) return null;

    final owner = parts[1];
    final repo = parts[2];

    final branchIndex = (parts.length > 3 && parts[3] == 'raw') ? 4 : 3;
    final branch = parts.length > branchIndex ? parts[branchIndex] : 'main';
    final path = parts.skip(branchIndex + 1).join('/');

    final base = 'https://gcore.jsdelivr.net/gh/$owner/$repo@$branch';
    return path.isEmpty ? base : '$base/$path';
  } catch (_) {
    return null;
  }
}

Future<void> downloadPackageFile(
  http.Client client,
  String url,
  String destPath, {
  void Function(int received, int? total)? onProgress,
}) async {
  final request = http.Request('GET', Uri.parse(url));
  final response = await client.send(request);

  if (response.statusCode != 200) {
    await response.stream.drain<void>();
    throw Exception(
      'Extension download failed (${response.statusCode}) for $url',
    );
  }

  final dest = File(destPath);
  await dest.parent.create(recursive: true);

  final temp = File('$destPath.tmp');
  final sink = temp.openWrite();
  final total = response.contentLength;
  var received = 0;

  try {
    if (onProgress == null) {
      await sink.addStream(response.stream);
    } else {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
    }
    await sink.flush();
  } finally {
    await sink.close();
  }

  try {
    await temp.rename(destPath);
  } on FileSystemException {
    await temp.copy(destPath);
    await temp.delete();
  }
}

class TachiyomiRepoEntry {
  final String id;
  final String name;
  final String? pkgName;
  final String? apkName;
  final String? lang;
  final String? version;
  final bool isNsfw;
  final ItemType itemType;
  final String repo;
  final String iconUrl;
  final String? apkUrl;
  final String? jarUrl;

  const TachiyomiRepoEntry({
    required this.id,
    required this.name,
    required this.pkgName,
    required this.apkName,
    required this.lang,
    required this.version,
    required this.isNsfw,
    required this.itemType,
    required this.repo,
    required this.iconUrl,
    this.apkUrl,
    this.jarUrl,
  });
}

List<T> parseTachiyomiRepoIndex<T extends Source>({
  required String body,
  required String repoUrl,
  required ItemType targetType,
  required Map<String, ItemType> prefixes,
  required T Function(TachiyomiRepoEntry entry) factory,
}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    const suffix = '/index.min.json';
    final baseIconUrl = repoUrl.endsWith(suffix)
        ? repoUrl.substring(0, repoUrl.length - suffix.length)
        : repoUrl;

    final sources = <T>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final name = map['name'] as String? ?? '';

      ItemType? detectedType;
      String displayName = name;
      for (final entry in prefixes.entries) {
        if (name.startsWith(entry.key)) {
          detectedType = entry.value;
          displayName = name.substring(entry.key.length);
          break;
        }
      }

      if (detectedType != targetType) continue;

      final sourcesList = map['sources'];
      final id = (sourcesList is List && sourcesList.isNotEmpty)
          ? (sourcesList.first['id']?.toString() ?? '')
          : '';

      final apkName = map['apk'] as String?;

      sources.add(
        factory(
          TachiyomiRepoEntry(
            id: id,
            name: displayName,
            pkgName: map['pkg'] as String?,
            apkName: apkName,
            lang: map['lang'] as String?,
            version: map['version']?.toString(),
            isNsfw: map['nsfw'] == 1,
            itemType: detectedType!,
            repo: repoUrl,
            iconUrl: '$baseIconUrl/icon/${map['pkg']}.png',
            apkUrl: (apkName != null && apkName.isNotEmpty)
                ? '$baseIconUrl/apk/$apkName'
                : null,
          ),
        ),
      );
    }

    return List.unmodifiable(sources);
  } catch (e) {
    debugPrint('Failed to parse Tachiyomi repo index from $repoUrl: $e');
    return const [];
  }
}

void detectTachiyomiUpdates(
  Extension ext,
  List<Source> available,
  ItemType type,
) {
  final repoById = <String?, PackagedSource>{
    for (final s in available)
      if (s is PackagedSource) s.id: s,
  };

  final installed = ext.getInstalledRx(type).value;
  var changed = false;

  for (final inst in installed) {
    if (inst is! PackagedSource) continue;

    final repo = repoById[inst.id];
    if (repo == null) continue;

    final hasUpdate =
        ext.compareVersions(repo.version ?? '0', inst.version ?? '0') > 0;

    if (hasUpdate) {
      inst
        ..hasUpdate = true
        ..apkName = repo.apkName
        ..apkUrlOverride = repo.apkUrlOverride
        ..jarUrl = repo.jarUrl
        ..pkgName = repo.pkgName ?? inst.pkgName
        ..iconUrl = repo.iconUrl
        ..versionLast = repo.version;
      changed = true;
    } else if (inst.hasUpdate == true) {
      inst.hasUpdate = false;
      changed = true;
    }
  }

  if (changed) {
    ext.getInstalledRx(type).value = List.unmodifiable(installed);
  }
}

enum RepoIndexFormat {
  json,
  protobuf,
}

RepoIndexFormat tachiyomiIndexFormat(String url) =>
    url.endsWith('.pb') ? RepoIndexFormat.protobuf : RepoIndexFormat.json;

List<T> parseTachiyomiIndexBytes<T extends Source>(
  Uint8List body,
  String repoUrl,
  ItemType targetType, {
  required Map<String, ItemType> prefixes,
  required T Function(TachiyomiRepoEntry entry) factory,
}) {
  if (tachiyomiIndexFormat(repoUrl) == RepoIndexFormat.protobuf) {
    return parseTachiyomiPbIndex<T>(
      body: body,
      repoUrl: repoUrl,
      targetType: targetType,
      factory: factory,
    );
  }
  return parseTachiyomiRepoIndex<T>(
    body: utf8.decode(body, allowMalformed: true),
    repoUrl: repoUrl,
    targetType: targetType,
    prefixes: prefixes,
    factory: factory,
  );
}

const _pbContentWarningMixed = 2;
const _pbStoreExtensionList = 101;
const _pbStoreExtensionListUrl = 102;
const _pbListExtensions = 1;
const _pbExtName = 1;
const _pbExtPackageName = 2;
const _pbExtResources = 3;
const _pbExtLib = 4;
const _pbExtVersionCode = 5;
const _pbExtVersionName = 6;
const _pbExtContentWarning = 7;
const _pbExtSources = 8;
const _pbResApkUrl = 1;
const _pbResIconUrl = 2;
const _pbResJarUrl = 501;
const _pbSourceId = 1;
const _pbSourceLanguage = 3;

Uint8List _gunzipIfNeeded(Uint8List body) {
  if (body.length >= 2 && body[0] == 0x1f && body[1] == 0x8b) {
    return Uint8List.fromList(gzip.decode(body));
  }
  return body;
}

String? tachiyomiPbExtensionListUrl(Uint8List body) {
  try {
    final store = ProtoMessage.decode(_gunzipIfNeeded(body));
    if (store.has(_pbStoreExtensionList)) return null;
    return store.readString(_pbStoreExtensionListUrl);
  } catch (_) {
    return null;
  }
}

List<T> parseTachiyomiPbIndex<T extends Source>({
  required Uint8List body,
  required String repoUrl,
  required ItemType targetType,
  required T Function(TachiyomiRepoEntry entry) factory,
}) {
  try {
    final store = ProtoMessage.decode(_gunzipIfNeeded(body));

    final list = store.readMessage(_pbStoreExtensionList);
    if (list == null) return const [];

    final sources = <T>[];

    for (final ext in list.readMessages(_pbListExtensions)) {
      final pkgName = ext.readString(_pbExtPackageName);
      final itemType = _pbItemType(pkgName) ?? targetType;
      if (itemType != targetType) continue;

      final resources = ext.readMessage(_pbExtResources);
      final apkUrl = resources?.readString(_pbResApkUrl);
      final iconUrl = resources?.readString(_pbResIconUrl) ?? '';
      final jarUrl = resources?.readString(_pbResJarUrl);

      final entrySources = ext.readMessages(_pbExtSources);
      final id = entrySources.isEmpty
          ? ''
          : (entrySources.first.readInt(_pbSourceId)?.toString() ?? '');

      final languages = <String>{
        for (final s in entrySources)
          if (s.readString(_pbSourceLanguage) case final l? when l.isNotEmpty)
            l,
      };

      final warning = ext.readInt(_pbExtContentWarning) ?? 0;

      sources.add(
        factory(
          TachiyomiRepoEntry(
            id: id,
            name: ext.readString(_pbExtName) ?? '',
            pkgName: pkgName,
            apkName: apkUrl?.split('/').last,
            lang: languages.length == 1 ? languages.first : 'all',
            version:
                ext.readString(_pbExtVersionName) ??
                ext.readInt(_pbExtVersionCode)?.toString(),
            isNsfw: warning >= _pbContentWarningMixed,
            itemType: itemType,
            repo: repoUrl,
            iconUrl: iconUrl,
            apkUrl: apkUrl,
            jarUrl: jarUrl,
          ),
        ),
      );
    }

    return List.unmodifiable(sources);
  } catch (e) {
    debugPrint('Failed to parse index.pb from $repoUrl: $e');
    return const [];
  }
}

ItemType? _pbItemType(String? pkgName) {
  if (pkgName == null) return null;
  if (pkgName.contains('.animeextension.')) return ItemType.anime;
  if (pkgName.contains('.extension.')) return ItemType.manga;
  return null;
}

String? tachiyomiPbExtensionLib(ProtoMessage extension) =>
    extension.readString(_pbExtLib);

typedef RepoIndexResponse = ({Uint8List body, String url});

Future<RepoIndexResponse> fetchTachiyomiRepoIndex(
  http.Client client,
  String repoUrl, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final primary = tachiyomiIndexUrl(repoUrl);

  try {
    final res = await client.get(Uri.parse(primary)).timeout(timeout);
    if (res.statusCode == 200) return (body: res.bodyBytes, url: primary);
    throw Exception('Primary index fetch failed (${res.statusCode})');
  } catch (e) {
    Logger.log('Primary repo failed: $primary -> $e');

    final fallback = tachiyomiFallbackRepoUrl(repoUrl);
    if (fallback == null) {
      throw Exception('Failed to fetch repo and no fallback available');
    }

    final fallbackUrl = tachiyomiIndexUrl(fallback);

    try {
      final res = await client.get(Uri.parse(fallbackUrl)).timeout(timeout);
      if (res.statusCode == 200) return (body: res.bodyBytes, url: fallbackUrl);
      throw Exception('Fallback index fetch failed (${res.statusCode})');
    } catch (e2) {
      Logger.log('Fallback failed: $fallbackUrl -> $e2');
      throw Exception('Failed to fetch repo (primary + fallback)');
    }
  }
}
