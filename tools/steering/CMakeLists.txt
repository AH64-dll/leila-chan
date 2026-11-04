# Steering tools (P3.01): llama-dump-residuals — per-layer residual capture via
# the llama.cpp eval callback (docs/06 §2, option b).
#
# LLAMA_DIR defaults to the pinned source checkout (README "Local artifacts":
# tools/llama/llama.cpp at build b12024, commit ddf48f85c). Override with
#   -DLLAMA_DIR=/path/to/llama.cpp
#
# Linux:
#   cmake -S tools/steering -B tools/steering/build -DCMAKE_BUILD_TYPE=Release
#   cmake --build tools/steering/build -j
# Windows (Developer prompt / Git Bash, MSVC or MinGW — same commands):
#   cmake -S tools\steering -B tools\steering\build
#   cmake --build tools\steering\build --config Release
# Binary lands in <build>/llama-dump-residuals[.exe]; copy it next to the
# llama shared libs or keep LLAMA_DIR on PATH/LD_LIBRARY_PATH as usual.

cmake_minimum_required(VERSION 3.14)
project(llama-steering-tools CXX)

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(LLAMA_DIR "${REPO_ROOT}/tools/llama/llama.cpp" CACHE PATH "llama.cpp source checkout")

if (NOT EXISTS "${LLAMA_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp source not found at ${LLAMA_DIR} "
            "(expected the pinned b12024 checkout; see README 'Local artifacts' / tools/llm/fetch_llama.*)")
endif()

# Just the libs the tool links against — skip tools/examples/tests of llama.cpp itself.
set(LLAMA_BUILD_COMMON   ON  CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL           OFF CACHE BOOL "" FORCE)

add_subdirectory("${LLAMA_DIR}" llama.cpp EXCLUDE_FROM_ALL)

add_executable(llama-dump-residuals dump_residuals.cpp)
target_compile_features(llama-dump-residuals PRIVATE cxx_std_17)
target_link_libraries(llama-dump-residuals PRIVATE llama-common llama)
