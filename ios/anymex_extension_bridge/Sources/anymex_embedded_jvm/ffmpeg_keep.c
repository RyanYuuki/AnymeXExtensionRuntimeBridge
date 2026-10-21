#include <TargetConditionals.h>

// DartotsuFfmpeg.xcframework has no x86_64 simulator slice; there the Dart side
// finds no symbol and falls back to folder downloads.
#if !(TARGET_OS_SIMULATOR && defined(__x86_64__))
extern int dartotsu_ffmpeg_run(int argc, char **argv) __attribute__((weak_import));
extern void dartotsu_ffmpeg_cancel(void) __attribute__((weak_import));

__attribute__((used)) void *const dartotsu_ffmpeg_keep[] = {
    (void *)dartotsu_ffmpeg_run,
    (void *)dartotsu_ffmpeg_cancel,
};
#endif
