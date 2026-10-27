import '../../LnReader/service.dart';
import '../Eval/dart/service.dart';
import '../Eval/javascript/service.dart';
import '../Models/Source.dart';
import 'interface.dart';

ExtensionService getExtensionService(MSource source) {
  return switch (source.sourceCodeLanguage) {
    SourceCodeLanguage.dart => DartExtensionService(source),
    SourceCodeLanguage.javascript => JsExtensionService(source),
    SourceCodeLanguage.lnreader => LNReaderExtensionService(source),
  };
}

const _cachedServiceLimit = 6;
final _serviceCache = <String, ExtensionService>{};

ExtensionService getCachedExtensionService(MSource source) {
  final key = '${source.id}|${source.version}|${source.sourceCode?.hashCode}';
  final cached = _serviceCache.remove(key);
  if (cached != null) {
    _serviceCache[key] = cached;
    return cached;
  }
  final service = getExtensionService(source);
  _serviceCache[key] = service;
  if (_serviceCache.length > _cachedServiceLimit) {
    _serviceCache.remove(_serviceCache.keys.first)?.dispose();
  }
  return service;
}

void evictCachedExtensionService(String sourceId) {
  _serviceCache.removeWhere((k, v) {
    if (k.startsWith('$sourceId|')) {
      v.dispose();
      return true;
    }
    return false;
  });
}
