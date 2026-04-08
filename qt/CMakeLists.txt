cmake_minimum_required(VERSION 3.25)
project(MindTrace VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_PREFIX_PATH "C:/Qt/6.11.0/msvc2022_64")

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Widgets Quick QuickControls2 Multimedia)

# ONNX Runtime C++ SDK (bundled in repo)
# Use onnxruntime-win-x64-gpu-1.24.4 for NVIDIA CUDA support.
# Use onnxruntime-win-x64-1.24.4 for AMD/Intel (DirectML) support.
# Runtime provider priority: CUDA → DirectML → CPU (handled in onnx_tracker.cpp).
set(ONNX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/onnxruntime-win-x64-1.24.4")

qt6_add_resources(QRC_SOURCES resources.qrc)

add_executable(MindTrace WIN32
    "${CMAKE_CURRENT_SOURCE_DIR}/src/main.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ExperimentManager.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ExperimentManager.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ExperimentTableModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ExperimentTableModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ArenaModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ArenaModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ArenaConfigModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/ArenaConfigModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/dlc_controller.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/dlc_controller.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/onnx_tracker.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/onnx_tracker.h"
    "${QRC_SOURCES}"
)

# ONNX Runtime headers — two include dirs so dml_provider_factory.h
# in src/ can find onnxruntime_c_api.h from the bundle
target_include_directories(MindTrace PRIVATE
    "${ONNX_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(MindTrace PRIVATE
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    "${ONNX_DIR}/lib/onnxruntime.lib"
    "${ONNX_DIR}/lib/onnxruntime_providers_shared.lib"
    dxgi
    d3d12
)
