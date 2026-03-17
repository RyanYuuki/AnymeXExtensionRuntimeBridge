typedef JsMethod = Future<dynamic> Function(Map data);

class BridgeReg {
  static final Map<String, JsMethod> methods = {};

  static void register(String name, JsMethod method) {
    methods[name] = method;
  }

  static Future<dynamic> call(String name, Map data) async {
    final method = methods[name];

    if (method != null) {
      return await method(data);
    }

    throw Exception("Unknown bridge call: $name");
  }
}
