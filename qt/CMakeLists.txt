cmake_minimum_required(VERSION 3.12)
project(MindTrace VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_PREFIX_PATH "C:/Qt/Qt5.12.12/5.12.12/msvc2017_64")
set(Qt5_DIR "C:/Qt/Qt5.12.12/5.12.12/msvc2017_64/lib/cmake/Qt5")

find_package(Qt5 5.12 REQUIRED COMPONENTS Core Widgets Quick QuickControls2 Multimedia)

# ONNX Runtime C++ SDK (bundled in repo)
set(ONNX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/onnxruntime-win-x64-1.16.3")

qt5_add_resources(QRC_SOURCES resources.qrc)

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
    Qt5::Core
    Qt5::Widgets
    Qt5::Quick
    Qt5::QuickControls2
    Qt5::Multimedia
    "${ONNX_DIR}/lib/onnxruntime.lib"
    # d3d12.lib removido: nosso executável não chama DirectX 12 diretamente.
    # O provider DirectML é carregado dentro de onnxruntime.dll em tempo de execução.
    # Linkar d3d12.lib causava falha de carregamento no Windows 7 (d3d12.dll inexistente).
)
