#pragma once

#ifdef _WIN32
  #ifdef TORRENT_BRIDGE_EXPORTS
    #define TORRENT_API __declspec(dllexport)
  #else
    #define TORRENT_API __declspec(dllimport)
  #endif
#else
  #define TORRENT_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef void*   lt_session_t;
typedef int64_t lt_torrent_id;
typedef int64_t lt_stream_id;

/* torrent states */
#define LT_STATE_ERROR             -2
#define LT_STATE_UNKNOWN           -1
#define LT_STATE_CHECKING_FILES     0
#define LT_STATE_DOWNLOADING_META   1
#define LT_STATE_DOWNLOADING        2
#define LT_STATE_FINISHED           3
#define LT_STATE_SEEDING            4
#define LT_STATE_ALLOCATING         5
#define LT_STATE_CHECKING_RESUME    6

/* stream states */
#define LT_STREAM_IDLE       0
#define LT_STREAM_BUFFERING  1
#define LT_STREAM_READY      2
#define LT_STREAM_SEEKING    3
#define LT_STREAM_ERROR      4

typedef struct {
    lt_torrent_id id;
    char          name[512];
    char          save_path[1024];
    char          error_msg[256];
    int32_t       state;
    float         progress;
    int32_t       download_rate;
    int32_t       upload_rate;
    int64_t       total_done;
    int64_t       total_wanted;
    int64_t       total_uploaded;
    int32_t       num_peers;
    int32_t       num_seeds;
    int32_t       num_pieces;
    int32_t       pieces_done;
    int32_t       is_paused;
    int32_t       is_finished;
    int32_t       has_metadata;
    int32_t       queue_position;
} lt_torrent_status;

typedef struct {
    int32_t index;
    char    name[512];
    char    path[1024];
    int64_t size;
    int32_t is_streamable;
} lt_file_info;

typedef struct {
    lt_stream_id  id;
    lt_torrent_id torrent_id;
    int32_t       file_index;
    char          url[256];
    int64_t       file_size;
    int64_t       read_head;
    int32_t       stream_state;      /* LT_STREAM_* */
    float         buffer_seconds;    /* estimated seconds of data buffered ahead */
    int32_t       buffer_pieces;     /* contiguous completed pieces ahead */
    int32_t       readahead_window;  /* current adaptive readahead size */
    int32_t       active_peers;
    int32_t       download_rate;     /* bytes/s for this stream */
} lt_stream_status;

/* ── port of settings/btsets.go BTSets struct ── */
typedef struct {
    /* Cache */
    int64_t cache_size;              /* bytes, default 64MB */
    int32_t reader_read_ahead;       /* percent 5-100, default 95 */
    int32_t preload_cache;           /* percent 0-100, default 50 */

    /* Torrent engine */
    int32_t connections_limit;       /* default 25 */
    int32_t torrent_disconnect_timeout; /* seconds, default 30 */
    int32_t force_encrypt;           /* 0=enabled, 1=forced */
    int32_t disable_tcp;             /* 0=enabled (default), 1=disabled */
    int32_t disable_utp;             /* 0=enabled (default), 1=disabled */
    int32_t disable_upload;          /* 0=enabled (default), 1=disabled */
    int32_t disable_dht;             /* 0=enabled (default), 1=disabled */
    int32_t disable_upnp;            /* 0=enabled (default), 1=disabled */
    int32_t enable_ipv6;             /* 0=disabled (default), 1=enabled */
    int32_t download_rate_limit;     /* KB/s, 0=unlimited */
    int32_t upload_rate_limit;       /* KB/s, 0=unlimited */
    int32_t peers_listen_port;       /* 0=random (default) */

    /* Reader */
    int32_t responsive_mode;         /* 1=enabled (default), 0=disabled */
} lt_bt_config;

typedef void (*lt_alert_callback)(int alert_type, lt_torrent_id id,
                                  const char* message, void* user_data);

/* session */
TORRENT_API lt_session_t lt_create_session(const char* listen_interface,
                                           int download_limit,
                                           int upload_limit);
TORRENT_API void         lt_destroy_session(lt_session_t session);

/* engine config — port of settings/btsets.go + btserver.go configure() */
TORRENT_API void lt_configure_session(lt_session_t session,
                                      const lt_bt_config* config);
TORRENT_API void lt_get_default_config(lt_bt_config* out);

/* alerts */
TORRENT_API void lt_set_alert_callback(lt_session_t session,
                                       lt_alert_callback cb, void* user_data);
TORRENT_API void lt_poll_alerts(lt_session_t session,
                                lt_alert_callback cb, void* user_data);

/* torrent management */
TORRENT_API lt_torrent_id lt_add_magnet(lt_session_t session,
                                        const char* magnet_uri,
                                        const char* save_path,
                                        int stream_only);
TORRENT_API lt_torrent_id lt_add_torrent_file(lt_session_t session,
                                              const char* file_path,
                                              const char* save_path,
                                              int stream_only);
TORRENT_API void lt_remove_torrent(lt_session_t session,
                                   lt_torrent_id id, int delete_files);
TORRENT_API void lt_pause_torrent(lt_session_t session, lt_torrent_id id);
TORRENT_API void lt_resume_torrent(lt_session_t session, lt_torrent_id id);
TORRENT_API void lt_recheck_torrent(lt_session_t session, lt_torrent_id id);

/* status queries */
TORRENT_API int lt_get_torrent_count(lt_session_t session);
TORRENT_API int lt_get_all_statuses(lt_session_t session,
                                    lt_torrent_status* out, int max_count);
TORRENT_API int lt_get_status(lt_session_t session, lt_torrent_id id,
                              lt_torrent_status* out);

/* file queries */
TORRENT_API int  lt_get_file_count(lt_session_t session, lt_torrent_id id);
TORRENT_API int  lt_get_files(lt_session_t session, lt_torrent_id id,
                              lt_file_info* out, int max_count);
TORRENT_API void lt_set_file_priorities(lt_session_t session, lt_torrent_id id,
                                        const int32_t* priorities, int count);

/* streaming */
TORRENT_API lt_stream_id lt_start_stream(lt_session_t session,
                                         lt_torrent_id torrent_id,
                                         int file_index,
                                         int64_t max_cache_bytes);
TORRENT_API void         lt_stop_stream(lt_session_t session, lt_stream_id id);
TORRENT_API int          lt_get_stream_status(lt_session_t session,
                                              lt_stream_id id,
                                              lt_stream_status* out);
TORRENT_API int          lt_get_all_stream_statuses(lt_session_t session,
                                                    lt_stream_status* out,
                                                    int max_count);

/* preload — port of torr/preload.go */
TORRENT_API int  lt_preload_stream(lt_session_t session, lt_stream_id id,
                                   int64_t preload_bytes);

/* cache settings — port of settings/btsets.go */
TORRENT_API void lt_set_cache_settings(lt_session_t session, lt_stream_id id,
                                       int64_t capacity,
                                       int read_ahead_pct,
                                       int connections_limit);

/* speed limits */
TORRENT_API void lt_set_download_limit(lt_session_t session, int bytes_per_sec);
TORRENT_API void lt_set_upload_limit(lt_session_t session, int bytes_per_sec);

/* utility */
TORRENT_API const char* lt_last_error(void);
TORRENT_API const char* lt_version(void);
TORRENT_API int         lt_get_active_streams(lt_session_t session);

#ifdef __cplusplus
}
#endif
