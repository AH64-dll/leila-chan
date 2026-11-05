# leila_llm: GDExtension linking pinned llama.cpp (+ common) and godot-cpp.
# Driven by native/build_linux.sh. See native/README.md.
cmake_minimum_required(VERSION 3.25)
project(leila_llm LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Inputs: sources from fetch_deps.sh and the Godot API dump.
set(LEILA_NATIVE_DEPS "$ENV{HOME}/.cache/leila-native/deps" CACHE PATH "Output dir of native/fetch_deps.sh")
if(NOT GODOTCPP_CUSTOM_API_FILE)
  set(GODOTCPP_CUSTOM_API_FILE "$ENV{HOME}/.cache/leila-native/api/extension_api.json"
      CACHE FILEPATH "Godot extension_api.json from --dump-extension-api" FORCE)
endif()
foreach(dep llama.cpp/CMakeLists.txt godot-cpp/CMakeLists.txt)
  if(NOT EXISTS "${LEILA_NATIVE_DEPS}/${dep}")
    message(FATAL_ERROR "Missing ${LEILA_NATIVE_DEPS}/${dep}. Run native/fetch_deps.sh first.")
  endif()
endforeach()
if(NOT EXISTS "${GODOTCPP_CUSTOM_API_FILE}")
  message(FATAL_ERROR "Missing Godot API file ${GODOTCPP_CUSTOM_API_FILE}")
endif()

# RPATH: our lib, llama and ggml all resolve siblings from their own directory ($ORIGIN).
# The build tree uses the install RPATH too, so the copies in game/ carry the same RUNPATH.
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
set(CMAKE_BUILD_RPATH "$ORIGIN")
set(CMAKE_INSTALL_RPATH "$ORIGIN")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH OFF)

# godot-cpp: static, template_release, exceptions off.
# GODOTCPP_USE_STATIC_CPP stays OFF: its PUBLIC -static-libstdc++ would put a second
# libstdc++ inside leila_llm next to libllama.so.
set(GODOTCPP_TARGET "template_release" CACHE STRING "" FORCE)
set(GODOTCPP_USE_STATIC_CPP OFF CACHE BOOL "" FORCE)
set(GODOTCPP_DISABLE_EXCEPTIONS ON CACHE BOOL "" FORCE)
add_subdirectory("${LEILA_NATIVE_DEPS}/godot-cpp" godot-cpp)

# llama.cpp: shared libs, ggml CPU backends as runtime-loaded DL modules.
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL ON CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS ON CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
foreach(opt LLAMA_BUILD_TESTS LLAMA_BUILD_TOOLS LLAMA_BUILD_EXAMPLES LLAMA_BUILD_SERVER
            LLAMA_BUILD_APP LLAMA_BUILD_UI LLAMA_OPENSSL LLAMA_CONNECT)
  set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
# LLAMA_CURL does not exist at this pin.
# Tarball build has no .git, so llama's build-info would report b0-unknown. Pin it here.
set(LLAMA_BUILD_NUMBER 12024)
set(LLAMA_BUILD_COMMIT "ddf48f85")
add_subdirectory("${LEILA_NATIVE_DEPS}/llama.cpp" llama.cpp)

add_library(leila_llm SHARED
  src/register_types.cpp
  src/leila_llm.cpp)
target_compile_features(leila_llm PRIVATE cxx_std_17)
target_include_directories(leila_llm PRIVATE src)
target_link_libraries(leila_llm PRIVATE godot::cpp llama llama-common)
