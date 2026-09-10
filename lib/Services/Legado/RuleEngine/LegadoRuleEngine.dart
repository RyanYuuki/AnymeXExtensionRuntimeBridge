import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class LegadoRuleEngine {
  /// Resolves Legado URL templates like:
  /// /novel-list/search?keyword={{key}}<,&page={{page}}>
  static String buildUrl({
    required String urlTemplate,
    required String baseUrl,
    String query = '',
    int page = 1,
  }) {
    String url = urlTemplate.trim();

    // Check if there are method / header options in URL (Legado supports: url,{"method":"POST",...})
    String? optionsJson;
    final commaIndex = url.indexOf(',{');
    if (commaIndex != -1) {
      optionsJson = url.substring(commaIndex + 1);
      url = url.substring(0, commaIndex);
    }

    // Handle conditional sections <...{{page}}...>
    final conditionalRegex = RegExp(r'<([^>]*?\{\{page\}\}[^>]*?)>');
    if (page <= 1) {
      url = url.replaceAll(conditionalRegex, '');
    } else {
      url = url.replaceAllMapped(conditionalRegex, (m) => m.group(1) ?? '');
    }

    // Replace {{key}}, {{searchKey}}, {{page}}
    url = url
        .replaceAll('{{key}}', Uri.encodeComponent(query))
        .replaceAll('{{searchKey}}', Uri.encodeComponent(query))
        .replaceAll('{{page}}', page.toString());

    // Resolve relative URL
    String resolvedUrl = url;
    if (!resolvedUrl.startsWith('http://') && !resolvedUrl.startsWith('https://')) {
      resolvedUrl = resolveUrl(baseUrl, resolvedUrl);
    }

    if (optionsJson != null) {
      return '$resolvedUrl,$optionsJson';
    }

    return resolvedUrl;
  }

  /// Resolves relative URL against base URL
  static String resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.isEmpty) return baseUrl;
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(relativeUrl).toString();
    } catch (_) {
      if (baseUrl.endsWith('/') && relativeUrl.startsWith('/')) {
        return '$baseUrl${relativeUrl.substring(1)}';
      } else if (!baseUrl.endsWith('/') && !relativeUrl.startsWith('/')) {
        return '$baseUrl/$relativeUrl';
      } else {
        return '$baseUrl$relativeUrl';
      }
    }
  }

  /// Extracts a list of elements from Document or Element (e.g. for bookList or chapterList)
  static List<Element> selectElements(dynamic root, String? rule) {
    if (root == null || rule == null || rule.trim().isEmpty) return [];

    final rules = rule.split(RegExp(r'\s*\|\|\s*'));
    for (final singleRule in rules) {
      final elements = _selectElementsSingle(root, singleRule.trim());
      if (elements.isNotEmpty) return elements;
    }
    return [];
  }

  static List<Element> _selectElementsSingle(dynamic root, String rule) {
    if (rule.isEmpty) return [];

    // Remove any trailing @attribute for element selectors
    String css = rule;
    int atIdx = css.indexOf('@');
    if (atIdx != -1) {
      css = css.substring(0, atIdx).trim();
    }

    // Handle index slicing like selector!0
    String? indexFilter;
    if (css.contains('!')) {
      final parts = css.split('!');
      css = parts[0].trim();
      if (parts.length > 1) indexFilter = '!${parts[1].trim()}';
    }

    List<Element> matched = [];

    // Check for :containsOwn(...) or :contains(...)
    final containsOwnRegex = RegExp(r':containsOwn\(([^)]+)\)');
    final containsRegex = RegExp(r':contains\(([^)]+)\)');

    if (containsOwnRegex.hasMatch(css) || containsRegex.hasMatch(css)) {
      matched = _selectWithCustomPseudo(root, css);
    } else {
      try {
        if (root is Document) {
          matched = root.querySelectorAll(css);
        } else if (root is Element) {
          matched = root.querySelectorAll(css);
        }
      } catch (_) {
        matched = [];
      }
    }

    // Apply index filter if present
    if (indexFilter != null && matched.isNotEmpty) {
      if (indexFilter.startsWith('!')) {
        final idx = int.tryParse(indexFilter.substring(1));
        if (idx != null && idx >= 0 && idx < matched.length) {
          matched.removeAt(idx);
        }
      }
    }

    return matched;
  }

  /// Extracts text or attribute string from a single element/document according to Legado rule
  static String extractString(dynamic root, String? rule, {String baseUrl = ''}) {
    if (root == null || rule == null || rule.trim().isEmpty) return '';

    // Handle piped alternatives (||)
    final alternatives = rule.split(RegExp(r'\s*\|\|\s*'));
    for (final alt in alternatives) {
      final result = _extractStringSingle(root, alt.trim(), baseUrl: baseUrl);
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  static String _extractStringSingle(dynamic root, String rule, {String baseUrl = ''}) {
    if (rule.isEmpty) return '';

    // Separate regex replacements (##pattern##replacement###...)
    String selectorPart = rule;
    List<List<String>> replacements = [];

    final regexIndex = rule.indexOf('##');
    if (regexIndex != -1) {
      selectorPart = rule.substring(0, regexIndex).trim();
      final regexPart = rule.substring(regexIndex + 2);
      replacements = _parseReplacements(regexPart);
    }

    // Separate attribute: selector@attr
    String css = selectorPart;
    String attr = 'text';

    final atIndex = selectorPart.lastIndexOf('@');
    if (atIndex != -1 && !selectorPart.contains('@@')) {
      css = selectorPart.substring(0, atIndex).trim();
      attr = selectorPart.substring(atIndex + 1).trim();
    } else if (selectorPart.contains('@@')) {
      final parts = selectorPart.split('@@');
      css = parts[0].trim();
      if (parts.length > 1) {
        attr = parts[1].trim();
      }
    }

    // If CSS is empty, extract from the current root element
    List<Element> targets = [];
    if (css.isEmpty) {
      if (root is Element) targets = [root];
    } else {
      targets = _selectElementsSingle(root, css);
    }

    String result = '';

    if (targets.isNotEmpty) {
      if (attr == 'text') {
        result = targets.map((e) => e.text.trim()).where((s) => s.isNotEmpty).join('\n');
      } else if (attr == 'html') {
        result = targets.map((e) => e.innerHtml.trim()).join('\n');
      } else {
        // Specific attribute like href, src, data-src, etc.
        final values = <String>[];
        for (final el in targets) {
          String? val;
          if (attr == 'href' || attr == 'src') {
            val = el.attributes[attr] ??
                el.attributes['data-$attr'] ??
                el.attributes['data-original'] ??
                el.attributes['data-lazy-src'];
          } else {
            val = el.attributes[attr];
          }

          if (val != null && val.isNotEmpty) {
            if ((attr == 'href' || attr == 'src') && baseUrl.isNotEmpty) {
              val = resolveUrl(baseUrl, val);
            }
            values.add(val);
          }
        }
        result = values.join('\n');
      }
    } else if (root is Element && (css == 'text' || css == 'href' || css == 'src')) {
      // Shorthand rule like 'text' or 'href' directly
      if (css == 'text') {
        result = root.text.trim();
      } else {
        final val = root.attributes[css] ?? root.attributes['data-$css'];
        if (val != null && val.isNotEmpty) {
          result = baseUrl.isNotEmpty ? resolveUrl(baseUrl, val) : val;
        }
      }
    }

    // Apply regex replacements
    for (final rep in replacements) {
      if (rep.isEmpty) continue;
      final pattern = rep[0];
      final replacement = rep.length > 1 ? rep[1] : '';
      try {
        result = result.replaceAll(RegExp(pattern, multiLine: true), replacement);
      } catch (_) {}
    }

    return result.trim();
  }

  /// Parses replacement string like "p1##r1###p2##r2" or "to_remove"
  static List<List<String>> _parseReplacements(String raw) {
    final list = <List<String>>[];
    final blocks = raw.split('###');
    for (final block in blocks) {
      if (block.isEmpty) continue;
      final parts = block.split('##');
      if (parts.length == 1) {
        list.add([parts[0], '']);
      } else {
        list.add([parts[0], parts[1]]);
      }
    }
    return list;
  }

  /// Handles JSOUP pseudo-selectors :containsOwn(...) and :contains(...)
  static List<Element> _selectWithCustomPseudo(dynamic root, String css) {
    String baseSelector = css;
    String searchText = '';
    bool own = false;

    final ownMatch = RegExp(r':containsOwn\(([^)]+)\)').firstMatch(css);
    if (ownMatch != null) {
      own = true;
      final rawArg = ownMatch.group(1)!.trim();
      searchText = rawArg.replaceAll(RegExp("^['\"]|['\"]\$"), '');
      baseSelector = css.replaceFirst(ownMatch.group(0)!, '').trim();
    } else {
      final containsMatch = RegExp(r':contains\(([^)]+)\)').firstMatch(css);
      if (containsMatch != null) {
        final rawArg = containsMatch.group(1)!.trim();
        searchText = rawArg.replaceAll(RegExp("^['\"]|['\"]\$"), '');
        baseSelector = css.replaceFirst(containsMatch.group(0)!, '').trim();
      }
    }

    // If there's a sibling operator like '~ a' or '+ a' following :contains
    String? siblingSelector;
    if (baseSelector.contains('~')) {
      final parts = baseSelector.split('~');
      baseSelector = parts[0].trim();
      siblingSelector = '~ ${parts[1].trim()}';
    } else if (baseSelector.contains('+')) {
      final parts = baseSelector.split('+');
      baseSelector = parts[0].trim();
      siblingSelector = '+ ${parts[1].trim()}';
    }

    if (baseSelector.isEmpty) baseSelector = '*';

    List<Element> candidates = [];
    try {
      if (root is Document) {
        candidates = root.querySelectorAll(baseSelector);
      } else if (root is Element) {
        candidates = root.querySelectorAll(baseSelector);
      }
    } catch (_) {
      return [];
    }

    final filtered = <Element>[];
    for (final el in candidates) {
      final targetText = own ? _getOwnText(el) : el.text;
      if (targetText.contains(searchText)) {
        if (siblingSelector != null) {
          // Find siblings matching siblingSelector
          final parent = el.parent;
          if (parent != null) {
            final subMatches = parent.querySelectorAll(siblingSelector.substring(2));
            filtered.addAll(subMatches);
          }
        } else {
          filtered.add(el);
        }
      }
    }

    return filtered;
  }

  static String _getOwnText(Element el) {
    final buffer = StringBuffer();
    for (final node in el.nodes) {
      if (node.nodeType == Node.TEXT_NODE) {
        buffer.write(node.text ?? '');
      }
    }
    return buffer.toString().trim();
  }

  /// Parses an HTML document from string
  static Document parseHtml(String html) {
    return html_parser.parse(html);
  }
}
