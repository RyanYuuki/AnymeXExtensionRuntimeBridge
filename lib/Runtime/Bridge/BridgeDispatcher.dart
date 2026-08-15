import 'package:get/get.dart';
import 'JniBridge.dart';
import 'SidecarBridge.dart';
import 'ServerBridge.dart';
import '../../ExtensionManager.dart';

enum BridgeType { jni, sidecar, server }

class BridgeDispatcher {
  static final BridgeDispatcher _instance = BridgeDispatcher._internal();
  factory BridgeDispatcher() => _instance;
  BridgeDispatcher._internal();

  BridgeType get _mode {
    if (Get.isRegistered<ExtensionManager>()) {
      return Get.find<ExtensionManager>().bridgeType.value;
    }
    return BridgeType.sidecar;
  }

  void setMode(BridgeType mode) {
    if (Get.isRegistered<ExtensionManager>()) {
      Get.find<ExtensionManager>().bridgeType.value = mode;
    }
    print('Bridge Mode set to: $mode');
  }

  BridgeType get mode => _mode;

  Future<void> initialize(String bridgeJarPath) async {
    if (_mode == BridgeType.jni) {
      await JniBridge().initialize(bridgeJarPath);
    } else if (_mode == BridgeType.sidecar) {
      await SidecarBridge().initialize(bridgeJarPath);
    }
    // Server bridge initializes via ServerBridge().initialize() separately
  }

  Future<dynamic> invokeMethod(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_mode == BridgeType.jni) {
      return await JniBridge().invokeMethod(method, args);
    } else if (_mode == BridgeType.server) {
      return await ServerBridge().invokeMethod(method, args, timeout: timeout);
    } else {
      return await SidecarBridge().invokeMethod(method, args, timeout: timeout);
    }
  }

  Stream<dynamic> invokeStreamMethod(String method, Map<String, dynamic> args) {
    if (_mode == BridgeType.jni) {
      return const Stream.empty();
    } else if (_mode == BridgeType.server) {
      return ServerBridge().invokeStreamMethod(method, args);
    } else {
      return SidecarBridge().invokeStreamMethod(method, args);
    }
  }

  Future<bool> cancelRequest(String id) async {
    if (_mode == BridgeType.jni) {
      return JniBridge().cancelRequest(id);
    } else if (_mode == BridgeType.server) {
      return ServerBridge().cancelRequest(id);
    } else {
      return SidecarBridge().cancelRequest(id);
    }
  }

  void dispose() {
    if (_mode == BridgeType.jni) {
      JniBridge().dispose();
    } else if (_mode == BridgeType.server) {
      ServerBridge().dispose();
    } else {
      SidecarBridge().dispose();
    }
  }
}
