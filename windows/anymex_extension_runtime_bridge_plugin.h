#ifndef FLUTTER_PLUGIN_anymex_extension_runtime_bridge_PLUGIN_H_
#define FLUTTER_PLUGIN_anymex_extension_runtime_bridge_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace anymex_extension_runtime_bridge {

class AnymeXBridgePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AnymeXBridgePlugin();

  virtual ~AnymeXBridgePlugin();

  // Disallow copy and assign.
  AnymeXBridgePlugin(const AnymeXBridgePlugin&) = delete;
  AnymeXBridgePlugin& operator=(const AnymeXBridgePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace anymex_extension_runtime_bridge

#endif  // FLUTTER_PLUGIN_anymex_extension_runtime_bridge_PLUGIN_H_
