import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import '../../Models/Source.dart';
import '../../Util/extension_preferences_providers.dart';
import '../../Util/interface.dart';
import '../dart/model/filter.dart';
import '../dart/model/m_manga.dart';
import '../dart/model/m_pages.dart';
import '../dart/model/page.dart';
import '../dart/model/source_preference.dart';
import '../dart/model/video.dart';
import 'dom_selector.dart';
import 'extractors.dart';
import 'http.dart';
import 'preferences.dart';
import 'utils.dart';

class JsExtensionService implements ExtensionService {
  late JavascriptRuntime runtime;
  @override
  late MSource source;
  bool _isInitialized = false;
  late JsDomSelector _jsDomSelector;

  JsExtensionService(this.source);

  void _init() {
    if (_isInitialized) return;
    runtime = getJavascriptRuntime();
    JsHttpClient(runtime).init();
    _jsDomSelector = JsDomSelector(runtime)..init();
    JsVideosExtractors(runtime).init();
    JsUtils(runtime).init();
    JsPreferences(runtime, source).init();
    final sourceJson = jsonEncode(source.toMSource().toJson());

    runtime.evaluate('''
class MProvider {
    get source() {
        return $sourceJson;
    }
    get supportsLatest() {
        throw new Error("supportsLatest not implemented");
    }
    getHeaders(url) {
        throw new Error("getHeaders not implemented");
    }
    async getPopular(page) {
        throw new Error("getPopular not implemented");
    }
    async getLatestUpdates(page) {
        throw new Error("getLatestUpdates not implemented");
    }
    async search(query, page, filters) {
        throw new Error("search not implemented");
    }
    async getDetail(url) {
        throw new Error("getDetail not implemented");
    }
    async getPageList() {
        throw new Error("getPageList not implemented");
    }
    async getVideoList(url) {
        throw new Error("getVideoList not implemented");
    }
    async getHtmlContent(name, url) {
        throw new Error("getHtmlContent not implemented");
    }
    async cleanHtmlContent(html) {
        throw new Error("cleanHtmlContent not implemented");
    }
    getFilterList() {
        throw new Error("getFilterList not implemented");
    }
    getSourcePreferences() {
        throw new Error("getSourcePreferences not implemented");
    }
}
async function jsonStringify(fn) {
    return JSON.stringify(await fn());
}
''');
    _throwIfError(
      runtime.evaluate('''${source.sourceCode}
var extention = new DefaultExtension();
'''),
      'loading the source',
    );
    _isInitialized = true;
  }

  @override
  void dispose() {
    if (!_isInitialized) return;
    _jsDomSelector.dispose();
    _isInitialized = false;
  }

  @override
  Map<String, String> getHeaders() {
    return _extensionCall<Map>(
      'getHeaders(${jsonEncode(source.baseUrl ?? '')})',
      {},
    ).toMapStringString!;
  }

  @override
  bool get supportsLatest {
    return _extensionCall<bool>('supportsLatest', true);
  }

  @override
  String get sourceBaseUrl {
    return source.baseUrl!;
  }

  @override
  Future<MPages> getPopular(int page) async {
    final res = await _extensionCallAsync('getPopular($page)');
    if (res == null) return MPages(list: [], hasNextPage: false);
    return MPages.fromJson(res);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = await _extensionCallAsync('getLatestUpdates($page)');
    if (res == null) return MPages(list: [], hasNextPage: false);
    return MPages.fromJson(res);
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    final activeFilters =
        filters.isNotEmpty ? filters : getFilterList().filters;
    final res = await _extensionCallAsync(
      'search(${jsonEncode(query)},$page,${jsonEncode(filterValuesListToJson(activeFilters))})',
    );
    if (res == null) return MPages(list: [], hasNextPage: false);
    return MPages.fromJson(res);
  }

  @override
  Future<MManga> getDetail(String url) async {
    final res = await _extensionCallAsync('getDetail(${jsonEncode(url)})');
    if (res == null) return MManga();
    return MManga.fromJson(res);
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final res = await _extensionCallAsync('getPageList(${jsonEncode(url)})');
    if (res == null || res is! List) return [];
    return res
        .map(
          (e) => e is String
              ? PageUrl(e.trim())
              : PageUrl.fromJson((e as Map).toMapStringDynamic!),
        )
        .toList();
  }

  @override
  Future<List<Video>> getVideoList(String url) async {
    final res = await _extensionCallAsync('getVideoList(${jsonEncode(url)})');
    if (res == null || res is! List) return [];
    return res
        .where(
          (element) =>
              element is Map &&
              element['url'] != null &&
              element['originalUrl'] != null,
        )
        .map((e) => Video.fromJson(e))
        .toList()
        .toSet()
        .toList();
  }

  @override
  Future<String> getHtmlContent(String name, String url) async {
    _init();
    final res = (await runtime.handlePromise(
      await runtime.evaluateAsync(
        'jsonStringify(() => extention.getHtmlContent(${jsonEncode(name)}, ${jsonEncode(url)}))',
      ),
    )).stringResult;
    try {
      final decoded = jsonDecode(res);
      return decoded is String ? decoded : decoded?.toString() ?? '';
    } catch (_) {
      return res;
    }
  }

  @override
  Future<String> cleanHtmlContent(String html) async {
    _init();
    final res = (await runtime.handlePromise(
      await runtime.evaluateAsync(
        'jsonStringify(() => extention.cleanHtmlContent(${jsonEncode(html)}))',
      ),
    )).stringResult;
    try {
      final decoded = jsonDecode(res);
      return decoded is String ? decoded : decoded?.toString() ?? '';
    } catch (_) {
      return res;
    }
  }

  @override
  FilterList getFilterList() {
    List<dynamic> list;

    try {
      list = fromJsonFilterValuesToList(_extensionCall('getFilterList()', []));
    } catch (_) {
      list = [];
    }

    return FilterList(list);
  }

  @override
  List<SourcePreference> getSourcePreferences() {
    return _extensionCall(
      'getSourcePreferences()',
      [],
    )
        .map((e) => SourcePreference.fromJson(e)
          ..sourceId = extractSourceId(source.id!))
        .toList();
  }

  T _extensionCall<T>(String call, T def) {
    _init();

    final res = runtime.evaluate('JSON.stringify(extention.$call)');
    if (res.isError) {
      if (_isNotImplemented(res) && def != null) return def;
      _throwIfError(res, call);
    }

    try {
      return jsonDecode(res.stringResult) as T;
    } catch (_) {
      if (def != null) return def;
      rethrow;
    }
  }

  Future<T> _extensionCallAsync<T>(String call) async {
    _init();

    final evaluated = await runtime.evaluateAsync(
      'jsonStringify(() => extention.$call)',
    );
    _throwIfError(evaluated, call);

    final promised = await runtime.handlePromise(evaluated);
    _throwIfError(promised, call);

    return jsonDecode(promised.stringResult) as T;
  }

  void _throwIfError(JsEvalResult result, String what) {
    if (!result.isError) return;
    final detail = result.stringResult.trim();
    throw Exception(
      'Extension "${source.name ?? 'unknown'}" failed while $what'
      '${detail.isEmpty ? '' : ': $detail'}',
    );
  }

  bool _isNotImplemented(JsEvalResult result) =>
      result.stringResult.contains('not implemented');
}
