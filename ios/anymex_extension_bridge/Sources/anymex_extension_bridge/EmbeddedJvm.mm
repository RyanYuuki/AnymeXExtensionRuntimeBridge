#import "EmbeddedJvm.h"
#import <TargetConditionals.h>

// Adapted from https://github.com/kodjodevf/m_extension_server
// (ios/Classes/MihonEmbeddedBridge.mm). Kept verbatim: the dlopen of the
// static OpenJDK Zero framework, the required-symbol probe, the dedicated
// JVM-sized bootstrap NSThread, the Serial-GC / -Xss tuning. Changed: the VM
// classpath is only the `embedded-bridge` shim JAR, and the cached entry
// points are load/call/unload/pause/resume on
// `com.aayush262.dartotsu_extension_bridge.EmbeddedBridge` rather than a fixed
// server bridge.

#if !TARGET_OS_SIMULATOR
#include <jni.h>

#include <cstdio>
#include <cstdint>
#include <dlfcn.h>
#include <os/lock.h>
#include <string>
#include <vector>

@interface DartotsuEmbeddedJvmThread : NSThread {
  NSCondition *_condition;
  NSMutableArray *_pendingBlocks;
}
- (void)enqueueBlock:(dispatch_block_t)block;
@end

@implementation DartotsuEmbeddedJvmThread

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _condition = [[NSCondition alloc] init];
    _pendingBlocks = [[NSMutableArray alloc] init];
    self.name = @"com.aayush262.dartotsu_extension_bridge.embedded-jvm";
    // The Zero interpreter splits the current native stack between its Java
    // operand stack and C/C++ calls. iOS dispatch workers only give a small
    // implementation-defined stack, which can exhaust during java.lang
    // bootstrap. Give the embedded VM a stable, JVM-sized stack.
    self.stackSize = 8 * 1024 * 1024;
  }
  return self;
}

- (void)enqueueBlock:(dispatch_block_t)block {
  [_condition lock];
  [_pendingBlocks addObject:[block copy]];
  [_condition signal];
  [_condition unlock];
}

- (void)main {
  while (!self.cancelled) {
    dispatch_block_t block = nil;
    [_condition lock];
    while (_pendingBlocks.count == 0 && !self.cancelled) {
      [_condition wait];
    }
    if (_pendingBlocks.count > 0) {
      block = _pendingBlocks.firstObject;
      [_pendingBlocks removeObjectAtIndex:0];
    }
    [_condition unlock];

    if (block != nil) {
      @autoreleasepool {
        block();
      }
    }
  }
}

@end

namespace {

NSString *const kEmbeddedJvmErrorDomain =
    @"com.aayush262.dartotsu_extension_bridge.embedded_jvm";
const char *const kEmbeddedBridgeClassName =
    "com/aayush262/dartotsu_extension_bridge/EmbeddedBridge";
const char *const kOpenJDKFrameworkRelativePath =
    "Frameworks/OpenJDKRuntime.framework/OpenJDKRuntime";

using LoadFunctions = void (*)(void);
using CreateJavaVM = jint (*)(JavaVM **, void **, void *);

JavaVM *gJavaVM = nullptr;
jclass gEmbeddedBridgeClass = nullptr;
jmethodID gLoadMethod = nullptr;
jmethodID gCallMethod = nullptr;
jmethodID gUnloadMethod = nullptr;
jmethodID gPauseMethod = nullptr;
jmethodID gResumeMethod = nullptr;
void *gOpenJDKHandle = nullptr;
LoadFunctions gLoadFunctions = nullptr;
CreateJavaVM gCreateJavaVM = nullptr;
os_unfair_lock gJavaVMLock = OS_UNFAIR_LOCK_INIT;

class JavaVMLockGuard {
 public:
  JavaVMLockGuard() { os_unfair_lock_lock(&gJavaVMLock); }
  ~JavaVMLockGuard() { os_unfair_lock_unlock(&gJavaVMLock); }
  JavaVMLockGuard(const JavaVMLockGuard &) = delete;
  JavaVMLockGuard &operator=(const JavaVMLockGuard &) = delete;
};

void Trace(NSString *message) {
  const char *utf8 = message.UTF8String;
  fprintf(stderr, "dartotsu EmbeddedJvm: %s\n",
          utf8 == nullptr ? "(null)" : utf8);
  fflush(stderr);
}

DartotsuEmbeddedJvmThread *EmbeddedJvmThread() {
  static DartotsuEmbeddedJvmThread *thread;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    thread = [[DartotsuEmbeddedJvmThread alloc] init];
    [thread start];
  });
  return thread;
}

NSError *EmbeddedJvmError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:kEmbeddedJvmErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

NSString *OpenJDKRuntimePath() {
  NSString *relativePath =
      [NSString stringWithUTF8String:kOpenJDKFrameworkRelativePath];
  return [NSBundle.mainBundle.bundlePath
      stringByAppendingPathComponent:relativePath];
}

NSString *OpenJDKRuntimeHome() {
  return [[OpenJDKRuntimePath() stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"lib"];
}

NSString *EmbeddedRuntimeResourcePath() {
#if SWIFT_PACKAGE
  NSString *bundlePath = SWIFTPM_MODULE_BUNDLE.resourcePath;
  return bundlePath == nil
      ? NSBundle.mainBundle.resourcePath
      : [bundlePath stringByAppendingPathComponent:@"Runtime"];
#else
  NSBundle *pluginBundle = [NSBundle
      bundleForClass:NSClassFromString(
                         @"dartotsu_extension_bridge.DartotsuExtensionBridgePlugin")];
  NSString *bundlePath =
      [pluginBundle pathForResource:@"dartotsu_extension_bridge_runtime"
                            ofType:@"bundle"];
  if (bundlePath == nil) {
    bundlePath = [NSBundle.mainBundle
        pathForResource:@"dartotsu_extension_bridge_runtime"
                 ofType:@"bundle"];
  }
  NSBundle *runtimeBundle =
      bundlePath == nil ? nil : [NSBundle bundleWithPath:bundlePath];
  return runtimeBundle.resourcePath ?: NSBundle.mainBundle.resourcePath;
#endif
}

bool LoadOpenJDKRuntime(NSError **error) {
  if (gOpenJDKHandle != nullptr && gLoadFunctions != nullptr &&
      gCreateJavaVM != nullptr) {
    return true;
  }

  NSString *runtimePath = OpenJDKRuntimePath();
  dlerror();
  // The static OpenJDK build resolves its bundled JIMAGE and JDK native
  // functions through dlsym(RTLD_DEFAULT, ...). RTLD_GLOBAL is therefore
  // required even though the framework itself is loaded lazily.
  void *handle = dlopen(runtimePath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
  if (handle == nullptr) {
    const char *details = dlerror();
    if (error != nullptr) {
      *error = EmbeddedJvmError(
          12, [NSString stringWithFormat:
                   @"The embedded Java runtime could not be loaded: %s",
                   details == nullptr ? "unknown dynamic loader error"
                                      : details]);
    }
    return false;
  }

  const char *const requiredGlobalSymbols[] = {
      "JDK_Canonicalize",   "JIMAGE_Open",         "JIMAGE_Close",
      "JIMAGE_FindResource", "JIMAGE_GetResource", "VerifyClassForMajorVersion",
  };
  for (const char *symbol : requiredGlobalSymbols) {
    dlerror();
    if (dlsym(RTLD_DEFAULT, symbol) == nullptr) {
      if (error != nullptr) {
        *error = EmbeddedJvmError(
            14, [NSString stringWithFormat:
                     @"The embedded Java runtime cannot expose %s.", symbol]);
      }
      dlclose(handle);
      return false;
    }
  }

  dlerror();
  auto loadFunctions = reinterpret_cast<LoadFunctions>(
      dlsym(handle, "MExtensionServerOpenJDKLoadFunctions"));
  const char *loadFunctionsError = dlerror();
  dlerror();
  auto createJavaVM =
      reinterpret_cast<CreateJavaVM>(dlsym(handle, "JNI_CreateJavaVM"));
  const char *createJavaVMError = dlerror();
  if (loadFunctions == nullptr || createJavaVM == nullptr ||
      loadFunctionsError != nullptr || createJavaVMError != nullptr) {
    if (error != nullptr) {
      *error = EmbeddedJvmError(
          13, @"The embedded Java runtime is missing its JNI entry points.");
    }
    dlclose(handle);
    return false;
  }

  gOpenJDKHandle = handle;
  gLoadFunctions = loadFunctions;
  gCreateJavaVM = createJavaVM;
  return true;
}

NSString *JavaExceptionMessage(JNIEnv *env, NSString *fallback) {
  jthrowable exception = env->ExceptionOccurred();
  if (exception == nullptr) {
    return fallback;
  }
  env->ExceptionClear();

  NSString *message = fallback;
  jclass throwableClass = env->FindClass("java/lang/Throwable");
  if (throwableClass != nullptr) {
    jmethodID toStringMethod =
        env->GetMethodID(throwableClass, "toString", "()Ljava/lang/String;");
    if (toStringMethod != nullptr) {
      auto text = static_cast<jstring>(
          env->CallObjectMethod(exception, toStringMethod));
      if (!env->ExceptionCheck() && text != nullptr) {
        const char *utf8 = env->GetStringUTFChars(text, nullptr);
        if (utf8 != nullptr) {
          message = [NSString stringWithUTF8String:utf8];
          env->ReleaseStringUTFChars(text, utf8);
        }
        env->DeleteLocalRef(text);
      } else {
        env->ExceptionClear();
      }
    }
    env->DeleteLocalRef(throwableClass);
  } else {
    env->ExceptionClear();
  }
  env->DeleteLocalRef(exception);
  return message;
}

bool VerifyRuntimeFiles(NSString *resourcePath, NSString *runtimeHome,
                        NSError **error) {
  NSArray<NSString *> *requiredFiles = @[
    @"lib/security/cacerts",
    @"embedded-bridge.jar",
    @"java-logging-shim.jar",
  ];
  NSFileManager *fileManager = NSFileManager.defaultManager;
  for (NSString *relativePath in requiredFiles) {
    NSString *path = [resourcePath stringByAppendingPathComponent:relativePath];
    if (![fileManager fileExistsAtPath:path]) {
      if (error != nullptr) {
        *error = EmbeddedJvmError(
            1, [NSString stringWithFormat:
                    @"The embedded runtime is incomplete: %@ is missing.",
                    relativePath]);
      }
      return false;
    }
  }
  NSArray<NSString *> *homeFiles = @[
    @"lib/modules",
    @"conf/security/java.security",
    @"lib/tzdb.dat",
  ];
  for (NSString *relativePath in homeFiles) {
    NSString *path = [runtimeHome stringByAppendingPathComponent:relativePath];
    if (![fileManager fileExistsAtPath:path]) {
      if (error != nullptr) {
        *error = EmbeddedJvmError(
            1, [NSString stringWithFormat:
                    @"The framework-local OpenJDK is incomplete: %@ is missing.",
                    relativePath]);
      }
      return false;
    }
  }
  return true;
}

NSString *CreateApplicationDirectory(NSError **error) {
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSURL *supportURL = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                          inDomain:NSUserDomainMask
                                 appropriateForURL:nil
                                            create:YES
                                             error:error];
  if (supportURL == nil) {
    return nil;
  }
  NSURL *appURL = [supportURL URLByAppendingPathComponent:@"DartotsuExtensions"
                                             isDirectory:YES];
  if (![fileManager createDirectoryAtURL:appURL
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:error]) {
    return nil;
  }
  return appURL.path;
}

bool CacheBridgeEntryPoints(JNIEnv *env, NSError **error) {
  jclass localClass = env->FindClass(kEmbeddedBridgeClassName);
  if (localClass == nullptr) {
    if (error != nullptr) {
      *error = EmbeddedJvmError(
          3, JavaExceptionMessage(
                 env, @"The embedded bridge class could not be loaded."));
    }
    return false;
  }

  gEmbeddedBridgeClass = static_cast<jclass>(env->NewGlobalRef(localClass));
  env->DeleteLocalRef(localClass);
  if (gEmbeddedBridgeClass == nullptr) {
    if (error != nullptr) {
      *error = EmbeddedJvmError(
          4, @"The embedded bridge class could not be retained.");
    }
    return false;
  }

  gLoadMethod = env->GetStaticMethodID(gEmbeddedBridgeClass, "load",
                                       "(Ljava/lang/String;)V");
  gCallMethod = env->GetStaticMethodID(
      gEmbeddedBridgeClass, "call",
      "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
  gUnloadMethod = env->GetStaticMethodID(gEmbeddedBridgeClass, "unload",
                                         "(Ljava/lang/String;)V");
  gPauseMethod = env->GetStaticMethodID(gEmbeddedBridgeClass, "pause", "()V");
  gResumeMethod = env->GetStaticMethodID(gEmbeddedBridgeClass, "resume", "()V");
  if (gLoadMethod == nullptr || gCallMethod == nullptr ||
      gUnloadMethod == nullptr || gPauseMethod == nullptr ||
      gResumeMethod == nullptr || env->ExceptionCheck()) {
    if (error != nullptr) {
      *error = EmbeddedJvmError(
          5, JavaExceptionMessage(
                 env, @"The embedded bridge entry points are invalid."));
    }
    return false;
  }
  return true;
}

bool CreateJavaVMIfNeeded(JNIEnv **environment, NSError **error) {
  JavaVMLockGuard guard;
  if (gJavaVM != nullptr) {
    if (gEmbeddedBridgeClass == nullptr || gCallMethod == nullptr) {
      if (error != nullptr) {
        *error = EmbeddedJvmError(
            2, @"The embedded Java runtime did not initialize completely.");
      }
      return false;
    }
    jint result = gJavaVM->AttachCurrentThread(
        reinterpret_cast<void **>(environment), nullptr);
    if (result != JNI_OK) {
      if (error != nullptr) {
        *error = EmbeddedJvmError(
            6, @"The embedded Java runtime could not attach its worker.");
      }
      return false;
    }
    return true;
  }

  NSString *resourcePath = EmbeddedRuntimeResourcePath();
  NSString *runtimeHome = OpenJDKRuntimeHome();
  if (!VerifyRuntimeFiles(resourcePath, runtimeHome, error)) {
    return false;
  }
  if (!LoadOpenJDKRuntime(error)) {
    return false;
  }

  NSString *applicationDirectory = CreateApplicationDirectory(error);
  if (applicationDirectory == nil) {
    return false;
  }
  NSString *temporaryDirectory = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"DartotsuExtensions"];
  if (![NSFileManager.defaultManager createDirectoryAtPath:temporaryDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:error]) {
    return false;
  }

  NSString *bridgeJar =
      [resourcePath stringByAppendingPathComponent:@"embedded-bridge.jar"];
  NSString *loggingShim =
      [resourcePath stringByAppendingPathComponent:@"java-logging-shim.jar"];
  NSString *trustStore =
      [resourcePath stringByAppendingPathComponent:@"lib/security/cacerts"];

  std::vector<std::string> optionStrings = {
      std::string("-Djava.class.path=") + bridgeJar.UTF8String,
      std::string("-Xbootclasspath/a:") + loggingShim.UTF8String,
      std::string("-Djava.home=") + runtimeHome.UTF8String,
      std::string("-Djava.io.tmpdir=") + temporaryDirectory.UTF8String,
      std::string("-Duser.home=") + applicationDirectory.UTF8String,
      std::string("-Djavax.net.ssl.trustStore=") + trustStore.UTF8String,
      "-Djavax.net.ssl.trustStorePassword=changeit",
      "-Djava.awt.headless=true",
      "-Dfile.encoding=UTF-8",
      "-Djava.net.preferIPv4Stack=true",
      "-Dorg.slf4j.simpleLogger.defaultLogLevel=warn",
      // OpenJDK Zero uses Serial GC on iOS.
      "-XX:+UseSerialGC",
      "-Xms128m",
      "-Xmx512m",
      "-XX:NewSize=64m",
      "-XX:MaxNewSize=256m",
      // The bootstrap thread has an 8 MiB stack, but the backend JARs create
      // ordinary Java threads (okhttp, coroutine dispatchers). BSD Zero would
      // otherwise give them only 1536 KiB and its stack-overflow signal path
      // is not implemented, turning a deep call into a process-fatal
      // ShouldNotCall instead of StackOverflowError.
      "-Xss8m",
  };
  std::vector<JavaVMOption> options(optionStrings.size());
  for (size_t index = 0; index < optionStrings.size(); index++) {
    options[index].optionString =
        const_cast<char *>(optionStrings[index].c_str());
    options[index].extraInfo = nullptr;
  }

  JavaVMInitArgs arguments = {};
  arguments.version = JNI_VERSION_1_8;
  arguments.nOptions = static_cast<jint>(options.size());
  arguments.options = options.data();
  arguments.ignoreUnrecognized = JNI_FALSE;

  Trace(@"calling JNI_CreateJavaVM");
  gLoadFunctions();
  jint result = gCreateJavaVM(&gJavaVM,
                              reinterpret_cast<void **>(environment), &arguments);
  if (result != JNI_OK || gJavaVM == nullptr || *environment == nullptr) {
    gJavaVM = nullptr;
    if (error != nullptr) {
      *error = EmbeddedJvmError(
          7, [NSString stringWithFormat:
                  @"The embedded Java runtime could not start (JNI %d).",
                  result]);
    }
    return false;
  }
  if (!CacheBridgeEntryPoints(*environment, error)) {
    return false;
  }
  Trace(@"embedded Java runtime initialization completed");
  return true;
}

void DetachCurrentWorker() {
  if (gJavaVM != nullptr) {
    gJavaVM->DetachCurrentThread();
  }
}

// Runs `body` on the dedicated 8 MiB-stack bootstrap thread with a live
// JNIEnv. Used for VM creation and the rare load/unload/lifecycle ops:
// creating the VM must happen on this big stack (Zero's java.lang bootstrap
// exhausts a small one), and load/unload just mutate a ConcurrentHashMap.
void RunOnJvm(void (^body)(JNIEnv *env, NSString **result, NSError **error),
              EmbeddedJvmResultCompletion completion) {
  [EmbeddedJvmThread() enqueueBlock:^{
    @autoreleasepool {
      NSError *error = nil;
      NSString *result = nil;
      JNIEnv *environment = nullptr;
      if (CreateJavaVMIfNeeded(&environment, &error)) {
        body(environment, &result, &error);
        DetachCurrentWorker();
      }
      NSString *captured = result;
      NSError *capturedError = error;
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(captured, capturedError);
      });
    }
  }];
}

// Concurrent queue for `call`. The single bootstrap thread would serialize
// every extension request across all backends (M-Extension-Server gets
// concurrency from NanoHTTPD's worker pool). Instead each call attaches a
// fresh JNI thread, runs, and detaches; same-source calls still serialize
// inside `Server.handleEmbedded` (`withSourceLock`), different sources run in
// parallel. The VM is never *created* here — `EmbeddedJvmStart` (bootstrap
// thread) must have run first, which the Dart side awaits.
dispatch_queue_t EmbeddedJvmCallQueue() {
  static dispatch_queue_t queue;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create(
        "com.aayush262.dartotsu_extension_bridge.embedded-jvm.call",
        DISPATCH_QUEUE_CONCURRENT);
  });
  return queue;
}

void AttachInvokeDetach(void (^body)(JNIEnv *env, NSString **result,
                                     NSError **error),
                        EmbeddedJvmResultCompletion completion) {
  dispatch_async(EmbeddedJvmCallQueue(), ^{
    @autoreleasepool {
      NSError *error = nil;
      NSString *result = nil;
      JavaVM *vm = gJavaVM;
      if (vm == nullptr) {
        error = EmbeddedJvmError(
            2, @"The embedded Java runtime is not started yet.");
      } else {
        JNIEnv *environment = nullptr;
        jint attach = vm->AttachCurrentThread(
            reinterpret_cast<void **>(&environment), nullptr);
        if (attach != JNI_OK || environment == nullptr) {
          error = EmbeddedJvmError(
              6, @"The embedded Java runtime could not attach a worker.");
        } else {
          body(environment, &result, &error);
          vm->DetachCurrentThread();
        }
      }
      NSString *captured = result;
      NSError *capturedError = error;
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(captured, capturedError);
      });
    }
  });
}

}  // namespace

void EmbeddedJvmStart(EmbeddedJvmCompletion completion) {
  RunOnJvm(
      ^(JNIEnv *env, NSString **result, NSError **error) {
        // CreateJavaVMIfNeeded already did the work.
        (void)env;
        (void)result;
        (void)error;
      },
      ^(NSString *_, NSError *error) {
        completion(error);
      });
}

void EmbeddedJvmLoad(NSString *jarPath, EmbeddedJvmCompletion completion) {
  RunOnJvm(
      ^(JNIEnv *env, NSString **result, NSError **error) {
        jstring path = env->NewStringUTF(jarPath.UTF8String);
        env->CallStaticVoidMethod(gEmbeddedBridgeClass, gLoadMethod, path);
        if (env->ExceptionCheck()) {
          *error = EmbeddedJvmError(
              8, JavaExceptionMessage(env, @"Loading the backend JAR failed."));
        }
        if (path != nullptr) {
          env->DeleteLocalRef(path);
        }
        (void)result;
      },
      ^(NSString *_, NSError *error) {
        completion(error);
      });
}

void EmbeddedJvmCall(NSString *jarPath, NSString *requestJson,
                     EmbeddedJvmResultCompletion completion) {
  AttachInvokeDetach(
      ^(JNIEnv *env, NSString **result, NSError **error) {
        jstring path = env->NewStringUTF(jarPath.UTF8String);
        jstring request = env->NewStringUTF(requestJson.UTF8String);
        auto response = static_cast<jstring>(env->CallStaticObjectMethod(
            gEmbeddedBridgeClass, gCallMethod, path, request));
        if (env->ExceptionCheck()) {
          *error = EmbeddedJvmError(
              9, JavaExceptionMessage(env, @"The embedded bridge call failed."));
        } else if (response != nullptr) {
          const char *utf8 = env->GetStringUTFChars(response, nullptr);
          if (utf8 != nullptr) {
            *result = [NSString stringWithUTF8String:utf8];
            env->ReleaseStringUTFChars(response, utf8);
          }
        }
        if (response != nullptr) {
          env->DeleteLocalRef(response);
        }
        if (request != nullptr) {
          env->DeleteLocalRef(request);
        }
        if (path != nullptr) {
          env->DeleteLocalRef(path);
        }
      },
      completion);
}

void EmbeddedJvmUnload(NSString *jarPath, EmbeddedJvmCompletion completion) {
  RunOnJvm(
      ^(JNIEnv *env, NSString **result, NSError **error) {
        jstring path = env->NewStringUTF(jarPath.UTF8String);
        env->CallStaticVoidMethod(gEmbeddedBridgeClass, gUnloadMethod, path);
        if (env->ExceptionCheck()) {
          *error = EmbeddedJvmError(
              10, JavaExceptionMessage(env, @"Unloading the backend JAR failed."));
        }
        if (path != nullptr) {
          env->DeleteLocalRef(path);
        }
        (void)result;
      },
      ^(NSString *_, NSError *error) {
        completion(error);
      });
}

static void CallVoidLifecycle(jmethodID method, NSString *what,
                              EmbeddedJvmCompletion completion) {
  [EmbeddedJvmThread() enqueueBlock:^{
    @autoreleasepool {
      NSError *error = nil;
      JNIEnv *environment = nullptr;
      if (gJavaVM != nullptr && CreateJavaVMIfNeeded(&environment, &error)) {
        environment->CallStaticVoidMethod(gEmbeddedBridgeClass, method);
        if (environment->ExceptionCheck()) {
          error = EmbeddedJvmError(
              11, JavaExceptionMessage(
                      environment,
                      [NSString stringWithFormat:@"Embedded bridge %@ failed.",
                                                 what]));
        }
        DetachCurrentWorker();
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(error);
      });
    }
  }];
}

void EmbeddedJvmPause(EmbeddedJvmCompletion completion) {
  CallVoidLifecycle(gPauseMethod, @"pause", completion);
}

void EmbeddedJvmResume(EmbeddedJvmCompletion completion) {
  CallVoidLifecycle(gResumeMethod, @"resume", completion);
}

#else  // TARGET_OS_SIMULATOR

namespace {
NSError *UnsupportedSimulatorError() {
  return [NSError
      errorWithDomain:@"com.aayush262.dartotsu_extension_bridge.embedded_jvm"
                 code:1
             userInfo:@{
               NSLocalizedDescriptionKey :
                   @"The embedded Java runtime supports physical iOS devices only."
             }];
}
}  // namespace

void EmbeddedJvmStart(EmbeddedJvmCompletion completion) {
  completion(UnsupportedSimulatorError());
}
void EmbeddedJvmLoad(NSString *jarPath, EmbeddedJvmCompletion completion) {
  (void)jarPath;
  completion(UnsupportedSimulatorError());
}
void EmbeddedJvmCall(NSString *jarPath, NSString *requestJson,
                     EmbeddedJvmResultCompletion completion) {
  (void)jarPath;
  (void)requestJson;
  completion(nil, UnsupportedSimulatorError());
}
void EmbeddedJvmUnload(NSString *jarPath, EmbeddedJvmCompletion completion) {
  (void)jarPath;
  completion(nil);
}
void EmbeddedJvmPause(EmbeddedJvmCompletion completion) { completion(nil); }
void EmbeddedJvmResume(EmbeddedJvmCompletion completion) { completion(nil); }

#endif
