#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^EmbeddedJvmCompletion)(NSError *_Nullable error);
typedef void (^EmbeddedJvmResultCompletion)(NSString *_Nullable result,
                                            NSError *_Nullable error);
typedef void (^EmbeddedJvmLogHandler)(NSArray<NSString *> *lines);

/// Receives every line the VM produces (HotSpot output, System.out/err,
/// uncaught exceptions, bridge trace), batched, on the main queue.
FOUNDATION_EXPORT void EmbeddedJvmSetLogHandler(
    EmbeddedJvmLogHandler _Nullable handler);

/// Creates the single in-process OpenJDK Zero VM if it is not already up.
/// Idempotent; safe to call from every backend as it initializes.
/// [logDirectory] receives `jvm.log` (every line, written synchronously so it
/// survives a crash) and HotSpot's fatal error report `hs_err.log`.
FOUNDATION_EXPORT void EmbeddedJvmStart(NSString *_Nullable logDirectory,
                                       EmbeddedJvmCompletion completion);

/// Attaches a backend fat JAR in its own child-first class loader and
/// instantiates its `com.aayush262.dartotsu_extension_bridge.Main.api()`.
/// Keyed by [jarPath]; a second call for the same path is a no-op.
FOUNDATION_EXPORT void EmbeddedJvmLoad(NSString *jarPath,
                                      EmbeddedJvmCompletion completion);

/// Dispatches one `{"method":...,"args":{...}}` request against the api loaded
/// for [jarPath]. Returns the `{"success":...,"data"|"error":...}` envelope.
FOUNDATION_EXPORT void EmbeddedJvmCall(NSString *jarPath,
                                      NSString *requestJson,
                                      EmbeddedJvmResultCompletion completion);

/// Drops the class loader + api for [jarPath]. The VM itself stays up.
FOUNDATION_EXPORT void EmbeddedJvmUnload(NSString *jarPath,
                                        EmbeddedJvmCompletion completion);

/// Lifecycle hints forwarded from the app: trims caches / lets the VM idle.
FOUNDATION_EXPORT void EmbeddedJvmPause(EmbeddedJvmCompletion completion);
FOUNDATION_EXPORT void EmbeddedJvmResume(EmbeddedJvmCompletion completion);

NS_ASSUME_NONNULL_END
