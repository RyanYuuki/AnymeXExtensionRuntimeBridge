import 'dart:async';
import 'dart:io';
import 'SidecarBridge.dart';
import '../../Engines/JavaEngine/Bridge/EmbeddedJvmBridge.dart';

enum BridgeType { jni, sidecar }

class BridgeDispatcher {
  static final BridgeDispatcher _instance = BridgeDispatcher._internal();
  factory BridgeDispatcher() => _instance;
  BridgeDispatcher._internal();

  BridgeType get mode => BridgeType.sidecar;

  void setMode(BridgeType mode) {}

  Future<void> initialize(String bridgeJarPath) async {
    if (Platform.isIOS) {
      await EmbeddedJvmBridge().init(pluginJarPath: bridgeJarPath);
      return;
    }
    await SidecarBridge().initialize(bridgeJarPath);
  }

  Future<dynamic> invokeMethod(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (Platform.isIOS) {
      return await EmbeddedJvmBridge().invokeMethod(method, args, timeout: timeout);
    }
    return await SidecarBridge().invokeMethod(method, args, timeout: timeout);
  }

  Stream<dynamic> invokeStreamMethod(String method, Map<String, dynamic> args) {
    if (Platform.isIOS) {
      final controller = StreamController<dynamic>();
      invokeMethod(method, args).then((data) {
        if (data is List) {
          for (final item in data) {
            controller.add(item);
          }
        } else if (data != null) {
          controller.add(data);
        }
        controller.close();
      }).catchError((err, st) {
        controller.addError(err, st);
        controller.close();
      });
      return controller.stream;
    }
    return SidecarBridge().invokeStreamMethod(method, args);
  }

  Future<bool> cancelRequest(String id) async {
    if (Platform.isIOS) return false;
    return SidecarBridge().cancelRequest(id);
  }

  void dispose() {
    if (Platform.isIOS) {
      EmbeddedJvmBridge().dispose();
      return;
    }
    SidecarBridge().dispose();
  }
}
