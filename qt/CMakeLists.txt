cmake_minimum_required(VERSION 3.25)
project(MindTrace VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_PREFIX_PATH "C:/Qt/6.11.0/msvc2022_64")

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Widgets Quick QuickControls2 Multimedia)

# ONNX Runtime C++ SDK (bundled in project root)
# Use directml_x64 for AMD/Intel/NVIDIA DirectML support
set(ONNX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../directml_x64")

qt6_add_resources(QRC_SOURCES resources.qrc)

add_executable(MindTrace WIN32
    "${CMAKE_CURRENT_SOURCE_DIR}/src/core/main.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/manager/ExperimentManager.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/manager/ExperimentManager.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models/ExperimentTableModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models/ExperimentTableModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models/ArenaModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models/ArenaModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models/ArenaConfigModel.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models/ArenaConfigModel.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/tracking/inference_controller.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/tracking/inference_controller.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/tracking/inference_engine.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/tracking/inference_engine.h"
    "${QRC_SOURCES}"
)

# ONNX Runtime headers
target_include_directories(MindTrace PRIVATE
    "${ONNX_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/core"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/manager"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/tracking"
)

target_link_libraries(MindTrace PRIVATE
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    "${ONNX_DIR}/onnxruntime.lib"
    dxgi
    d3d12
)
