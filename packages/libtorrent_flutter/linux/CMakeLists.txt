# Linux CMakeLists.txt — uses prebuilt lib if available, otherwise builds from source.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "libtorrent_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# Map host arch (uname -m) to the prebuilt-zip slug used by GitHub Releases.
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(LTF_LINUX_ARCH "arm64")
else()
  set(LTF_LINUX_ARCH "x64")
endif()

set(PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/linux")
set(PREBUILT_SO "${PREBUILT_DIR}/${LTF_LINUX_ARCH}/liblibtorrent_flutter.so")

option(LIBTORRENT_FLUTTER_SKIP_DOWNLOAD "Skip downloading prebuilt native lib" OFF)

if(NOT EXISTS "${PREBUILT_SO}" AND NOT LIBTORRENT_FLUTTER_SKIP_DOWNLOAD)
  set(_PUBSPEC "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml")
  if(EXISTS "${_PUBSPEC}")
    file(READ "${_PUBSPEC}" _PUBSPEC_CONTENT)
    if("${_PUBSPEC_CONTENT}" MATCHES "version:[ \t]*([^\r\n ]+)")
      set(_LTF_VERSION "${CMAKE_MATCH_1}")
      set(_DL_URL "https://github.com/ayman708-UX/libtorrent_flutter/releases/download/v${_LTF_VERSION}/linux-native-lib-${LTF_LINUX_ARCH}.zip")
      set(_ZIP "${CMAKE_CURRENT_BINARY_DIR}/linux-native-lib-${LTF_LINUX_ARCH}.zip")
      message(STATUS "libtorrent_flutter: downloading prebuilt from ${_DL_URL}")
      file(DOWNLOAD "${_DL_URL}" "${_ZIP}" SHOW_PROGRESS STATUS _DL_STATUS TLS_VERIFY ON)
      list(GET _DL_STATUS 0 _DL_CODE)
      if(_DL_CODE EQUAL 0)
        file(MAKE_DIRECTORY "${PREBUILT_DIR}")
        execute_process(
          COMMAND "${CMAKE_COMMAND}" -E tar xf "${_ZIP}"
          WORKING_DIRECTORY "${PREBUILT_DIR}"
          RESULT_VARIABLE _UNZIP_RC
        )
        file(REMOVE "${_ZIP}")
        if(NOT _UNZIP_RC EQUAL 0)
          message(WARNING "libtorrent_flutter: failed to extract prebuilt zip (rc=${_UNZIP_RC}); will build from source")
        endif()
      else()
        message(WARNING "libtorrent_flutter: prebuilt download failed (${_DL_STATUS}); will build from source")
      endif()
    endif()
  endif()
endif()

if(EXISTS "${PREBUILT_SO}")
  message(STATUS "Using prebuilt Linux ${LTF_LINUX_ARCH} native library")
  set(libtorrent_flutter_bundled_libraries
    "${PREBUILT_SO}"
    PARENT_SCOPE
  )
else()
  message(STATUS "Building from source (no prebuilt found at ${PREBUILT_SO})")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")
  set(libtorrent_flutter_bundled_libraries
    $<TARGET_FILE:libtorrent_flutter>
    PARENT_SCOPE
  )
endif()