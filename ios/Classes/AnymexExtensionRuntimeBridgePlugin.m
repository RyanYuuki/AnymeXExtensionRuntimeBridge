#import "AnymexExtensionRuntimeBridgePlugin.h"

@implementation AnymexExtensionRuntimeBridgePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"anymex_extension_runtime_bridge"
                                  binaryMessenger:[registrar messenger]];
  AnymexExtensionRuntimeBridgePlugin* instance = [[AnymexExtensionRuntimeBridgePlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    NSString* version = [@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]];
    result(version);
    return;
  }
  result(FlutterMethodNotImplemented);
}

@end

