#include "include/anymex_extension_runtime_bridge/anymex_extension_runtime_bridge_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "anymex_extension_runtime_bridge_plugin.h"

void AnymeXExtensionRuntimeBridgePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  anymex_extension_runtime_bridge::AnymeXExtensionRuntimeBridgePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
