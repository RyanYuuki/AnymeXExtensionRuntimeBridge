import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class DomBridge {
  int _docCounter = 0;
  int _elemCounter = 0;

  final Map<String, dom.Document> _documents = {};
  final Map<String, Map<String, dom.Element>> _elements = {};

  String load(String html) {
    final docId = 'doc_${++_docCounter}';
    final document = html_parser.parse(html);
    _documents[docId] = document;
    _elements[docId] = {};
    return docId;
  }

  List<dom.Element> _queryElements(dynamic root, String selector) {
    final containsRegex = RegExp(r':contains\(["' "'" r']?([^"' "'" r'\)]*)["' "'" r']?\)');
    final match = containsRegex.firstMatch(selector);
    if (match != null) {
      final textToFind = match.group(1) ?? '';
      final baseSelector = selector.replaceAll(containsRegex, '').trim();
      final effectiveSelector = baseSelector.isEmpty ? '*' : baseSelector;
      List<dom.Element> elements;
      try {
        if (root is dom.Document) {
          elements = root.querySelectorAll(effectiveSelector);
        } else if (root is dom.Element) {
          elements = root.querySelectorAll(effectiveSelector);
        } else {
          elements = [];
        }
      } catch (_) {
        elements = [];
      }
      return elements.where((el) => el.text.contains(textToFind)).toList();
    }
    try {
      if (root is dom.Document) {
        return root.querySelectorAll(selector);
      } else if (root is dom.Element) {
        return root.querySelectorAll(selector);
      }
    } catch (_) {}
    return [];
  }

  String select(String docId, String selector) {
    final doc = _documents[docId];
    if (doc == null) return '[]';

    final matched = <String>[];
    try {
      final elements = _queryElements(doc, selector);
      final elemMap = _elements[docId] ??= {};

      for (final el in elements) {
        final elId = 'elem_${++_elemCounter}';
        elemMap[elId] = el;
        matched.add(elId);
      }
    } catch (_) {}

    return jsonEncode(matched);
  }

  String find(String docId, String parentId, String selector) {
    final elemMap = _elements[docId];
    if (elemMap == null) return '[]';

    final parent = elemMap[parentId];
    if (parent == null) return '[]';

    final matched = <String>[];
    try {
      final elements = _queryElements(parent, selector);
      for (final el in elements) {
        final elId = 'elem_${++_elemCounter}';
        elemMap[elId] = el;
        matched.add(elId);
      }
    } catch (_) {}

    return jsonEncode(matched);
  }

  String text(String docId, String elementIdsCsv) {
    final elemMap = _elements[docId];
    if (elemMap == null) return '';

    final ids = elementIdsCsv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    final buffer = StringBuffer();

    for (final id in ids) {
      final el = elemMap[id];
      if (el != null) {
        buffer.write(el.text);
      }
    }

    return buffer.toString();
  }

  String innerHtml(String docId, String elementId) {
    final elemMap = _elements[docId];
    if (elemMap == null) return '';
    final el = elemMap[elementId];
    return el?.innerHtml ?? '';
  }

  String html(String docId, String elementId) {
    if (elementId.isEmpty) {
      return _documents[docId]?.outerHtml ?? '';
    }
    final elemMap = _elements[docId];
    return elemMap?[elementId]?.outerHtml ?? '';
  }

  String attr(String docId, String elementId, String name) {
    final elemMap = _elements[docId];
    if (elemMap == null) return '__UNDEFINED__';

    final el = elemMap[elementId];
    if (el == null) return '__UNDEFINED__';

    if (el.attributes.containsKey(name)) {
      return el.attributes[name] ?? '';
    }
    return '__UNDEFINED__';
  }

  String next(String docId, String elementId) {
    final elemMap = _elements[docId];
    if (elemMap == null) return '__NONE__';

    final el = elemMap[elementId];
    if (el == null) return '__NONE__';

    final nextSibling = el.nextElementSibling;
    if (nextSibling == null) return '__NONE__';

    final newId = 'elem_${++_elemCounter}';
    elemMap[newId] = nextSibling;
    return newId;
  }

  String prev(String docId, String elementId) {
    final elemMap = _elements[docId];
    if (elemMap == null) return '__NONE__';

    final el = elemMap[elementId];
    if (el == null) return '__NONE__';

    final prevSibling = el.previousElementSibling;
    if (prevSibling == null) return '__NONE__';

    final newId = 'elem_${++_elemCounter}';
    elemMap[newId] = prevSibling;
    return newId;
  }

  void clear() {
    _documents.clear();
    _elements.clear();
  }
}
