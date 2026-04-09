cmake_minimum_required(VERSION 3.25)
project(MindTrace VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_PREFIX_PATH "C:/Qt/6.11.0/msvc2022_64")

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Widgets Quick QuickControls2 Multimedia)

# ONNX Runtime C++ SDK — extraia o pacote adequado e renomeie para onnxruntime_sdk/
#   AMD / Intel  →  onnxruntime-win-x64-1.24.4.zip     extraído como onnxruntime_sdk/
#   NVIDIA CUDA  →  onnxruntime-win-x64-gpu-1.24.4.zip  extraído como onnxruntime_sdk/
# Ambos têm a mesma estrutura: onnxruntime_sdk/include/ e onnxruntime_sdk/lib/
set(ONNX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../onnxruntime_sdk")

if(NOT EXISTS "${ONNX_DIR}/include/onnxruntime_cxx_api.h")
    message(FATAL_ERROR
        "\n[MindTrace] ONNX Runtime SDK não encontrado em: ${ONNX_DIR}\n"
        "  Baixe o pacote adequado para sua GPU (ver README.md Seção 2)\n"
        "  e renomeie a pasta extraída para 'onnxruntime_sdk' na raiz do projeto.\n"
    )
endif()

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
    "${CMAKE_CURRENT_SOURCE_DIR}/src/settings/ThemeSettings.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/settings/ThemeSettings.h"
    "${QRC_SOURCES}"
)

# ONNX Runtime headers
target_include_directories(MindTrace PRIVATE
    "${ONNX_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/core"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/manager"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/tracking"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/settings"
)

target_link_libraries(MindTrace PRIVATE
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    "${ONNX_DIR}/lib/onnxruntime.lib"
    dxgi
    # d3d12 — NÃO linkar: DX12/CUDA são internos ao onnxruntime.dll
)
